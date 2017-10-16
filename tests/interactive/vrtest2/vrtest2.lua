--
-- work-in-progress simple model /scene viewer using distortion shader
--
local dist_frag = [[
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
	if (tc_g.x < 0.0 || tc_g.x > 1.0 || tc_g.y < 0.0 || tc_g.y > 1.0)
		gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
	else
		gl_FragColor = vec4(cr, cg, cb, 1.0);
}
]];
local dir_light_v =
-- vertex
[[
uniform mat4 modelview;
uniform mat4 projection;
uniform vec3 wlightdir;

attribute vec4 vertex;
attribute vec3 normal;
attribute vec2 texcoord;

varying vec3 lightdir;
varying vec2 txco;
varying vec3 fnormal;

void main(){
	fnormal = vec3(modelview * vec4(normal, 0.0));
	lightdir = normalize(wlightdir);

	txco = texcoord;
	gl_Position = (projection * modelview) * vertex;
}
]];

-- fragment
local dir_light_f = [[
uniform vec3 wdiffuse;
uniform vec3 wambient;
uniform sampler2D map_diffuse;

varying vec3 lightdir;
varying vec3 fnormal;
varying vec2 txco;

void main() {
	vec4 color = vec4(wambient,1.0);
	vec4 txcol = texture2D(map_diffuse, txco);

	float ndl = max( dot(fnormal, lightdir), 0.0);
	if (ndl > 0.0){
		txcol += vec4(wdiffuse * ndl, 0.0);
	}

	gl_FragColor = txcol * color;
}
]];

local hmd_state = {
	px = 0,
	py = 0,
	pz = -5,
	ss = 0.05,
	separation = 0.01
};

local function update_hmd_state(md, s)
	local scale_x = md.horizontal / 2.0;
	local scale_y = md.vertical;

	local cl_x = scale_x - md.hsep / 2.0;
	local cr_x = md.hsep / 2.0;

	local warp_scale = cl_x > cr_x and cl_x or cr_x;
	local dist_override = {
		1, 0.22, 0.120, 0
	};
	local abb_override = {
		1, 1, 1, 0
	};

-- abb: 0.99, -0.004, 1.014, 0
-- scale: 0.81, aspect: 0.89
-- warp: 1, 0.22, 0.120, 0,
-- factor: 1.1
--	md.distortion = dist_override;
--	md.abberation = abb_override;

	shader_uniform(s.l_shid, "viewport_scale", "ff", scale_x, scale_y);
	shader_uniform(s.l_shid, "warp_scale", "f", warp_scale);
	shader_uniform(s.l_shid, "dist", "ffff",
		md.distortion[1], md.distortion[2], md.distortion[3], md.distortion[4]);
	shader_uniform(s.l_shid, "aberr", "fff",
		md.abberation[1], md.abberation[2], md.abberation[3]);

-- relative the pos anchor
	move3d_model(hmd_state.l_cam, -s.separation, 0, 0);
	move3d_model(hmd_state.r_cam,  s.separation, 0, 0);

-- per eye
	shader_uniform(s.l_shid, "center_xy", "ff", md.vpos, cl_x);
	shader_uniform(s.r_shid, "center_xy", "ff", md.vpos, cr_x);

	print("HMD properties:")
	print("h/vsize:", md.horizontal, md.vertical);
	print("ar:", md.left_ar, md.right_ar);
	print("fov:", md.left_fov, md.right_fov);
	print("warp_scale:", warp_scale);
	print("viewport_scale:", scale_x, scale_y);
	print("distortion:",
		md.distortion[1], md.distortion[2], md.distortion[3], md.distortion[4]);
	print("abberation:",
		md.abberation[1], md.abberation[2], md.abberation[3], md.abberation[4]);

-- set the individual cameras as responsible for a rendertarget each
	camtag_model(hmd_state.l_cam, 0.1, 1000.0,
			md.left_fov * 180 / 3.1416, md.left_ar, false, true, 0, s.l_eye);
	camtag_model(hmd_state.r_cam, 0.1, 1000.0,
			md.right_fov * 180 / 3.1416, md.right_ar, false, true, 0, s.r_eye);
end

-- build a pipeline and return as a table of vids
local function setup_3d_scene()
	local dir_light = build_shader(dir_light_v, dir_light_f, "dirlight");
	shader_uniform(dir_light, "map_diffuse", "i", PERSIST, 0);
	shader_uniform(dir_light, "wlightdir", "fff", PERSIST, 1, 0, 0);
	shader_uniform(dir_light, "wambient",  "fff", PERSIST, 0.3, 0.3, 0.3);
	shader_uniform(dir_light, "wdiffuse",  "fff", PERSIST, 0.6, 0.6, 0.6);

	local tex = fill_surface(32, 32, 255, 255, 255);
	cube = build_3dbox(1, 1, 1);
	show_image(cube);
	image_sharestorage(tex, cube);
	image_shader(cube, dir_light);
	delete_image(tex);
	return {cube};
