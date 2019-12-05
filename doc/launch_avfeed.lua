-- launch_avfeed
-- @short: Launch a customized frameserver
-- @inargs:
-- @inargs: string:argument
-- @inargs: string:argument, string:mode
-- @inargs: string:argument, string:mode, func:callback
-- @outargs: vid:newvid, aid:newaid, string:guid, int:cookie
-- @longdescr: launch_avfeed is intended for launching authoritative frameservers
-- for the 'decode', 'terminal' and 'avfeed' archetypes.
-- The 'decode' archetype is used for providing streaming audio and video decoding
-- of some input source defined by the *argument* string.
-- The 'terminal' archetype is used for spawning an interactive command-line
-- interface, and the 'avfeed' is for unspecified custom input providers,
-- typically for binding to other media frameworks.
-- The support for these archetypes are probed at engine startup and set in the
-- global variable FRAMESERVER_MODES. If no *mode* argument is provided, it will
-- default to 'avfeed'.
-- The possible values for *argument* is dependent on the frameserver implementation,
-- where the defaults can be probed by running the respective binaries standalone
-- with the ARCAN_ARG=help environment set, though this can vary slightly with the
-- underlying OS. It uses a special key1:key2=value with a tab character acting
-- as element separator, and the tab character itself being forbidden.
-- If *avmode* is not specified, it defaults to 'avfeed'.
-- As with other frameserver- related management functions, it is advised that
-- you provide a handler callback function directly or via the ref:target_updatehandler
-- call. The contents and behavior of this callback function is described in detail
-- in ref:launch_target.
-- If successful, new audio and video reference identifiers are returned, along
-- with a per-instance unique uid (base-64 encoded), intended to be used to regain
-- tracking should a connection be lost, by accident or voluntary.
-- @note: The reason *argument* comes before *mode* is for historical reasons
-- as the function name previously held a different behavior and use.
-- @note: SECURITY- alert: allowing the _terminal frameserver is currently
-- a possible scriptable way of running arbitrary programs within the context
-- of the terminal, partly through the possible exec= argument but also by
-- manually inputting commands through ref:target_input. This can be hardened
-- in multiple ways: by intercepting ref:target_input and only allow if it is visible
-- (appl specific solution), by intercepting ref:launch_avfeed and filtering argstr
-- or by simply not allowing the terminal frameserver (disable at buildtime or
-- specify a different set of afsrv_ binaries using the --binpath argument).
-- @group: targetcontrol
-- @cfunction: setupavstream
-- @related: launch_target, define_recordtarget, net_open, net_listen
function main()
#ifdef MAIN
	local vid, _, guid = launch_avfeed("", "terminal",
		function(source, status)
			print("[new event]");
			for k,v in pairs(status) do
				print("", k, v);
			end
			if (status.kind == "resized") then
				resize_image(source, status.width, status.height);
			end
		end
	);
	show_image(vid);
	print("launched as", vid, guid);
#endif

#ifdef ERROR
#endif
end
