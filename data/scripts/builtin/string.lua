--
-- public domain string handling functions, extends the normal Lua string
-- table with some additional convenience functions needed by other builtin
-- scripts.
--
-- [destructive transforms]
-- split(s, delim) => table
-- split_first(s, delim) => first, rest
-- trim(s) => trimmed_str, remove trailing / leading whitespace
--
-- [matching]
-- starts_with(s, prefix) => bool
-- shorten(s, length) => shorter string
--
-- [utf8 support]
-- utf8back
-- utf8forward(s, ofs) => next offset for cp start (fast)
-- utf8ralign(s, ofs)  => next offset for cp start (arbitrary pos)
-- utf8lalign(s, ofs)  => previous start offset
-- utf8translateofs(s, pos, beg) => byte position from utf8 cp position
-- utf8len(s, ofs) => #codepoints from ofs to end
-- insert(s, msg, pos, lim) => add up to lim characters from msg into s at code point position
-- delete_at(s, pos) => remove utf8 cp at logical position
-- utf8valid(s)
--
-- [conversions]
-- to_u8(s = "hex hex hex hex ..." % 2 == 0) => codepoint str
-- hexenc(bytestr) => hexstr
-- dump(s) => dec_bytestr
--
if not string.split then
function string.split(instr, delim)
	if (not instr) then
		return {};
	end

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
end

