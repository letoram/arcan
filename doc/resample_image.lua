-- resample_image
-- @short: scale an image to new dimensions using a shader
-- @inargs: vid, shid, desired width, desired height
-- @longdescr: This function serves two purposes, a. to populate a textured backing store with the output of a shader and b. to use a shader in order to create an upscaled or downscaled version.
-- @note: The resampled storage is subject to the same limitations as other image functions that create a storage buffer, exceeding MAX_SOURCEW, MAX_SOURCEH is a terminal state transition.
-- @note: This function internally aggregates several regular calls into one and presented here more for a convenience use of a complex setup. The flow can be modeled as: 1. create temporary renderbuffer with a temporary output and a null object reusing the storage in vid. 2. apply shader, do an off-screen pass into the renderbuffer. 3. switch glstore from temporary into vid, readback into local buffer and update initial state values (width, height, ..).
-- @group: image
-- @cfunction: resampleimage
-- @related:

function main()
	local img = load_image("images/icons/arcanicon.png");
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

#ifdef ERROR1
	resample_image(img, shid, -64, -64);
#endif

#ifdef ERROR2
	resample_image(img, shid, 6400, 4800);
#endif
end
