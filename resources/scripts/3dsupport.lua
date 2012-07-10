-- Collection of support functions and shaders

local function load_material(modelname, meshname, synth)
	local rvid = BADID;
	local fnameb = "models/" .. modelname .. "/textures/" .. meshname;

	if (resource(fnameb .. ".png")) then
		rvid = load_image_asynch(fnameb .. ".png", function(source, status) end);
	elseif (resource(fnameb .. ".jpg")) then
		rvid = load_image_asynch(fnameb .. ".jpg", function(source, status) end);
	elseif (synth) then 
		rvid = fill_surface(8,8, 255, math.random(1,255), math.random(1,255))
	end

	return rvid;
end

function load_model_generic(modelname, rndmissing)
	if (rndmissing == nil) then rndmissing = true; end

	local basep  = "models/" .. modelname .. "/";
	local meshes = glob_resource(basep .. "*.ctm", SHARED_RESOURCE);
	if (#meshes == 0) then return nil end
  
	local model  = {
		labels = {}, images = {}
};

-- This just gives us an empty model to fill with meshes,
-- however it provides a reference point for other vid operations (i.e.
-- instancing, linking etc.)

	model.vid = new_3dmodel();
	if (model.vid == BADID) then return nil end
	image_framesetsize(model.vid, #meshes);
	switch_default_imageproc(IMAGEPROC_FLIPH);

	for i=1, #meshes do
		slot = i - 1;
		add_3dmesh(model.vid, basep .. meshes[i], 1);
		local vid = load_material(modelname, string.sub(meshes[i], 1, -5), rndmissing);

		model.labels[string.sub(meshes[i], 1, -5)] = slot;
		
		model.images[slot] = vid;
		model.screenview = {};
		model.default_orientation = {roll = 0, pitch = 0, yaw = 0};
		model.screenview.position = {x = 0, y = 0.5, z = 1.0};
		model.screenview.orientation = {roll = 0, pitch = 0, yaw = 0};
		set_image_as_frame(model.vid, vid, slot, 1);
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
	
	if ( open_rawresource(vertname) ) then
		local line = read_rawresource();

		while (line ~= nil) do
			table.insert(verttbl, shaderproc_line(line, defines ~= nil) );
			line = read_rawresource();
		end

		vprog = table.concat(verttbl, "\n");
		close_rawresource();
	end

	if (open_rawresource(fragname) ) then
		local line = read_rawresource();
		while (line ~= nil) do
			table.insert(fragtbl, shaderproc_line(line, defines ~= nil) );
			line = read_rawresource();
		end

		fprog = table.concat(fragtbl, "\n"); 
		close_rawresource();
	end

	return build_shader(vprog, fprog, label);
end

function load_model(modelname)
	rv = nil;
-- use one of the generic loaders
	if (resource("models/" .. modelname .. "/" .. modelname .. ".lua")) then
		rv = system_load("models/" .. modelname .. "/" .. modelname .. ".lua")();
	else
		rv = load_model_generic(modelname);
	end

	if (rv ~= nil) then
-- add some helper functions 
	end
	
	return rv;
end
