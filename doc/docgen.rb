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
				add_function(in_grp.downcase, $1, $2)
			end

		end
	end
}

