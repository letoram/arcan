-- build_shader
-- @short: Compile a vertex,fragment tupe into a shader and
-- index using a string shortname (label).
-- @inargs: vertex_program, fragment_program, label
-- @outargs: shader_id
-- @longdescr: All VIDs (including clones) can have shaders
-- (or rather, GPU programs) associated that can greatly effect
-- the final output. This function, along with image_shader
-- and shader_uniform are used to configure and activate
-- shaders on a VID per VID basis.
-- @note: There is no abstraction to help dealing with the
-- number of possible shader language versions. The global constant
-- SHADER_LANGUAGE can be used to determine which language that
-- the graphics platform requests that you use.
-- @note: Some symbols are reserved and populated by the engine
-- if their respective uniform or attribute slot is requested.
-- @note: Reserved attributes: modelview (mat4), projection (mat4),
-- texturem (mat4).
-- @note: Reserved uniforms: obj_opacity (float),
-- trans_move (float, 0.0 .. 1.0), trans_scale (float, 0.0 .. 1.0)
-- trans_rotate (float, 0.0 .. 1.0), obj_input_sz (vec2, orig w/h)
-- obj_output_sz (vec2, current w/h), obj_storage_sz (vec2, texture
-- storage w/h).
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
