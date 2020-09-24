-- input_capabilities
-- @short: query platform layer or target for input capabilities
-- @inargs:
-- @inargs: vid:fsrv
-- @outargs: captbl, ident
-- @longdescr: This function can be used to query the platform (default)
-- or a frameserver (providing a valid *fsrv* argument) for its current
-- set of input capabilities in terms of devices (both cases) and data
-- types (frameserver only).
-- The returned table is key indexed of booleans indicating whether the
-- type is supported or not. A frameserver may update this mask for a
-- segment at will. When the mask is changed, an "input_mask" event will
-- be sent to the frameservers assigned event handler. This mask will
-- be applied to samples provided through ref:target_input.
-- For the platform, the set may also change when devices are added and
-- removed in response to a device appearing and removing.
-- The set of provided or accepted devices may be zero, one or many of the
-- following: "keyboard, "mouse", "game", "touch", "position", "orientation",
-- "eyetracker".
-- The set of accepted datatypes may be zero, one or many of the following:
-- "analog", "digital", "translated", "touch", "eyes".
--
-- @group: iodev
-- @cfunction: inputcap
-- @related:
function main()
#ifdef MAIN
	for k,v in pairs(input_capabilities()) do
		print(k, v);
	end
#endif
end
