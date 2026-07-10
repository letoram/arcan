--
-- misc convenience functions that do not for elsewhere:
--
--  exposes:
--   update_lastdir(): grab the current dir from rootwnd -> hem.lastdir
--   add_message(msg): queue a message to be shown close to the readline
--   get_message(deq) -> str: return the most important message queued, clear if deq is set
--
--   run_lut(cmd, tgt, lut, set):
--    take a set of unordered options (n-indexed, like 'err', 'tog')
--    match to a lut of [key = fptr(set, i, job)] and invoke all entries with
--    a match.
--
return
function(hem, root, config)
local lastmsg

function hem.url_ptn()
	return "https?://(([%w_.~!*:@&+$/?%%#-]-)(%w[-.%w]*%.)(%w%w%w?%w?)(:?)(%d*)(/?)([%w_.~!*:@&+$/?%%#=-]*))"
end

function hem.each_ch(str, cb, err, pos, dir)
	local u8_step = root.utf8_step
	local dir = dir or 1
	err = err or function() end

	if pos then
-- seek positive to codepoint position
		pos = u8_step(str, pos)

		if pos == -1 then
			err(str, pos)
			return
		end
	else
		pos = 1
	end

-- now step in direction and callback
	while true do
		local nextch, ch = u8_step(str, dir, pos)
		if nextch == -1 then
			if nextch < #str then
				err(str, pos)
			end
			return
		end

-- slice out the character, order based on direction
		if nextch < pos then
			if cb(string.sub(str, nextch, pos-1), nextch) then
				break
			end
		else
			if cb(string.sub(str, pos, nextch-1), pos) then
				break
			end
		end

		pos = nextch
	end

	return pos
end

function hem.remove_match(tbl, ent)
	for i, v in ipairs(tbl) do
		if v == ent then
			table.remove(tbl, i)
			return true, i
		end
	end
end

function table.find_key_i(table, field, r)
	for k,v in ipairs(table) do
		if (v[field] == r) then
			return k, v;
		end
	end
end

function table.find_i(table, r)
	for k,v in ipairs(table) do
		if (v == r) then return k, table[k]; end
	end
end

-- assumes no cycles
function table.copy_recursive(tbl)
	local res = {}
	for k,v in pairs(tbl) do
		if type(v) == "table" then
			res[k] = table.copy_recursive(v)
		else
			res[k] = v
		end
	end
	return res
end

function table.equal(tbl1, tbl2)
	if not tbl1 or not tbl2 then
		return false
	end
	if #tbl1 ~= #tbl2 then
		return false
	end
	for i,v in ipairs(tbl1) do
		if v ~= tbl2[i] then
			return false
		end
	end
	return true
end

function string.fit_to_length(str, cap, lpad, ofs)
	local left = cap
	local out = ""
	ofs = ofs or 0

	if cap == 0 then
		return str
	end

-- other options here is to consider other unicode quirks, e.g. combiners,
-- non-advancing space, double-width, and put them as arguments to each_ch
	hem.each_ch(str,
		function(ch)
			if ofs > 0 then
				ofs = ofs - 1
			else
				out = out .. ch
				left = left - 1
			end
			return left == 0
		end,
		function()
		end
	)

	if left > 0 then
		if lpad then
			return string.rep(" ", left) .. out
		else
			return out .. string.rep(" ", left)
		end
	end

	return out
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

