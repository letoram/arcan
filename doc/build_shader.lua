-- build_shader
-- @short: Compile a vertex,fragment tupe into a shader and index through a string shortname.
-- @inargs: vertex_program, fragment_program, label
-- @outargs: shader_id
-- @longdescr: All VIDs (including clones) can have shaders (or rather, GPU programs) associated that can greatly effect the final output. This function, along with image_shader and shader_uniform are used to configure and activate shaders on a VID per VID basis.
-- @group: vidsys
-- @cfunction: arcan_lua_buildshader
-- @flags:
vshader = [[uniform mat4 modelview;
uniform mat4 projection;

attribute vec4 vertex;
attribute vec2 texcoord;

varying vec2 texco;

void main(void)
{
	texco = texcoord;
	gl_Position = (projection * modelview) * vertex;
}]];

fshader = [[uniform sampler2D map_diffuse;
uniform float obj_opacity;

varying vec2 texco;

void main(){
  vec4 col = texture2D(map_diffuse, texco);
  col.a = col.a * obj_opacity;
  gl_FragColor = col;
}
]];

function main()
#ifdef MAIN
	build_shader(vshader, fshader, "default");
#endif

#ifdef ERROR1
	build_shader(nil, nil, nil);
#endif

#ifdef ERROR2
	build_shader(vshader, fshader, 0.5);
#endif

#ifdef ERROR3
	build_shader(nil, nil, "default");
#endif
end
