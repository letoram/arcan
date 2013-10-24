-- decode_modifiers
-- @short:  Convert a modifiers bitmap (from a translated input event table) to a textual representation.
-- @inargs: modval 
-- @outargs: modtbl 
-- @longdescr: The input table that is called in input 
-- @group: system 
-- @cfunction: arcan_lua_decodemod
-- @flags: 
-- 1 0: 
function main()
#define MAIN
	print( decode_modifiers( 0xffffff ) );
#endif
end
