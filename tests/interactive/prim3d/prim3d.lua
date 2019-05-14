function get_shader()
local dir_light = build_shader(
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
]],
-- fragment
[[
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
]], "dir_light");
shader_uniform(dir_light, "map_diffuse", "i", PERSIST, 0);
shader_uniform(dir_light, "wlightdir", "fff", PERSIST, 1, 0, 0);
shader_uniform(dir_light, "wambient",  "fff", PERSIST, 0.3, 0.3, 0.3);
shader_uniform(dir_light, "wdiffuse",  "fff", PERSIST, 0.6, 0.6, 0.6);
return dir_light;
end

function prim3d()
	camera = null_surface(1, 1);
	camtag_model(camera, 0.01, 100.0, 45.0, 1.33, 1, 1);
	image_tracetag(camera, "camera");
	forward3d_model(camera, -10.0);

	local csurf = fill_surface(32, 32, 127, 0, 0);
	cube_1 = build_3dbox(1, 1, 1);
	show_image(cube_1);
	move3d_model(cube_1, 1, -1, 0, 500);
	scale3d_model(cube_1, 0.5, 0.5, 1.0, 500);
	image_sharestorage(csurf, cube_1);
	delete_image(csurf);
	image_shader(cube_1, get_shader());
end

function prim3d_input(iotbl)
	if iotbl.source ~= "mouse" then
		return;
	end

	if iotbl.digital then
		if iotbl.active then
			if iotbl.subid == MOUSE_BTNLEFT then
				image_origo_offset(cube_1, -1, -1, -1);
				print("-1 corner");
			elseif iotbl.subid == MOUSE_BTNRIGHT then
				image_origo_offset(cube_1, 1, 1, 1);
				print("+1 corner");
			else
				image_origo_offset(cube_1, 0, 0, 0);
				print("center");
			end
		end
		return;
	end

	local mx = 0;
	local my = 0;
	if (iotbl.relative) then
		if (iotbl.subid == 1) then
			my = iotbl.samples[1];
		else
			mx = iotbl.samples[1];
		end
		rotate3d_model(cube_1, mx * 0.01, my * 0.01, 0, 0, ROTATE_RELATIVE);
	else
		if (iotbl.subid == 1) then
			my = iotbl.samples[1] / VRESH;
		else
			mx = iotbl.samples[1] / VRESW;
		end
		rotate3d_model(cube_1, mx * 0.01, my * 0.01, 0, 0, ROTATE_ABSOLUTE);
	end
end
