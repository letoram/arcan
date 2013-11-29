# Skeleton of a Mupen specific importer,
# Just a modified version of Mupen64Plus importer

class Mupen
	attr_accessor :target

	def initialize
		@mupenargs = []
		@mupenargs[0] = ["--noosd", "--nosaveoptions", "--datadir", "[gamepath]/mupen", "--plugindir", "[gamepath]/mupen"]
		@mupenargs[1] = ["--windowed", "--resolution 640x480", "[romsetfull]"]
		@mupenargs[2] = ["--fullscreen", "[romsetfull]"]
	end

	def usage
		[
			"Mupen64Plus Importer Arguments:",
			"(--mupenargs) - comma- separated list of launch arguments",
			"(--mupenintargs) - comma- separated list of internal- launch arguments",
			"(--mupenextargs) - comma- separated list of external- launch arguments",
			""
		]
	end

	def accepted_arguments
		[
			["--mupenargs", GetoptLong::REQUIRED_ARGUMENT],
			["--mupenintargs", GetoptLong::REQUIRED_ARGUMENT],
			["--mupenextargs", GetoptLong::REQUIRED_ARGUMENT]
		]
	end

	def set_defaults(basepath, options, opts)	
		chkargs = ["--mupenargs", "--mupenintargs", "--mupenextargs"]
		chkargs.each_with_index{|argstr, ind|
			if (arg = opts[argstr])
				arg.each{|subarg|
					subargs = subarg.split(/,/)
					if (subargs.size < 1)
						STDERR.print("[MUPEN Importer] couldn't set #{argstr}, format; arg1,arg2,...")
						return false
					else
						@mupenargs[ind] = subargs
					end
				}	
			end
		}
	
		true
	end
	
	def check_target(target, targetpath)
		@mupenpath = nil;
		@titles = {}

		execs = ["n64", "mupen64plus.exe", "mupen64plus", "mupen"]

		execs.each{|ext|
			fullname = "#{targetpath}/#{ext}"
			
			if (File.exists?(fullname))
				@mupentarget = fullname
				executable = ext
				break
			end
		}

		if (@mupentarget == nil)
			return false
		end
	
		# GRAB TARGET mupen
		@target = Target.Load(0, "mupen")
		if (@target == nil)
			@target = Target.Create("mupen", "mupen", @mupenargs)
		else
			@target.arguments = @mupenargs
			@target.store
		end

		return (File.exists?(@mupentarget) and File.stat(@mupentarget).executable?)
	end

	def to_s
		"[Mupen64Plus Importer]"
	end

	def check_games(rompath)
		Dir["#{rompath}/*.*64"].each{|fn|
			if (fn == "." || fn == "..")
				next
			else
				setname = fn[ fn.rindex('/') +1 .. -1 ]
				newgame = Game.LoadSingle(setname, setname, @target.pkid)
				newgame = Game.new unless newgame
				newgame.title = setname
				newgame.setname = setname
				newgame.target = @target
				newgame.players = 1
				newgame.buttons = 0
				newgame.ctrlmask = newgame.get_mask("trackball")
				newgame.pkid = 0
				newgame.genre = ""
				newgame.year = 0
				newgame.system = ""
				newgame.manufacturer = ""

				yield newgame
			end
		}
	end
end
