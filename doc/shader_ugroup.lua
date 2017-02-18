-- shader_ugroup
-- @short: Allocate a uniform group inside a shader
-- @inargs: shid
-- @outargs: out_shid or nil
-- @longdescr: All shaders have a default group of shaders that the
-- ref:shader_uniform function applies to. In many cases, however, one might
-- want to have multiple objects that uses the same shader but with a slightly
-- different set of uniforms. shader_ugroup can be used to create a derivative
-- shader that uses most of the same underlying resources but switches to a
-- different set of uniforms when activated. The returned shader is valid
-- for all shader related calls but has its lifecycle to the shader it was
-- derived from. Any forced uniform at the time of group creation will
-- be copied from the group associated with the specified shid.
-- There's a finite amount of uniform group slots available to each shader,
-- and if the provided *shid* is invalid or there are not enough free group
-- slots left in the shader, the *out_shid* will be nil.
-- @note: Though it is bad form to ever rely in the specific value of
-- a shid, shaders that are derived typically have a value > 65535.
-- @group: vidsys
-- @cfunction: shader_ugroup
-- @related: build_shader, delete_shader
function main()
#ifdef MAIN
	local frag = [[
		uniform float r;
		uniform float g;
		uniform float b;

		void main(){
			gl_FragColor = vec4(r, g, b, 1.0);
		}
]];

	local shid = build_shader(nil, frag, "csh");
	a = fill_surface(64, 64, 0, 0, 0);
	b = fill_surface(64, 64, 0, 0, 0);
	show_image({a, b});
	move_image(b, 64, 0);
	image_shader(a, shid);

	shader_uniform(shid, "r", "f", 1.0);
	shader_uniform(shid, "b", "f", 0.0);

-- r and b values will be inherited, g is undefined
	local shid2 = shader_ugroup(shid);
	image_shader(b, shid2);

-- g is now defined in shid1, undefined in shid2
	shader_uniform(shid, "g", "f", 1.0);
	shader_uniform(shid2, "g", "f", 0.0);
#endif
end
