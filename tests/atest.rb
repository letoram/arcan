#!/usr/bin/ruby
require 'fileutils'
require 'pathname'

def find_bin(name)
	if File.exists?("/usr/local/bin/#{name}")
		return "/usr/local/bin/#{name}"
	elsif File.exists?("/usr/bin/#{name}")
		return "/usr/bin/#{name}"
	end
		nil
end

#
# override these environments to fit the current device
#
$GITMIRROR = ENV["ARCAN_GIT"] ? ENV["ARCAN_GIT"] :
	"https://github.com/letoram/arcan.git"
$GITAPP = ENV["GIT_BIN"] ? ENV["GIT_BIN"] : find_bin("git")
$CMAKEAPP = ENV["CMAKE_BIN"] ? ENV["CMAKE_BIN"] : find_bin("cmake")

$ARCANDIR = ENV["ARCAN_SOURCE"] ? ENV["ARCAN_SOURCE"] : "#{ENV["HOME"]}/.atemp"
unless Dir.exist?($ARCANDIR)
	STDOUT.print("Target arcan directory (#{$ARCANDIR}) missing, "\
		"cloning from (#{$GITMIRROR})\n")

	system("#{$GITAPP} clone \"#{$GITMIRROR}\" \"#{$ARCANDIR}\" > /dev/null")

	STDOUT.print("Pulling static/external dependencies")
	system("#{$ARCANDIR}/external/git/clone.sh > /dev/null")
else
	STDOUT.print("Pulling updates to (#{$ARCANDIR})\n")
	cur = Dir.pwd
	Dir.chdir($ARCANDIR)
	system("#{$GITAPP} pull> /dev/null")
	Dir.chdir(cur)
end

tests = {
	"build" => false,
	"benchmark" => false,
	"doc" => false,
	"regression" => false
}

$QUICKFAIL = false

ARGV.each{|a|
	if (a == "--quickfail") then
		$QUICKFAIL = true
		next
	end

	if tests[a] != nil then
		tests[a] = true
	end
}

if Dir.exists?("#{$ARCANDIR}/bintmp")
	FileUtils.rm_r("#{$ARCANDIR}/bintmp")
end

if Dir.exists?("#{$ARCANDIR}/reports")
	FileUtils.rm_r("#{$ARCANDIR}/reports")
end

Dir.mkdir("#{$ARCANDIR}/bintmp")
Dir.mkdir("#{$ARCANDIR}/reports")

#
# Probe these based on OS and current running environment
# An issue for now is the manual management of X vs. not-X,
# Nvidia vs. mesaGL environment
#
compilers = []
platforms = []

if (RUBY_PLATFORM =~ /darwin/)
	compilers << find_bin("clang")
	platforms << "sdl"
else
# more autodetect heuristic needed here, e.g. version
# header presence etc. A special path for BCM is also
# needed
	compilers << find_bin("gcc") if find_bin("gcc")
	compilers << find_bin("clang") if find_bin("clang")
	platforms += ["sdl", "x11", "x11-headless", "egl-gles"]
end

# for benchmarking, we're only concerned about release builds,
# should a case cause a crash it should be reduced and replicated
# in the regression suite.
dp = "#{$ARCANDIR}/tests/benchmark/"
benchmark_cases = []
Dir["#{dp}*"].each{|a|
	path = a[dp.size..-1]
	benchmark_cases << path if Dir.exists?(a)
}
benchmark_platforms = platforms
benchmark_configurations = ["Release"]
benchmark_compilers = compilers
benchmark_flags = ["-DENABLE_LTO=OFF -DENABLE_SIMD_ALIGNED=ON"]

# for build tests, we are just concerned about whether the
# build completed or not, along with count of warnings and errors
build_platforms = platforms
build_configurations = ["Debug", "Release"]
build_compilers = compilers
build_flags = ["-DENABLE_LWA=ON"]

# for regression cases we're primarily interested in the execution
# output of various sanitizers, verification can be done with imagemagick
regression_configurations = ["Debug"]
regression_compilers = compilers[0]
regression_platforms = platforms;
regression_flags = [
	"-DENABLE_ASAN=ON -DASAN_TYPE=address",
	"-DENABLE_ASAN=ON -DASAN_TYPE=undefined"
]

# for documentation cases we are primarily concerned that the ERROR
# cases should give a valid exit code / fatal invocation and that the
# MAIN examples doesn't generate one. We inject a post-init hook
# to have a timed shutdown.
doc_configurations = ["Release"]
doc_compilers = ["clang"]
doc_platforms = platforms[1]
doc_flags = [""]

class Cfg
	attr_accessor :group, :name, :args, :ver, :bin
	def to_s
		"#{@group}/#{@name}:#{ver} - #{args}"
	end
