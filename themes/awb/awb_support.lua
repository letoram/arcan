--
-- Basic table/string manipulation additions and overloads used throught
--
--

-- This require some explanation, by default, the 
-- "tonumber/..." classes of functions seriously takes locale into 
-- account. This breaks heavily when linked with some libs that
-- actually manipulate radix throughout program lifecycle, when
-- can happen in window managers /etc. that switch locale
-- dynamically based on locale (this seriously happens) and we
-- get inconsistent behavior between LUA51 and LUA51jit.
local radix_point = ".";
function tonumber_rdx(ins, reccall)
	if (ins == nil) then
		print(debug.traceback());
	end

	local rdx_in  = string.byte(',', 1);
	local rdx_out = string.byte('.', 1);

	if (radix_point == ",") then
		rdx_in = string.byte('.', 1);
		rdx_out = string.byte(',', 1);
	end

	local len = string.len(ins);

	for i=1,len do
		if (string.byte(ins, i) == rdx_in) then -- ","
			if (i > 1) then
				ins = string.sub(ins, 1, i-1) .. 
					string.char(rdx_out) .. string.sub(ins, i+1);
			else
				ins = string.char(rdx_out) .. string.sub(ins, 2);
			end
			break;
		end
	end

	local res = tonumber(ins);
	if (res == nil and reccall == nil) then
		radix_point = ",";
		return tonumber_rdx(ins, true);
	else
		return res;
	end
end

-- for strings out we always enforce "C" style point
function tostring_rdx(inv)
	local rdx_in  = string.byte(',', 1);
	local rdx_out = string.byte('.', 1);

	local outs = tostring(inv);
	local len = string.len(outs);

	for i=1,len do
		if (string.byte(outs, i) == rdx_in) then -- ","
			if (i > 1) then
				outs = string.sub(outs, 1, i-1) .. 
					string.char(rdx_out) .. string.sub(outs, i+1);
			else
				outs = string.char(rdx_out) .. string.sub(outs, 2);
			end
			break;
		end
	end

	return outs;
end

function string.utf8back(src, ofs)
	if (ofs > 1 and string.len(src)+1 >= ofs) then
		ofs = ofs - 1;
		while (ofs > 1 and utf8kind(string.byte(src,ofs) ) == 2) do
			ofs = ofs - 1;
		end
	end

	return ofs;
end

function string.utf8forward(src, ofs)
	if (ofs <= string.len(src)) then
		repeat
			ofs = ofs + 1;
		until (ofs > string.len(src) or 
			utf8kind( string.byte(src, ofs) ) < 2);
	end

	return ofs;
end

function string.utf8lalign(src, ofs)
	while (ofs > 1 and utf8kind(string.byte(src, ofs)) == 2) do
		ofs = ofs - 1;
	end
	return ofs;
end

function string.utf8ralign(src, ofs)
	while (ofs <= string.len(src) and string.byte(src, ofs)  
		and utf8kind(string.byte(src, ofs)) == 2) do
		ofs = ofs + 1;
	end
	return ofs;
end

function string.translateofs(src, ofs, beg)
	local i = beg;
	local eos = string.len(src);

	-- scan for corresponding UTF-8 position
	while ofs > 1 and i <= eos do
		local kind = utf8kind( string.byte(src, i) );
		if (kind < 2) then
			ofs = ofs - 1;
		end
		
		i = i + 1;
	end

	return i;
end

function string.utf8len(src, ofs)
	local i = 0;
	local rawlen = string.len(src);
	ofs = ofs < 1 and 1 or ofs
	
	while (ofs <= rawlen) do
		local kind = utf8kind( string.byte(src, ofs) );
		if (kind < 2) then
			i = i + 1;
		end

		ofs = ofs + 1;
	end

	return i;
end

function string.insert(src, msg, ofs, limit)
	local xlofs = src:translateofs(ofs, 1);
	if (limit == nil) then
		limit = string.len(msg) + ofs;
	end
	
	if ofs + string.len(msg) > limit then
		msg = string.sub(msg, 1, limit - ofs);

-- align to the last possible UTF8 char..
		
		while (string.len(msg) > 0 and 
			utf8kind( string.byte(msg, string.len(msg))) == 2) do
			msg = string.sub(msg, 1, string.len(msg) - 1);
		end
	end
	
	return string.sub(src, 1, xlofs - 1) .. msg .. 
		string.sub(src, xlofs, string.len(src)), string.len(msg);
end

function string.delete_at(src, ofs)
	local fwd = string.utf8forward(src, ofs);
	if (fwd ~= ofs) then
		return string.sub(src, 1, ofs - 1) .. string.sub(src, fwd, string.len(src));
	end
	
	return src;
end

function string.utf8back(src, ofs)
	if (ofs > 1 and string.len(src)+1 >= ofs) then
		ofs = ofs - 1;
		while (ofs > 1 and utf8kind(string.byte(src,ofs) ) == 2) do
			ofs = ofs - 1;
		end
	end

	return ofs;
end

function stepfun_tbl(trig, wnd, c, name, tbl, up)
	local ind = 1;
	for i=1, #tbl do
		if (tbl[i] == c[name]) then
			ind = i;
			break;
		end
	end

	if (up) then
		ind = ind + 1;
		ind = ind > #tbl and 1 or ind;
	else
		ind = ind - 1;
		ind = ind == 0 and #tbl or ind;
	end

	trig.cols[2] = tbl[ind];
	c[name] = tbl[ind];
end

function stepfun_num(trig, wnd, c, name, shsym, shtype, min, max, step)
	c[name] = c[name] + step;
	c[name] = c[name] < min and min or c[name];
	c[name] = c[name] > max and max or c[name];

	trig.cols[2] = tostring(c[name]);

	wnd:force_update();
	if (shsym) then
		shader_uniform(c.shid, shsym, shtype, PERSIST, c[name]);
	end
end

function string.split(instr, delim)
	local res = {};
	local strt = 1;
	local delim_pos, delim_stp = string.find(instr, delim, strt);
	
	while delim_pos do
		table.insert(res, string.sub(instr, strt, delim_pos-1));
		strt = delim_stp + 1;
		delim_pos, delim_stp = string.find(instr, delim, strt);
	end
	
	table.insert(res, string.sub(instr, strt));
	return res;
end

function string.trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function string.extension(src)
	local ofs = #src;

	while (ofs > 1) do
		if (string.sub(src, ofs, ofs) == ".") then
			local base = string.sub(src, 1, ofs-1);
			local ext  = string.sub(src, ofs + 1);

			return base, ext;
		end

		ofs = string.utf8back(src, ofs);
	end

	return src, nil;
end


