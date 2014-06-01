# Generic importer,
# Uses the correlation between <rompath>/<foldername> with <targetpath>/<foldername>,
# Sets the name and target executable of the target to <foldername> (so that parameters 
# can be individualized later on anyhow by a alterdb on the target)
# --
require File.join(File.dirname(__FILE__), 'gamedb.rb')

# the end system set will be based on the folder name (remapped by the table below)
# augmented with the shortname extensions and libretro core
# the end name should preferably match the gameDB platform names for scraping to work
SystemTable = {
"fceu"   => "Nintendo Entertainment System (NES)",
"bnes"   => "Nintendo Entertainment System (NES)",
"snes"   => "Super Nintendo (SNES)",
"bsnes"  => "Super Nintendo (SNES)",
"snes9x" => "Super Nintendo (SNES)",
	
"mess"   => "Multi",
"ume"    => "Multi",

"2600"   => "Atari 2600",
	
"psx"    => "Sony Playstation",

"tg16"   => "TurboGrafx 16",
"pce"    => "TurboGrafx 16",
"mupen64" => "Nintendo 64",
"n64"    => "Nintendo 64",

"genplus"=> "Sega",
"genesis"=> "Sega Genesis",
"gg"     => "Sega Game Gear",
"sms"    => "Sega Master System",
"vba"    => "Nintendo Game Boy Advance",
"gba"    => "Nintendo Game Boy Advance",
"gb"     => "Nintendo Game Boy",
"gbc"    => "Nintendo Game Boy Color",
"nds"    => "Nintendo DS"
}

# Common target- names and their corresponding system
class Generic
	attr_accessor :target

	def initialize
		@gentargets = {}
		@genromlist = {}
		@striptitle = true
	end

	def usage
		[
			"Generic importer arguments:",
			"(first argument in each --gen*args must match targetname",
			"(--genargs) - comma-separated list of launch arguments",
			"(--genintargs) - comma- separated list of internal- launch arguments",
			"(--genextargs) - comma- separated list of external- launch arguments",
			"(--genrompath) targetname - encodes full rompath (as per --rompath) into the romset",
			"(--gennostriptitle) try and shrink the game title as much as possible",
			"(--genscrape) - try and scrape metadata from online sources",
			"(--genscrapemedia) - download media while scraping (screenshots, boxart, ...)",
			""
		]
	end

	def accepted_arguments
		[
			["--genrompath", GetoptLong::REQUIRED_ARGUMENT],
			["--genargs", GetoptLong::REQUIRED_ARGUMENT],
			["--genintargs", GetoptLong::REQUIRED_ARGUMENT],
			["--genextargs", GetoptLong::REQUIRED_ARGUMENT],
			["--gennostriptitle", GetoptLong::NO_ARGUMENT],
			["--genscrape", GetoptLong::NO_ARGUMENT],
			["--genscrapemedia", GetoptLong::NO_ARGUMENT]
		]
	end

	def set_defaults(basepath, options, opts)
		chkargs = ["--genargs", "--genintargs", "--genextargs"]

		@options = options
		if (opts["--genscrape"])
			begin
				@gamedb = GamesDB.new
				@gamedb_media = opts["--genscrapemedia"]
			rescue => er
				STDERR.print( "#{self} GamesDB Scraper not responding (#{er}), scraping disabled.\n");
				@gamedb = nil
				@gamedb_media = nil
				@options["--genscrape"] = nil
			end
		end
		
		if (opts["--genrompath"] != nil)
			opts["--genrompath"].each{|tgt|
			@genromlist[tgt] = true
		}
		end

		if (opts["--gennostriptitle"]) 
			@striptitle = false
		end
		
		chkargs.each_with_index{|argstr, ind|
			if (arg = opts[argstr])
				arg.each{|subarg|
					subargs = subarg.split(/,/)
					if (subargs.size <= 1)
						STDERR.print("#{self} couldn't set #{argstr}, format; target,arg1,arg2,..\n")
						return false
					else
						@gentargets[subargs[0]] = [[], [], []] if @gentargets[subargs[0]] == nil 
						@gentargets[subargs[0]][ind] = subargs[1..-1]
					end
				}	
			end
		}
	
		true
	end
	
	def check_target(target, targetpath)
		@genericpath = nil
		@filter_ext = nil
		extension = ""
		execs = ["", ".exe", ".so", ".dll", ".dylib"];
		libloader = false # for dynamic libraries, we don't accept user supplied arguments, only target + romsetfull
		
		execs.each{|ext|
			fullname = "#{targetpath}/#{target}#{ext}"
			if (File.exists?(fullname))
				@genericpath = fullname
				extension = ext
				if (ext == ".so" or ext == ".dll" or ext == ".dylib")
					libloader = true
				end	          
				break
			end
		}
		
		return false if @genericpath == nil 
	
		if libloader
			if File.exists?(@options[:frameserver])
				info  = {}
				args = ""
				if @options[:in_windows]
					args  = "#{@options[:frameserver]} nokey 0 0 0 libretro \"core=#{targetpath}/#{target}#{extension}:info\" #{args}"
				else
					ENV["ARCAN_ARG"] = "core=#{targetpath}/#{target}#{extension}:info"
					args = "#{@options[:frameserver]} libretro nokey"
				end
						
				begin
					in_block = false
	
					IO.popen(args).each_line{|line|
						if (in_block)
							line = line.strip
							if (line != "/arcan_frameserver(info)")
								key = line[0.. line.index(":")-1]
								val = line[line.index(":")+1 .. -1]
								info[key] = val
							else
								break
							end
						else
							in_block = line.strip == "arcan_frameserver(info)"
						end
					}
					
					STDOUT.print("#{self} Libretro core found, #{info["library"]} #{info["version"]}\n\t")
					if (info["extensions"])
						exts = info["extensions"].split(/\|/)
					else
						exts = {};
					end
					STDOUT.print("#{self} Accepted extensions: #{exts}\n")

					@extensions = {}
					exts.each{|val| @extensions[".#{val.upcase}"] = true }
					@filter_ext = @extensions.size > 0
	
				rescue => er
					STDERR.print("#{self} couldn't parse frameserver output (#{er}, #{er.backtrace}).\n");
					@extensions = nil
					@filter_ext = nil
				end

			else
			   STDERR.print("#{self} couldn't find frameserver, no library extension filtering will be performed.\n")
			end
		end
		
		@titles = {}
		@targetname = target
		@target = Target.Load(0, @targetname)

