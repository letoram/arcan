-- input_remap_translation
-- @short: Reset or modify platform level keyboard translation
-- @inargs: number:devid, number:action, string:arg_1, ...
-- @inargs: number:devid, number:action, bool:extract, string:arg_1, ...
-- @outargs: bool:ok, string:reason or nbiotbl
-- @longdescr: For some low level platforms it makes sense modifying input
-- translation before the inputs are processed and forwarded onwards and forego
-- patchin in the scripting layer. The main case where this has caused problems
-- is for Arcan running as the main display server on Linux and BSD machines,
-- where the set of tables, configuration and so on are highly OS specific and
-- can get quite complicated. This function can be used to define and tune such
-- a mapping.
--
-- The *devid* is provided by input devices and is thus discovered dynamically,
-- but it can also be indirectly probed by sweeping negative indices in the
-- way shown in the example further below.
--
-- The *action* can be one out of:
-- TRANSLATION_CLEAR, TRANSLATION_SET and TRANSLATION_REMAP.
-- TRANSLATION_CLEAR is to revert as close to as the initial state as possible.
-- TRANSLATION_SET is to set/override a complete map.
-- TRANSLATION_REMAP is to add a specific remapping.
--
-- The set of string arguments following the action will be raw-forwarded to
-- the input platform and is thus platform dependent.
--
-- It is also possible to get a readable representation of the platform input
-- map through the *extract* parameter form. With TRANSLATION_SET this will
-- just give you the map based on the spec as an iostream (see
-- ref:open_nonblock). With TRANSLATION_REMAP this will instead provide the
-- current active map. No local modifications will be made with the *extract*
-- form.
--
-- The constant API_ENGINE_BUILD can be used to obtain which input platform
-- is currently in use, which mutates the interpretation and effect of the
-- various actions.
--
-- A false result means that the feature is not supported by the platform,
-- and *reason* is set to some short error message.
--
-- @note: for the 'evdev' platform, the order and contents of the argument
-- strings corresponds to xkb 'layout' -> 'model' -> 'variant' -> 'options'
--
-- @group: iodev
-- @cfunction: inputremaptranslation
-- @related:
function main()
#ifdef MAIN
	if string.match(API_ENGINE_BUILD, "evdev") then
		local ind = -1
		while	(input_remap_translation(ind, TRANSLATION_SET,
			"us,cz,de", "logicordless", "basic", "grp:alt_shift_toggle")) do
			ind = ind - 1
		end
	end
#endif

#ifdef MAIN2
	local err, msg = input_remap_translation(6666, TRANSLATION_CLEAR)
	if err then
		warning(msg)
	end
#endif

#ifdef ERROR1
#endif
end
