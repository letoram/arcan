class Mame
	attr_accessor :target

	def initialize
		@categories = {}
		@series = {}
		@mameargs = [ [], [], [] ]
		@dbinit = false
		@target = Target.new
	end

	def accepted_arguments
		[ 
			["--mamecatver", GetoptLong::REQUIRED_ARGUMENT],
			["--mameseries", GetoptLong::REQUIRED_ARGUMENT],
			["--mameverify", GetoptLong::NO_ARGUMENT ],
			["--mameargs", GetoptLong::REQUIRED_ARGUMENT],
			["--mameintargs", GetoptLong::REQUIRED_ARGUMENT],
			["--mameextargs", GetoptLong::REQUIRED_ARGUMENT],
			["--mamegood", GetoptLong::NO_ARGUMENT ],
			["--mameskipclone", GetoptLong::NO_ARGUMENT],
			["--mameshorttitle", GetoptLong::NO_ARGUMENT]
		]
	end

	def usage()
	   [
		"MAME Importer arguments:", 
		"(--mamecatver) filename - Specify a catver.ini file",
		"(--mameseries) filename - Specify a series.ini file",
		"(--mameverify) - Only add games that pass verification",
		"(--mameargs) - comma-separated list of launch arguments",
		"(--mameintargs) - comma- separated list of internal- launch arguments",
		"(--mameextargs) - comma- separated list of external- launch arguments",
		"(--mamegood) - Only add games where the driver emulation status is good",
		"(--mameskipclone) - Skip drivers that are marked as clones",
		"(--mameshorttitle) - Don't store extraneous title data (set,revision,..)",
		""
		]
	end

	def set_defaults(basepath, options, cmdopts)
# keep a reference to these as we want to defer loading catver until
# the importer is actually run
		@options  = cmdopts
		@basepath = basepath
		
		@mameargs[0] << "-rompath"
		@mameargs[0] << "[gamepath]/mame"
		@mameargs[0] << "-cfg_directory"
		@mameargs[0] << "[applpath]/_mame/cfg"
		@mameargs[0] << "-nvram_directory"
		@mameargs[0] << "[applpath]/_mame/nvram"
		@mameargs[0] << "-memcard_directory"
		@mameargs[0] << "[applpath]/_mame/memcard"
		@mameargs[0] << "-input_directory"
		@mameargs[0] << "[applpath]/_mame/input"
		@mameargs[0] << "-state_directory"
		@mameargs[0] << "[applpath]/_mame/state"
		@mameargs[0] << "-snapshot_directory"
		@mameargs[0] << "[applpath]/_mame/snapshot"
		@mameargs[0] << "-diff_directory"
		@mameargs[0] << "[applpath]/_mame/diff"
		@mameargs[0] << "-comment_directory"
		@mameargs[0] << "[applpath]/_mame/comment"
		@mameargs[0] << "-skip_gameinfo"

