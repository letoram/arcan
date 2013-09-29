#!/usr/bin/ruby
keys = [
"RESOURCE", "CONTROL", "DATABASE",
"AUDIO", "IMAGE", "3D", "SYSTEM",
"IODEV", "VIDSYS", "NETWORK" 
]

def add_function(groupname, symname, cname)
	fn = "#{symname}.lua"
	if (File.exists?(fn))
# 
# should checksum C source function, compare to
# whatever is stored in the .lua file header
# and alter the user if the function has changed 
# (i.e. documentation might need to be updated)
	# 
		else
			STDOUT.print("--- new function found: #{symname}\n")
			outf = File.new(fn, IO::CREAT | IO::RDWR)
			outf.print("-- #{symname}\n\
-- @short: \n\
-- @inargs: \n\
-- @outargs: \n\
-- @longdescr: \n\
-- @group: #{groupname} \n\
-- @cfunction: #{cname}\n\
-- @related:\n\
\
function main()
\#ifdef MAIN
\#endif

\#ifdef ERROR1
\#endif
end\n") end
end

def cscan(cfun)
	in_grp = false
	File.open("../arcan_lua.c").each_line{|line|
	if (not in_grp and line =~ /\#define\sEXT_MAPTBL_(\w+)/)
		in_grp = $1
	elsif (in_grp)
			if (line =~ /\#undef\sEXT_MAPTBL_(\w+)/)
				in_grp = nil
			else
				line =~ /\{\"([a-z0-9_]+)\",\s*([a-z0-9_]+)\s*\}/
				if ($1 != nil and $2 != nil) then
					send(cfun, in_grp.downcase, $1, $2)
				end
			end
		end
	}
end

$grouptbl = {};
def scangroups(group, sym, csym)
	if ($grouptbl[group] == nil) then
		$grouptbl[group] = [];
	end
	$grouptbl[group] << sym;
end

def scangrp(inf)
	line = "";
	res = {};
	group = "unknown";

	while ( (line = inf.readline)[0..2] == "-- ") do
		if line[0..3] == "-- @"
			group = line[4..line.index(":")-1]
			msg = line[(line.index(":")+1)..-1];
			if (msg != nil)
				msg.strip!
				res[group] = msg if msg.length > 0
			end
		else
			res[group] << line[3..-1].strip;
		end
	end
	
	return res, line	

rescue
	return res, ""
end

def funtoman(fname)
	cgroup = nil;
	inexample = false;

	outm = File.new("man/#{fname}.3", IO::CREAT | IO::RDWR)
	outm << ".\\\" groff -man -Tascii #{fname}.3\n";
	outm << ".TH #{fname} 3 \"October 2013\" arcan \"Arcan API Reference\"";

	inf = File.open("#{fname}.lua")
	shortnm = inf.readline()[3..-1].strip
	outm << ".SH #{shortnm}\n"

	groups, line = scangrp(inf)
	p line
	groups.each_pair{|group, line|
		workstr = line.strip
		if (workstr.length > 0)
			outm << ".SH #{group}\n"
			outm << workstr << "\n"
		end
	}
end

if (ARGV[0] == "scan")
	cscan(:add_function)
elsif (ARGV[0] == "mangen")
	cscan(:scangroups)
	inf = File.open("arcan_api_overview_hdr")
	File.delete("arcan_api_overview.1")
	outf = File.new("arcan_api_overview.1", IO::CREAT | IO::RDWR)
	inf.each_line{|line| outf << line}
	
# setup default intro manpage by taking the stub and then attaching
# group references to the other manpages
	$grouptbl.each_pair{|key, val|
		gotc = false
		outf << ".SH #{key}\n"
		val.each{|i|
			if gotc == false
				outf << "\\&\\fI#{i}\\fR\\|(3)"
				gotc = true
			else
				outf << ",\\&\\fI#{i}\\fR\\|(3)"
			end
			outf << "\n"
			funtoman(i)
		}
	}
	inf = File.open("arcan_api_overview_ftr").each_line{|line|
		outf << line;
	}
	

else
	STDOUT.print("Usage: ruby docgen.rb command\nscan:\n\
scrape arcan_lua.c and generate stubs for missing corresponding .lua\n\n\
mangen:\n sweep each .lua file and generate corresponding manpages.\n")
end
