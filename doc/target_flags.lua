-- target_flags
-- @short: Set special frameserver processing flags
-- @inargs: vid:tgt, number:flag
-- @inargs: vid:tgt, number:flag, bool:enable=true
-- @inargs: vid:tgt, number:flag, number:max_w, number:max_h
-- @longdescr: Some frameserver features and management behaviors that
-- are unsafe to use as a default can be enabled/disabled on a per-target basis
-- through the use of this function. The flag argument is used to specify the
-- feature in question, and the optional enable argument is if the
-- state should be set to on or off.
--
-- The special max_w and max_h argument interpretation is only for the
-- TARGET_FORCESIZE and TARGET_LIMITSIZE flags.
--
-- The possible flags are:
-- TARGET_VSTORE_SYNCH, TARGET_SYNCHRONOUS, TARGET_NOALPHA,
-- TARGET_AUTOCLOCK, TARGET_VERBOSE, TARGET_NOBUFFERPASS, TARGET_ALLOWCM,
-- TARGET_ALLOWLODEF, TARGET_ALLOWHDR, TARGET_ALLOWVECTOR, TARGET_ALLOWINPUT,
-- TARGET_FORCESIZE, TARGET_ALLOWGPU, TARGET_LIMITSIZE, TARGET_SYNCHSIZE,
-- TARGET_BLOCKADOPT, TARGET_DRAINQUEUE
--
-- @note: flag, TARGET_VSTORE_SYNCH makes sure that there is a local
-- copy of the buffer that is also uploaded to the GPU. This saves a
-- readback in cases where direct access to pixel values are needed.
-- @note: flag, TARGET_SYNCHRONOUS blocks CPU<->GPU transfers until
-- the transfer has been marked as completed. This will stall the
-- rendering pipeline and possibly incur a heavy performance impact.
-- @note: flag, TARGET_NOALPHA manually sets the alpha field for new
-- frames to 0xff. A faster way of disabling (that would require less
-- memory operations) alpha blending for untrusted sources would be
-- to associate the respective VIDs with a shader that doesn't use or
-- lookup alpha value.
-- @note: flag: TARGET_AUTOCLOCK is on by default and provides a
-- standardd implementation for some of the autoclock requests that
-- are then filtered and not forwarded to the eventhandler.
-- @note: flag: TARGET_VERBOSE is off by default. Turning it on
-- will emit additional data about delivered or dropped frames.
-- @note: flag: TARGET_NOBUFFERPASS applies to plaforms where accelerated
-- buffer passing is supported. This can be disabled statically/globally
-- through a platform specific environment variable, and dynamically by setting
-- this flag. The default behavior is to allow buffer passing, but if the
-- graphics (agp) layer gets an invalid buffer, this flag is automatically set
-- to true.
-- @note: flag: TARGET_ALLOWCM allows a client to send/receive color
-- lookup tables for one or several displays. You still need to explicitly
-- specify when- and which tables- are to be sent or retrieved via the
-- ref:video_displaygamma call. The event handler will indicate when
-- gamma tables have been updated.
-- @note: flag: TARGET_ALLOWLODEF allows a client to treat its video buffers
-- in half-depth mode. Similar to TARGET_ALLOWHDR, this means that more
-- advanced features than compositing (accessing / manipulating store,
-- direct-feed share and so on) should be avoided.
-- @note: flag: TARGET_ALLOWHDR allows the client to provide the video buffers
-- in an extended range format with associated metadata. This metadata is
-- descriptive but not normative. If you permit this feature you are
-- responsible for conversion/mapping during composition. Setting this
-- flag will make ref:target_verbose attach the metadata to each framestatus
-- event delivery to help with this. This can be forcibly overridden / locked
-- by using ref:image_metadata. Lokcing is relevant when ref:map_video_display
-- is used to try to forward without composition, as the metadata of the
-- mapped object will be forwarded to the relevant sink.
-- @note: flag: TARGET_ALLOWVECTOR allows a client to treat its video buffers
-- in vector mode. This converts the contents of its buffers to work as
-- textures, and metadata for specifying content in a GPU friendly triangle-
-- soup format. Like with allow-lodef/hdr.
-- @note: flag: TARGET_ALLOWINPUT remaps any _IO events received unto the
-- main event queue rather than being delivered in the normal frameserver
-- bound callback. This allows for semi-transparent controlled IO injection
-- with all the implications that might have. It is only intended for the
-- cases where overhead needs to be minimized over having a forward from
-- the normal event handler to the appl_input(iotbl) one.
-- @note: flag: TARGET_ALLOWGPU allows a client to authenticate a platform
-- specific token that can provide higher levels of GPU access than the
-- implementation defined default. This is a security tradeoff as it may
-- provide the client with access to read or modify private GPU state.
-- @note: flag: TARGET_LIMITSIZE sets an upper limit to the dimensions that
-- the client can negotiate. This is primarily to prevent accidental absurd
-- behavior, such as 8192x8192 sized mouse cursors.
-- @note: flag: TARGET_SYNCHSIZE changes the semantics for the 'resized' event to
-- block the client, pending a ref:stepframe_target call to release. It is not
-- stable to toggle this flag on as the off state can be activated with a synch
-- pending. On stepframe, the next update will contain the new buffer contents.
-- @note: flag: TARGET_BLOCKADOPT prevents the engine from preserving the target
-- on calls to ref:system_collapse or on script-error recovery.
-- @note: flag: TARGET_DRAINQUEUE allows events coming from the frameserver to
-- be queued directly into the script event handler without being multiplexed
-- on the master queue. This is a complex operation mainly intended for more
-- trusted clients that act as protocol bridges or external input drivers where
-- a higher event dispatch rate and lower event dispatch latency might be
-- beneficial.
-- @group: targetcontrol
-- @cfunction: targetflags
-- @related:
function main()
#ifdef MAIN
	a = launch_avfeed("", "avfeed", function(source, status)
		for k,v in pairs(status) do
			print(k, v);
		end
	end);
	target_flag(a, TARGET_VERBOSE);
	target_flag(a, TARGET_SYNCHRONOUS);
	target_flag(a, TARGET_NOALPHA);
	target_flag(a, TARGET_AUTOCLOCK);
	target_flag(a, TARGET_NOBUFFERPASS);
#endif

#ifdef ERROR
	a = null_surface(64, 64);
	target_flag(a, FLAG_SYNCHRONOUS);
#endif

#ifdef ERROR2
	a = launch_avfeed("", "avfeed", function() end);
	target_flag(a, 10000);
#endif
end
