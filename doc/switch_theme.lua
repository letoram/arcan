-- switch_theme
-- @short: Reset the engine and relaunch with the same input arguments
-- but a different active theme.
-- @inargs: themename
-- @note: This is treated as an event, so the current event queue will
-- be emptied before the switch takes place as to prevent data-loss in frameservers.
-- @group: system
-- @cfunction: arcan_lua_switchtheme

