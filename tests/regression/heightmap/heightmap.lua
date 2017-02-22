local vshader = [[
	uniform mat4 modelview;
	uniform mat4 projection;
	uniform sampler2D map_diffuse;

	uniform float ampl;

	attribute vec2 texcoord;
	attribute vec4 vertex;

	varying vec2 texco;

	void main(){
		vec4 dv   = texture2D(map_diffuse, texcoord);
		vec4 vert = vertex;
		vert.y    = ampl * (dv.r + dv.g + dv.b) / 3.0;
		gl_Position = (projection * modelview) * vert;
		texco = texcoord;
	}
]];

local fshader = [[
void main(){
	gl_FragColor = vec4(1.0, 1.0, 1.0, 1.0);
}
]];

function heightmap()
	bgc = fill_surface(VRESW, VRESH, 127, 0, 127);
	fbo = alloc_surface(0.5 * VRESW, 0.5 * VRESH);
	vid = build_3dplane(-2, -2, 2, 2, 0, 0.05, 0.05, 1);
	hmap = random_surface(64, 64);
	image_sharestorage(hmap, vid);
	delete_image(hmap);
	show_image(vid);
	resize_image(fbo, VRESW, VRESH);
	local shid = build_shader(vshader, fshader, "hmap");
	shader_uniform(shid, "ampl", "f", 1.0);
	image_shader(vid, shid);
	define_rendertarget(fbo, {vid},
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, -1, RENDERTARGET_FULL);
	image_color(fbo, 0, 0, 0, 0);
	show_image(bgc);
	local camera = null_surface(1, 1);
	scale3d_model(camera, 1.0, -1.0, 1.0);
	move3d_model(vid, 0.0, -0.2, 0.0);
	rendertarget_attach(fbo, camera, RENDERTARGET_DETACH);
	camtag_model(camera, 0.01, 100.0, 45.0, 1.33, true, false, 4);
	blend_image(fbo, 1.0, 2);
end

function heightmap_clock_pulse()
end
