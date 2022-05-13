-- define_recordtarget
-- @short: Create a rendertarget with a periodic readback
-- @inargs: vid:buffer, string:resource, string:arguments, vidtbl:vids,
-- aidtbl:aids, int:detach, int:scale, int:samplerate, function:callback
-- @inargs: vid:buffer, vid:resource, string:arguments, vidtbl:vids,
-- aidtbl:aids, int:detach, int:scale, int:samplerate, function:callback
-- @outargs:
-- @longdescr: This function inherits from ref:define_rendertarget. Please
-- refer to the description of that function for assistance with the
-- *detach*, *scale* and *samplerate* arguments.
--
-- There are two distinct cases for using recordtargets. One is to create
-- a new frameserver (afsrv_encode process) session used for features such
-- as streaming and remote displays i.e. lossy output.
--
-- In this case, *resource* will be used as the output resource path
-- which will either be mapped to a NULL file (in the case of container=stream
-- in *arguments* or "") or created in the APPL_TEMP namespace, and passed as
-- a file descriptor into the process on creation. *arguments* will be forwarded
-- using the ARCAN_ARG environment variable. ARCAN_ARG=help afsrv_encode from
-- a command-line can be used to see the possible values for *arguments*.
--
-- The second usecase is creating an *output* segment in an existing client.
-- Here, *arguments* will be ignored and *resource* is expected to refer to
-- a valid (ref:valid_vid) frameserver segment. Trying to push a subsegment
-- to a VID that is not a connected frameserver is a terminal state transition.
--
-- The *callback* argument should point to a Lua defined function that accepts
-- a source_id(will match *dest_buffer*) and a table with members that describe
-- events that are performed on the underlying segment.
--
-- *aids* should either be a table of valid AIDs that should be mixed and
-- forwarded, or to WORLDID as a means of hooking all arcan managed audio
-- input. By default, they are mixed and clipped equally.
-- This can be changed using ref:recordtarget_gain.
--
-- @group: targetcontrol
-- @cfunction: recordset
-- @related: define_rendertarget, define_calctarget, target_alloc,
-- recordtarget_gain
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

#ifdef ERROR
	define_recordtarget(nil, "output.mkv", "vpreset=8:noaudio:fps=25", {}, {},
		RENDERTARGET_NODETACH, RENDERTARGET_SCALE, -4);
#endif

#ifdef ERROR2
	dst = fill_surface(VRESW, VRESH, 0, 0, 0);
	define_recordtarget(dst, "output.mkv", "vpreset=11:noaudio:fps120", "", "",
		RENDERTARGET_NODETACH, RENDERTARGET_SCALE, -4);
#endif
end