end

class ATest
	def initialize
		@configurations = []
		@dir = $ARCANDIR
		@bindir = "#{@dir}/bintmp/"
		@repdir = "#{@dir}/reports/"
	end

#
# Use docgen to generate all needed testcases,
# run them with the post-init hook of a timed shutdown.
# check error- code (MAIN, MAIN2, etc. should return
# EXIT_SUCCESS and ERROR1, ERROR2 etc. should return
# EXIT_FAILURE. Make note of coredumps.
#
	def doctest()
		STDOUT.print("doctest, generating test cases\n")
		FileUtils.rm_r("#{@bindir}/doc") if Dir.exists?("#{@bindir}/doc")
		FileUtils.rm_r("#{@repdir}/doc") if Dir.exists?("#{@repdir}/doc")

		Dir.mkdir("#{@repdir}/doc")
		Dir.mkdir("#{@bindir}/doc")

		system("/usr/bin/ruby \"#{@dir}/doc/docgen.rb\" testgen \"#{@dir}/doc\"\
 \"#{@bindir}/doc\" > #{@repdir}/doc/docgen")

		STDOUT.print("running OK cases")
			list = []

			Dir["#{@bindir}/doc/test_ok/*"].each{|a|
				next unless (Dir.exist?(a) and a != "." and a != "..")
				list << a
			}

# should only be one though
			output_brief = File.open("#{@repdir}/doc/test_ok_fail", "w+")
			@configurations.each{|cfg|
				list.each{|test|
					line = "#{cfg.bin} -B \"#{cfg.bin}_frameserver\" \
-p \"#{@dir}/doc/res\" #{cfg.args} -H okhook.lua \"#{test}\""
					p line
					testout = IO.popen(line).readlines
					if ($?.success? == false)
						output_brief.print("#{test} failed:\n#{testout.join("\n\t")}\n")
					end
				}
			}
	end

#
# Look for possible core,
# also attempt to separate debug- information from the
# binary and store the debug- information
#
	def crash_check(dstbase)
# this is not sufficient on OSX (using /cores),
# for linux we have to parse proc..
		if (File.exists?("core"))
			File.rename("core", "#{dstbase}_core")
		end
	end

# run the specific set of benchmark applications,
# save the brief runs as they are, generate graphs over the
# detailed reports.
	def benchmark(set)
		@configurations.each{|cfg|
			STDOUT.print("benchmark, run #{cfg.name}\n")
			output_brief = File.open("#{@repdir}/#{cfg.group}/"\
				"#{cfg.name}.brief", "w+")
			output_detail = File.open("#{@repdir}/#{cfg.group}/"\
				"#{cfg.name}.detail", "w+")

			set.each{|test|
				vals = IO.popen("#{cfg.bin} -p #{@dir}/data/resources "\
					"-B \"#{cfg.bin}_frameserver\" "\
					" #{cfg.args} #{@dir}/tests/benchmark/#{test} 2>/dev/null").readlines

				crash_check("#{@repdir}/#{cfg.group}/core_#{test}")
				output_brief.print("#{test}=#{$?.exitstatus}:#{vals[-1]}")
				output_detail.print("#{test}\n")
				vals.each{|line| output_detail << line}
			}
		}
	end

# run the specific set of regression tests (nil == all)
# and verify against the manually checked result
# with a verify appl.
	def regression(set)
		@configurations.each_pair{|k, v|
			set.each{|test|
				IO.popen("#{@bindir}/#{v[0]} -B \"#{@bindir}/#{v[0]}\" "\
					"#{@bindir}/#{arcan_cmd} #{test}").readlines

				crash_check("#{@bindir}/#{v[0]}", "#{@repdir}/core_#{test}")
			}
		}
	end

#generate a build and save the main arcan binary as bin
	def add_conf(group, name, constr, binargs, bin)
		FileUtils.rm_r("#{@dir}/build") if Dir.exists?("#{@dir}/build")
		FileUtils.rm_r("#{@repdir}/#{group}") if Dir.exists?("#{@repdir}/#{group}")

		Dir.mkdir("#{@repdir}/#{group}")
		Dir.mkdir("#{@dir}/build")
		Dir.mkdir("#{@repdir}/build") unless Dir.exists?("#{@repdir}/build")

		if system("#{$CMAKEAPP} -B\"#{@dir}/build\" -H\"#{@dir}/src\" #{constr} "\
			"1> #{@repdir}/#{name}.config.out 2> "\
			"#{@repdir}/#{name}.config.err") != true
			STDOUT.print("#{name} couldn't be generated\n")
			return false
		end
		STDOUT.print("#{name} configured\n")

		sstr = "make -C #{@dir}/build -j12 1> #{@repdir}/#{name}.build.out" \
			" 2> #{@repdir}/#{name}.build.err"
		if system(sstr) != true
			STDOUT.print("#{name} couldn't be compiled:\n\t#{sstr}\n")
			return false
		end

		version = IO.popen("#{@dir}/build/arcan -V").readlines[0]
		if (version == nil) then
			STDOUT.print("#{name} didn't produce a valid binary")
			return false
		end
		version.chop!
		STDOUT.print("#{name} compiled, reported as #{version}\n")

		File.delete("#{@dir}/build/arcan_db")

