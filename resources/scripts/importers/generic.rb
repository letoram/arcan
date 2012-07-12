# Generic importer,
# Uses the correlation between <rompath>/<foldername> with <targetpath>/<foldername>,
# Sets the name and target executable of the target to <foldername> (so that parameters 
# can be individualized later on anyhow by a alterdb on the target)
# --
# Would be somewhat fun to play around with heuristics + websearchengines and try to
# automatically deduce reasonable data for each target, but that's for the future ..
#
SystemTable = {
"fceu" => "nes",
"bnes" => "nes",
"snes9x" => "snes",
"n64" => "n64",
"bsnes" => "snes",
"mame" => "arcade/multi",
"mess" => "multi",
"ume" => "multi",
"mednafen" => "multi",
"vba" => "gameboy",
"fba" => "arcade",
"psx" => "playstation",
"dolphin" => "wii",
"genplus" => "sega/multi",
"scummvm" => "adventure/VM"
}

# Common target- names and their corresponding system
class Generic
	def initialize
		@gentargets = {}
		@genromlist = {}
		@striptitle = true
	end

	def usage
		[
			"\ngeneric importer, first argument in each --gen*args must match targetname",
			"(--genargs) - comma-separated list of launch arguments",
			"(--genintargs) - comma- separated list of internal- launch arguments",
			"(--genextargs) - comma- separated list of external- launch arguments",
			"(--genrompath) targetname - encodes full rompath (as per --rompath) into the romset",
			"(--genstriptitle) try and shrink the game title as much as possible",
		]
	end

	def accepted_arguments
		[
			["--genrompath", GetoptLong::REQUIRED_ARGUMENT],
			["--genargs", GetoptLong::REQUIRED_ARGUMENT],
			["--genintargs", GetoptLong::REQUIRED_ARGUMENT],
			["--genextargs", GetoptLong::REQUIRED_ARGUMENT],
			["--gennostriptitle", GetoptLong::NO_ARGUMENT]
		]
	end

	def set_defaults(basepath, options, opts)
		chkargs = ["--genargs", "--genintargs", "--genextargs"]
	
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
						STDERR.print("[Generic Importer] couldn't set #{argstr}, format; target,arg1,arg2,..\n")
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
		extension = ""
		execs = ["", ".exe", ".so", ".dll"];
		libloader = false # for dynamic libraries, we don't accept user supplied arguments, only target + romsetfull
		
		execs.each{|ext|
		           fullname = "#{targetpath}/#{target}#{ext}"
		           if (File.exists?(fullname))
		               @genericpath = fullname
						extension = ext
						if (ext == ".so" or ext == ".dll")
							libloader = true
						end
		          
						break
		           end
		}
		
		return false if @genericpath == nil 
		
		@titles = {}
		@targetname = target
		@target = Target.Load(0, @targetname)
		
		if (libloader)
			@gentargets[target] = [ ["[romsetfull]"], [], [] ]
		end
		
		if (@target == nil)
			@target = Target.Create(@targetname, "#{@targetname}#{extension}",@gentargets[target])
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

# should also try and extract other features,
# [code] (country) + specials (???k) (Unl)
# system codes [C] (Color GB) [S] (Super GB), (M#) Multilang, [M] Mono/NGP, (PC10), (1,4,5,8) Genesis,
# (BS,ST,NP) Snes, (Adam) ColecoVision, (PAL) PALVideo + bsnes XML folder format
	def check_games(rompath)
		codetbl = {
			"a" => "Alternate",
			"b" => "Bad Dump",
			"BF" => "Bung Fix",
			"c" => "cracked",
			"f" => "Other Fix",
			"h" => "hack",
			"o" => "overdump",
			"p" => "Pirate",
			"t" => "Trained",
			"T" => "Translation",
			"x" => "Bad Checksum",
			"\!" => "Verified Good Dump",
		}
		
		Dir["#{rompath}/*"].each{|fn|
			if (fn == "." || fn == ".." || fn =~ /\.srm\z/) 
				next
			else
				setname = fn[ fn.rindex('/') +1 .. -1 ]

				newgame = Game.new
				newgame.title = @striptitle ? strip_title(setname) : setname
				newgame.setname = @genromlist[@targetname] == true ? fn : setname
				newgame.target = @target
				newgame.system = SystemTable[ @targetname ]
				if (newgame.system == nil) then
				    newgame.system = @targetname
				end

				yield newgame
			end
		}
	end
end
