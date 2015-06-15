-- shader_ugroup
-- @short: Allocate a uniform group inside a shader
-- @inargs: shid
-- @outargs: shid
-- @longdescr: All shaders have a default group of shaders that the
-- ref:shader_uniform function applies to. In many cases, however, one might
-- want to have multiple objects that uses the same shader but with a slightly
-- different set of uniforms. shader_ugroup can be used to create a derivative
-- shader that uses the same underlying shader but switches to a different set
-- of uniforms when activated. The returned shader is valid for all shader
-- related calls but has its lifecycle to the shader it was derived from.
-- @group: vidsys
-- @cfunction: shader_ugroup
-- @related:
function main()
#ifdef MAIN
	local frag = [[
		uniform float vec3 col;
		void main(){
			gl_FragColor = vec4(col, 1.0);
		}
]];

-- create two black surfaces that are modified by the associated shader
-- that sets color using a uniform.
	local shid = build_shader(nil, frag, "csh");
	a = fill_surface(64, 64, 0, 0, 0);
	b = fill_surface(64, 64, 0, 0, 0);
	show_image({a, b});
	image_shader(a, shid);

	local shid2 = shader_ugroup(shid);
	image_shader(b, shid2);

	shader_uniform(shid, "col", "fff", PERSIST, 1.0, 0.0, 0.0);
	shader_uniform(shid2,"col", "fff", PERSIST, 0.0, 1.0, 0.0);
#endif
end
