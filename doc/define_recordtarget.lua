-- define_recordtarget
-- @short: Create an offscreen audio/video pipeline that can be sampled by a frameserver.
-- @inargs: dstvid, dstresstr, encodeargs, vidtbl, aidtbl, detacharg, scalearg, samplerate, *aidweights* 
-- @outargs: 
-- @longdescr: This function takes a *dstvid* (allocated through fill_surface), and creates a separate audio / video rendertarget populated with the entries in *vidtbl* and *aidtbl*. The *detacharg* can be set to FRAMESERVER_DETACH or FRAMESERVER_NODETACH regulating if the VIDs in *vidtbl* should be removed from the normal rendering pipeline or not. The *scalearg* can be set to RENDERTARGET_SCALE or RENDERTARGET_NOSCALE, and comes into play when the dimensions of the active display fail to match those of *dstvid*. With RENDERTARGET_SCALE, a transformation matrix is calculated that stretches or squeezes the results to fit *dstvid*, with RENDERTARGET_NOSCALE, clipping can occur. The samplerate dictates how often the rendertarget should be read-back into *dstvid*, with negative numbers meaning *abs(samplerate)* video frames between each sample, and positive numbers meaning *samplerate* ticks between each sample. *Encodeargs* are passed unto the frameserver that is able to process the data sampled, see the section on *frameserver arguments* for more details. Lastly, *aidweights* are a series of float values matching the number of input AIDs, and regulates how the inputs should be mixed together.
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
-- @note: specifying WORLDID instead of a table of VIDs means that the whole of the current active pipeline will be sampled instead.
-- @cfunction: arcan_lua_recordset
-- @related: define_rendertarget
-- @flags: 
function main()
#define MAIN
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

	cycle_image_transform(a);
	cycle_image_transform(b);
	cycle_image_transform(c);

	dst = fill_surface(VRESW * 0.5, VRESH * 0.5, 0, 0, 0);
	define_recordtarget(dst, "output.mkv", "vpreset=8:noaudio:fps=25", {a,c}, {}, 
		RENDERTARGET_NODETACH, RENDERTARGET_SCALE, -4);  
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
