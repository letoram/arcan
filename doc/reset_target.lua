-- reset_target
-- @short: Request that a target resets to a known starting state.
-- @inargs: targetid
-- @longdescr: This functions inserts an event into the target process
-- linked to *targetid*, requesting that the process should be reset
-- to an initial safe-state (which may or may not exist depending on
-- the target).
-- @group: targetcontrol
-- @cfunction: arcan_lua_targetreset

