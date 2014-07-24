-- define_recordtarget
-- @short: Create an offscreen audio/video pipeline that can be sampled by a frameserver.
-- @inargs: dstvid, dstres, encodeargs, vidtbl, aidtbl, detacharg, scalearg, samplerate, *callback*
-- @outargs:
-- @longdescr: This function takes a *dstvid* (allocated through alloc_surface),
-- and creates a separate audio / video rendertarget populated with the entries
-- in *vidtbl* and *aidtbl*. The *detacharg* can be set to FRAMESERVER_DETACH or
-- FRAMESERVER_NODETACH regulating if the VIDs in *vidtbl* should be removed
-- from the normal rendering pipeline or not. The *scalearg* can be set to
-- RENDERTARGET_SCALE or RENDERTARGET_NOSCALE, and comes into play when the
-- dimensions of the active display fail to match those of *dstvid*.
-- With RENDERTARGET_SCALE, a transformation matrix is calculated that
-- stretches or squeezes the results to fit *dstvid*, with RENDERTARGET_NOSCALE,
-- clipping can occur. The samplerate dictates how often the rendertarget
-- should be read-back into *dstvid*, with negative numbers meaning
-- *abs(samplerate)* video frames between each sample, and positive numbers
-- meaning *samplerate* ticks between each sample. *encodeargs* are passed
-- directly in a key=value:key form to the frameserver. See the
-- section on *frameserver arguments* below for more details.
-- Lastly, *callback* works as an optional trigger for feedback from the
-- frameserver (use target_verbose to toggle frametransfer status updates).
-- @group: targetcontrol
-- @frameserver: vbitrate=kilobitspersecond (1..n)
-- @frameserver: abitrate=kilobitspersecond (1..n)
-- @frameserver: vpreset=videoqualitylevel (1..10)
-- @frameserver: apreset=audioqualitylevel (1..10)
-- @frameserver: vcodec=identifier (default: webm)
-- @frameserver: acodec=identifier (default: mp3)
-- @frameserver: fps=outputframerate
-- @frameserver: container=identifier (default: mkv)
-- @frameserver: noaudio (special flag, disables all audio processing)
-- @frameserver: protocol=type (for remoting)
-- @frameserver: pass=password (for remoting)
-- @frameserver: port=listenport (for remoting)
-- @frameserver: name=servername (for remoting)
-- @frameserver: interface=if (for remoting)
-- @note: although WORLDID is not a valid recipient as such, a trick is to define a null_surface, image_sharestorage WORLDID into the null_surface and that works as a valid attachment. Two caveats though is that the contents of null_surface will have its coordinate system flipped around Y (rotate null_surface 180 degrees) and neither the record destination nor the null surface should be visible, as that would add a feedback loop which quickly turns the result into an undefined value (typically black).
-- @note: specifying a valid frameserver connected VID in the dstres slot
-- will allocate a new output segment and attach to the pre-existing frameserver.
-- @note: if dstres is empty, no file will be created or pushed. This is useful
-- for using the encode frameserver for remoting.
-- @cfunction: arcan_lua_recordset
-- @related: define_rendertarget
-- @flags:
function main()
#ifdef MAIN
	a = fill_surface(64, 64, 128, 0, 0);
	b = fill_surface(32, 32, 0, 128, 0);
	c = fill_surface(16, 16, 0, 0, 128);
	move_image(b, VRESW - 32, 0);
	move_image(c, VRESW - 16, VRESH - 16);

	show_image({a,b,c});
	move_image(a, VRESW - 64, 0, 100);
	move_image(b, VRESW - 32, VRESH - 32, 100);
	move_image(c, 0, VRESH - 16, 100);

	move_image(a, VRESW - 64, VRESH - 64, 100);
	move_image(b, 0, VRESH - 32, 100);
	move_image(c, 0, 0, 100);

	image_transform_cycle(a, 1);
	image_transform_cycle(b, 1);
	image_transform_cycle(c, 1);

	dst = alloc_surface(VRESW * 0.5, VRESH * 0.5);

	define_recordtarget(dst, "output.mkv", "vpreset=8:noaudio:fps=25", {a,c}, {},
		RENDERTARGET_NODETACH, RENDERTARGET_SCALE, -4);
#endif

#ifdef MAIN2
	a = fill_surface(64, 64, 128, 0, 0);
	move_image(a, VRESW - 64, 0, 100);
	move_image(a, VRESW - 64, VRESH - 64 ,100);
	cycle_image_transform(a);
	dst = alloc_surface(VRESW * 0.5, VRESH * 0.5);
	define_recordtarget(dst,  "", "protocol=vnc:port=6200:fps=10", {a}, {},
		RENDERTARGET_NODETACH, RENDERTARGET_SCALE, -4, function(source, status)
		for k,v in pairs(status) do
			print("key:", k, "value:", v);
		end
	end);

#endif

#ifdef ERROR1
	define_recordtarget(nil, "output.mkv", "vpreset=8:noaudio:fps=25", {}, {},
		RENDERTARGET_NODETACH, RENDERTARGET_SCALE, -4);
#endif

#ifdef ERROR2
	dst = fill_surface(VRESW, VRESH, 0, 0, 0);
	define_recordtarget(dst, "output.mkv", "vpreset=11:noaudio:fps120", "", "",
		RENDERTARGET_NODETACH, RENDERTARGET_SCALE, -4);
#endif
end
