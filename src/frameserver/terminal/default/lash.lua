--
-- basic chain-loading harness/protective shell
--
-- designed to be static-included into afsrv_terminal cli=lua mode, and act as
-- an outer 'bootstrap' shell in order to live use/develop own shell rules and
-- still have a workable fallback. As such the focus is to reach basic utility
-- and stability, then leave fancier functions to user provided scripts.
--
--

-- this table is exposed to the user shell, and can be used to pass state
-- between invocations of the same script (should it fail during execution)
-- which is especially important for ongoing jobs that should not just
-- terminate.
--
-- The flow to consider here is:
--      :process() -> [process_jobs]
--
-- This just maps into 'setup_window' that switched the window into readline
-- and a closure that tokenise -> 'parse_tokens' -> run_job or commands[cmd].
--
-- To add a new builtin- command, just extend the commands table below.
--
lash =
{
	jobs = {}
}

-- A lexer for the command line intended to provide some shared building block
-- the 'simple' mode basically just escapes strings, while the normal provides
-- some operators, primitive types and symbols. This is derived from pipeworld
lash.tokenize_command =
function(wnd, msg, simple)
	return
		{},
		nil, -- error
		0, -- error ofs
		{} -- type table (e.g. STRING, NUMBER, BOOLEAN, SYMBOL)
end

-- 'Messages' are shell messages to the user to print on refresh, it is cached
-- based on window width and rebuilt on resize to allow wrapping / linebreaks.
lash.messages = {}
lash.message_fmt = {}

-- buffer of commands as the raw strings (not the lexed output).
lash.history = {}

-- 5.3 -> 5.1 conversion hack.
unpack = table.unpack or unpack

local setup_window
local commands = {}
local fallback_handlers = {}
local history_limit = 500
local prompt_row = 1
local message_offset = 0
local readline
local readline_row = 0

-- it is just always useful
if not string.split then
function string.split(instr, delim)
	if (not instr) then
		return {}
	end

	local res = {}
	local strt = 1
	local delim_pos, delim_stp = string.find(instr, delim, strt)

	while delim_pos do
		table.insert(res, string.sub(instr, strt, delim_pos-1))
		strt = delim_stp + 1
		delim_pos, delim_stp = string.find(instr, delim, strt)
	end

	table.insert(res, string.sub(instr, strt))
	return res
end
end

if not string.trim then
function string.trim(s)
	local n = s:find"%S"
	return n and s:match(".*%S", n) or ""
end
end

