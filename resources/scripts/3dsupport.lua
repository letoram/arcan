-- Collection of support functions and shaders

local function load_material(modelname, meshname)
	local rvid = BADID;
	local fnameb = "models/" .. modelname .. "/textures/" .. meshname;

	if (resource(fnameb .. ".png")) then
		rvid = load_image_asynch(fnameb .. ".png", function(source, status) end);
	elseif (resource(fnameb .. ".jpg")) then
		rvid = load_image_asynch(fnameb .. ".jpg", function(source, status) end);
	else
		tmpvid = fill_surface(8,8, 255, math.random(1,255), math.random(1,255))
	end

	return rvid;
end

function load_model_generic(modelname)
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
		local vid = load_material(modelname, string.sub(meshes[i], 1, -5));

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

-- Simple wrapper around the "raw-resource" bit.
function load_shader(vertname, fragname, label)
	local vprog = "";
	local fprog = "";
	local verttbl = {};
	local fragtbl = {};

	if ( open_rawresource(vertname) ) then
		local line = read_rawresource();

		while (line ~= nil) do
			table.insert(verttbl, line);
			line = read_rawresource();
		end

		vprog = table.concat(verttbl, "\n");
		close_rawresource();
	end

	if (open_rawresource(fragname) ) then
		local line = read_rawresource();
		while (line ~= nil) do
			table.insert(fragtbl, line);
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
