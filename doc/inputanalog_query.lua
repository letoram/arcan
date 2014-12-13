-- inputanalog_query
-- @short: Query analog devices for filtering details.
-- @inargs: *devnum*, *axnum*, *rescan*
-- @outargs: analogtbl_tbl or analogtbl
-- @longdescr: This function allows you to query a device for analog
-- device options and current values, either globally (no arguments,
-- table of analogtbl returned) or from a specific device (and, optionally)
-- axis. If rescan is set to != 0, the input subsystem will first scan for
-- new devices.
-- @note: rescan is a rather costly operation and may possibly lose data
-- for devices that doesn't identify properly.
-- @note: analogtbl members:
-- devid, subid (device and axis indices)
-- upper_bound, lower_bound (value > upper and < lower will be discarded)
-- deadzone (abs(value) within deadzone will be discarded.
-- kernel_size, number of samples in for every sample out.
-- mode(drop), analog processing disabled
-- mode(pass), emit every sample
-- mode(avg), average the kernel_size buffer
-- mode(latest), only emit when buffer full, and keep only most recent value
-- @group: iodev
-- @cfunction: inputanalogquery
-- @related:
function main()
#ifdef MAIN
	local antbl = inputanalog_query();
	print(#antbl, "devices found.");
	for i = 1, #antbl do
		print("-----\n");
		print(string.format("%d:%d, upper:%d, lower: %d, deadzone: %d, " ..
			"kernel_size: %d, filter_mode: %s\n", antbl[i].devid, antbl[i].subid,
			antbl[i].upper_bound, antbl[i].lower_bound, antbl[i].deadzone,
			antbl[i].kernel_size, antbl[i].mode));
		print("-----\n\n");
	end

#endif

#ifdef ERROR
	inputanalog_query("ind");
#endif
end
