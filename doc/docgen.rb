#!/usr/bin/ruby

def scangrp(inf)
	line = "";
	res = {};
	group = "unknown";

	while ( (line = inf.readline)[0..2] == "-- ") do
		if line[0..3] == "-- @"
			group = line[4..line.index(":")-1]
			msg = line[(line.index(":")+1)..-1];
			if (res[group] == nil) then
				res[group] = []
			else
			end

			if (msg != nil)
				msg.strip!
				res[group] << msg if msg.length > 0
			end
		else
			res[group] << line[3..-1].strip;
		end
	end
	
	return res, line	

rescue => er
	STDERR.print("parsing error, #{er} while processing " \
							 "(#{inf.path}\n lastline: #{line}\n")
	return res, ""
end

class String
	def join(a)
		"#{self}#{a}"
	end
end

class DocReader
	def initialize
		@short = ""
		@inargs = []
		@outargs = []
		@longdescr = ""
		@group = ""
		@cfunction = ""
		@related = []
		@note = []
		@example = ""
		@main_tests = []
		@error_tests = []
	end

	def incomplete?
		return @short.length == 0
	end

	def DocReader.Open(fname)
		a = File.open(fname)
		if (a == nil) then
			return
		end

		a.readline # skip first line (just the function name)
		res = DocReader.new
		groups, line = scangrp(a)
		groups.each_pair{|a, v|
			if res.respond_to? a.to_sym
				res.send("#{a}=".to_sym, v);
			end	
		}

		res	
	rescue
		nil	
	end

	def note=(v)
		@note << v
	end

	attr_accessor :short, :inargs, :outargs, 
		:longdescr, :group, :cfunction, :related, 
		:example, :main_tests, :error_tests

	attr_reader :note

	private :initialize
end

def find_empty()
	Dir["*.lua"].each{|a|
		if ( DocReader.Open(a).incomplete? ) then
			yield a
		end	
	}

	nil
end

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

#
# Parse the C binding file. look for our preprocessor 
# markers, extract the lua symbol, c symbol etc. and 
# push to the function pointer in cfun
#
def cscan(cfun)
	in_grp = false
	File.open("../engine/arcan_lua.c").each_line{|line|
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

$grouptbl = {}
def scangroups(group, sym, csym)
	if ($grouptbl[group] == nil) then
		$grouptbl[group] = []
	end
	$grouptbl[group] << sym
end

def troffdescr(descr)
	a = descr.join("\n")
  a.gsub!(/\*(\w+)\*/, "\\fI \\1 \\fR ") 
	a.gsub!("  ", " ")	
end

def funtoman(fname)
	cgroup = nil
	inexample = false

	inf = DocReader.Open("#{fname}.lua")
	outm = File.new("mantmp/#{fname}.3", IO::CREAT | IO::RDWR)
	outm << ".\\\" groff -man -Tascii #{fname}.3\n"
	outm << ".Th \"#{fname}\" 3 \"#{Time.now.strftime("%B %Y")}\" \"Arcan LUA API\"\n"
	outm << ".Sh NAME\n"
	outm << ".Nm #{fname}\n"
	outm << ".Nd #{inf.short.join(" ")}\n"
	outm << ".Sh SYNOPSIS\n"

	if (inf.outargs.size > 0)
		outm << ".Ft #{inf.outargs.join("\n.Ft ")}\n"
	end

	inf.inargs.size.times{|a|
		inf.inargs[a].gsub!(/\,/, " ")
	}

	outm << ".Fo #{fname}\n"
	if (inf.inargs.size > 0)
		outm << ".Fa #{inf.inargs.join("\n.Fa ")} \n"
	end
	outm << ".Fc\n"

	if (inf.longdescr.size > 0)
		outm << ".Sh DESCRIPTION\n"
		outm << troffdescr(inf.longdescr)
		outm << "\n"
	end

	if (inf.note.size > 0)
		outm << ".Sh NOTE\n"
		inf.note.each{|a| 
			outm << a
		}
		outm << "\n"
	end

	if (inf.example.size > 0)
		outm << ".SH EXAMPLE"
		outm << inf.example.join("\n")
		outm << "\n"
	end

	if (inf.related.size > 0)
		outm << ".Sh SEE ALSO:\n"
		outm << "\n"
	end

#	inf = File.open("#{fname}.lua")
#	shortnm = inf.readline()[3..-1].strip
#	outm << ".SH #{shortnm}\n"

#	groups, line = scangrp(inf)
#	groups.each_pair{|group, line|
#		workstr = line.join("\n").strip
#		if (workstr.length > 0)
#			outm << ".SH #{group}\n"
#			outm << workstr << "\n"
#		end
#	}
rescue => er
	STDERR.print("Failed to parse/generate (#{fname} reason: #{er}\n #{er.backtrace.join("\n")})\n")
end

if (ARGV[0] == "scan")
	cscan(:add_function)

elsif (ARGV[0] == "lookup")
	DocReader.Open("#{ARGV[1]}.lua")		

elsif (ARGV[0] == "missing")
	find_empty(){|a|
		STDOUT.print("#{a} is incomplete.\n")
	}

elsif (ARGV[0] == "mangen")
# add preamble / header to the overview file,
	inf = File.open("arcan_api_overview_hdr")

	if (Dir.exists?("mantmp"))
		Dir["mantmp/*"].each{|a| File.delete(a) }
	else
		Dir.mkdir("mantmp")
	end

	outf = File.new("mantmp/arcan_api_overview.1", IO::CREAT | IO::RDWR)
	inf.each_line{|line| outf << line}

# populate $grptbl with the contents of the lua.c file	
	cscan(:scangroups)

# add the functions of each group to a section in the
# overview file
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

	outf.close

else
	STDOUT.print("Usage: ruby docgen.rb command\nscan:\n\
scrape arcan_lua.c and generate stubs for missing corresponding .lua\n\n\
mangen:\n sweep each .lua file and generate corresponding manpages.\n\n\
lookup function_name:\n generate a quick-reference \n\n\
missing:\n scan all .lua files and list those that are incomplete.\n")
end
