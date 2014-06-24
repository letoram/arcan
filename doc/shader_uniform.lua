-- shader_uniform
-- @short: Set values for a uniform values in a specific shader.
-- @inargs: shid, symlbl, typestr, persistfl, vals
-- @longdescr: A shader can have a number of uniform variables declared.
-- The specific values of such a uniform can be set through this function.
-- shid is a reference to a shader allocated through build_shader.
-- symlbl is the identifier of the uniform and typestr is a string that
-- specifies the actual type of the uniform. Accepted patterns for typestr
-- include "b" (bool), "i" (int) "f" (float), "ff" (vec2), "fff" (vec3),
-- "ffff" (vec4), f*16 (mat4). If persistfl is set, the member values
-- will be stored locally and survives external-launch state transitions.
-- If persistfl is not set, the uniform vales are expected to be continously
-- updated.
-- @group: vidsys
-- @cfunction: arcan_lua_shader_uniform
function main()
#ifdef MAIN
	local shid = build_shader(nil, [[ uniform float vec3 col;
	void main(){
		gl_FragColor = vec4(col, 1.0);
	}]],
	a = fill_surface(128, 128, 0, 0, 0);
	show_image(a);
	image_shader(a, shid);
	shader_uniform(shid, "col", "fff", PERSIST, 0.0, 1.0, 0.0);
#endif
end
