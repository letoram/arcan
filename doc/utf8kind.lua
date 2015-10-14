-- utf8kind
-- @short: Quick check an offset into a string
-- @inargs: offset
-- @outargs: state
-- @longdescr: Built-in support for internationalized strings is fairly
-- rudimentary, although the render_text class of functions handle UTF8
-- internally, no such support has been mapped into the built-in LUA VM.
-- This function is a quick helper to determine if you're about to
-- corrupt a UTF-8 string or not. state values:
-- 0 = 7bit character, 1 = start of char, 2 = middle of char.
-- @note: This is very primitive and was added before we included the
-- bitopts- LuaJIT extension into the codebase. It does not directly
-- help for validating UTF8 sequences, only for avoiding obvious truncation.
-- @group: system
-- @cfunction: utf8kind
function main()
#ifdef MAIN
	a = "åäö";
	for i=1,#a do
		print(utf8kind(a[i]));
	end
#endif
end