end

local function vr_event_handler(source, status)
	if (status.kind == "limb_added") then
-- got our eyes [special case], map both cameras to the same limb-id
-- it is first now that we have access to our hmd as well
		if (status.name == "neck") then
			vr_map_limb(source, hmd_state.l_cam, status.id);
			vr_map_limb(source, hmd_state.r_cam, status.id);
			local md = vr_metadata(source);
			hmd_state.alive = true;
			hmd_state.metadata = md;
			update_hmd_state(md, hmd_state);
		end
	elseif (status.kind == "limb_removed") then
		if (status.name == "neck") then
			hmd_state.alive = false;
		end
	end
end

function vrtest2(args)
-- this is in -p arcan/data/resources
	symtable = system_load("scripts/symtable.lua"){};

-- FIXME: parse from args
	local l_eye_res_w = VRESW;
	local l_eye_res_h = VRESH;
	local r_eye_res_w = VRESW;
	local r_eye_res_h = VRESH;
	local l_eye_shader = build_shader(nil, dist_frag, "distortion");
	local r_eye_shader = shader_ugroup(l_eye_shader);

-- FIXME: these really should use MSAA and MSAA- aware sampling in l/r shader
	local l_eye = alloc_surface(l_eye_res_w, l_eye_res_h);
	local r_eye = alloc_surface(r_eye_res_w, r_eye_res_h);
	image_shader(l_eye, l_eye_shader);
	image_shader(r_eye, r_eye_shader);

	define_rendertarget(l_eye, setup_3d_scene(),
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, -1, RENDERTARGET_FULL);

-- and the alias that renders it from a different view
	define_linktarget(r_eye, l_eye,
		RENDERTARGET_NOSCALE, -1, RENDERTARGET_FULL);

-- position the composition output and assign distortion
	resize_image(l_eye, VRESW * 0.5, VRESH);
	resize_image(r_eye, VRESW * 0.5, VRESH);
	move_image(r_eye, VRESW * 0.5, 0);

-- build our cameras (update AR/FOV/near,far later)
	local pos = null_surface(1, 1);
	local camera_l = null_surface(1, 1);
	local camera_r = null_surface(1, 1);
	link_image(camera_l, pos);
	link_image(camera_r, pos);

-- back up a bit so we see what's at 0.0
	show_image({pos, l_eye, r_eye});

-- the state we want to keep
	hmd_state.l_cam = camera_l;
	hmd_state.r_cam = camera_r;
	hmd_state.l_eye = l_eye;
	hmd_state.r_eye = r_eye;
	hmd_state.anchor = pos;
	hmd_state.l_shid = l_eye_shader;
	hmd_state.r_shid = r_eye_shader;

-- activate VR
	vr_setup("", vr_event_handler);
end

-- tie stepping to the monotonic clock so movement doesn't vary
-- with sample delivery rate
function vrtest2_clock_pulse()
	if (hmd_state.sx) then
		hmd_state.px = hmd_state.px + hmd_state.sx;
	end
	if (hmd_state.sy) then
		hmd_state.py = hmd_state.py + hmd_state.sy;
	end
	if (hmd_state.sz) then
		hmd_state.pz = hmd_state.pz + hmd_state.sz;
	end

	move3d_model(hmd_state.anchor, hmd_state.px, hmd_state.py, hmd_state.pz, 1);
end

function vrtest2_input(iotbl)
	if (not iotbl.translated) then
		return;
	end

	local sym = symtable[iotbl.keysym];
	if (not sym) then
		return;
	end

	if (sym == "LEFT") then
		hmd_state.sx = iotbl.active and -hmd_state.ss or nil;
	elseif (sym == "RIGHT") then
		hmd_state.sx = iotbl.active and hmd_state.ss or nil;
	elseif (sym == "UP") then
		hmd_state.sz = iotbl.active and hmd_state.ss or nil;
	elseif (sym == "DOWN") then
		hmd_state.sz = iotbl.active and -hmd_state.ss or nil;
	elseif (sym == "PAGEUP") then
		hmd_state.sy = iotbl.active and hmd_state.ss or nil;
	elseif (sym == "PAGEDOWN") then
		hmd_state.sy = iotbl.active and -hmd_state.ss or nil;
	elseif (sym == "ESCAPE") then
		return shutdown();
	end
end
