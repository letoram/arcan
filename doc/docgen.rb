#!/usr/bin/ruby
require 'fileutils'

def scangrp(inf)
	line = ""
	res = {}
	group = "unknown"

	while ( (line = inf.readline)[0..1] == "--") do
# special paragraph break
		if line[0..2] == "--\n"
			res[group] << ""

# switch group
		elsif line[0..3] == "-- @"
			group = line[4..line.index(":")-1]
			msg = line[(line.index(":")+1)..-1]
			if (res[group] == nil) then
				res[group] = []
			else
				res[group] << ""
			end

# some groups have a header
			res[group] << msg.strip if msg != nil
# more data
		else
			res[group] << line[3..-1].strip
		end
	end

	return res, line

rescue => er
	STDERR.print("parsing error, #{er} while processing " \
		"(#{inf.path}\n lastline: #{line}\n"
	)
	return res, ""
end

class String
	def join(a)
		"#{self}#{a}"
	end
end

# run through the list of lines through the C pre-parser, this is used multiple
# times with MAIN, MAIN2, ERROR1, ... defined in order to both generate test
# cases and for manpage examples
def extract_example(lines, defs)
	res = []
	iobj = IO.popen(
		"cpp -pipe -fno-builtin -fno-common #{defs}",
		File::RDWR
	)
	iobj.print(lines)
	iobj.close_write
	iobj.each_line{|a|
		if (a[0] == "#" or a.strip == "")
			next
		end
		line = a.gsub(/\n/, "")
		line = ("     " * line[/\A */].size) << line
		res << line;
	}
	iobj.close_read
	res
end

def extract_examples(name, inlines)
	res_ok = []
	res_fail = []

	base_sz = extract_example(inlines, "").size

	10.times{|a|
		suff = a == 0 ? "" : (a + 1).to_s
		lines = extract_example(inlines, "-DMAIN#{suff} -Dmain=#{name}#{a}")
		if (lines.size == base_sz)
			break
		else
			res_ok << lines.join("\n")
		end
	}

	10.times{|a|
		suff = a == 0 ? "" : (a + 1).to_s
		lines = extract_example(inlines, "-DERROR#{suff} -Dmain=#{name}#{a}")
		if (lines.size == base_sz)
			break
		else
			res_fail << lines.join("\n")
		end
	}

	return res_ok, res_fail
end

#
# Missing;
# alias, flags
#
class DocReader
	def initialize
		@short = ""
		@inargs = []
		@outargs = []
		@longdescr = ""
		@group = ""
		@cfunction = ""
		@error = []
		@related = []
		@note = []
		@examples = [ [], [] ]
		@main_tests = []
		@error_tests = []
	end

	def incomplete?
		return @short.length == 0
	end

	def DocReader.Open(fname)
		typetbl = {
			"int" => true,
			"inttbl" => true,
			"bool" => true,
			"float" => true,
			"floattbl" => true,
			"str" => true,
			"strtbl" => true,
			"vid" => true,
			"vidtbl" => true,
			"aidtbl" => true,
			"func" => true,
		}
		a = File.open(fname)
		if (a == nil) then
			return
		end

		res = DocReader.new
		res.name = a.readline[3..-1].strip
		groups, line = scangrp(a)
		groups.each_pair{|a, v|
			if res.respond_to? a.to_sym
				res.send("#{a}=".to_sym, v);
			end
		}

		while (line.strip! == "")
			line = a.readline
			if (line == nil) then
				return res
			end
		end

		lines = a.readlines
		lines.insert(0, line)
		remainder = lines.join("\n")

		main = ""
		ok, err = extract_examples(res.name, remainder)
		res.examples[ 0 ] = ok
		res.examples[ 1 ] = err

# verify the inargs field to make sure that it is typed
		res.inargs.delete_if{|a| a.length == 0}
		res.outargs.delete_if{|a| a.length == 0}
		res.inargs.each{|a|
			largs = a.split(/,/)
			largs.each{|b|
				type = b.split(/:/)
				if (not type or type.size != 2)
					res.error << "missing type on #{b}"
					next
				end
				res.error << "unknown type #{type[0]}" unless typetbl[type[0]]
			}
		}

		res

	rescue EOFError
		res
	rescue => er
					p er
					p er.backtrace
		nil
	end

	def note=(v)
		@note << v
	end

	def ok?()
		return @error.length == 0
	end

	attr_accessor :short, :inargs, :outargs,
		:longdescr, :group, :cfunction, :related,
		:examples, :main_tests, :error_tests, :name, :error

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

def find_old()
	Dir["*.lua"].each{|a|
		doc = DocReader.Open(a)
		unless (doc.ok? ) then
			yield a, doc.error
		end
	}
end

def add_function(groupname, symname, cname)
	fn = "#{symname}.lua"
	if (File.exists?(fn))
		true
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
end\n")
	end
end

