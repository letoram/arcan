-- 3D Editor theme,
-- Goal is to develop it in such a way that
-- It can be migrated to a resource- script so that
-- the functionality can be added to any theme

a3ded_settings = {
	culling = true,
	debug_geometry = true,
	active_model = BADID,
	active_submesh = -1
};

systemlbls = {
	"Load Scene...",
	"Save Scene...",
	"Quit A3DED"
};

modelctxlbls = {"Attach Mesh...",
	"Assign Material",
	"Assign Shader",
	"Drop..."};

geommenlbls = {"Add Model...",
	"Build Plane...",
	"Build Geometry..."};

function a3ded_keyconf()
	labels = {'rMENU_ESCAPE', 'rSELECT', 'rMENU_UP', 'rMENU_DOWN', 'rMENU_LEFT', 'rMENU_RIGHT', 'rMENU_SETTINGS', ' ROTATE_PX', ' ROTATE_PY', ' ROTATE_PZ', ' ROTATE_NX', ' ROTATE_NY', ' ROTATE_NZ', ' TRANSLATE_NX', ' TRANSLATE_NY', ' TRANSLATE_NZ', ' TRANSLATE_PX', ' TRANSLATE_PY', ' TRANSLATE_PZ', ' SCALE_P', ' SCALE_N', 'rMENU_RESOURCE', 'rMENU_CTX', 'rMENU_SYSTEM'};

	keyconfig = keyconf_create(1, keylabels);
	a3ded_settings.keyconfig.iofun = gridle_input;

	if (keyconfig.active == false) then
		gridle_input = function(iotbl) -- keyconfig io function hook
			if (keyconfig:input(iotbl) == true) then
				a3ded_input = keyconfig.iofun;
			end
		end
	end

	a3ded_settings.keyconfig = keyconfig;
end

function browse_resource( parent, path, group )
	if (subgroup == nil) then
		
	end
end

function a3ded()
	system_load("scripts/keyconf.lua")();

	a3ded_keyconf();
--  load settings from KV
--  setup skybox with debugging primitives
end


function a3ded_input()
end

function a3ded_clock_pulse()
end

function a3ded_video_event()
end
