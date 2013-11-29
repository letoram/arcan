# Skeleton of a ScummVM specific importer,
# Currently just matches the output of the ScummVM target with --list-games
# to the games detected. There really should be a database- source for 
# more specific details (subgenre for finding games targeting children,
# along with year, manufacturer,  ...)

class ScummVM 
	attr_accessor :target

	def initialize
		@scummargs = [ [], [], [] ]
	end

	def usage
		[
			"ScummVM Importer Arguments:",
			"(--scummargs) - comma- separated list of launch arguments",
			"(--scummintargs) - comma- separated list of internal- launch arguments",
			"(--scummextargs) - comma- separated list of external- launch arguments",
			""
		]
	end

	def accepted_arguments
		[
			["--scummargs", GetoptLong::REQUIRED_ARGUMENT],
			["--scummintargs", GetoptLong::REQUIRED_ARGUMENT],
			["--scummextargs", GetoptLong::REQUIRED_ARGUMENT]
		]
	end

	def set_defaults(basepath, options, opts)
		chkargs = ["--scummargs", "--scummintargs", "--scummextargs"]
		chkargs.each_with_index{|argstr, ind|
			if (arg = opts[argstr])
				arg.each{|subarg|
					subargs = subarg.split(/,/)
					if (subargs.size < 1)
						STDERR.print("[SCUMMVM Importer] couldn't set #{argstr}, format; arg1,arg2,...")
						return false
					else
						@scummargs[ind] = subargs
					end
				}	
			end
		}

		true
	end
	
	def check_target(target, targetpath)
		@scummpath = nil; 
		@titles = {}
		
		execs = ["", ".exe"];
		execs.each{|ext|
			fullname = "#{targetpath}/#{target}#{ext}"
			if (File.exists?(fullname))
				@scummpath = fullname
				break
			end
		}
		
		if (@scummpath == nil)
			STDERR.print("[SCUMMVM importer] cannot find scummvm binary at #{@scummpath}, skipping.\n")
			return false
		end

		if (IO.popen("#{@scummpath} --version").readlines.join("").lines.grep(/ScummVM/).size == 0)	
			STDERR.print("[SCUMMVM importer] version check failed, skipping.\n")
			return false
		end

		lines = IO.popen("#{@scummpath} --list-games").readlines
 		lines[2..-1].each{|line|
			args = line.split(/\s{2,}/)
			setname = args[0]
			title = args[1].strip
			@titles[setname] = title
		}

		# GRAB TARGET scummvm
		@target = Target.Load(0, "scummvm")
		if (@target == nil)
			@target = Target.Create("scummvm", "scummvm", @scummargs)
		else
			@target.arguments = @scummargs
			@target.store
		end

		true
	end

	def to_s
		"[ScummVM Importer]"
	end

	def check_games(rompath, group)
		Dir["#{rompath}/*"].each{|fn|
			if (fn == "." || fn == ".." || File.directory?(fn) == false) 
				next
			else
				setname = fn[ fn.rindex('/') +1 .. -1 ]
				
				if (@titles[setname])
					newgame = Game.LoadSingle(@titles[setname], setname, @target.pkid)
					newgame = Game.new unless newgame
					newgame.title = @titles[setname]
					newgame.setname = setname
					newgame.target = @target
					newgame.players = 1
					newgame.buttons = 0
					newgame.ctrlmask = newgame.get_mask("trackball")
					newgame.pkid = 0
					newgame.genre = "Adventure"
					newgame.year = 0
					newgame.system = "(SCUMM)"
					newgame.manufacturer = ""
					newgame.arguments[1] = ["-F", "#{setname}"]
					newgame.arguments[2] = ["-f", "#{setname}"]
					newgame.arguments[0] = ["-n", "-p", "[gamepath]/scummvm/#{setname}"]

					yield newgame
				end
			end
		}
	end
end