#
# Parse the C binding file. look for our preprocessor
# markers, extract the lua symbol, c symbol etc. and
# push to the function pointer in cfun
#
def cscan(cfun, cfile)
	in_grp = false
  linec = 0
	File.open(cfile).each_line{|line|
		linec = linec + 1
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
rescue
	STDOUT.print("exception at line #{linec}")
end

$grouptbl = {}
def scangroups(group, sym, csym)
	if ($grouptbl[group] == nil) then
		$grouptbl[group] = []
	end
	$grouptbl[group] << sym
end

# special paragraphing fixups for *ROFF output (manpages) in
# the context @longdescr group
#
# empty -> \n.PP\n
# *bla* -> \n.I bla\n
# ref:function\w -> \n.BR function\n
# . text -> \n.IP
# \[A-Z_]1+ -> \n.B MSG\n
#
def troff_highlight_str(str)
	str.gsub!(/([A-Z_]{2,})/, "\n.B \\1\n\\\\&")
	str.gsub!(/\*([a-z_]{2,})\*/, "\n.I \\1\n\\\\&")
	str.gsub!(/ref:(\w{2,})/, "\n.BR \\1 \n\\\\&")
	str
end

def troffdescr(descr)
	out = ""
	descr.each{|block|
		case block
			when "" then out << "\n.PP\n"
			when /^\.\s/ then out << troff_highlight_str("\n.B #{block[2..-1]} \n")
		else
			out << troff_highlight_str(block) << " "
		end
	}

	out.strip
end

# template:
# .TH PRJ 3 "Date" System "Group"
# .SH NAME
# function \- descr
# .SH SYNOPSIS
# .I retval
# .B fname
# .R (
# .I arg
# .I arg2
# .R )
# .SH DESCRIPTION
# .B somethingsomething
# somethingsoemthing
# .BR highlight
# something
# .SH NOTES
# .IP seqn.
# descr
# .SH EXAMPLE
# if present
# .SH SEE ALSO
#

def funtoman(fname, outm)
	cgroup = nil

	inf = DocReader.Open("#{fname}.lua")
	outm << ".\\\" groff -man -Tascii #{fname}.3\n"
	outm << ".TH \"#{fname}\" 3 \"#{Time.now.strftime(
		"%B %Y")}\" #{inf.group[0]} \"Arcan Lua API\"\n"
	outm << ".SH NAME\n"
	outm << ".B #{fname} \ - \n#{inf.short.join(" ")}\n"
	outm << ".SH SYNOPSIS\n"

	if (inf.outargs.size > 0)
		outm << ".I #{inf.outargs.join(", ")}\n"
	else
		outm << ".I nil \n"
	end

	if (inf.inargs.size == 0)
		outm << ".br\n.B #{fname}()\n"
	else
		inf.inargs.each{|argf|
			outm << ".br\n.B #{fname}(\n"
			tbl = argf.split(/\,/)
			tbl.each_with_index{|a, b|
				if (a =~ /\*/)
					outm << "\n.I #{a.gsub(/\*/, "").gsub("  ", " ").strip}"
				else
					outm << "#{a.strip}"
				end

				if (b < tbl.size - 1) then
					outm << ", "
				else
					outm << "\n"
				end
			}
			outm << ")\n"
		}
	end

	if (inf.longdescr.size > 0)
		outm << ".SH DESCRIPTION\n"
		outm << troffdescr(inf.longdescr)
		outm << "\n\n"
	end

	if (inf.note.size > 0)
		outm << ".SH NOTES\n.IP 1\n"
		count = 1

		inf.note[0].each{|a|
			if (a.strip == "")
				count = count + 1
				outm << ".IP #{count}\n"
			else
				outm << "#{troff_highlight_str(a)}\n"
			end
		}
	end

	inf.examples[0].each{|a|
		outm << ".SH EXAMPLE\n.nf \n\n"
		outm << a
		outm << "\n.fi\n"
	}

	inf.examples[1].each{|a|
		outm << ".SH MISUSE\n.nf \n\n"
		outm << a
		outm << "\n.fi\n"
	}

	if (inf.related.size > 0)
		outm << ".SH SEE ALSO:\n"
		inf.related[0].split(",").each{|a|
			outm << ".BR #{a.strip} (3)\n"
		}
		outm << "\n"
	end

rescue => er
	STDERR.print("Failed to parse/generate (#{fname} reason: #{er}\n #{
		er.backtrace.join("\n")})\n")
end

case (ARGV[0])
when "scan" then
	cf = ENV["ARCAN_SOURCE_DIR"] ?
		"#{ENV["ARCAN_SOURCE_DIR"]}/engine/arcan_lua.c" :
		"../src/engine/arcan_lua.c"

	cscan(:add_function, cf)

when "vimgen" then

	kwlist = []

