-- launch_avfeed
-- @short: Launch a customized frameserver
-- @inargs: *argstr*, *avmode*, *callback*
-- @outargs: vid, aid
-- @longdescr: launch_avfeed serves two purposes, over time it should be
-- the principal way to launch authoritative frameservers and unify the
-- others (load_movie etc.) and allow a quick and dirty interface for testing
-- and experimenting with custom ones through the AVFEED_LIBS AVFEED_SOURCES
-- compile time arguments. The global environment in FRAMESERVER_MODES
-- limits the possible arguments to avmode and is defined at compile time.
-- If *avmode* is not specified, it defaults to 'avfeed'. The possible contents
-- of the 'status' table are described in ref:launch_target.
-- @note: SECURITY- alert: allowing the _terminal frameserver is currently
-- a possible scriptable way of running arbitrary programs within the context
-- of the terminal, partly through the possible cmd= argument but also by
-- manually inputting commands through ref:target_input. This can be hardened
-- in multiple ways: by intercepting ref:target_input and only allow if it is vissible
-- (appl specific solution), by intercepting ref:launch_avfeed and filtering argstr
-- or by simply not allowing the terminal frameserver (disable at buildtime or
-- specify a different set of afsrv_ binaries using the --binpath argument).
-- @group: targetcontrol
-- @cfunction: setupavstream
-- @related: load_movie, launch_target, define_recordtarget, net_open, net_listen
function main()
#ifdef MAIN
	local vid = launch_avfeed("", "terminal",
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
#endif

#ifdef ERROR
#endif
end
