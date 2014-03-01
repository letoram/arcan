# quick and dirty libretro FBA importer
# -----
# Uses a patched output DB from the perl scripts of the normal Final Burn emulator.
# These look-ups, as with Mame and MESS gamelists should all just be merged into a shared sqlite database
# packed in a full release, with an online lookup fallback
#
class FBA 
	attr_accessor :target

	def initialize
		@categories = {}
		@series = {}
		@fbaargs = [ [], [], [] ] 
		@target = Target.new
	end

	def merge_gameinfo(catver)
		STDERR.print("[FBA importer] processing catver file\n")

		File.open(catver, File::RDONLY).each_line{|line|
			break if line[0..9] == "[VerAdded]"
			name, category = line.split(/\=/)
			maincat, subcat = category.split(/\//) if category
			maincat.strip! if maincat
			subcat.strip! if subcat
			@categories[name] = [maincat, subcat]
		}	
		STDERR.print("[FBA importer::catver], categories loaded\n")	
		true

	rescue => er
		STDERR.print("[FBA importer::catver] Couldn't open category file, #{catver} -- #{er}\n")
		false
	end 

	def merge_relatives(series)
		STDERR.print("[FBA importer::series] processing series file\n")
		gname = ""
		
		infile = File.open(series, File::RDONLY).each_line{|line|
			cline = line.strip
			next if cline.size == 0
			
			if cline =~ /\[(\w|\s)*\]/
				gname = cline[1..-2]
			else
				@series[cline] = gname
			end
		}
		STDERR.print("[FBA importer::series] series processed\n")
		true

	rescue => er
		STDERR.print("[FBA importer::series] couldn't open series file, #{series}\n")
		false
	end
	
# just take the pregenerated gamelist.fba, extract necessary fields and store in a table
# which is used for lookup during romscan
	def load_gamedata(path)
		@games = {}
		count = 0
	
		File.open(path).each_line{|line|
		args      = line.split(/\|/)
		                         
		setname   = args[1].strip
		next unless setname and setname.length > 0
#
# since we only use this as a libretro core currently, skip the console targets for which we have
# dedicated cores already
#
		if (setname[0..3] == "pce_" or setname[0..2] == "md_" or setname[0..2] == "tg_")
			next
		end
		@games[setname] = {}
		@games[setname][:status] = args[2].strip
		@games[setname][:title ] = args[3].strip                         
		@games[setname][:parent] = args[4].strip
		@games[setname][:year]   = args[5].strip	
		@games[setname][:dev]    = args[6].strip	
		@games[setname][:sys]    = args[7].strip
		@games[setname][:setname]= setname
		count = count + 1
	}
		
	STDOUT.print("[FBA importer::gamedata] loaded #{count} games (pce/md/tg skipped).\n");
	rescue => er
		STDERR.print("[FBA importer::gamedata] couldn't process gamedata from (#{path}, #{er})\n")
	end
	
	def set_defaults(basepath, options, cmdopts)
		if (res = cmdopts["--fbacatver"])
			merge_gameinfo( res[0] )
		elsif File.exists?("#{basepath}/importers/catver.ini")
			merge_gameinfo("#{basepath}/importers/catver.ini")
		end

		if (res = cmdopts["--fbaseries"])
			merge_relatives( res[0] )
		elsif File.exists?("#{basepath}/importers/series.ini")
			merge_relatives("#{basepath}/importers/series.ini")
		end

		if (res = cmdopts["--fbadb"])
			load_gamedata( res[0] )
		else
			load_gamedata( "#{basepath}/importers/gamelist.fba" )
		end
			
		@skipclone = cmdopts["--fbaskipclone"] ? true : false
		@shorttitle = cmdopts["--fbashorttitle"] ? true : false
	end

	def accepted_arguments
		[ 
			["--fbacatver", GetoptLong::REQUIRED_ARGUMENT],
			["--fbaseries", GetoptLong::REQUIRED_ARGUMENT],
			["--fbaskipclone", GetoptLong::NO_ARGUMENT],
			["--fbashorttitle", GetoptLong::NO_ARGUMENT]
		]
	end

	def usage()
	   [
		"Final Burn Alpha, fba (libretro) importer arguments:",
		"(--fbacatver) filename - Specify a catver.ini file",
		"(--fbaseries) filename - Specify a series.ini file",
		"(--fbaskipclone) - Skip drivers that are marked as clones",
		"(--fbashorttitle) - Don't store extraneous title data (set,revision,..)",
		""
		]
	end

	def process_game( tbl, filename )
		return nil if @skipclone and tbl[:parent] and tbl[:parent].size == 0
	
		title = tbl[:title]
		if @shorttitle and title.index('(')
			title = [0..title.index('(')-1]
		end
	
		setname = tbl[:setname]

		newgame = Game.LoadSingle(title, filename, @target.pkid)
		newgame = Game.new unless newgame

# FIXME, status ignored
	
		newgame.target  = @target
		newgame.title   = title
		newgame.setname = filename 
		newgame.year    = tbl[:year].to_i > 1960 ? tbl[:year].to_i : 0
		newgame.ctrlmask = 0
		newgame.system  = tbl[:sys]
		newgame.manufacturer = tbl[:dev]
		newgame.family = @series[setname]

		if (@categories[setname])
			newgame.genre    = @categories[setname][0]
			newgame.subgenre = @categories[setname][1]
		end

		newgame
	end
	
	def check_target(target, targetpath)
		@fbatarget = nil
		executable = nil

		execs = ["fba.so", "fba.dylib", "fba.dll"];
		execs.each{|ext|
			fullname = "#{targetpath}/#{ext}"
			if (File.exists?(fullname))
				@fbatarget = fullname
				executable = ext
				break
			end
		}

		if (@fbatarget == nil)
			raise "Could not locate fba, giving up (tried #{targetpath}/#{execs.join(', ')}. "
		end
		
		@target = Target.Load(0, "fba")
		fbaargs = [ ["[romsetfull]"], [], [] ]
		
		if (@target == nil)
			@target = Target.Create("fba", executable, fbaargs)
		else
			@target.arguments = fbaargs 
			@target.store
		end

		return (File.exists?(@fbatarget) )
	end

	def check_games(rompath )
		setnames = {}
		exts = ["zip", "ZIP", "iso", "ISO"]
		
		exts.each{|ext|
			dn = Dir["#{rompath}/*.#{ext}"].each{|romname|
				basename = romname[ romname.rindex('/')+1 .. romname.rindex('.')-1 ]
				setnames[basename] = romname[romname.rindex('/')+1 .. -1] 
			}
		}
	
		setnames.each_pair{|key, val|
			if @games[key] then
				game = process_game( @games[key], val)
				yield game if game
			else
				STDERR.print("[FBA Importer] setname #{key} not found in database, ignoring.\n")
		  end                
		}

		true

	rescue => er
		STDERR.print("[FBA Importer] failed, reason: #{er}, #{er.backtrace}\n")
		false
	end

	def to_s
		"[FBA Importer]"
	end
end
