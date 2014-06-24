-- raw_surface
-- @short: Convert a LUA table, convert to a texture and store in a new VID.
-- @inargs: desw, desh, bpp, tbl
-- @outargs: vid
-- @note: There might be a loss of precision imposed by the texture format
-- native to the system that is running.
-- @note: desw and desh should be within the compile-time constraints of
-- MAX_SURFACEW and MAX_SURFACEH.
-- @note: acceptible values for bpp are 1, 3 and 4.
-- @note: the numbers will be treated as integers clamped to 0..255.
-- @note: referencing a table that has less than desw * desh * bpp elements
-- is a terminal state.
-- @group: image
-- @cfunction: arcan_lua_rawsurface
function main()
#ifdef MAIN
	local rtbl = {};
	local ofs = 1;

	for row=1,64 do
		for col=1,64 do
			rtbl[ofs+0] = math.random(255);
			rtbl[ofs+1] = math.random(255);
			rtbl[ofs+2] = math.random(255);
			ofs = ofs + 3;
		end
	end

	local vid = raw_surface(64, 64, 3, rtbl);
	show_image(vid);
#endif
end
