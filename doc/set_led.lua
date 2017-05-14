-- set_led
-- @short: Change the active state of a single LED.
-- @inargs: id, num, state
-- @longdescr: Set the state of the specific led (0..n leds) on
-- led controller (id, > 0) to state (1: on, not1: off).
-- @group: iodev
-- @cfunction: setled
-- @related: led_intensity, set_led_rgb, controlled_leds
function main()
#ifdef MAIN
	set_led(1, 0, 1);
#endif
end
