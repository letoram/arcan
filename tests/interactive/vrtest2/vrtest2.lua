--
-- work-in-progress simple model /scene viewer using distortion shader
--
-- input calculations:
-- scale (0.001 steps, viewport_scale[0] - sep/2.0)
-- warp_adj: *= 1.0 / 0.9 or *= 0.9
-- ipd -= -0.001 or +=a
-- distortion toggle: 0.0, 0.0, 0.0, 1.0
--
-- translated from OpenHMD distortion_frag
local frag = [[
#version 120
uniform sampler2D map_tu0;
uniform vec2 center_xy;
uniform vec2 viewport_scale;
uniform float warp_scale;
uniform vec4 dist;
uniform vec3 aberr;
varying vec2 texco;

void main()
{
	vec2 output_loc = vec2(texco.s, texco.t);
	vec2 r = (output_loc * viewport_scale - center_xy) / warp_scale;
	float r_mag = length(r);
	vec2 r_displaced = r *
		(dist.w + dist.z + r_mag +
		dist.y * r_mag * r_mag +
		dist.x * r_mag * r_mag * r_mag);
	r_displaced *= warp_scale;

	vec2 tc_r = (center_xy + aberr.r * r_displaced) / viewport_scale;
	vec2 tc_g = (center_xy + aberr.g * r_displaced) / viewport_scale;
	vec2 tc_b = (center_xy + aberr.b * r_displaced) / viewport_scale;
	float cr = texture2D(map_tu0, tc_r).r;
	float cg = texture2D(map_tu0, tc_g).g;
	float cb = texture2D(map_tu0, tc_b).b;
	gl_FragColor = vec4(cr, cg, cb, 1.0);
}
]];

local function setup_hmd_uniforms(md, lsh, rsh)
	local scale_x = md.horizontal / 2.0;
	local scale_y = md.vertical;

	local cl_x = scale_x - md.hsep / 2.0;
	local cr_x = md.hsep / 2.0;

	local warp_scale = cl_x > cr_x and cl_x or cr_x;

	shader_uniform(lsh, "viewport_scale", "ff", scale_x, scale_y);
	shader_uniform(lsh, "warp_scale", "f", warp_scale);
	shader_uniform(lsh, "dist", "ffff",
		md.distortion[1], md.distortion[2], md.distortion[3], md.distortion[4]);
	shader_uniform(lsh, "aberr", "fff",
		md.abberation[1], md.abberation[2], md.abberation[3]);

-- per eye
	shader_uniform(lsh, "center_xy", "ff", md.vpos, cl_x);
	shader_uniform(rsh, "center_xy", "ff", md.vpos, cr_x);
end

function vrtest2(args)
-- FIXME: parse from args
	local l_eye_res_w = VRESW;
	local l_eye_res_h = VRESH;
	local r_eye_res_w = VRESW;
	local r_eye_res_h = VRESH;
	local l_eye_shader = build_shader(nil, frag, "distortion");
	local r_eye_shader = shader_ugroup(l_eye_shader);

-- FIXME: these really should use MSAA and a blit step between
	local l_eye = alloc_surface(l_eye_res_w, l_eye_res_h);
	local r_eye = alloc_surface(r_eye_res_w, r_eye_res_h);

-- our main object pipeline
	local tex = fill_surface(32, 32, 255, 255, 255);

	cube = build_3dbox(1, 1, 1);
	blend_image(cube, 0.5, 10);
	image_sharestorage(tex, cube);
	define_rendertarget(l_eye, {cube},
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, -1, RENDERTARGET_FULL);

-- and the alias that renders it from a different view
	define_linktarget(r_eye, l_eye,
		RENDERTARGET_NOSCALE, -1, RENDERTARGET_FULL);

-- position the composition output and assign distortion
	resize_image(l_eye, VRESW * 0.5, VRESH);
	resize_image(r_eye, VRESW * 0.5, VRESH);
	move_image(r_eye, VRESW * 0.5, 0);
	print("build for", VRESW, VRESH);

-- build our cameras (update AR/FOV/near,far later)
	local pos = build_3dbox(0.01, 0.01, 0.01);
	local camera_l = null_surface(1, 1);
	local camera_r = null_surface(1, 1);
	camtag_model(camera_l, 0.1, 100.0, 45.0, 1.33, true, false, 0, l_eye);
	camtag_model(camera_r, 0.1, 100.0, 45.0, 1.33, true, false, 0, r_eye);
	link_image(camera_l, pos);
	link_image(camera_r, pos);
	move3d_model(camera_l, -0.1, 0, 0);
	move3d_model(camera_r,  0.1, 0, 0);
	forward3d_model(pos, -10);
	show_image({pos, l_eye, r_eye});

-- activate VR
	vr_setup("", function(source, status)
		if (status.kind == "limb_added") then
			if (status.name == "neck") then
				vr_map_limb(source, cube, status.id);
				local md = vr_metadata(source);

				image_shader(l_eye, l_eye_shader);
				image_shader(r_eye, r_eye_shader);
				setup_hmd_uniforms(md, l_eye_shader, r_eye_shader);
			end
		elseif (status.kind == "limb_removed") then
			print("lost limb", status.name);
		end
	end);
end
