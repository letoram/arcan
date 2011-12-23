#!/usr/bin/ruby
#
# Simple wrapper / loader script that ought to reside in the same folder 
# as the main application binaries. Tries to locate the resource folder
# in use, where the main script is, along with importers.

searchpath = [".", "./resources/scripts", "#{ENV["HOME"]}/.arcan/resources/scripts", "/usr/local/share/arcan/resources/scripts", "/usr/share/arcan/resources/scripts"]

searchpath.insert(0, ENV['ARCAN_RESOURCEPATH']) if ENV['ARCAN_RESOURCEPATH']

basepath = nil

searchpath.each{|path|
	if (File.exists?("#{path}/romman_base.rb"))
		basepath = path
		break
	end
}
	
if (!basepath)
	STDERR.print("Fatal, could not find romman_base.rb (should reside in resources/scripts)\n")
	exit(1)
end
		
load "#{basepath}/romman_base.rb"


# just split based on ',', allow '\' to make the next character stick
def argsplit( inarg )
	res = []
	ignore = false
	buf = ""
	inarg.each_char{|ch|
		case ch
			when '\\' then
	               ignore = true
			when ',' then
					if (ignore)
						buf << ch
						ignore = false
	               else
						res << buf if buf.length > 0
						buf = ""
	               end
		else
			buf << ch
			ignore = false
		end
	}
	
	res << buf if buf.length > 0
	res
end

def show_usage
STDOUT.print "Arcan Romman (romman.rb) #{ROMMAN_VERSION}, usage:\n\
romman.rb command generic-options command-specific arguments\n\
\n\
valid commands:\n\
builddb - scans roms/targets and creates a database\n\
list - shows single or multiple entries that match specified search criteria\n\
alterdb - manually add or change single entries in the database\n\
exec - show the arguments that would be used to launch a specific game\n\
\n\
generic options:\n\
(--help, -h) - this text\n\
(--dbname) (filename) - set the input/output database\n\
(--rompath) (path) - use path as root for finding roms\n\
(--targetpath) (path) - use path as root for finding targets\n\
\n\
builddb options:\n\
(--generic) - Use generic importer for unknown targets\n\
(--skiptarget) targetname - Don't try to import the specified target\n\
"
	Importers.Each_importer{|imp|
		line = imp.usage.join("\n")
		STDOUT.print(line)
		STDOUT.print("\n") if (imp.usage.size > 0)
	}

STDOUT.print "\n\
alterdb options:\n\
(--deletegame) title - Remove matching title\n\
(--gameargs) title,arglist - Override target- specific arguments with arglist\n\
(--gameintargs) title,arglist - Override target arguments for internal launch\n\
(--gameextargs) title,arglist - Override target arguments for external launch\n\
(--addgame) title,tgtnme,stnme,optfld=value - Add a game entry, optfields:\n\
\tplayers (num), buttons (num), ctrlmask (specialnum), genre (text),\n\
\tsubgenre (text),year (num), launch_counter (num), manufacturer (text)\n\
(--deletetarget) target - Remove target and all associated games\n\
(--addtarget) name,executable - Manually add the specified target\n\
(--targetargs) name,arglist - Replace the list of shared arguments\n\
(--targetintargs) name,arglist - Replace the list of internal launch arguments\n\
(--targetextargs) name,arglist - Replace the list of external launch arguments\n\
\n\
list options:\n\
(--gamesbrief) - List all available game titles\n\
(--targets) - List all available targets\n\
(--showgame) title - Display verbose information for a specific title (* wildcard)\n\
\n\
exec options:\n\
(--execgame) - Required, sets the game to generate execution arguments for\n\
(--internal) - Use arguments intended for internal launch mode\n\
(--execlaunch) - Run the execstr\n\
"
end

# scan importers/* folder,
# load and record classes introduced to the namespace
# uses these classes to populate the "usage" description
# and command-line arguments
Importers.Load(basepath)

# the first argument is always command, grab that before
# letting GetoptLong mess things up. 
cmdlist = ["builddb", "list", "alterdb", "exec"]
cmd = ARGV.shift
unless (cmdlist.grep(cmd).size > 0)
	STDOUT.print("Unknown command: #{cmd}\n\n")
	show_usage()
	exit(1)
end

genericopts = [
	[ '--help', GetoptLong::NO_ARGUMENT ], 
	[ '--dbname', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--rompath', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--targetpath', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--generic', GetoptLong::NO_ARGUMENT ],
	[ '--skiptarget', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--deletegame', GetoptLong::REQUIRED_ARGUMENT],
	[ '--deletetarget', GetoptLong::REQUIRED_ARGUMENT],
	[ '--showgame', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--gamesbrief', GetoptLong::NO_ARGUMENT ],
	[ '--execgame', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--internal', GetoptLong::NO_ARGUMENT ],
	[ '--launch', GetoptLong::NO_ARGUMENT ],
	[ '--targets', GetoptLong::NO_ARGUMENT ], 
	[ '--gameargs', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--gameintargs', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--gameextargs', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--addgame', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--addtarget', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--altertarget', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--targetargs', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--targetintargs', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--targetextargs', GetoptLong::REQUIRED_ARGUMENT ]
]

# defaultopts, these should work for both
# "relative" and "absolute" (since they translate to
# rompath/targetpath in the main app as well)

options = {
	:generic => false,
	:rompath => "#{basepath}/../games",
	:targetpath => "#{basepath}/../targets",
	:resetdb => true,
	:dbname => "#{basepath}/../arcandb.sqlite",
	:execlaunch => false,
	:execmode => "external",
	:skiptarget => {}
}

Importers.Each_importer{|imp|
	imp.accepted_arguments.each{|arg|
		genericopts << arg
	}
}

opttbl = {}
GetoptLong.new( *genericopts ).each { |opt, arg|
	addarg = arg ? arg : opt

	unless (opttbl[opt])
		opttbl[opt] = []
	end

	opttbl[opt] << addarg
}

# rest is just mapping arguments to opttable
# and to corresponding functions in romman_base

if (opttbl["--help"])
	show_usage()
	exit(0)
end

if (arg = opttbl["--skiptarget"])
	options[:skiptarget] = {}
	arg.each{|skiptgt|
		options[:skiptarget][skiptgt] = true
	}
end

# map in the pseudo-parsed arguments untop of the 
# default arguments already set
opttbl.each_pair{|key, val| 
	key = key[2..-1].to_sym
	options[key] = true
	options[key] = val[0] if val and val.size == 1
}

if (opttbl["--internal"])
	options[:execmode] = "internal"
end

case cmd
	when "builddb" then
		STDOUT.print("[builddb] Scanning importers\n")
		
		Importers.Each_importer{|imp|
			STDOUT.print("\t#{imp.class}\n")
			imp.set_defaults(options, opttbl)
		}

		import_roms(options)

	when "list" then
		list(options)

	when "alterdb" then
		alterdb(options)

	when "exec" then
		execstr(options)
end