if not string.starts_with then
function string.starts_with(instr, prefix)
	return string.sub(instr, 1, #prefix) == prefix;
end
end

--
--  Similar to split but only returns 'first' and 'rest'.
--
--  The edge cases of the delim being at first or last part of the
--  string, empty strings will be returned instead of nil.
--
if not string.split_first then
function string.split_first(instr, delim)
	if (not instr) then
		return;
	end
	local delim_pos, delim_stp = string.find(instr, delim, 1);
	if (delim_pos) then
		local first = string.sub(instr, 1, delim_pos - 1);
		local rest = string.sub(instr, delim_stp + 1);
		first = first and first or "";
		rest = rest and rest or "";
		return first, rest;
	else
		return "", instr;
	end
end
end

-- can shorten further by dropping vowels and characters
-- in beginning and end as we match more on those
if not string.shorten then
function string.shorten(s, len)
	if (s == nil or string.len(s) == 0) then
		return "";
	end

	local r = string.gsub(
		string.gsub(s, " ", ""), "\n", ""
	);
	return string.sub(r and r or "", 1, len);
end
end

if not string.utf8back then
function string.utf8back(src, ofs)
	if (ofs > 1 and string.len(src)+1 >= ofs) then
		ofs = ofs - 1;
		while (ofs > 1 and utf8kind(string.byte(src,ofs) ) == 2) do
			ofs = ofs - 1;
		end
	end

	return ofs;
end
end

if not string.to_u8 then
function string.to_u8(instr)
-- drop spaces and make sure we have %2
	instr = string.gsub(instr, " ", "");
	local len = string.len(instr);
	if (len % 2 ~= 0 or len > 8) then
		return;
	end

	local s = "";
	for i=1,len,2 do
		local num = tonumber(string.sub(instr, i, i+1), 16);
		if (not num) then
			return nil;
		end
		s = s .. string.char(num);
	end

	return s;
end
end

if not string.utf8forward then
function string.utf8forward(src, ofs)
	if (ofs <= string.len(src)) then
		repeat
			ofs = ofs + 1;
		until (ofs > string.len(src) or
			utf8kind( string.byte(src, ofs) ) < 2);
	end

	return ofs;
end
end

if not string.utf8lalign then
function string.utf8lalign(src, ofs)
	while (ofs > 1 and utf8kind(string.byte(src, ofs)) == 2) do
		ofs = ofs - 1;
	end
	return ofs;
end
end

if not string.utf8ralign then
function string.utf8ralign(src, ofs)
	while (ofs <= string.len(src) and string.byte(src, ofs)
		and utf8kind(string.byte(src, ofs)) == 2) do
		ofs = ofs + 1;
	end
	return ofs;
end
end

if not string.translateofs then
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
end

if not string.utf8len then
function string.utf8len(src, ofs)
	local i = 0;
	local rawlen = string.len(src);
	ofs = ofs < 1 and 1 or ofs;

	while (ofs <= rawlen) do
		local kind = utf8kind( string.byte(src, ofs) );
		if (kind < 2) then
			i = i + 1;
		end

		ofs = ofs + 1;
	end

	return i;
end
end

if not string.insert then
function string.insert(src, msg, ofs, limit)
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

	return string.sub(src, 1, ofs - 1) .. msg ..
		string.sub(src, ofs, string.len(src)), string.len(msg);
end
end

if not string.delete_at then
function string.delete_at(src, ofs)
	local fwd = string.utf8forward(src, ofs);
	if (fwd ~= ofs) then
		return string.sub(src, 1, ofs - 1) .. string.sub(src, fwd, string.len(src));
	end

	return src;
end
end

local function hb(ch)
	local th = {"0", "1", "2", "3", "4", "5",
		"6", "7", "8", "9", "a", "b", "c", "d", "e", "f"};

	local fd = math.floor(ch/16);
	local sd = ch - fd * 16;
	return th[fd+1] .. th[sd+1];
end

if not string.hexenc then
function string.hexenc(instr)
	return string.gsub(instr, "(.)", function(ch)
		return hb(ch:byte(1));
	end);
end
end

if not string.trim then
function string.trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"));
end
end

if not string.utf8valid then
-- reformated PD snippet
function string.utf8valid(str)
  local i, len = 1, #str
	local find = string.find;
  while i <= len do
		if (i == find(str, "[%z\1-\127]", i)) then
			i = i + 1;
		elseif (i == find(str, "[\194-\223][\123-\191]", i)) then
			i = i + 2;
		elseif (i == find(str, "\224[\160-\191][\128-\191]", i)
			or (i == find(str, "[\225-\236][\128-\191][\128-\191]", i))
 			or (i == find(str, "\237[\128-\159][\128-\191]", i))
			or (i == find(str, "[\238-\239][\128-\191][\128-\191]", i))) then
			i = i + 3;
		elseif (i == find(str, "\240[\144-\191][\128-\191][\128-\191]", i)
			or (i == find(str, "[\241-\243][\128-\191][\128-\191][\128-\191]", i))
			or (i == find(str, "\244[\128-\143][\128-\191][\128-\191]", i))) then
			i = i + 4;
    else
      return false, i;
    end
  end

  return true;
end
end

if not string.dump then
function string.dump(msg)
	local bt ={};
	for i=1,string.len(msg) do
		local ch = string.byte(msg, i);
		bt[i] = ch;
	end
end
end

if not string.unpack_shmif_argstr then
function string.unpack_shmif_argstr(a1, a2)
	local arg
	local res

	if type(a1) == "table" then
		res = a1
		arg = a2
	else
		arg = a1
		res = {}
	end

	if type(arg) ~= "string" or #arg == 0 then
		return res
	end

	local entries = string.split(arg, ":")
	for _,v in ipairs(entries) do
		local elem = string.split(v, "=")
		if elem and elem[1] and #elem[1] > 0 then
			if #elem == 1 then
				res[elem[1]] = true
			elseif #elem == 2 then
				res[elem[1]] = string.gsub(elem[2], "\t", ":")
			end
		end
	end

	return res
end
end

-- add (slow) string.format workaround for the string.format bug, this is still
-- not complete as trailing	'nil' will still not be converted and there seem to
-- be no stable solution to this as we won't get the count of trailing 'nil'
-- arguments.
if not string.find(API_ENGINE_BUILD, "luajit51") then
	local of = string.format
function string.format(...)
	local arg = {...}
	for i=2,#arg do
		if type(arg[i]) == "boolean" then
			arg[i] = arg[i] and "true" or "false"
		elseif arg[i] == nil then
			arg[i] = "nil"
		end
	end
	return of(unpack(arg))
end
end