# could do something more with this, i.e. maintain group/category relations
	Dir["*.lua"].each{|a|
		a = DocReader.Open(a)
		kwlist << a.name
	}

	fname = ARGV[1]
	if fname == nil then
		Dir["/usr/share/vim/vim*"].each{|a|
			next unless Dir.exists?(a)
			if File.exists?("#{a}/syntax/lua.vim") then
				fname = "#{a}/syntax/lua.vim"
				break
			end
		}
	end

	if (fname == nil) then
		STDOUT.print("Couldn't find lua.vim, please specify on the command-line")
		exit(1)
	end

	consts = []
	if (File.exists?("constdump/consts.list"))
		File.open("constdump/consts.list").each_line{|a|
			consts << a.chop
		}
	else
		STDOUT.print("No constdump/consts.list found, constants ignored.\n\
run arcan with constdump folder to generate.\n")
	end

	lines = File.open(fname).readlines
	File.delete("arcan-lua.vim") if File.exist?("arcan-lua.vim")
	outf = File.new("arcan-lua.vim", IO::CREAT | IO::RDWR)

	last_ch = "b"
	lines[1..-5].each{|a|
		if (a =~ /let\s(\w+):current_syntax/) then
			last_ch = $1
			next
		end
		outf.print(a)
	}

	kwlist.each{|a|
		next if (a.chop.length == 0)
		outf.print("syn keyword luaFunc #{a}\n")
	}

	consts.each{|a|
		outf.print("syn keyword luaConstant #{a}\n")
	}

	outf.print("let #{last_ch}:current_syntax = \"arcan_lua\"\n")

	lines[-4..-1].each{|a| outf.print(a) }

when "testgen" then
	if ARGV[1] == nil or Dir.exist?(ARGV[1]) == false or
		ARGV[2] == nil or Dir.exist?(ARGV[2]) == false
		STDOUT.print("input or output directory wrong or omitted\n")
		exit(1)
	end

	indir = ARGV[1]
	outdir = ARGV[2]
	FileUtils.rm_r("#{outdir}/test_ok") if Dir.exists?("#{outdir}/test_ok")
	FileUtils.rm_r("#{outdir}/test_fail") if Dir.exists?("#{outdir}/test_fail")
	Dir.mkdir("#{outdir}/test_ok")
	Dir.mkdir("#{outdir}/test_fail")

	ok_count = 0
	fail_count = 0
	missing_ok = []
	missing_fail = []

	Dir["#{indir}/*.lua"].each{|a|
		doc = DocReader.Open(a)
		if (doc.examples[0].size > 0)
			ok_count += doc.examples[0].size
			doc.examples[0].size.times{|c|
				Dir.mkdir("#{outdir}/test_ok/#{doc.name}#{c}")
				outf = File.new("#{outdir}/test_ok/#{doc.name}#{c}/#{doc.name}#{c}.lua",
												IO::CREAT | IO::RDWR)
				outf.print(doc.examples[0][c])
				outf.close
			}
		else
			missing_ok << a
		end

		if (doc.examples[1].size > 0)
			fail_count += doc.examples[1].size
			doc.examples[1].size.times{|c|
				Dir.mkdir("#{outdir}/test_fail/#{doc.name}#{c}")
				outf = File.new(
					"#{outdir}/test_fail/#{doc.name}#{c}/#{doc.name}#{c}.lua",
					IO::CREAT | IO::RDWR
				)
				outf.print(doc.examples[0][c])
				outf.close
			}
		else
			missing_fail << a
		end
	}

	STDOUT.print("OK:#{ok_count},FAIL:#{fail_count}\n\
Missing OK:#{missing_ok.join(",")}\n\
Missing Fail:#{missing_fail.join(",")}\n")

when "verify" then
	find_empty(){|a|
		STDOUT.print("#{a} is incomplete (missing test/examples).\n")
	}

	find_old(){|a, b|
		STDOUT.print("#{a} dated/incorrect formatting: #{b}.\n")
	}

when "view" then
	funtoman(ARGV[1], STDOUT)

when "mangen" then
	inf = File.open("arcan_api_overview_hdr")

	if (Dir.exists?("mantmp"))
		Dir["mantmp/*"].each{|a| File.delete(a) }
	else
		Dir.mkdir("mantmp")
	end

	outf = File.new("mantmp/arcan_api_overview.3", IO::CREAT | IO::RDWR)
	inf.each_line{|line| outf << line}

# populate $grptbl with the contents of the lua.c file
	cf = ENV["ARCAN_SOURCE_DIR"] ? "#{ENV["ARCAN_SOURCE_DIR"]}/engine/arcan_lua.c" :
		"../src/engine/arcan_lua.c"

	cscan(:scangroups, cf)

# add the functions of each group to a section in the
# overview file
	$grouptbl.each_pair{|key, val|
		gotc = false
		outf << ".SH #{key}\n"
		val.each{|i|
			outf << "\\&\\fI#{i}\\fR\\|(3)\n"

			if File.exists?("#{fname}.lua")
				funtoman(i, File.new("mantmp/#{fname}.3", IO::CREAT | IO::RDWR))
			end
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
vimgen:\n generate a syntax highlight .vim file that takes the default\n\
vim lua syntax file and adds the engine functions as new built-in functions.\n\
\ntestgen indir outdir:\n extract MAIN, MAIN2, ... and ERROR1, ERROR2 etc. \
from each lua file in indir\n\ and add as individual tests in the \n\
outdir/test_ok\ outdir/test_fail\ subdirectories\n\n\
missing:\n scan all .lua files and list those that are incomplete.\n\n
view:\n convert a single function to man-format and send to stdout.\n\n\
verify:\n scan all .lua files and list those that use the old format. or \
specify wrong/missing argument types.\n")
end
