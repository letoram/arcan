-- target_verbose
-- @short: Increase frameserver callback verbosity
-- @inargs: tgtvid, *state*
-- @outargs:
-- @longdescr: Exposing hi-frequency events from a frameserver to the scripting
-- environment comes at a certain cost which although it may be negligible most
-- of the time, it is still unnecessary. This function can increase the level
-- of verbosity associated with a frameserver. An example for the use of this
-- function is to get raw timing and framestatus updates from video playback
-- (decode frameservers with a framequeue associated).
--
-- This behavior can be switched on or off dynamically by
-- setting state to 1/true(default) or 0/false.
-- @group: targetcontrol
-- @cfunction: targetverbose
-- @related:
function main()
#ifdef MAIN
#endif

#ifdef ERROR
#endif
end
