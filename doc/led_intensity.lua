-- led_intensity
-- @short: Change the intensity of a specifid LED light.
-- @inargs: ctrlid, ledid, intensity
-- @group: iodev
-- @cfunction: led_intensity
-- @related: set_led, set_led_rgb, controller_leds
-- @note: the LED set of functions can be disabled at buildtime,
-- if this symbol is set to nil, then the engine has been compiled
-- without support for LEDs.
-- @note: Accepted range is 0..255, though not all controllers support
-- more variations than 0 (off) and > 0 (fullbright).
function main()
#ifdef MAIN
	led_intensity(0, 1, 255);
#endif
end