if not string.lpad then
	function string.lpad(instr, digits)
		if #instr < digits then
			return string.rep(" ", digits - #instr) .. instr
		end
		return instr
	end
end

function hem.compact_path(str, lastcap)
	local set = string.split(str, "/")
	local compact = {}

-- build to /a/b/c/filename
	for i=1,#set do
		if i < #set then
			local next = root.utf8_step(set[i], 1, 1)
			table.insert(compact, next == -1 and set[i] or string.sub(set[i], 1, next))
		else
			table.insert(compact, set[i])
		end
	end
	return table.concat(compact, "/")
end

function math.clamp(num, low, high)
	if low and num < low then
		return low
	elseif high and num > high then
		return high
	else
		return num
	end
end

function hem.modifier_string(mod)
	local str = ""
	if bit.band(mod, tui.modifiers.SHIFT) > 0 then
		str = str .. "shift_"
	end
	if bit.band(mod, tui.modifiers.CTRL) > 0 then
		str = str .. "ctrl_"
	end
	if bit.band(mod, tui.modifiers.ALT) > 0 then
		str = str .. "alt_"
	end
	if bit.band(mod, tui.modifiers.META) > 0 then
		str = str .. "meta_"
	end
	return str
end

function hem.system_path(ns)
	local base = lash.scriptdir .. "/state"
	if hem.env["XDG_STATE_HOME"] then
		base = hem.env["XDG_STATE_HOME"]
	end

	return base
end

function hem.run_in_dir(root, dir, cb)
	local old = root:chdir()
	root:chdir(dir)
	cb()
	root:chdir(old)
end

function hem.chdir(step)
	hem.prevdir = root:chdir()
	root:chdir(step)

	if (step) then
		local new = root:chdir()
		if new ~= hem.prevdir then
			for k, v in pairs(hem.dir_monitor) do
				v(new, hem.prevdir)
			end
			root:update_identity(new)
		end
	end

	hem.scanner_path = nil
	hem.update_lastdir()
end

function hem.update_lastdir()
	local wd = root:chdir()
	local dirs = string.split(wd, "/")
	local dir = "/"
	if #dirs then
		hem.lastdir = dirs[#dirs]
	end
end

-- sweeps through args and replaces job references with temp files, return a
-- closure for unlinking them as well as a trigger for when all writes have
-- completed.
function hem.build_tmpjob_files(args, dispatch, fail)
-- pre-alloc files so we don't run into fd cap
	local files = {}
	local names = {}

	local function
	closure()
		for _,v in ipairs(names) do
			root:funlink(v)
		end
		for _,v in ipairs(files) do
			v:close()
		end
	end

	for _,v in ipairs(args) do
		if type(v) == "table" and v.slice then
			local tpath, file = root:tempfile()
			if file then
				table.insert(files, file)
				table.insert(names, tpath)
			else
				hem.add_message("build tmp-job: couldn't create temporary storage")
				return closure()
			end
		end
	end

-- nothing to do? just return
	if #files == 0 then
		return
	end

-- now actually queue the transfers, when the last report done, signal
	local pending = 0
	local failed = 0
	local ok = 0
	local writeh =
	function(oob, finish_ok)
		if finish_ok then
			ok = ok + 1
		else
			failed = failed + 1
		end

		if failed+ok == pending then
			if failed > 0 then
				fail()
			else
				dispatch()
			end
		end
	end

	for i,v in ipairs(args) do
		if type(v) == "table" and v.slice then
			pending = pending + 1
			files[pos]:write(v:slice(), writeh)
		end
	end

	return closure
end

-- expected to return nil (block_reset) to fit in with expectations of builtins
function hem.add_message(msg)
	if not msg then
		lastmsg = ""
	elseif type(msg) ~= "string" then
		print("add_message(" .. type(msg) .. ")" .. debug.traceback())
	else
		lastmsg = msg
		if #lastmsg > 0 then
			hem.a11y_buffer(msg)
		end
	end
	-- bug 0014: mirror user-facing messages to a shmif MESSAGE event so
	-- external harnesses (shmon/autorun.lua extevh wrap) can verify cell
	-- content without scraping rasterised text.  Truncate to 200 chars
	-- and strip newlines; pcall guards against root not being ready
	-- during early init.
	if msg and type(msg) == "string" and lash and lash.root then
		local s = msg:gsub("[\r\n]", " ")
		if #s > 200 then s = s:sub(1, 200) end
		pcall(function() lash.root:message("hem:msg:" .. s) end)
	end
end

function hem.get_message(dequeue)
	local old = lastmsg
	if dequeue then
		lastmsg = nil
	end
	return old
end

function hem.opt_number(set, ind, default)
	local num = set[ind] and tonumber(set[ind])
	return num and num or default
end

function hem.run_lut(cmd, tgt, lut, set)
	local i = 1
	while i and i <= #set do
		local opt = set[i]

		if type(opt) ~= "string" then
			lastmsg = string.format("%s >...< %d argument invalid", cmd, i)
			return
		end

-- ignore invalid
		if not lut[opt] then
			i = i + 1
		else
			i = lut[opt](set, i, tgt)
		end
	end
end

local maptype = {
	s = tostring,
	n = tonumber,
	b = function(v) return v == true; end
}

-- shallow and only simple types
function hem.stableb64(tbl)
	local res = {}

	local typemap = {
		["string"] = "s",
		["boolean"] = "b",
		["number"] = "n"
	}

	for k,v in pairs(tbl) do
		local kt = typemap[type(k)]
		local vt = typemap[type(v)]

		if kt and vt then
			table.insert(res, hem.to_b64(kt .. vt .. tostring(k)))
			table.insert(res, hem.to_b64(tostring(v)))
		end
	end

	return table.concat(res, ":")
end

function hem.b64stable(str)
	local sub = string.split(str, ":")
	local deq = table.remove
	local res = {}

	while #sub > 0 do
		local key = hem.from_b64(deq(sub, 1))
		local val = hem.from_b64(deq(sub, 1))

		if key then
			local kt = string.sub(key, 1, 1)
			local vt = string.sub(key, 2, 2)
			key = string.sub(key, 3)

			if key and val and maptype[kt] and maptype[vt] then
				res[maptype[kt](key)] = maptype[vt](val)
			end
		end
	end

	return res
end

-- taken from Ilya Kolbins unlicensed b64 enc/dec
local function extract(v, from, width)
	return bit.band(bit.rshift(v, from), bit.lshift(1, width) - 1)
end

-- build LUTs
local b64enc = {}
local b64dec = {}
for b64, ch in pairs({[0]='A','B','C','D','E','F','G','H','I','J',
		'K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y',
		'Z','a','b','c','d','e','f','g','h','i','j','k','l','m','n',
		'o','p','q','r','s','t','u','v','w','x','y','z','0','1','2',
		'3','4','5','6','7','8','9','+','/','='})
do
	b64enc[b64] = ch:byte()
end

for b64, char in pairs(b64enc) do
	b64dec[char] = b64
end

function hem.to_b64(str)
	local char, concat = string.char, table.concat
	local encoder = b64enc

	local t, k, n = {}, 1, #str
	local lastn = n % 3

	for i = 1, n-lastn, 3 do
		local a, b, c = str:byte( i, i+2 )
		local v = a*0x10000 + b*0x100 + c
		local s
			s = char(
				encoder[extract(v,18,6)],
				encoder[extract(v,12,6)],
				encoder[extract(v,6,6)],
				encoder[extract(v,0,6)]
			)
		t[k] = s
		k = k + 1
	end

	if lastn == 2 then
		local a, b = str:byte( n-1, n )
		local v = a*0x10000 + b*0x100
		t[k] = char(
			encoder[extract(v,18,6)],
			encoder[extract(v,12,6)],
			encoder[extract(v,6,6)],
			encoder[64]
		)
	elseif lastn == 1 then
		local v = str:byte( n )*0x10000
		t[k] = char(
			encoder[extract(v,18,6)],
			encoder[extract(v,12,6)],
			encoder[64],
			encoder[64]
		)
	end

	return concat(t)
end

function hem.from_b64(b64)
	local char, concat = string.char, table.concat
	local decoder = b64dec
	local pattern = '[^%w%+%/%=]'
	b64 = b64:gsub( pattern, '' )

	local t, k = {}, 1
	local n = #b64
	local padding = b64:sub(-2) == '==' and 2 or b64:sub(-1) == '=' and 1 or 0

	for i = 1, padding > 0 and n-4 or n, 4 do
		local a, b, c, d = b64:byte( i, i+3 )
		local s
		local v =
			decoder[a] * 0x40000 +
			decoder[b] * 0x1000  +
			decoder[c] * 0x40    +
			decoder[d]

		s = char(
			extract(v,16,8),
			extract(v, 8,8),
			extract(v,0,8)
		)
		t[k] = s
		k = k + 1
	end

	if padding == 1 then
		local a, b, c = b64:byte( n-3, n-1 )
		local v =
			decoder[a]*0x40000 +
			decoder[b]*0x1000  +
			decoder[c]*0x40

		t[k] = char(
			extract(v,16,8),
			extract(v,8,8)
		)

	elseif padding == 2 then
		local a, b = b64:byte( n-3, n-2 )
		local v =
			decoder[a]*0x40000 +
			decoder[b]*0x1000

		t[k] = char(extract(v,16,8))
	end

	return concat( t )
end

function hem.reader_factory(io, tick, cb)
	local cd = tick
	local buf = {}

-- perform a read into a buffer, on timeout or eof submit the buffer
	table.insert(
		hem.timers,
		function()
			local oc = #buf
			local _, ok = io:read(buf)
			if not ok then
				cb(buf, true)
				buf = {}
				return false
			end

			if #buf == oc and #buf > 0 then
				cd = cd - 1
				if cd <= 0 then
					cd = tick
				end
				local ob = buf
				buf = {}
				return cb(ob, false)
			end

			return true
		end
	)
end

function hem.add_job_suggestions(set, allow_hidden, filter)
	local filter = filter or function(job) return true, job.short end
	if not set.hint then
		set.hint = {}
	end

	if hem.selectedjob then
		local ok, hint = filter(hem.selectedjob)
		if ok then
			table.insert(set, "#csel")
			table.insert(set.hint, hint or "")
		end
	end

	if hem.latestjob then
		local ok, hint = filter(hem.latestjob)
		if ok then
			table.insert(set, "#last")
			table.insert(set.hint, hint or "")
		end
	end

	for _,v in ipairs(lash.jobs) do
		local ok, hint = filter(v)
		if ok and (not v.hidden or allow_hidden) then
			table.insert(set, "#" .. tostring(v.id))
			table.insert(set.hint, hint or "")
			if v.alias then
				table.insert(set, "#" .. v.alias)
				table.insert(set.hint, hint or "")
			end
		end
	end
end

local function expand_helpers(helpers, v, ...)
	local a, b, c = string.find(v, "$([%w_]+)")
	if not c then
		return v
	end

	local res = ""
	if a > 1 then
		res = string.sub(v, 1, a-1)
	end

	if helpers[c] then
		local expanded = helpers[c](...)
		if expanded then
			if #expanded == 0 then
				return nil
			end
			res = res .. expanded
		end
	end

-- drop leading first whitespacing, forcing a double-escape to get padding
-- between expansion and possible unit indicator
	local suf = string.sub(v, b+1)
	if string.sub(suf, 1, 1) == " " then
		suf = string.sub(suf, 2)
	end

	res = res .. suf

	return expand_helpers(helpers, res)
end

-- part of prompt expansion:
--   wrap items in some user-defined block (prefix data suffix) or
--   omitt the block entirely if there is no actual data
local function apply_queue(dst, queue, template)
	if not queue or #queue == 0 then
		return
	end

	if template.prefix and type(template.prefix) == "table" then
		for _,v in ipairs(template.prefix) do
			table.insert(dst, v)
		end
	end

	for _,v in ipairs(queue) do
		table.insert(dst, v)
	end

	if template.suffix and type(template.suffix) == "table" then
		for _,v in ipairs(template.suffix) do
			table.insert(dst, v)
		end
	end
end

-- used for prompt expansion, should be improved a bit to better support
-- decorating groups (rather than forcing the prompt template to do it)
function hem.template_to_str(template, helpers, job)
	local res = {}
	local queue

	for _,v in ipairs(template) do

-- tables are treated as format tables and added verbatim
		if type(v) == "table" then
			table.insert(res, v)

-- strings have expansion based on $ but we can stack expansions
-- and ignore them if they expansions do not produce any results
		elseif type(v) == "string" then
			if v == "$begin" or v == "$end" then
				apply_queue(res, queue, template)
				if v == "$begin" then
					queue = {}
				else
					queue = nil
				end
			else
				table.insert(queue or res, expand_helpers(helpers, v, job))
			end

-- functions are just executed and expected to return string or nil
-- and only a string with non-whitespace characters are considered
		elseif type(v) == "function" then
			local fret = v(hem, job)
			if fret and string.find(fret, "%S") then
				table.insert(queue or res, fret)
			end
		else
			hem.add_message("bad member in prompt")
		end
	end

-- implicit $end
	apply_queue(res, queue, template)
	return res
end

function hem.always_active()
	return true
end

function hem.table_copy_shallow(intbl)
	local outtbl = {}
	for k,v in pairs(intbl) do
		outtbl[k] = v
	end
	return outtbl
end

local function escape(line, expand)
	if not expand then
		return line
	end

	if string.find(line, " ") or string.find(line, "\"") then
		return '"' .. string.trim(string.gsub(line, "\"", "\\\"")) .. '"'
	end

	return line
end

-- this also takes parg on table with slicing into account
function hem.expand_string_table(intbl, cap, expand)
-- treat as a FIFO
	local out = {}
	local count = 0

	while #intbl > 0 do
		local item = table.remove(intbl, 1)
		local as_string = escape(tostring(item), expand)

-- just a simple literal?
		if type(item) ~= "table" and as_string then
			table.insert(out, as_string)
			count = count + #as_string

-- a job that needs to be sliced out
		elseif type(item) == "table" and item.slice then
			local arg = nil

-- possibly constrained by a parg
			if type(intbl[1]) == "table" and intbl[1].parg then
				arg = table.remove(intbl, 1)
			end

-- that can fail
			local set = item:slice(arg)

-- abort on overflow
			if set then
-- merge
				for _,v in ipairs(set) do
					v = escape(tostring(v), expand)
					count = count + #v
					table.insert(out, v)
				end
			end
-- or an unhandled / unknown entry
		else
			return nil, "unexpected type in arguments"
		end
	end

	return out
end

function hem.switch_env(job, force_prompt)
	if hem.job_stash and not job then
		hem.chdir(hem.job_stash.dir)
		hem.env = hem.job_stash.env
		hem.get_prompt = hem.job_stash.get_prompt
		hem.builtins = hem.job_stash.builtins
		hem.views = hem.job_stash.views
		hem.suggest = hem.job_stash.suggest
		hem.builtin_name = hem.job_stash.builtin_name
		hem.job_stash = nil
	end

	if not job then
		return
	end

	hem.job_stash =
	{
		dir = root:chdir(),
		env = hem.table_copy_shallow(hem.env),
		get_prompt = hem.get_prompt,
		views = hem.views,
		builtins = hem.builtins,
		builtin_name = hem.builtin_name,
		suggest = job.suggest
	}

-- actually swap out the builtins, this doesn't cover views though
-- perhaps it should.
	hem.builtins = job.builtins
	hem.builtin_name = job.builtin_name

	if force_prompt then
		hem.get_prompt =
		function()
			if type(force_prompt) == "string" then
				return {force_prompt}
			elseif type(force_prompt) == "table" then
				return force_prompt
			else
				return {""}
			end
		end
		if hem.readline then
			hem.readline:set(job.raw)
		end
	end

	hem.chdir(job.dir)
	hem.env = job.env
end

function hem.hide_readline(root)
	if not hem.readline then
		return
	end

	hem.laststr = hem.readline:get()
	root:revert()
	hem.flag_dirty()
end

function hem.set_readline(rl, src)
	hem.readline = rl
	hem.readline_src = src
end

function hem.block_readline(root, on, hide)
	hem.readline_block = on
	hem.readline_block_hide = hide
end

local KiB = 1024
local MiB = 1024 * 1024
local GiB = 1024 * 1024 * 1024
local TiB = 1024 * 1024 * 1024 * 1024
function hem.sz_to_human(sz)
	if sz < KiB then
		return "B", sz
	elseif sz < MiB then
		return "K", sz / KiB
	elseif sz < GiB then
		return "M", sz / MiB
	elseif sz < TiB then
		return "G", sz / GiB
	else
		return "T", sz / TiB
	end
end

function hem.list_processes(closure)
	local env = {}
	local _, out, _, pid = root:popen("ps ax", "r", env)
	hem.add_background_job(out, pid, {lf_strip = true},
		function(job, code)
			if code == 0 then
				local set = {}
				for i,v in ipairs(job.data) do
					local elem = string.split(string.trim(v), "%s+")
					local pid = tonumber(elem[1])

					table.insert(set, {
						pid = tonumber(elem[1]),
						tty = elem[2],
						state = elem[3],
						time = elem[4],
						name = table.concat(elem, " ", 5)
					}
				)
				end
				table.remove(set, 1)
				closure(set)
			else
				closure({})
			end
		end
	)
end

function hem.get_history_source()
	local builtin =
		hem.config.history.builtin_bin and hem.builtin_name or "default"

	if not hem.history[builtin] then
		hem.history[builtin] =
		{
			bytecount = 0,
			linecount = 0,
			meta = {}
		}
	end

	return hem.history[builtin]
end

local histflt = {
	"^cd%s",
	"^builtin%s"
}

function hem.append_history(line, job)
	local hist = hem.get_history_source(hem.history[builtin])

-- ensure that we do not have duplicates, but keep the line as most recent
	if not hist[line] then
		hist[line] = true
	elseif config.history.filter_duplicate then
		for i=#hist,1,-1 do
			if hist[i] == line then
				table.remove(hist, i)
				-- bug 0012: hist.meta can be shorter than hist when
				-- persistence wrote the two arrays at different times
				-- (or before .meta was tracked at all).  Guard the
				-- companion remove so hem init survives a stale
				-- history file instead of falling back to bootstrap.
				if hist.meta and i <= #hist.meta then
					table.remove(hist.meta, i)
				end
				hist.linecount = hist.linecount - 1
				hist.bytecount = hist.bytecount - #line
				break
			end
		end
	end

	if type(job) == "table" and job.pid then
		local defer
		defer =
		function()
			hem.append_history(line)
			hem.remove_match(job.hooks.on_finish, defer)
		end
		table.insert(job.hooks.on_finish, defer)
		return
	end

-- Future consideration:
-- If this resulted in a shell job and we have only-success filter on, we
-- need to latch onto the completion event handler and only add when it
-- completes. This is much harder for an asynch pipeline.

	table.insert(hist, 1, line)
	hist.linecount = hist.linecount + 1
	hist.bytecount = hist.bytecount + #line
end

function hem.setup_readline(root)
	if hem.readline_block then
		if not hem.readline_block_hide then
			hem.hide_readline(root)
		end
		return
	end

	local cx, cy = root:cursor_pos()
	root:cursor_to(cx, cy,
		config.readline.cursor, unpack(config.readline.cursor_rgb or {}))

	local rl = root:readline(
		function(self, line)
			hem.set_readline(nil, "readline_cb")

			if not line or #line == 0 then
				local on_cancel = hem.on_cancel
				if on_cancel then
					hem.on_cancel = nil
					on_cancel()
					hem.reset()
					return
				end
			end
			hem.on_cancel = nil

-- allow the line to be intercepted once, with optional block- out
			local on_line = hem.on_line
			if on_line then
				hem.on_line = nil
				if on_line() then
					hem.reset()
					return
				end
			end

-- if the parse created a single job (e.g. !!something or basic shell command)
-- forward that to the history so we can attach a possible closure to filter
-- only jobs that succeeded
			local jobret = hem.parse_string(self, line)
			hem.append_history(line, jobret)

			if not hem.readline_block then
				hem.reset()
			end
		end, config.readline)

	hem.set_readline(rl, "setup_readline")
	rl:set(hem.laststr)
	rl:set_prompt(hem.get_prompt())
	rl:set_history(hem.get_history_source())
	rl:suggest(config.autosuggest)
end

-- this is part of a refactoring to deal with the many times this is being
-- repeated across builtins, and that they currently uniformely bug out on
-- input locking and attach to the wrong window when detached
function hem.custom_readline(wnd, prompt, initial, handler)
	local oprompt = hem.get_prompt
	local got_readline = hem.readline
	hem.block_readline(wnd.root, false, false)
	hem.reset()
	hem.set_readline(
		wnd.root:readline(
			function(self, line)
				hem.get_prompt = oprompt
				hem.block_readline(wnd.root, false, false)
				hem.reset()
				wnd.in_query = false

				if not got_readline then
					hem.hide_readline(wnd.root)
				end
				handler(line)
			end,
		{
			cancellable = true,
			forward_meta = false,
			forward_paste = false,
			forward_mouse = true,
		}), identity
	)

	wnd.in_query = true
	hem.block_readline(lash.root, true, true)
	hem.readline:set(initial)
	hem.get_prompt = prompt
end

-- use the same parg setup everywhere for extracting parameters on embed,
-- tab, ... like properties. this is used by term/shmif like handovers.
function hem.misc_resolve_mode(arg, cmode)
	if type(arg[1]) ~= "table" then
		return "", cmode
	end
	local open_mode = ""

	local t = table.remove(arg, 1)
	if not t.parg then
		hem.add_message("spurious #job argument in subshell command")
		return
	end

	for _,v in ipairs(t) do
		if v == "err" then
			open_mode = "e"
		elseif v == "nokeep" then
			open_mode = open_mode .. "!"
		elseif v == "embed" then
			cmode = "embed"
		elseif v == "v" then
			cmode = "join-d"
		elseif v == "tab" then
			cmode = "tab"
		end
	end

	return open_mode, cmode
end

function hem.expand_arg_dst(cmd, ...)
	local base = {...}
	local dst

	if type(base[1]) == "table" then
		dst = table.remove(base, 1)
	else
		dst = hem.selectedjob
	end

-- ensure #job or set #job ...
	if not dst then
		return false, cmd .. " >job< : job specifier missing"
	end

	local set = {}

-- now it's safe to expand #args
	local ok, msg = hem.expand_arg(set, base)
	if not ok then
		return false, msg
	end

	return dst, set
end

function hem.get_active_root()
	if hem.selectedjob then
		return hem.selectedjob.root
	else
		return lash.root
	end
end

function hem.set_history_exporter()
	if not hem.config.history.persist then
		hem.state.export.history = nil
		hem.state.import.history = nil
		return
	end

-- need to prefix with the metadata so we can distinguish, we should really
-- have another format for this where the exporter can just write into the
-- iostream directly
	hem.state.export["history"] =
	function()
		local set = {}

		for k,v in pairs(hem.history) do
			for i,v in ipairs(v) do
				set[k .. "_" .. tostring(i)] = v
			end
		end

		return set
	end

	hem.state.import["history"] =
	function(lines)
		local oldb = hem.builtin_name
		local cur = oldb

-- the index will be ordered so we can ignore that entirely, it's just there
-- to avoid collisions in key = ..
-- should also encode timestamp and cwd in meta so we can join / reorder states
-- between multiple instances.
		for k,v in pairs(lines) do
			local group, _ = unpack(string.split(k, "_"))
			if cur ~= group then
				cur = group
				hem.builtin_name = cur
			end
			v = string.trim(v)
			if #v > 0 then
				hem.append_history(v)
			end
		end

		hem.builtin_name = oldb
	end

	end
end
