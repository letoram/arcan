-- shader_uniform
-- @short: Set values for a uniform values in a specific shader.
-- @inargs: shid, symlbl, typestr, vals
-- @longdescr: A shader can have a number of uniform variables declared.
-- The specific values of such a uniform can be set through this function.
-- shid is a reference to a shader allocated through build_shader.
-- symlbl is the identifier of the uniform and typestr is a string that
-- specifies the actual type of the uniform. Accepted patterns for typestr
-- include "b" (bool), "i" (int) "f" (float), "ff" (vec2), "fff" (vec3),
-- "ffff" (vec4), f*16 (mat4).
-- It is also possible for one shaderid to maintain different sets
-- of uniform values. Each group is tied to the life-cycle of the program
-- and is allocated with ref:shader_ugroup. The id that is returned can
-- then be used in ref:image_shader to specify which subgroup that is to
-- be used.
-- @note: There is a deprecated version of this function around that has
-- a PERSIST or NOPERSIST value placed after *typestr*. This is now ignored
-- and forced to PERSIST (keep local copies of uniforms that can survive
-- video layer resets). This has the side-effect that the argument validation
-- is less aggressive and may permit a mismatch of up to one argument.
-- @group: vidsys
-- @related: shader_ugroup, image_shader, build_shader
-- @cfunction: shader_uniform
function main()
#ifdef MAIN
	local shid = build_shader(nil, [[ uniform float vec3 col;
	void main(){
		gl_FragColor = vec4(col, 1.0);
	}]], "csh");
	a = fill_surface(128, 128, 0, 0, 0);
	show_image(a);
	image_shader(a, shid);
	shader_uniform(shid, "col", "fff", PERSIST, 0.0, 1.0, 0.0);
#endif
end