# rename all produced binaries, included frameservers
# then append the argument needed to override default search
# for frameserver binary
#
		File.rename("#{@dir}/build/arcan", "#{@bindir}/#{bin}")
		dstr = "#{@dir}/build/arcan"
		Dir["#{dstr}*"].each{|a|
			File.rename(a, "#{@bindir}/#{bin}#{a[dstr.size..-1]}")
		}

		cfg = Cfg.new
		cfg.group = group
		cfg.name = bin
		cfg.bin = "#{@bindir}/#{bin}"
		cfg.args = binargs
		cfg.ver = version
		@configurations << cfg
	end

	def finalize
# drop configurations, generate ident-str and create tarball
	end

	def drop_configurations
		@configurations = []
	end
end

#
# Possibly restrict / probe if some tests or build
# configurations are unwise, particularly for platforms
# that would collide with X.
#
test = ATest.new

def gen_variants(platforms, types, compilers, flagset)
	confs = []
	compilers.each{|comp|
		platforms.each.each{|var|
			types.each{|type|
				flagset.each{|flags|

				compbase = Pathname.new(comp).basename.to_s
			confs << ["#{var}-#{compbase}-#{type}", "#{var}",
	"-DCMAKE_BUILD_TYPE=#{type} -DCMAKE_C_COMPILER=#{comp} "\
	"-DVIDEO_PLATFORM=#{var} -DAVFEED_SOURCES=frameserver/avfeed.c #{flags}"]

				}
			}
		}
	}
	confs
end

failed_variants = []
ok_variants = []

STDOUT.print("Step one - build configurations\n")
if tests["build"]
vars = gen_variants(build_platforms,
	build_configurations, build_compilers, build_flags)
vars.each{|var|
	if test.add_conf("build", var[0], var[2], "", var[0])
		ok_variants << "build:#{var[0]}"
	else
		failed_variants << "build:#{var[0]}"
		if ($QUICKFAIL) then
			exit
		end
	end
}
test.drop_configurations
else
	STDOUT.print("-- omitted --\n")
end

STDOUT.print("Step two - benchmark run\n")
if tests["benchmark"]
vars = gen_variants(benchmark_platforms,
	benchmark_configurations, benchmark_compilers, benchmark_flags)
vars.each{|var|
	if test.add_conf("benchmark", var[0], var[2], "-w 1280 -h 720", var[0])
		ok_variants << "benchmark:#{var[0]}"
	else
		failed_variants << "benchmark:#{var[0]}"
	end
}
test.benchmark(benchmark_cases)
test.drop_configurations
else
	STDOUT.print("-- omitted --\n")
end

STDOUT.print("Step three - regression run\n")
if tests["regression"]
vars = gen_variants(regression_platforms,
	regression_configurations, regression_compilers, regression_flags)
vars.each{|var|
	if test.add_conf("regression", var[0], var[2], "", var[0])
		ok_variants << "regression:#{var[0]}"
	else
		failed_variants << "regression:#{var[0]}"
	end
}
test.regression
test.drop_configurations
else
	STDOUT.print("-- omitted --\n")
end

STDOUT.print("Step four - doc- examples\n")
if tests["doc"]
vars = gen_variants(doc_platforms, doc_configurations, doc_compilers, doc_flags)
test.add_conf("doc", vars[0][0], vars[0][2], "", vars[0][0])
test.doctest
test.drop_configurations
else
	STDOUT.print("-- omitted --\n")
end

#
# We wait with specific appl- tests when package format is finished
# and we have a proper serialization format for the event layer that
# can be activated enviroment-variable style e.g.
# ARCAN_EVENT_REPLAY=filepath and ARCAN_EVENT_RECORD=filepath
#
# Then package the debug / use-data in each application, like
# input_recording/case1.rec and use that to also be able to create
# tailored builds with profile-based builds, automatic tuning of
# VM/JIT etc.
#

STDOUT.print("done, #ok variants: #{ok_variants.size}, #failed variants:"\
 " #{failed_variants.size}\n")

STDOUT.print("Packaging results\n")
test.finalize

