-- build_shader
-- @short: using
-- @inargs: string/nil:vertex_program, string/nil:fragment_program, string:label
-- @outargs: uint:shader_id
-- @longdescr: All video objects can have a series of processing/
-- rendering instructions associated with them. These are platform
-- dependent, and you can check (GL_VERSION, SHADER_LANGUAGE) for
-- identification strings to help support your choice, and the
-- most commonly supported shader language is currently GLSL120.
-- This function is used to go from a higher level description
-- (like a string) to some implementation defined internal
-- interpretation that can later be referenced and connected to
-- VIDs using the returned *shader_id* or the *label*.
-- *vertex_program* describes the processing stage that determines
-- the shape of the object to be drawn, and *fragment_program* the
-- content that will be filled inside the shape. Both of these are
-- allowed to be nil, and the engine will then use whatever platform
-- specific default that is defined.
-- A shader can also have a set of limited user-defined variables,
-- called _uniforms_ (see ref:shader_uniform for details) along
-- with a number of built in ones (see the notes below).
-- If the contents of the supplied *vertex_program* or *fragment_program*
-- could not be interpreted, or there was insufficient shader slots left
-- to create another one, the returned *shader_id* will be nil.
-- To associate a successfully built shader to a vid, see ref:image_shader.
-- @note: For GLSL120, reserved attributes are:
-- vertex (vec4), normal (vec3), color (vec4), texcoord (vec2),
-- texcoord1 (vec2), tangent (vec3), bitangent (vec3), joints (ivec4),
-- weights (vec4)
-- @note: For GLSL120, reserved uniforms are:
-- modelview (mat4), projection (mat4), texturem (mat4),
-- trans_move (float, 0.0 .. 1.0), trans_scale (float, 0.0 .. 1.0)
-- trans_rotate (float, 0.0 .. 1.0), obj_input_sz (vec2, orig w/h)
-- obj_output_sz (vec2, current w/h), obj_storage_sz (vec2, texture
-- storage w/h), obj_opacity(float, 0.0 .. 1.0), obj_col (vec3, 0.0 .. 1.0),
-- rtgt_id (uint), fract_timestamp (float), timestamp (int)
-- @group: vidsys
-- @related: shader_uniform, image_shader, shader_ugroup, delete_shader
-- @cfunction: buildshader
-- @flags:

local shfmt = {};
shfmt["GLSL120"].vertex = [[
uniform mat4 modelview;
uniform mat4 projection;

attribute vec4 vertex;
attribute vec2 texcoord;

varying vec2 texco;

void main(void)
{
	texco = texcoord;
	gl_Position = (projection * modelview) * vertex;
}
]];

shfmt["GLSL120"].fragment = [[
uniform sampler2D map_diffuse;
uniform float obj_opacity;

varying vec2 texco;

void main(){
  vec4 col = texture2D(map_diffuse, texco);
  col.a = col.a * obj_opacity;
  gl_FragColor = col;
}
]];

function main()
	local sh = shfmt[SHADER_LANGUAGE];
	if (sh == nil) then
		return shutdown("no matching shader for the platform language:" ..
			SHADER_LANGUAGE, EXIT_FAILURE);
	end

#ifdef MAIN
	build_shader(sh.vertex, sh.fragment, "default");
#endif

#ifdef ERROR
	build_shader(nil, nil, nil);
#endif

#ifdef ERROR2
	build_shader(vshader, fshader, 0.5);
#endif
end
