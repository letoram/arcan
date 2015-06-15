-- image_shader
-- @short: Set the active shader for an object.
-- @inargs: vid, *shid or string*, *group*
-- @outargs: oldshid
-- @group: image
-- @note: if only the vid is provided, the active program won't be changed
-- @note: if a string argument is supplied as the second argument, the routine
-- will first resolve it by looking for a previously compiled shader with a
-- name that matches the argument. If no match is found, the shader state will
-- forcibly be reset to DEFAULT.
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