# internal launch arguments, we want the data as "pure" as and "cheap" possible
		@mameargs[1] << "-window"
		@mameargs[1] << "-scalemode"
		@mameargs[1] << "none"
		@mameargs[1] << "-video"
		@mameargs[1] << "opengl" 
		@mameargs[1] << "-nomaximize"
		@mameargs[1] << "-multithreading"
		@mameargs[1] << "-keepaspect"
		@mameargs[1] << "[romset]"
		@mameargs[2] << "[romset]"

		@onlygood   = cmdopts["--mamegood"]       ? true : false
		@verify     = cmdopts["--mameverify"]     ? true : false
		@skipclone  = cmdopts["--mameskipclone"]  ? true : false
		@shorttitle = cmdopts["--mameshorttitle"] ? true : false

		chkargs = ["--mameargs", "--mameintargs", "--mameextargs"]
		chkargs.each_with_index{|argstr, ind|
			if (arg = cmdopts[argstr])
				arg.each{|subarg|
					subargs = subarg.split(/,/)
					if (subargs.size < 1)
						STDERR.print("[MAME Importer] couldn't set #{argstr}, format; arg1,arg2,...")
						return false
					else
						@mametargets[ind] = arg[1..-1]
					end
				}
			end
		}
	end

	def merge_gameinfo(catver)
		STDERR.print("[MAME importer] processing catver file\n")

		File.open(catver, File::RDONLY).each_line{|line|
			break if line[0..9] == "[VerAdded]"
			name, category = line.split(/\=/)
			maincat, subcat = category.split(/\//) if category
			maincat.strip! if maincat
			subcat.strip! if subcat
			@categories[name] = [maincat, subcat]
		}	
		STDERR.print("[MAME importer::catver], categories loaded\n")	
		true

	rescue => er
		STDERR.print("[MAME importer::catver] Couldn't open category file, #{catver} -- #{er}\n")
		false
	end 
	
	def merge_relatives(series)
		STDERR.print("[MAME importer::series] processing series file\n")
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
		STDERR.print("[MAME importer::series] series processed\n")
		true

	rescue => er
		STDERR.print("Couldn't open series file, #{series}\n")
		false
	end

# Just launch mame separately, let it scan the romset and then check the return result
	def checkrom(mamepath, rompath, romset)
		a = IO.popen("#{mamepath} -rompath #{rompath} -verifyroms #{romset} 1> /dev/null 2>/dev/null")
		a.readlines
		a.close

		return $?.exitstatus == 0
	
	rescue => ex
		false
	end

# wrap new (0.144ish?) "joy -> 4,8, ..." ways into the older version, since that one was heavily embedded already
	def subjoy_str(waylbl, waylbl2)
		resstr = waylbl2 ? "doublejoy" : "joy"
		case waylbl
			when "2"
				resstr << "2way"
			when "4"
				resstr << "4way"
			when "8"
				resstr << "8way"
			when "vertical2"
				resstr = "v#{resstr}2way"
			else
				resstr = nil # silently ignore
			end

		resstr
	end

	def convert_inputtype(inputnode)
	    res = nil
	    case inputnode.attributes["value"]
	    when "gambling"
	    when "hanafuda"
	    when "mahjong"
	    when "joy"
	        res = subjoy_str(inputnode.attributes["ways"], nil)
	    when "doublejoy"
	        res = subjoy_str(inputnode.attributes["ways"], inputnode.attributes["ways2"])
	    else
	        res = inputnode.attributes["value"]
	    end
	    res 
	end

# use the internal gamedb of mame from the verified target, splice subtrees off as separate documents and parse individually,
# mem-usage is insane otherwise.
	def mame_each
		status = {}
		xmlin = IO.popen("#{@mametarget} -listxml")

		endid = 0
		
# seriously ugly hack around Nokogiri versioning issues
		begin
			endid = Nokogiri::XML::Reader::TYPE_END_ELEMENT
		rescue
			endid = 15
		end
		
		xp = Nokogiri::XML::Reader.from_io( xmlin )
		while (xp.read)
			next unless xp.name == "game"
			next if xp.node_type == endid
			
			node_tree = Nokogiri::XML.parse( xp.outer_xml.dup ) 
			next if node_tree.root.attributes["isbios"]
			next if @skipclone and node_tree.root.attributes["cloneof"]

			title = node_tree.xpath("//game/description").text
			shorttitle = title.split(/\s\(/)[0]
			shorttitle = shorttitle.split(/\//)[0] if shorttitle.index("/")
			
			title.strip! if title
			shorttitle.strip! if title
			
			title = @shorttitle ? shorttitle : title
			setname = node_tree.root.attributes['name'].value

			res = Game.LoadSingle(title, setname, @target.pkid)
			res = Game.new unless res
			
			res.target  = @target
			res.title   = title
			res.setname = setname
		
			res.ctrlmask = 0
			res.year = node_tree.xpath("//game/year").text
			res.year = res.year.to_i if (res.year) 
			res.year = 0 if res.year < 1900
			
			res.manufacturer = node_tree.xpath("//game/manufacturer").text
			res.system = "Arcade" # It might be possible to parse more out of the description
			res.family = @series[res.setname]
			if (@categories[res.setname])
				res.genre = @categories[res.setname][0]
				res.subgenre = @categories[res.setname][1]
			end
			
			driver = node_tree.xpath("//game/driver")[0]
			
			next if (driver == nil)
			next if (@onlygood and driver.attributes["status"].value != "good")

			node_input = node_tree.xpath("//game/input")[0]
			res.players = node_input.attributes["players"].value
			res.buttons = node_input.attributes["buttons"]
			res.buttons = res.buttons == nil ? 0 : res.buttons.value
			res.target  = @target

# currently just ignored, but there can be seriously weird combinations (wheel + paddle + stick + buttons + ...)
			node_input.children.each{|child|
				if (child and child.attributes["type"])
#				    inputlabel = convert_inputtype(child)
#				    res.ctrlmask = res.ctrlmask | res.get_mask( mmask ) if inputlabel
				end 
			}

			yield res
		end
	end

	def check_target(target, targetpath)
		@mametarget = nil
		executable = nil

		execs = ["mame", "mame.exe", 
			"mame64", "mame64.exe", 
			"ume", "ume.exe",
			"ume64", "ume64.exe"];

		execs.each{|ext|
			fullname = "#{targetpath}/#{ext}"
			
			if (File.exists?(fullname))
				@mametarget = fullname
				executable = ext
				break
			end
		}

		if (@mametarget == nil)
			STDERR.print("[MAME Importer] Couldn't locate MAME, giving up.\n")
			return false
		end
		
		@target = Target.Load(0, "mame")

		if (@target == nil)
			@target = Target.Create("mame", executable, @mameargs)
		else
			@target.arguments = @mameargs
			@target.store
		end

		return (File.exists?(@mametarget) and File.stat(@mametarget).executable?)
	end

	def check_games(rompath)
		romset = {}

# load these once (the same importer could possibly be used for more targets
		if @dbinit == false
			if (res = @options["--mamecatver"])
				merge_gameinfo( res[0] )
			elsif File.exists?("#{@basepath}/importers/catver.ini")
				merge_gameinfo("#{@basepath}/importers/catver.ini")
			end

			if (res = @options["--mameseries"])
				merge_relatives( res[0] )
			elsif File.exists?("#{@basepath}/importers/series.ini")
				merge_relatives("#{@basepath}/importers/series.ini")
			end
			
			@dbinit = true
		end

# to limit further, just check directory and the extensions zip, 7z, chd
		Dir["#{rompath}/*"].each{|fname| romset[ File.basename( fname, File.extname(fname) ) ] = true }

# extract XML from mame, parse it and check each setname against the romset table
# and propagate to caller if a match was found. optionally, use mame's own checking facility
# another option would be to have a sane database and just scan the ones found
		mame_each{|game| 
			if romset[game.setname] 
				if (@verify and checkrom(@mametarget, rompath, game.setname) == false)
					STDERR.print("[MAME Importer] romset (#{game.setname}) failed verification.\n")
				else 
					yield game
				end
			end
		}

# shold perhaps instead return a list of games for which there were no match (just
# set to false in romset when used, then iterate table for those still marked as true
		true

	rescue => er
		STDERR.print("[MAME importer] failed, reason: #{er}, #{er.backtrace}\n")
		false
	end

	def to_s
		"[MAME Importer]"
	end
end
