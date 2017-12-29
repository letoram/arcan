-- random_surface
-- @short: Generate a pseudo-random image surface.
-- @inargs: int:width, int:height
-- @inargs: int:width, int:height, string:method=uniform-3
-- @inargs: int:width, int:height, string:method=uniform-4
-- @inargs: int:width, int:height, string:method=fbm, float:lacunarity, float:gain, float:octaves, int:xstart, int:ystart, int:z
-- @inargs: width, height, method
-- @outargs: vid
-- @longdescr: This function is used to create pseudorandom noise textures,
-- a useful building block in many graphics effects. If no method or an unknown
-- one is specified, it will default to 1 channel randomness from the global csprng,
-- duplicated into the RGB channels of a RGBA destination buffer (A=fully opaque).
-- The other methods, uniform-3 and uniform-4 work similarly, but have different
-- values in 3 or all 4 channels. FBM creates fractal noise by adding multiple
-- octaves of perlin noise together.
-- @group: image
-- @cfunction: randomsurface
function main()
#ifdef MAIN
	a = random_surface(64, 64);
	b = random_surface(64, 64, "uniform-3");
	c = random_surface(64, 64, "fbm", 2, 0.5, 6, 0, 0, 0);
	show_image({a,b,c});
	move_image(b, 64, 0);
	move_image(c, 0, 64);
#endif
end
