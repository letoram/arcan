-- toggle_mouse_grab
-- @short: Switch grabbing mode for the primary mouse device.
-- @inargs: *mode
-- @outargs: grabastate 
-- @longdescr: When running the engine inside another windowing 
-- system, it may be necessary to forcibly gain control over the
-- mouse device in order for movement samples to be useful and
-- for avoiding losing input control. This function can be used
-- to turn this ability on and off.
-- @note: If mode isn't specified, the current state will be inverted.
-- @note: This requires input control in the underlying platform
-- support, which might not be present for all platforms. 
-- @note: Be careful on linux/X11 when this is used and a debugger is attached,
-- breaking into the debugger with the mouse device locked may prevent you
-- from using or recovering interface controls (depending on the window
-- manager in use).
-- @group: iodev 
-- @cfunction: arcan_lua_mousegrab
function main()
#ifdef MAIN
	print("grabstate:", tostring(toggle_mouse_grab()));
	print("grabstate:", tostring(toggle_mouse_grab()));
#endif
end