# gamedb only valid if scraping is activated, try and match to target (and if that fails, perhaps
# add a translation table based on libretro core output)
		target = SystemTable[target] ? SystemTable[target] : target
		if @gamedb
			@gamedb_sys = @gamedb.find_system(target)
			if @gamedb_sys == nil
				STDERR.print("#{self} Problem while scraping data, no system match for target #{target} found.\n")
			else
				STDOUT.print("#{self} Mapped #{target} to #{@gamedb_sys}\n")
			end
		end

		if (@target == nil)
			@target = Target.Create(@targetname, "#{@targetname}#{extension}", @gentargets[target])
		end 

		if (libloader)
			@gentargets[target] = [ ["[romsetfull]"], [], [] ]
		end
		
		if (@gentargets[target])
			@target.arguments = @gentargets[target]
			@target.store
		end
		
		true
	end

	def to_s
		"[Generic (#{@targetname}) Importer]"
	end

	def strip_title(instr)
		resstr = instr

		titleind = instr.index(/[()\[]/)
		if (titleind and titleind > 0)
			resstr = instr[0..titleind-1].strip
		end
		matchd = resstr.match( /(.*)([.]\w{3,4})\z/ )
		resstr = matchd[1] if matchd and matchd[1]
		
		matchd = resstr.match(/\A\d{4}\s-\s(.*)/)
		resstr = matchd[1] if matchd and matchd[1]

		resstr
	end

# use TheGamesDB to gather more metadata (system, year, title, etc.)
# and (if full setting) is enabled, also store relevant media
	def scrape_data(title, dstgame)
		gameid = @gamedb.find_game(title, @gamedb_sys)

		if (gameid)
			game = GamesDBGame.new(gameid[:gid].to_i) 
			
			if (@gamedb_media)
			begin
				bpth = "#{@options[:rompath]}/../"
				unless File.exists?("#{bpth}boxart")
					Dir.mkdir("#{@options[:rompath]}/../boxart")
				end

				unless File.exists?("#{bpth}/screenshots")
					Dir.mkdir("#{@options[:rompath]}/../screenshots")
				end

			rescue => er
				STDERR.print("#{self} Scraping media disabled, couldn't create output directories.\n");
				@gamedb_media = false
			end
			end
			
			if (game)
				STDOUT.print("#{self} Scraping matched (#{title}) to (#{game.title})\n")
				dstgame.title   = game.title
				dstgame.players = game.players
				dstgame.system  = game.platform

				begin
					dstgame.genre    = game.genres[0]
					dstgame.subgenre = game.genres[1]
				rescue
				end

				if (game.rlsdate.index('/'))
					dstgame.year = game.rlsdate[ game.rlsdate.rindex('/')+1 .. -1 ].to_i
				else
					dstgame.year = game.rlsdate.to_i
				end

# check for matching media (boxart, screenshots, ...) will only save if a matching filename isn't found
				if (@gamedb_media) 
					game.store_boxart( "#{@options[:rompath]}/../boxart/#{dstgame.setname}" )
					game.store_screenshot( "#{@options[:rompath]}/../screenshots/#{dstgame.setname}" )
				end

			end
	
		else
			STDERR.print("#{self} No match for (#{title}) while scraping.\n")
		end
		
	end
	
# should also try and extract other features,
# [code] (country) + specials (???k) (Unl)
# system codes [C] (Color GB) [S] (Super GB), (M#) Multilang, [M] Mono/NGP, (PC10), (1,4,5,8) Genesis,
# (BS,ST,NP) Snes, (Adam) ColecoVision, (PAL) PALVideo + bsnes XML folder format
	def check_games(rompath)
		codetbl = {
			"a" => "Alternate",
			"b" => "Bad Dump",
			"BF"=> "Bung Fix",
			"c" => "cracked",
			"f" => "Other Fix",
			"h" => "hack",
			"o" => "overdump",
			"p" => "Pirate",
			"t" => "Trained",
			"T" => "Translation",
			"x" => "Bad Checksum",
			"\!" => "Verified Good Dump"
		}
	
		Dir["#{rompath}/*"].each{|fn|
			ext = File.extname(fn).upcase

			if (fn == "." || fn == ".." || (@filter_ext and @extensions[ext] != true))
				STDERR.print("#{self} unknown extension (#{ext}), ignored.\n");
				next
			else
				setname = File.basename(fn) 

				title   = @striptitle ? strip_title(setname) : setname
				setname = @genromlist[@targetname] == true ? fn : setname
				newgame = Game.LoadSingle(title, setname, @target.pkid)
				if (not newgame) then
					newgame = Game.new
		    end
				
				newgame.setname = setname
				newgame.title = title
				newgame.target = @target
                   
				if @gamedb_sys
					newgame.system = @gamedb_sys
					scrape_data(title, newgame)
				else
					newgame.system = SystemTable[ @targetname ]
					if (newgame.system == nil) then
				    newgame.system = @targetname
					end
				end
                        
				yield newgame
			end
		}
	end
end