local function get_prompt(wnd)
	local wd = wnd:chdir()
	local path_limit = 8

	local dirs = string.split(wd, "/")
	local dir = "/"
	if #dirs then
		dir = dirs[#dirs]
	end

	return "[" .. dir .. "]$ "
end

local function add_split(wnd, msg, cap, dst)
	assert(type(msg) == "string", debug.traceback())
	msg = string.gsub(msg, "\t", "  ")

	local len = wnd:utf8_len(msg)
	local blen = #msg

	if len <= cap then
		table.insert(dst, msg)
		return
	end

-- better word-breaking rules should go here (e.g. align to whitespace, ...)
-- and possibly tag the cell as a 'odd_row', 'even_row' thing so that selection
-- acknowledges wrapping.
	local count = 0

	local start = 1
	local pos = 1

	while start < blen and start > 0 do
		while count < cap-1 and pos > 0 do
			pos = wnd:utf8_step(msg, pos)
			count = count + 1
		end

-- broken message or no more characters
		if pos < 0 then
			if start < blen then
				table.insert(dst, string.sub(msg, start))
			end
			start = blen
			break
		end

		table.insert(dst, string.sub(msg, start, pos))
		start = wnd:utf8_step(msg, pos)
		pos = start
		count = 0
	end

-- now we can also update the content hint, letting any outer graphics shell
-- decorate with scroll bars
end

local function draw(wnd)
	wnd:erase()
	local cols, rows = wnd:dimensions()
	local count = #lash.message_fmt
	local rlpos = rows-1

	if count < rows then
		for i=1,count do
			local msg = lash.message_fmt[i]
			wnd:write_to(1, i - 1, msg)
		end
		rlpos = count
	else
		for i=1,rows - 1 do
			local msg = lash.message_fmt[#lash.message_fmt - i + 1]
			wnd:write_to(1, rows - i - 1, msg)
		end
	end

-- change the bounding-box (which readline will clear) to fit what we have printed
	if readline then
		readline_row = rlpos
		readline:bounding_box(0, readline_row, cols, readline_row)
		readline:set_prompt(get_prompt(wnd))
	end
end

local function add_message(wnd, msg, cols)
	if not msg or #msg == 0 then
		return
	end

	if type(msg) == "table" then
	elseif type(msg) == "string" then
		msg = string.split(msg, "\n")
	end

	for _,v in ipairs(msg) do
		assert(type(v) == "string")
		add_split(wnd, v, cols, lash.message_fmt)
	end

	table.insert(lash.messages, msg)
end

-- Run [name.lua] via require from HOME/.arcan/lash or XDG_CONFIG_HOME and
-- route through pcall. Propagate the return (which should be a completed run
-- or the error message). This will re-activate the outer fallback
-- implementation.
local function run_usershell(wnd, name)
	local dirs = {}

	if os.getenv('LASH_BASE') then
		table.insert(dirs, string.format("%s/", os.getenv('LASH_BASE')))
	end

	if os.getenv('HOME') then
		table.insert(dirs, string.format("%s/.arcan/lash/", os.getenv('HOME')))
	end

	if os.getenv('XDG_CONFIG_HOME') then
		table.insert(dirs, string.format("%s/arcan/lash/", os.getenv('XDG_CONFIG_HOME')))
	end

-- prepend the search dirs, reason why we do not substitute them completely is to be able
-- to have the usershell scripts themselves require other lua modules or luarocks ones
	if #dirs > 0 then
		for _,v in ipairs(dirs) do
			local path = v .. name .. ".lua"
			local file = io.open(path)
			if file then
				local fptr, msg = loadfile(v .. name .. ".lua")
				if not fptr then
					return false, msg
				end
				lash.scriptdir = v
				local ok, msg = pcall(fptr)
				if not ok then
					msg = string.split(msg, ": ")
					local res = {"usershell (" .. name .. ") failed: "}
					for i,v in ipairs(msg) do
						table.insert(res, string.rep("\t", i-1) .. v)
					end
					lash.lasterr = res
					return false, res
				else
					return true
				end
			end
		end
	end

	return false, "shell " .. name .. " not found in ($LASH_BASE, $HOME/.arcan/lash or $XDG_CONFIG_HOME)"
end

local function finish_job(wnd, job, code, cols)
-- it's dead, flush the output
	while job.out do
		local msg = job.out:read()
		if not msg or #msg == 0 then
			break
		end

		add_message(msg, cols)
	end

	if code ~= 0 and job.cmd then
		add_message(wnd, "! " .. job.cmd .. " terminated with " .. tostring(code), cols)
	end
end

local function process_jobs(wnd)
	if #lash.jobs == 0 then
		return
	end

	local cols, _ = wnd:dimensions()

-- Just flush line-buffered and check if the process is still alive,
-- traverse backwards for table.remove to work. Use time-elapsed to
-- not let the job saturate our processing.
	for i=#lash.jobs,1 do
		local job = lash.jobs[i]

		while job.out do
			local msg = job.out:read()
			if not msg then
				break
			end

			add_message(wnd, msg, cols)
		end

		if job.pid then
			local running, code = wnd:pwait(job.pid)
			if not running then
				finish_job(wnd, job, code, cols)
				table.remove(lash.jobs, i)
			end
		end
	end

	draw(wnd)
end

function fallback_handlers.resized(wnd)
	local cols = wnd:dimensions()

	lash.message_fmt = {}
	local msg = lash.messages
	for i=#msg,1,-1 do
		if type(msg[i]) == "table" then
			for _,v in ipairs(msg[i]) do
				add_split(wnd, v, cols, lash.message_fmt)
			end
		else
			add_split(wnd, msg[i], cols, lash.message_fmt)
		end
	end

	draw(wnd)
end

fallback_handlers.recolor = draw

function commands.shell(wnd, name)
	if not name then
		name = "default.lua"
	end

	local res, msg = run_usershell(wnd, name)
	if not res then
		return msg
	end
end

function commands.lasterr(wnd)
	local cols, _ = wnd:dimensions()

	if lash.lasterr then
		for _,v in ipairs(lash.lasterr) do
			add_split(wnd, v, cols, lash.message_fmt)
		end
	end
end

function commands.cd(wnd, path)
	if not path then
		return wnd:chdir()
	end

	wnd:chdir(path)
end

function commands.flood(wnd, n)
	local cols, rows = wnd:dimensions()

	for i=1,n do
		add_message(wnd, "line " .. tostring(i), cols)
	end
end

function commands.debug(wnd)
-- integrate with mobdebug or 'debugger.lua' from luarocks both
-- (require('mobdebug').lusten()
	if lash.debug_handler then
		lash.debug_handler = nil
		return
	end

	local ok, dbg = pcall(require, 'debugger')
	if not ok then
		return "couldn't load debugger module"
	end
	dbg()
end

local function run_job(wnd, cmd, argtbl)
	local cmdstr = cmd .. " " .. table.concat(argtbl, " ")

	local _, out, err, pid = wnd:popen(cmdstr, "r")
	if not pid then
		return "could not spawn " .. cmd
	end

	local job =
	{
		wd = wnd:chdir(),
		pid = pid,
		out = out,
		err = err,
		cmd = cmd
	}

	table.insert(lash.jobs, job);
end

-- this is mainly a template for a more advanced language, here we only really care
-- about symbol, string, number, boolean
local function parse_tokens(wnd, tokens, types)
	local cmd = tokens[1]
	if cmd[1] ~= types.SYMBOL and cmd[1] ~= types.STRING then
		return "parser error: expecting built-in symbol or string"
	end

	local val = cmd[2]

	local arg = {}
	for i=2,#tokens do
		local tok = tokens[i]
		if tok[1] == types.SYMBOL or tok[1] == types.STRING then
			local outstr = string.gsub(tok[2], '"', "\\\"")
			table.insert(arg, outstr)
		elseif tok[1] == types.NUMBER then
			table.insert(arg, tok[2])
		elseif tok[1] == types.BOOLEAN then
			table.insert(arg, tok[2])
-- could be used to build our own command pipeline here instead rather than letting
-- popen/sh do all the work
		elseif tok[1] == types.OPERATOR then
			if tok[2] == types.OP_PIPE then
				table.insert(arg, " | ")
			else
				return "parser error: unsupported operator"
			end
		else
			return "parser error: bad token (" .. table.concat(tok, ",") .. ")"
		end
	end

	if commands[val] then
		return commands[val](wnd, unpack(arg))
	else
		return run_job(wnd, val, arg)
	end
end

local function add_history(msg)
	if not lash.history[msg] then
		table.insert(lash.history, msg)
		lash.history[msg] = true
	end

	if #lash.history > history_limit then
		table.remove(lash.history, 1)
	end
end

local function readline_handler(wnd, self, line)
	if not line or #line == 0 then
		setup_window(wnd)
		return
	end

	local tokens, msg, ofs, types = lash.tokenize_command(line, true)
	local cols, _ = wnd:dimensions()

-- add command visually to message history
	local cmd = "$ " .. line
	add_message(wnd, cmd, cols)

	if not msg then
		msg = parse_tokens(wnd, tokens, types)
	end

-- add to window message history, this is forwarded to the user script rules
	if msg then
		add_message(wnd, msg, cols)
	end

-- remember the input [if unique] and re-arm the window
	add_history(line)
	setup_window(wnd)
end

-- tokenize and dispatch command from set of built-ins, basically only help,
-- cd, exec and shell(scriptname), can also use that for verification.
setup_window =
function(wnd)
	wnd:revert()
	readline = nil
	wnd:set_handlers(fallback_handlers)

	readline =
	wnd:readline(
		function(self, line)
			if lash.debug_handler then
				lash.debug_handler(function() readline_handler(wnd, self, line); end)
			else
				readline_handler(wnd, self, line)
			end
		end
	)

	readline:set_prompt(get_prompt(wnd))
	readline:set_history(lash.history)
end

local function init()
-- root is set in global scope if running from afsrv_terminal
	if not tui or not tui.root then
		tui = require 'arcantui'
		lash.root = tui.open("lash", "", {handlers = fallback_handlers})
	else
		lash.root = tui.root
	end

	local shellname = os.getenv("LASH_SHELL") and os.getenv("LASH_SHELL") or "default"
	local res, msg = run_usershell(lash.root, shellname)
	setup_window(lash.root)

	if not res then
		local cols, _ = lash.root:dimensions()
		add_message(lash.root, msg, cols)
	end

	lash.root:refresh()
end

-- [lexer.lua] starts here
-- vendored as to be able to pull it all in binary as static,
--
-- parse-function takes a string and returns a table of tokens
-- where each token is a tuple with [1] being a token from the
-- token-table, [2] any associated value and [3] the message
-- byte offset of the token start.
--
local tokens = {
-- basic data types
	SYMBOL   = 1,
	FCALL    = 2,
	OPERATOR = 3,
	STRING   = 4,
	NUMBER   = 5,
	BOOLEAN  = 6,
	IMAGE    = 7,
	AUDIO    = 8,
	VIDEO    = 9,  -- (dynamic image and all external frameservers)
	NIL      = 10, -- for F(,,) argument passing
	CELL     = 11, -- reference to a cell
	FACTORY  = 12, -- cell 'producer' (arguments are type + type arguments)
	VARTYPE  = 13, -- dynamically typed, function validates on call
	VARARG   = 14, -- a variable number of arguments of the previous type,
	               -- combine with VARTYPE for completely dynamic

-- permitted operators, match to operator table below
	OP_ADD   = 20,
	OP_SUB   = 21,
	OP_DIV   = 22,
	OP_MUL   = 23,
	OP_LPAR  = 24,
	OP_RPAR  = 25,
	OP_MOD   = 26,
	OP_ASS   = 27,
	OP_SEP   = 28,
	OP_PIPE  = 29,
	OP_ADDR  = 30,
	OP_RELADDR  = 31,
	OP_SYMADDR  = 32,
	OP_STATESEP = 33,
	OP_NOT      = 34,
	OP_POUND    = 35,
	OP_AND      = 36,

-- return result states
	ERROR    = 40,
	STATIC   = 41,
	DYNAMIC  = 42,

-- special actions
	FN_ALIAS = 50, -- commit entry to alias table,
	EXPREND  = 51
}

local operators = {
['+'] = tokens.OP_ADD,
['-'] = tokens.OP_SUB,
['*'] = tokens.OP_MUL,
['/'] = tokens.OP_DIV,
['('] = tokens.OP_LPAR,
[')'] = tokens.OP_RPAR,
['%'] = tokens.OP_MOD,
['='] = tokens.OP_ASS,
[','] = tokens.OP_SEP,
['|'] = tokens.OP_PIPE,
['$'] = tokens.OP_RELADDR,
['@'] = tokens.OP_SYMADDR,
[';'] = tokens.OP_STATESEP,
['!'] = tokens.OP_NOT,
['#'] = tokens.OP_POUND,
['&'] = tokens.OP_AND
}

-- operators that we ignore and treat as 'whitespace terminated strings' in
-- simple mode (which is more appropriate for an interactive CLI)
local simple_operator_mask = {
['+'] = true,
['-'] = true,
['/'] = true,
[','] = true,
['='] = true,
}

local constant_ascii_a = string.byte("a")
local constant_ascii_f = string.byte("f")

local function isnum(ch)
	return (string.byte(ch) >= 0x30 and string.byte(ch) <= 0x39)
end

local function add_token(state, dst, kind, value, position, data)
-- lex- level optimizations can go here
	table.insert(dst, {kind, value, position, last_position, data})
	state.last_position = position
end

local function issymch(state, ch, ofs)
-- special character '_', num allowed unless first pos
	if isnum(ch) or ch == "_" or ch == "." or ch == ":" then
		return ofs > 0
	end

-- numbers and +- are allowed on pos2 if we have $ at the beginning
	local byte = string.byte(ch)
	if state.buffer == "$" then
		if ch == "-" or ch == "+" then
			return true
		end
	end

	return
		(byte >= 0x41 and byte <= 0x5a) or (byte >= 0x61 and byte <= 0x7a)
end

local lex_default, lex_num, lex_symbol, lex_str, lex_err, lex_whstr
lex_default =
function(ch, tok, state, ofs)
-- eof reached
	if not ch or #ch == 0 or ch == "\0" then
		if #state.buffer > 0 then
			state.error = "(def) unexpected end, buffer: " .. state.buffer
			state.error_ofs = ofs
			return lex_error
		end
		return lex_default
	end

-- alpha? move to symbol state
	if issymch(state, ch, 0) then
		state.buffer = ch
		return state.simple and lex_whstr or lex_symbol

-- number constant? process and switch state
	elseif isnum(ch) then
		state.number_fract = false
		state.number_hex = false
		state.number_bin = false
		state.base = 10
		return lex_num(ch, tok, state, ofs)

-- fractional number constant, set number format and continue
	elseif ch == "." then
		if state.simple then
			state.buffer = ch
			return lex_whstr
		else
			state.number_fract = true
			state.number_hex = false
			state.number_bin = false
			state.base = 10
			return lex_num
		end
	elseif ch == "\"" then
		state.buffer = ""
		state.lex_str_ofs = ofs
		return lex_str

	elseif ch == " " or ch == "\t" or ch == "\n" then
-- whitespace ? ignore
		return lex_default

	elseif operators[ch] ~= nil then
		if state.operator_mask[ch] then
			state.buffer = ch
			return lex_whstr
		end

-- if we have '-num' ' -num' or 'operator-num' then set state.negate
		if ch == "-" then
			if not state.last_ch or
				state.last_ch == " " or
				(#tok > 0 and tok[#tok][1] == tokens.OPERATOR) then
				state.negate = true
				state.number_fract = false
				state.number_hex = false
				state.number_bin = false
				state.base = 10
				return lex_num
			end
		end
		add_token(state, tok, tokens.OPERATOR, operators[ch], ofs)
		return lex_default
	else
-- switch to error state, won't return
		state.error = "(def) invalid token: " .. ch
		state.error_ofs = ofs
		return lex_error
	end
end

lex_error =
function()
	return lex_error
end

-- used in simple mode where a lot of operators and symbols become
-- strings instead, the only thing that terminates it is end,
-- whitespace, matched " or a non-masked operator
lex_whstr =
function(ch, tok, state, ofs)
	if not ch or #ch == 0  or ch == "\0" then
		if #state.buffer > 0 then
			add_token(state, tok, tokens.STRING, state.buffer, ofs)
		end
		state.whstr_escape = nil
		return lex_default
	end

	if state.whstr_escape then
		state.whstr_escape = nil
		state.buffer = state.buffer .. ch
		return lex_whstr
	end

	if ch == ' ' or ch == '\t' or ch == '\n' or ch == '"' then
		add_token(state, tok, tokens.STRING, state.buffer, ofs)
		state.buffer = ""
		return lex_default

	elseif operators[ch] and not state.operator_mask[ch] then
		add_token(state, tok, tokens.STRING, state.buffer, ofs)
		state.buffer = ""
		add_token(state, tok, tokens.OPERATOR, operators[ch], ofs)
		return lex_default

	elseif ch == '\\' then
		state.whstr_escape = true
	else
		state.buffer = state.buffer .. ch
	end

	return lex_whstr
end

lex_num =
function(ch, tok, state, ofs)
	if isnum(ch) then
		if state.number_bin and (ch ~= "0" and ch ~= "1") then
			state.error = "(num) invalid binary constant (" .. ch .. ") != [01]"
			state.error_ofs = ofs
			return lex_error
		end
		state.buffer = state.buffer .. ch
		return lex_num
	end

	if ch == "." then
		if state.number_fract then
			state.error = "(num) multiple radix points in number"
			state.error_ofs = ofs
			return lex_error

		else
-- note, we need to check what the locale radix-point is or tonumber
-- will screw us up on some locales that use , for radix
			state.number_fract = true
			state.buffer = state.buffer .. ch
			return lex_num
		end

	elseif ch == "b" and not state.number_hex then
		if state.number_bin or
			#state.buffer ~= 1 or
			string.sub(state.buffer, 1, 1) ~= "0" then
			state.error = "(num) invalid binary constant (0b[01]n expected)"
			state.error_ofs = ofs
			return lex_error
		else
			state.number_bin = true
			state.base = 2
			return lex_num
		end
	elseif ch == "x" then
		if state.number_hex or
			#state.buffer ~= 1 or
			string.sub(state.buffer, 1, 1) ~= "0" then
			state.error = "(num) invalid hex constant (0x[0-9a-f]n expected)"
			state.error_ofs = ofs
			return lex_error
		else
			state.number_hex = true
			state.base = 16
			return lex_num
		end
	elseif string.byte(ch) == 0 then
	else
		if state.number_hex then
			local dch = string.byte(string.lower(ch))

			if dch >= constant_ascii_a and dch <= constant_ascii_f then
				state.buffer = state.buffer .. ch
				return lex_num
			end
-- other characters terminate
		end
	end

	local num = tonumber(state.buffer, state.base)
	if not num then
-- case: def(-) -> num(-) then other operator or non-numeric literal/symbol
-- need to revert back to default and treat as operator
		if state.negate and #state.buffer == 0 then
			state.negate = false
			add_token(state, tok, tokens.OPERATOR, tokens.OP_SUB, ofs)
			return lex_default(ch, tok, state, ofs)
		end

		state.error = string.format("(num) invalid number (%s)b%d", state.buffer, state.base)
		state.error_ofs = ofs
		return lex_error
	end

	if state.negate then
		num = num * -1
		state.negate = false
	end
	add_token(state, tok, tokens.NUMBER, num, ofs)
	state.buffer = ""
	return lex_default(ch, tok, state, ofs)
end

lex_symbol =
function(ch, tok, state, ofs)
-- sym+( => treat sym as function
	if ch == "(" and #state.buffer > 0 then
		add_token(state, tok, tokens.FCALL, string.lower(state.buffer), ofs, state.got_addr)
		state.buffer = ""
		state.got_addr = nil
		return lex_default

	elseif issymch(state, ch, #state.buffer) then
-- track namespace separately
		if ch == "." then
			if state.got_addr then
				state.error = '(str) symbol namespace selection with . only allowed once per symbol'
				state.error_ofs = state.lex_str_ofs
				return lex_error
			end

			state.got_addr = string.lower(state.buffer)
			state.buffer = ""

			return lex_symbol
		end

-- or buffer and continue
		state.buffer = state.buffer .. ch
		return lex_symbol
	else

-- we are done
		if state.got_addr then
			add_token(state, tok, tokens.SYMBOL, state.got_addr, ofs, string.lower(state.buffer))
		else
			local lc = string.lower(state.buffer)
			if lc == "true" then
				add_token(state, tok, tokens.BOOLEAN, true, ofs)
			elseif lc == "false" then
				add_token(state, tok, tokens.BOOLEAN, false, ofs)
			else
				add_token(state, tok, tokens.SYMBOL, lc, ofs)
			end
		end

		state.buffer = ""
		state.got_addr = nil
		return lex_default(ch, tok, state, ofs)
	end
end

lex_str =
function(ch, tok, state, ofs)
	if not ch or #ch == 0 or ch == "\0" then
		state.error = '"(str) unterminated string at end'
		state.error_ofs = state.lex_str_ofs
		return lex_error
	end

	if state.in_escape then
		state.buffer = state.buffer .. ch
		state.in_escape = nil

	elseif ch == "\"" then
		add_token(state, tok, tokens.STRING, state.buffer, ofs)
		state.buffer = ""
		return lex_default

	elseif ch == "\\" then
		state.in_escape = true
	else
		state.buffer = state.buffer .. ch
	end

	return lex_str
end

-- the simple-mode ignored number conversion and treats arithmetic
-- operators and . as whitespace terminated strings
lash.tokenize_command =
function(msg, simple, opts)
	local ofs = 1
	local nofs = ofs
	local len = #msg

	local tokout = {}
	local state = {buffer = "", simple = simple}

-- allow operators vs string interpretation be controlled by the caller
	if simple then
		state.operator_mask = simple_operator_mask
	else
		state.operator_mask = {}
	end

	if opts then
		for k,v in pairs(opts) do
			state[k] = v
		end
	end

	local scope = lex_default

	local scopestr =
	function(scope)
		if scope == lex_default then
			return "default"
		elseif scope == lex_str then
			return "string"
		elseif scope == lex_num then
			return "number"
		elseif scope == lex_symbol then
			return "symbol"
		elseif scope == lex_whstr then
			return "symstring"
		elseif scope == lex_err then
			return "error"
		else
			return "unknown"
		end
	end

	local root = lash.root
	repeat
		nofs = root.utf8_step(msg, 1, ofs)
		local ch = string.sub(msg, ofs, nofs-1)

		scope = scope(ch, tokout, state, ofs)
		ofs = nofs
		state.last_ch = ch

	until nofs < 0 or nofs > len or state.error ~= nil
	scope("\0", tokout, state, ofs)

	return tokout, state.error, state.error_ofs, tokens
end

init()
while lash.root:process() do
	process_jobs(lash.root)
	lash.root:refresh()
end
