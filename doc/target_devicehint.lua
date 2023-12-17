-- target_devicehint
-- @short: Change connection- and device- use for a frameserver connection
-- @inargs: vid:dsrv, number:device
-- @inargs: vid:fsrv, string:target
-- @inargs: vid:fsrv, string:target, bool:force(=false)
-- @longdescr: This function serves several uses. The first use case is to
-- forward a device handle to an accelerated client. This will happen if the
-- *device* argument is provided and matches a valid card identifier. If an
-- invalid identifier is provided, the call will only be interpreted as a
-- mode hint.
-- The *mode* argument can also be specified as device-use hint. Previously,
-- this has been used to indicate of the client should produce a buffer for
-- direct output on the device in question, but this is now done heuristically
-- as part of ref:map_video_display calls. The valid values now are
-- DEVICE_INDIRECT for composed rendering, and DEVICE_LOST to indicate
-- that the currently used GPU should be dropped and, if possible, revert
-- to software- defined graphics.
-- The other uses are with a string target. This is used to indicate a
-- connection point to another arcan-shmif capable server. The default is
-- to mark this as a hint, 'in the event of the main connection being lost,
-- please go here'. If the *force* argument is also set, the connection may
-- be forcibly severed to make the client switch to the specified connection
-- point.
-- The *target* string is assumed to match the valid rules for a connection
-- point, but if the association is not forced, an empty string is also valid
-- and will be interpreted as disabling a previously set alternate connection.
-- There are two special forms to the *target* string, one is a12:// and a12s://
-- as a prefix which will involve the arcan-net tool to connect to a server. The
-- second is with a @ or @host suffix, like mytag@. This will use keystore
-- tags to find outbound connection parameters. These forms will also provide
-- the *fsrv* vid access to a keystore capability.
-- @note: The keystore access is currently the same as the one handed to the
-- arcan process. This may be changed in the future.
-- @note: If the forced target migration mode is used on a frameserver launched
-- in an authoritative mode via ref:define_avfeed or similar functions, the
-- process tracking will be disabled and the kill 'guarantee' on
-- ref:delete_image will be lost.
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
