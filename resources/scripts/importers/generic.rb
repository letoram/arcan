# Generic importer,
# Uses the correlation between <rompath>/<foldername> with <targetpath>/<foldername>,
# Sets the name and target executable of the target to <foldername> (so that parameters 
# can be individualized later on anyhow by a alterdb on the target)
# --
# Would be somewhat fun to play around with heuristics + websearchengines and try to
# automatically deduce reasonable data for each target, but that's for the future ..
#

class Generic
	def initialize
		@gentargets = {}
		@genromlist = {}
	end

	def usage
		[
			"\ngeneric importer, first argument in each --gen*args must match targetname",
			"(--genargs) - comma-separated list of launch arguments",
			"(--genintargs) - comma- separated list of internal- launch arguments",
			"(--genextargs) - comma- separated list of external- launch arguments",
			"(--genrompath) targetname - encodes full rompath (as per --rompath) into the romset",
		]
	end

	def accepted_arguments
		[
			["--genrompath", GetoptLong::REQUIRED_ARGUMENT],
			["--genargs", GetoptLong::REQUIRED_ARGUMENT],
			["--genintargs", GetoptLong::REQUIRED_ARGUMENT],
			["--genextargs", GetoptLong::REQUIRED_ARGUMENT],
		]
	end

	def set_defaults(options, opts)
		chkargs = ["--genargs", "--genintargs", "--genextargs"]
	
		if (opts["--genrompath"] != nil)
			opts["--genrompath"].each{|tgt|
			@genromlist[tgt] = true
		}
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
		@genericpath = "#{targetpath}/#{target}"
		@titles = {}
		@targetname = target
		return false unless File.exists?(@genericpath) and File.executable?(@genericpath)
		
		@target = Target.Load(0, target)
		if (@target == nil)
			@target = Target.Create(target, target, @gentargets[target])
		elsif (@gentargets[target])
			@target.arguments = @gentargets[target]
			@target.store
		end

		true
	end

	def to_s
		"[Generic (#{@targetname}) Importer]"
	end

	def check_games(rompath)
		Dir["#{rompath}/*"].each{|fn|
			if (fn == "." || fn == "..") 
				next
			else
				setname = fn[ fn.rindex('/') +1 .. -1 ]

				newgame = Game.new
				newgame.title = setname
				newgame.setname = @genromlist[@targetname] == true ? fn : setname
				newgame.target = @target

				yield newgame
			end
		}
	end
end
