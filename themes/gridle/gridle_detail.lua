-- Implement "detail view" in Gridle, albeit easily adapted to other themes.
--
-- gridledetail_show();
--  replaces the current "grid" with a single- game view,
--  trying to squeeze in as much extra information as possible (3d model,
--  flyer, history)
--
-- first determines layout by looking for specific resources;
-- 1. game- specific script (gamescripts/setname.lua)
-- 2. 3d- view (models/setname)
-- 3. (fallback) flow layout of whatever other (marquee, cpo, flyer, etc.) that was found.
--
-- Also allows for single (menu- up / down) navigation between games
-- MENU_ESCAPE returns to game
--
local detailview = {};

local vscanshader = [[
	uniform mat4 modelview;
	uniform mat4 projection;

	attribute vec4 vertex;
	
	void main(){
		gl_Position = (projection * modelview) * vertex;
	}
]];

local fscanshader = [[
	void main(){
		gl_FragColor = vec4(0.0, 0.5, 1.0, 1.0);
	}
]];

local vlitshader = [[
	uniform mat4 modelview;
	uniform mat4 projection;
	
	varying vec2 txco;

	attribute vec4 vertex;
	attribute vec2 texcoord;
	
void main(){
	txco = texcoord;
	gl_Position = (projection * modelview) * vertex;
}
]];

local fgreen = [[
	void main(){
		gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0);
	}
]];

local flitshader = [[
	uniform sampler2D map_diffuse;
	uniform int timestamp;
	varying vec2 txco;
	
	void main(){
		vec4 fragcol = texture2D(map_diffuse, txco);
		gl_FragColor = fragcol;
	}
]];

--		if (mod(timestamp, 128) == 0)
--			fragcol = vec4(0.0, 0.0, 0.0, 1.0);
local vshader = [[
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

local fshader = [[
	uniform sampler2D map_diffuse;
	uniform vec3 wdiffuse;
	uniform vec3 wambient;

	varying vec3 lightdir;
	varying vec3 fnormal;
	varying vec2 txco;

	void main() {
		vec4 color = vec4(wambient,1.0);
		vec4 txcol = texture2D(map_diffuse, txco);

		if (txcol.a < 0.5){
			discard;
		}
		
		float ndl = max( dot(fnormal, lightdir), 0.0);
		if (ndl > 0.0){
			txcol += vec4(wdiffuse * ndl, 0.0);
		}
		
		gl_FragColor = txcol * color;
	}
]];

backlit_shader3d = build_shader(vlitshader, flitshader);
default_shader3d = build_shader(vshader, fshader);
scanline_shader  = build_shader(vscanshader, fscanshader);

shader_uniform(default_shader3d, "wlightdir", "fff", 1.0, 0.0, 0.0);
shader_uniform(default_shader3d, "wambient", "fff", 0.3, 0.3, 0.3);
shader_uniform(default_shader3d, "wdiffuse", "fff", 0.6, 0.6, 0.6);

local function gridledetail_buildview( setname )
	detailview.model = load_model(setname);
	if (detailview.model) then
		scale_3dvertices(detailview.model.vid);
		show_image(detailview.model.vid);
		image_shader(detailview.model.vid, default_shader3d);
--		image_shader(detailview.model.images[ detailview.model.labels["marquee"] ], backlit_shader3d);
--		image_shader(detailview.model.images[ detailview.model.labels["display"] ], scanline_shader);
		detailview.roll  = 0;
		detailview.pitch = 0;
		detailview.yaw   = 0;
	else

	end
end

local function gridledetail_freeview()
	if (detailview.model) then
		delete_image(detailview.model.vid);
		detailview.model = nil;
	end
end

function gridledetail_show()
	-- override I/O table
	griddispatch = settings.iodispatch;
	
	settings.iodispatch = {};
	settings.iodispatch["MENU_UP"] = function(iotbl) print("missing, load prev. game"); end
	settings.iodispatch["MENU_DOWN"] = function(iotbl) print("missing, load next. game"); end
	settings.iodispatch["MENU_LEFT"] = function(iotbl)
		if (detailview.model) then
			instant_image_transform(detailview.model.vid);
			rotate3d_model(detailview.model.vid, 10, 0, 0, 10);
		end
	end
	
	settings.iodispatch["MENU_RIGHT"] = function(iotbl) print("rotate 3dmodel"); end
	settings.iodispatch["ZOOM_CURSOR"] = function(iotbl) print("zoom 3dmodel"); end
	settings.iodispatch["MENU_SELECT"] = griddispatch["MENU_SELECT"];
	settings.iodispatch["MENU_ESCAPE"] = function(iotbl)
		gridledetail_freeview();
		build_grid(settings.cell_width, settings.cell_height);
		settings.iodispatch = griddispatch;
	end

	
	move3d_camera(-1.0, 0.0, -4.0);
	erase_grid(false);
	-- load current game
	gridledetail_buildview("joust");
end
