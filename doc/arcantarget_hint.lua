-- arcantarget_hint
-- @short: Send a hint state through a frameserver tied to an arcan instance
-- @inargs: string:kind, tbl:hint
-- @inargs: vid:fsrv, string:kind, tbl:hint
-- @outargs: bool:ok
-- @longdescr: When the arcan-in-arcan platform is used (arcan_lwa binary) it
-- can forward hints like any normal arcan-shmif client. These are from a
-- subset of the ones that can be found in ref:launch_target.
-- If *fsrv* is not provided, the default output, WORLDID, will be used.
-- Otherwise it is expected that *fsrv* references a valid frameserver tied
-- to a valid source from ref:define_arcantarget or retrieved through the
-- _adopt event handler.
-- The currently supported ones are:
-- * input_label and the format of the *hint* table matches that of the description in ref:launch_target.
-- * ident with a string:message field in *hint*, provided as the new segment runtime identity (e.g. document name)
-- * alert with a string:message field in *hint*, provided as the reason for user attention
-- * statesize with a int:size field in *hint*, provided as the estimated current output size of a state-save
-- @group: targetcontrol
-- @cfunction: arcantargethint
-- @related:
function main()
#ifdef MAIN
	arcantarget_hint("input_label",
	{
		labelhint = "test",
		description = "this should register as a digital button",
	})
#endif

#ifdef ERROR1
	arcantarget_hint(BADID)
#endif

#ifdef ERROR1
	arcantarget_hint(BADID, 1)
#endif
end
