-- image_shader
-- @short: Set the active shader for an object.
-- @inargs: vid:image, string:identifier
-- @inargs: vid:image, integer:identifier
-- @inargs: vid:image, string:identifier, integer:attributes
-- @inargs: vid:image, integer:identifier, integer:attributes
-- @outargs: oldshid
-- @group: image
-- @longdescr: Processing programs can be created using the ref:build_shader
-- call. These programs can then be assigned to an *image* through this function.
-- if *attributes* are provided, the value is expected to be one of these constants:
--
-- SHADER_DOMAIN_RENDERTARGET : find a rendertarget bound to image and assign
-- the shader as the default program for objects using this rendertarget.
-- if *image* does not contain a rendertarget, it is a terminal state transition.
--
-- SHADER_DOMAIN_RENDERTARGET_HARD : same as for SHADER_DOMAIN_RENDERTARGET,
-- except all shaders on objects attached to the rendertarget will be ignored.
-- This is useful for a temporary suspension of all shaders, as well as for
-- rendertargets created using ref:define_linktarget.
-- @note: if only the vid is provided, the active program won't be changed and
-- the function is then used to query the active program of a video object.
-- @note: if a string argument is supplied as the second argument, the routine
-- will first resolve it by looking for a previously compiled shader with a
-- name that matches the argument.
-- @note: the shader state of all video objects are set to 'DEFAULT' which
-- is some platform default safe sate that follows obj_opacity and normal
-- texturing.
-- @related: build_shader, shader_ugroup, shader_uniform
-- @cfunction: setshader
-- @flags:
function main()
#ifdef MAIN
	shid = build_shader(nil, [[
		void main(){
			gl_FragColor = vec4(0.5, 1.0, 0.5, 1.0);
		}
	]], "demoshader");

	a = fill_surface(64, 64, 0, 0, 0);
	show_image(a);
	image_shader(a, shid);
#endif
end
