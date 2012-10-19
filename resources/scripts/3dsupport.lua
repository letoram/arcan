--
-- Collection of support functions and shaders
-- This is mostly temporary hacks, awaiting the 3D- revamp of 0.3
--
-- Format changes (0.1):
--  added format_version field
--  screenview properties are now specified RELATIVE to the base orientation
--

local support3d = {};

local fullbright_vshader = [[
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

local fullbright_flipvshader = [[
uniform mat4 modelview;
uniform mat4 projection;

attribute vec4 vertex;
attribute vec2 texcoord;

varying vec2 texco;

void main(void)
{
	texco = texcoord;
	texco.t = 1.0 - texco.t;

	gl_Position = (projection * modelview) * vertex;
}
]];

local fullbright_fshader = [[
uniform sampler2D map_diffuse;
uniform float obj_opacity;

varying vec2 texco;

void main(){
  vec4 col = texture2D(map_diffuse, texco);
  col.a = col.a * obj_opacity;
  gl_FragColor = col;
}
]];

local animtexco_vshader = [[
uniform mat4 modelview;
uniform mat4 projection;
uniform int timestamp;

uniform vec2 speedfact;

attribute vec4 vertex;
attribute vec2 texcoord;

varying vec2 texco;

void main(void)
{
	texco.s = texcoord.s + fract(float(timestamp) / speedfact.x);
	texco.t = texcoord.t + fract(float(timestamp) / speedfact.y);

	gl_Position = (projection * modelview) * vertex;
}
]];

local flicker_fshader = [[
uniform int timestamp;
uniform sampler2D map_diffuse;
varying vec2 texco;

void main(){
	vec4 fragcol = texture2D(map_diffuse, texco);

	if ( int( mod(float(timestamp), 256.0)) == 0)
		fragcol *= vec4(0.5, 0.5, 0.5, 1.0);

	gl_FragColor = fragcol;
}
]];

local def3d_fullbright_flip = build_shader(fullbright_flipvshader, fullbright_fshader, "3dsupp_fullbright_flip");
local def3d_fullbright      = build_shader(fullbright_vshader,     fullbright_fshader, "3dsupp_fullbright"     );
local def3d_txcoscroll      = build_shader(animtexco_vshader,      fullbright_fshader, "3dsupp_brokendisp"     );
local def3d_backlights      = build_shader(fullbright_vshader,     flicker_fshader,    "3dsupp_flicker"        );

shader_uniform(def3d_backlights, "map_diffuse", "i", PERSIST, 0);
shader_uniform(def3d_fullbright, "map_diffuse", "i", PERSIST, 0);
shader_uniform(def3d_txcoscroll, "map_diffuse", "i", PERSIST, 0);

local function material_loaded(source, statustbl)
	if (statustbl.kind == "load_failed") then
		warning("Material load failed on resource ( " .. tostring(statustbl.resource) .. " )\n");
	end
end

local function snap_loaded(source, statustbl)
end

local function load_material(modelname, meshname, synth)
	local rvid = BADID;
	local fnameb = "models/" .. modelname .. "/textures/" .. meshname;

	if (resource(fnameb .. ".png")) then
		rvid = load_image_asynch(fnameb .. ".png", material_loaded);
		image_tracetag(rvid, "3dmodel("..modelname.."):"..meshname);
	elseif (resource(fnameb .. ".jpg")) then
		rvid = load_image_asynch(fnameb .. ".jpg", material_loaded);
		image_tracetag(rvid, "3dmodel("..modelname.."):" ..meshname);
	elseif (synth) then 
		rvid = fill_surface(8,8, 255, math.random(1,255), math.random(1,255))
		image_tracetag(rvid, "3dmodel("..modelname.."):placeholder");
	end

	return rvid;
end

-- sort so that labels with known alpha attributes, get rendered last (just bezel and marquee in this case)
local function sort_meshes(a, b)
	if (a[1] == "bezel" and b[1] ~= "bezel") then 
		return false;
	elseif (b[1] == "bezel" and a[1] ~= "bezel") then
		return true;
	else
		return a[1] < b[1]
	end
end

function load_model_generic(modelname, rndmissing)
	if (rndmissing == nil) then rndmissing = true; end

	local basep  = "models/" .. modelname .. "/";
	local meshes = glob_resource(basep .. "*.ctm");

	if (#meshes == 0) then return nil end
  
	local model  = {
		labels = {}, images = {}
};

-- This just gives us an empty model to fill with meshes,
-- however it provides a reference point for other vid operations (i.e.
-- instancing, linking etc.)
	model.vid = new_3dmodel();
	image_tracetag(model.vid, "3dmodel(" .. modelname ..")");
	
	if (model.vid == BADID) then return nil end

	image_framesetsize(model.vid, #meshes);
	switch_default_imageproc(IMAGEPROC_FLIPH);

	seqlist = {}
	
	for i=1, #meshes do
		local ent = {};
		ent[1] = string.sub(meshes[i], 1, -5);
		ent[2] = meshes[i];
		seqlist[i] = ent;
	end

	table.sort(seqlist, sort_meshes);
	
	for i=1, #seqlist do
		slot = i-1;
		add_3dmesh(model.vid, basep .. seqlist[i][2], 1);
		local vid = load_material(modelname, seqlist[i][1], rndmissing);

		model.labels[seqlist[i][1]] = slot;
		model.images[slot] = vid;
		model.screenview = {};
		model.default_orientation    = {roll = 0, pitch = 0, yaw = 0};
		model.screenview.position    = {x    = 0,     y = 0.5, z = 1.0};
		model.screenview.orientation = {roll = 0, pitch = 0, yaw = 0};

		set_image_as_frame(model.vid, vid, slot, FRAMESET_DETACH);
	end
	
	switch_default_imageproc(IMAGEPROC_NORMAL);

	return model;
end

-- scan <filename> and look for #define SYMBOL <LF> or #ifdef <SYMBOL>
-- and return in two separate lists. 
function parse_shader(filename)
	local defines = {};
	local conditions = {};
	
	if (open_rawresource(filename)) then
		local line = read_rawresource();
		
		while (line ~= nil) do
			if (string.match(line, "^%s*//") == nil) then 
				local val = string.match(line, "#define%s+([%w_]+)$");

				if (val) then
					table.insert(defines, val);
				else
					val = string.match(line, "#ifdef%s+([%w_]+)$");
					if (val) then table.insert(conditions, val); end
				end
			end
				
			line = read_rawresource();
		end
	
		close_rawresource();
	end

	return defines, conditions;
end

local function shaderproc_line(instr, filter_toggle)
-- if we don't explicitly set a list of desired defines, we'll just return whatever we get 
	if (filter_toggle == false) then return instr; end

-- if the define is a "toggle define", just ignore it 
	
	local defkey = string.match(instr, "#define%s+([%w_]+)$")
	if (defkey) then
		return "";
	else
		return instr;
	end
end

-- raw resource wrapper that also inject pre-processor commands
-- in GLSL- shaders. Used in conjunction to find specific "toggle" defines,
-- e.g. #define SYMBOL, removes it if it's in the undefines list
-- or adds prior to a matching #ifdef. This should be used in conjunction with
-- parse_shader(filename)
function load_shader(vertname, fragname, label, defines)
	local vprog = "";
	local fprog = "";
	local verttbl = {};
	local fragtbl = {};

	if defines ~= nil then
			for key, val in pairs(defines) do
				table.insert(verttbl, "#define " .. key);
				table.insert(fragtbl, "#define " .. key);
			end
		end

	if (type(vertname) == "string") then
		if ( open_rawresource(vertname) ) then
			local line = read_rawresource();

			while (line ~= nil) do
				table.insert(verttbl, shaderproc_line(line, defines ~= nil) );
				line = read_rawresource();
			end

			vprog = table.concat(verttbl, "\n");
			close_rawresource();
		end
	elseif (type(vertname) == "table") then
		vprog = table.concat(vertname, "\n");
	else
		warning("load_shader(" .. label .. ") failed, bad vertex program argument.\n");
	end

	if (type(fragname) == "string") then
		if (open_rawresource(fragname) ) then
			local line = read_rawresource();
			while (line ~= nil) do
				table.insert(fragtbl, shaderproc_line(line, defines ~= nil) );
				line = read_rawresource();
			end

			fprog = table.concat(fragtbl, "\n"); 
			close_rawresource();
		end
	elseif (type(fragname) == "table") then
		fprog = table.concat(fragname, "\n");
		print(fprog);
	else
		warning("load_shader(" .. label .. ") failed, bad fragment program argument.\n");
	end

	return build_shader(vprog, fprog, label);
end

function load_model(modelname)
-- hack around legacy models, make sure that the script loaded can't use orient3d and log if it tries to
	local orient3d = orient3d_model;
	local oriented = nil;
	
	orient3d_model = function(vid, r, p, y)
		oriented = {roll = r, pitch = p, yaw = y};
	end
	
	rv = nil;
-- use one of the generic loaders
	if (resource("models/" .. modelname .. "/" .. modelname .. ".lua")) then
		rv = system_load("models/" .. modelname .. "/" .. modelname .. ".lua")();
	else
		rv = load_model_generic(modelname);
		if (rv ~= nil) then 
			rv.format_version = 0.1;
		end
	end

	orient3d_model = orient3d;
	
	if (rv ~= nil) then
		scale_3dvertices(rv.vid);
-- add some helper functions, view angles etc. are specified absolute rather than relative to the base, so we have to translate
		local o = rv.default_orientation;

-- only re-orient if the default orientation deviates too much as it's expensive and strips precision
		if (o.roll > 0.0001 or o.roll < -0.0001 or
			o.pitch > 0.0001 or o.pitch < -0.0001 or
			o.yaw > 0.0001 or o.yaw < -0.0001) then
			orient3d_model(rv.vid, rv.default_orientation.roll, rv.default_orientation.pitch, rv.default_orientation.yaw);
		end

		if (rv.format_version == nil) then
			rv.screenview.orientation.roll  = rv.screenview.orientation.roll  - rv.default_orientation.roll;
			rv.screenview.orientation.pitch = rv.screenview.orientation.pitch - rv.default_orientation.pitch;
			rv.screenview.orientation.yaw   = rv.screenview.orientation.yaw   - rv.default_orientation.yaw;
		end
		
	end
	
	return rv;
end

--
-- try and find a matching game cabinet based on a few easy heuristics
-- 1. setname (models/setname) (strip any extension as well)
-- 2. known clones (or family members) of the setname in question
-- 3. group mappers (nintendo, neo-geo, naomi etc.) for common cabinets
-- 4. generic shared fallback (or none)
--
-- returns a string to be used as input for setup_cabinet_model
function find_cabinet_model(gametbl)
-- quickhack for ex. fba importer that has mame shortnames but uses the fileextension in the setname
--	if (not res) then
--		res = gridledetail_checkmodel( string.sub(gametbl.setname, 1, -5) );
--	end

	return "neogeo";
end

--
-- generate and load basic textures etc.
-- until partial persistence is implemented, this will need to be run whenever
-- the stack gets pushed and pop:ed
--
function setup_3dsupport()
		support3d.camera = fill_surface(4, 4, 0, 0, 0);
		camtag_model(support3d.camera);
		image_tracetag(support3d.camera, "3d camera");
	
	if (not valid_vid(support3d.hf_noise)) then
		switch_default_texmode( TEX_REPEAT, TEX_REPEAT );
		support3d.hf_noise = random_surface(256, 256);
		switch_default_texmode( TEX_CLAMP, TEX_CLAMP );
		shader_uniform(def3d_txcoscroll, "speedfact", "ff", PERSIST, 12.0, 12.0);
		image_tracetag(support3d.hf_noise, "3dmodel(noise)");
	end

end

--
-- Try to map a full cabinet model (display, t-mold etc.)
-- modelname, matching subfolder in resources/models (this can be generic models, thus we separate restbl)
-- restbl,    result from resource lookup (used for loading screenshots etc.)
-- options,   per- cabinet configurable options (t-mold, coindoor type, alternative shaders etc.)
-- 
function setup_cabinet_model(modelname, restbl, options)
	local res = load_model(modelname);

	if (res) then
		res.display = function(self)
			return self.display_vid;
		end
		
-- after calling this function, vid is no-longer the responsibility of the caller
		res.update_display = function(self, vid, shid)
			if not valid_vid(self.vid) then -- edge case, asynch- event trigger -> update_display on something that was deleted the same cycle
				return;
			end
	
			if (self.labels["display"] == nil) then
				print("update_display( no display )");
				delete_image(vid);
				return;
			end

			shid = shid and shid or def3d_fullbright;
			flip = (flip == nil or flip == false) and 0 or 1;
			
-- update the display, free the old resource and invert texture coordinates (possible) in the vertex shader 
			local rvid = set_image_as_frame(self.vid, vid, self.labels["display"], FRAMESET_DETACH);

			mesh_shader(self.vid, shid, self.labels["display"]);
	
			if (valid_vid(rvid) and rvid ~= vid) then
				expire_image(rvid, 20);
			end
		end

-- change the display to show just a noisy image
		res.display_broken = function(self)
			local noiseinst = instance_image(support3d.hf_noise);
			image_tracetag(noiseinst, "3dmodel(noise instance)");
			self:update_display(noiseinst, def3d_txcoscroll);
		end

-- use this to set another colour for the t-mold if it is possible
		res.mold_color = function(self, r, g, b)
			if (self.labels["t-mold"] == nil) then return; end
			self.display_vid = fill_surface(2, 2, r, g, b);
			local rvid = set_image_as_frame(self.vid, self.display_vid, self.labels["t-mold"], FRAMESET_DETACH);
			if (valid_vid(rvid)) then
				delete_image(rvid);
			end
		end

-- clean-up model-specific resources
		res.destroy = function(self, timeout)
			expire_image(self.vid, timeout);
			self.vid = BADID;
		end

		image_shader(res.vid, def3d_fullbright);

-- try and use screenshots etc. from restbl to populate the display- submesh (or just an animated noise texture as a start)
-- labels to look for: marquee, coinlights, snapshot, display
		
-- if there's a snapshot slot, no movie but a snapshot found, it will be used in both places ;P
		local snapvid = nil;
		if (res.labels["snapshot"] and not options.nosnap) then
			mesh_shader(res.vid, def3d_fullbright, res.labels["snapshot"]);
			
			if (restbl.screenshots and #restbl.screenshots > 0) then
				snapvid = load_image_asynch(restbl.screenshots[math.random(1,#restbl.screenshots)], material_loaded);
				image_tracetag(snapvid, "3dmodel(" .. modelname .. "):display_snap");
				local rvid = set_image_as_frame(res.vid, snapvid, res.labels["snapshot"], FRAMESET_DETACH);
				if (valid_vid(rvid)) then delete_image(rvid); end
			end
		end
		
		if (res.labels["display"]) then
			res:display_broken(); -- always "break" the display as a means of managing the interval between the asynchronous operations and not. 

			if (restbl.movies and #restbl.movies > 0) then
				vid, aid = load_movie(restbl.movies[math.random(1,#restbl.movies)], FRAMESERVER_LOOP, function(source, tbl)
					if (tbl.kind ~= "frameserver_terminated") then
						play_movie(source);
						res:update_display(source, def3d_fullbright_flip);
					else
						res:display_broken();
					end
				end);

				image_tracetag(vid, "3dmodel(" .. modelname .. "):display_movie");
	
			elseif (restbl.screenshots and #restbl.screenshots > 0) then
-- try to reuse already loaded snapshot
				if (snapvid == nil) then
					snapvid = load_image_asynch(restbl.screenshots[math.random(1,#restbl.screenshots)], material_loaded);
					image_tracetag(snapvid, "3dmodel(" .. modelname .. "):display_ss");
				end

				res:update_display(snapvid);
			else
			end
			
		end

		if (res.labels["coinlights"]) then
			mesh_shader(res.vid, def3d_fullbright, res.labels["coinlights"]);
		end
		
-- even if the model may define these, they can be overridden by having the corresponding media elsewhere
		if (res.labels["marquee"]) then
			mesh_shader(res.vid, def3d_backlights, res.labels["marquee"]);
			if (restbl.marquees and #restbl.marquees > 0) then
				local marqvid = load_image_asynch(restbl.marquees[math.random(1,#restbl.marquees)], material_loaded);
				image_tracetag(marqvid, "3dmodel("..modelname.."):marqueeres");
				local rvid = set_image_as_frame(res.vid, marqvid, res.labels["marquee"], FRAMESET_DETACH);

				if (valid_vid(rvid)) then delete_image(rvid); end
			end
		end

	end
	
	return res;
end
