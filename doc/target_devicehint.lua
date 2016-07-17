-- target_devicehint
-- @short: Change connection- and device- use for a frameserver connection
-- @inargs: fsrvid, target, *mode*
-- @longdescr: This function serves several uses. The first use case is to
-- indicate to a frameserver or non-authoritative connection that the
-- underlying connection primitive has changed. *mode* is then used as a
-- boolean flag. If *target* is a string or network-fsrv-vid and *mode* is
-- set to true, the *target* should be be used for recovery. This means that
-- if the arcan instances crashes or the connection is lost in some other way,
-- the *target* should be used for recovery/rendez-vous. This is the default.
-- If *mode* is set to false, the target will be hinted that it should migrate
-- to using another connection-point voluntarily, albeit that this is not always
-- possible.
-- Another use case is to provide a handle to an accelerated device (this is
-- platform dependent and typically only available to low-level platforms like
-- egl-dri) to use for hardware accelerated rendering, "render-nodes" in KMS
-- terminology. In this case, *mode* is used as a use-hint flag, and can be
-- either DEVICE_INDIRECT (default), DEVICE_DIRECT or DEVICE_LOST.
-- DEVICE_INDIRECT means that the rendering output will be used for some
-- internal computation or indirect rendering and should use whatever memory
-- type that fits this purpose. DEVICE_LOST and DEVICE_DIRECT are sent as part
-- of other operations, e.g. when the *fsrvid* is directly mapped to an output
-- display. This means that the accelerated buffer output should be of a type
-- that supports being used for scanout.
-- @group: targetcontrol
-- @cfunction: targetdevhint
-- @flags: experimental
function main()
#ifdef MAIN
	target_alloc("devicehint", function(source, status)
		if (status.kind == "connected") then
			target_devicehint(source, "devicehint", true); -- send fallback path
			target_devicehint(source, 0); -- send rendernode
		end
	end);
#endif

#ifdef ERROR1
	target_devicehint(BADID);
#endif

#ifdef ERROR2
	target_devicehint("devicehint", true);
#endif
end
