-- resample_image
-- @short: scale an image to new dimensions using a shader
-- @inargs: vid:src, shid:shader, int:width, int:height, bool:nosynch
-- @inargs: vid:src, shid:shader, int:width, int:height, vid:dst
-- @inargs: vid:src, shid:shader, int:width, int:height, vid:dst, bool:nosynch
-- @longdescr:
-- This function takes the textured object referenced by *src*
-- and resamples to *width* and *height* output using the shader
-- specified in *shader*.
-- If the second argument form is used, the backing store of *dst*
-- will be replaced with the resampled output rather than the backing
-- store of *src*.
-- If the *nosynch* argument is specified (default to false), the local memory
-- copy of the backing store will be ignored. This means that the backing
-- can't be reconstructed if the engine suspends to an external
-- source which might lead to the data being lost or the time to
-- suspend increases to account for creation of the local copy.
-- @note: The resampled storage is subject to the same limitations
-- as other image functions that create a storage buffer, exceeding
-- MAX_SOURCEW, MAX_SOURCEH is a terminal state transition.
-- @note: This function internally aggregates several regular calls
-- into one and presented here more for a convenience use of a complex setup.
-- The flow can be modeled as: 1. create temporary renderbuffer with a
-- temporary output and a null object reusing the storage in vid.
-- 2. apply shader, do an off-screen pass into the renderbuffer.
-- 3. switch glstore from temporary into vid, readback into local
-- buffer and update initial state values (width, height, ..).
-- @group: image
-- @cfunction: resampleimage
-- @related:

function main()
	local img = load_image("test.png");
	local shid = build_shader(nil, [[
uniform sampler2D map_diffuse;
varying vec2 texco;

void main()
{
	vec4 col = texture2D(map_diffuse, texco);
	gl_FragColor = vec4(1.0, col.g, col.b, 1.0);
}
]], "redscale");
#ifdef MAIN
	resample_image(img, shid, 640, 480);
	show_image(img);
#endif

#ifdef ERROR
	resample_image(img, shid, -64, -64);
#endif

#ifdef ERROR2
	resample_image(img, shid, 6400, 4800);
#endif
end
