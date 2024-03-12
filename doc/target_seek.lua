-- target_seek
-- @short: Request a change playback or presentation position for a frameserver.
-- @inargs: vid:tgt, number:step
-- @inargs: vid:tgt, number:step, bool:relative
-- @inargs: vid:tgt, number:step, bool:relative
-- @inargs: vid:tgt, number:step, bool:relative, bool:time
-- @inargs: vid:tgt, number:step, bool:relative, bool:time=false,
-- @inargs: vid:tgt, number:step, bool:relative, bool:time=false, number:xaxis
-- @inargs: vid:tgt, number:step, bool:relative, bool:time=false, number:xaxis, number:zaxis
-- @longdescr: Request an absolute or relative *step* sized change in active content position
-- in either time or space. Frameservers communicate this capability and the meaning of the
-- ranges through the 'content_state' event. This feature can be used to implement things
-- like scrollbars, as well as client side defined UI 'scaling'.
-- If seeking in *time* (default), the relative (default) *step* is expected to be an offset in miliseconds.
-- If setting an absolute time position, the absolute *step* is floating point in the 0..1 range.
-- If seeking in *space* (panning) the relative (default) is in a discrete +- steps on a target defined scale.
-- Absolute seeking is a float in the 0..1 range from start (0) to end (1).
-- The *zaxis* axis is a hint on magnification where, the absolute value will treat 1 as normal scale,
-- < 1 as minification and > 1 as magnification.
-- The boolean arguments *relative* and *time* has constants defined as
-- SEEK_SPACE | SEEK_TIME and SEEK_ABSOLUTE | SEEK_RELATIVE.
-- @group: targetcontrol
-- @cfunction: targetseek
function main()
	vid = launch_avfeed("file=test.mkv", "",
		function(source, status)
			if status.kind == "resized" then
				show_image(source)
				resize_image(source, status.width, status.height)
			end
		end
	)
#ifdef MAIN
	target_seek(vid, 100) -- seek +100ms
#endif

#ifdef MAIN2
end

function main_clock_pulse()
	target_seek(vid, 1, SEEK_RELATIVE, SEEK_SPACE, 1) -- dx,dy += 1 every tick
end
#endif

#ifdef MAIN3
end

function main_clock_pulse()
	target_seek(vid, 0, SEEK_ABSOLUTE, SEEK_SPACE, 0, math.random(0.1, 3)) -- randomized zoom each tick
end
#endif
end

#ifdef ERROR
	target_seek(BADID)
end
#endif
