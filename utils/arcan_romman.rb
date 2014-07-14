#!/usr/bin/ruby
#
# Simple wrapper / loader script that ought to reside in the same folder 
# as the main application binaries. Tries to locate the resource folder
# in use, where the main script is, along with importers.
#
require 'rbconfig'

#
# although the program was initially designed to be driven from the command-line entirely,
# the UI library situation in Ruby is so terrible that the safer and more portable choice is (!)
# to use Webrick to set-up a local webserver, and Watir to spawn a browser and navigate to this server
# as an "alternative" UI. 
#

unless File.respond_to? :realpath
	require 'pathname'
	class File
		def File.realpath(path)
			a = Pathname.new(path)
			a.realpath
		rescue
			nil
		end
	end
end

is_windows = (RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/)

searchpath = [".", 
	"./resources/scripts", 
	"./scripts", 
	"../resources/scripts", 
	"#{ENV["HOME"]}/.arcan/resources/scripts", 
	"/usr/local/share/arcan/resources/scripts", 
	"/usr/share/arcan/resources/scripts"]
searchpath.insert(0, ENV['ARCAN_RESOURCEPATH']) if ENV['ARCAN_RESOURCEPATH']

basepath = nil

searchpath.each{|path|
	if (File.exists?("#{path}/romman_base.rb"))
		basepath = path
		break
	end
}

def show_usage
STDOUT.print "Arcan Romman (romman.rb) #{ROMMAN_VERSION ? ROMMAN_VERSION : "(basescripts not found)"}, usage:\n\
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
(--nogeneric) - Don't use generic importer for unknown targets\n\
(--update) - Only add new games, don't rebuild the entire database\n\
(--skipgroup) groupname - Don't try to import the specified games\group folder (can be used several times)\n\
(--scangroup) groupname - Only scan the specified games\group folder (can be used several times)\n\n\
"
begin	Importers.Each_importer{|imp|
		line = imp.usage.join("\n")
		STDOUT.print(line)
		STDOUT.print("\n") if (imp.usage.size > 0)
	}
rescue => er
 end

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

if (!basepath)
	show_usage()
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
	[ '--nogeneric', GetoptLong::NO_ARGUMENT ],
	[ '--generic', GetoptLong::NO_ARGUMENT ],
	[ '--update', GetoptLong::NO_ARGUMENT ],
	[ '--skipgroup', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--scangroup', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--deletegame', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--deletetarget', GetoptLong::REQUIRED_ARGUMENT ],
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
	:generic => true,
	:rompath => "#{basepath}/../games",
	:targetpath => "#{basepath}/../targets",
	:resetdb => false,
	:dbname => "#{basepath}/../arcandb.sqlite",
	:frameserver => "./arcan_frameserver",
	:execlaunch => false,
	:execmode => "external",
	:skipgroup => {},
	:in_windows => is_windows
}

if (is_windows) 
	options[:frameserver] = "./arcan_frameserver.exe"
else
	["./arcan_frameserver_libretro", "/usr/bin/arcan_frameserver_libretro", "/usr/local/bin/arcan_frameserver_libretro", "./arcan_frameserver", "/usr/bin/arcan_frameserver", "/usr/local/bin/arcan_frameserver"].each{|a|
		if File.exists?(a)
			options[:frameserver] = a
			break
		end
	}
end

# expand with the options from each found importer
Importers.Each_importer{|imp|
	imp.accepted_arguments.each{|arg|
		genericopts << arg
	}
}

# now just map all the set ones into a big table
opttbl = {}
GetoptLong.new( *genericopts ).each { |opt, arg|
	addarg = arg ? arg : opt

	unless (opttbl[opt])
		opttbl[opt] = []
	end

	opttbl[opt] << addarg
}

# map in the pseudo-parsed arguments untop of the default arguments already set,
opttbl.each_pair{|key, val| 
	key = key[2..-1].to_sym

#if (options[key] == nil)
#ext
#end
                
	options[key] = true
	options[key] = val[0] if val and val.size == 1
}

# rest is just mapping special arguments to opttable
# and to corresponding functions in romman_base

if (opttbl["--help"])
	show_usage()
	exit(0)
end

dbpath = File.exists?(options[:dbname]) ? File.realpath(options[:dbname]) : options[:dbname]

STDOUT.print("[Arcan Romman] Settings:\n rompath:\t #{File.realpath(options[:rompath])} \n targetpath:\t #{File.realpath(options[:targetpath])} \n dbpath:\t #{dbpath}\n");

if (arg = opttbl["--scangroup"])
	options[:scangroup] = []

	arg.each{|scangrp|
		options[:scangroup] << scangrp
	}
end

if (arg = opttbl["--nogeneric"])
	options[:generic] = false
end

if (arg = opttbl["--skipgroup"])
	arg.each{|group|
		options[:skipgroup][group] = true
	}
end

if (opttbl["--internal"])
	options[:execmode] = "internal"
end

case cmd
	when "builddb" then
		STDOUT.print("[builddb] Scanning importers\n")
		options[:resetdb] = true

		if (arg = opttbl["--update"])
			options[:resetdb] = false
		end
		
		Importers.Each_importer{|imp|
			STDOUT.print("\t#{imp.class}\n")
			imp.set_defaults(basepath, options, opttbl)
		}

		import_roms(options)

	when "list" then
		list(options)

	when "alterdb" then
		alterdb(options)

	when "exec" then
		execstr(options)
end

if (is_windows)
	STDOUT.print("Press Enter To Close...\n");
	STDIN.getc	
end
