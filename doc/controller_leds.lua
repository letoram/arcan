-- controller_leds
-- @short: Return the number of addressable LEDs on the specified controller.
-- @inargs: ctrlind
-- @outargs: nleds
-- @group: iodev
-- @cfunction: arcan_lua_n_leds
-- @flags:
function main()
#ifdef MAIN
	for i=0,9 do
		print(tostring( controller_leds(i) ));
#endif
end
