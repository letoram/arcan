-- decode_modifiers
-- @short: Convert a modifier-bitmap to a textual representation.
-- @inargs: modval, *separator*
-- @outargs: modtbl or modstr
-- @longdescr: The input table that is provided as part of the _input
-- event handler has a modifiers field that is a bitmap of different
-- modifier states.
-- This bitmap can be converted to either an integer indexed table
-- of text representations of each present modifier, or as a single
-- concatenated string with the character in *separator* added between
-- the individual modifiers.
-- If the *separator* argument is provided, and is a non-empty string,
-- then *modstr* will be returned. Otherwise *modtbl* will be returned.
-- The different possible text representations of the modifiers are:
-- "lshift", "rshift",
-- "lalt", "ralt",
-- "lctrl", "rctrl",
-- "lmeta", "rmeta",
-- "num", "caps", "mode"
-- @note: If the separator is an empty string, the '_' character will
-- be used as separator instead.
-- @note: There is also a modifier bit to indicate if the event was a
-- repeat (if the input platform supports that). This will not be added
-- to the decoded output as it would subtly break a lot of 'naive'
-- approaches to keybindings.
-- @group: system
-- @cfunction: decodemod
-- @flags:
function main()
#ifdef MAIN
	print( table.concat(decode_modifiers( 0xffffff ), "\n") );
	print( decode_modifiers(0xffffff, "_") );
#endif
end
