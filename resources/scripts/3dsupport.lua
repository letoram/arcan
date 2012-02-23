-- Collection of support functions and shaders

local function load_material(modelname, meshname)
	local rvid = BADID;
	local fnameb = "models/" .. modelname .. "/textures/" .. meshname;

	if (resource(fnameb .. ".png")) then
		rvid = load_image(fnameb .. ".png");
	elseif (resource(fnameb .. ".jpg")) then
		rvid = load_image(fnameb .. ".jpg");
	else
		rvid = fill_surface(8,8, 255, math.random(1,255), math.random(1,255));
	end

	return rvid;
end

function load_model_generic(modelname)
	local basep = "models/" .. modelname .. "/";
	local meshes   = glob_resource(basep .. "*.ctm", SHARED_RESOURCE);
	if (#meshes == 0) then return nil end
  
	local model  = {
		labels = {}, images = {}
};

-- This just gives us an empty model to fill with meshes,
-- however it provides a reference point for other vid operations (i.e.
-- instancing, linking etc.)

	model.vid = new_3dmodel();
	if (model.vid == BADID) then return nil end
	image_framesetsize(model.vid, #meshes * 2);

	for i=1, #meshes do
		slot = (i-1) * 2;
		add_3dmesh(model.vid, basep .. meshes[i], 2);
		switch_default_imageproc(IMAGEPROC_FLIPH);
			local vid = load_material(modelname, string.sub(meshes[i], 1, -5));
			image_maptype(vid, MAPTYPE_NORMAL);
		switch_default_imageproc(IMAGEPROC_NORMAL);

		model.labels[string.sub(meshes[i], 1, -5)] = slot;
		model.images[slot] = vid;

		set_image_as_frame(model.vid, vid, slot, 1);
		set_image_as_frame(model.vid, fill_surface(8, 8, math.random(1, 255), math.random(1,255), math.random(1,255)), slot+1, 1);
	end
	
	return model;
end

function load_model(modelname, shaderid)
	rv = nil;
-- use one of the generic loaders
	if (resource("models/" .. modelname .. "/" .. modelname .. ".lua")) then
		modelshaderid = shaderid; -- ugly hack
		rv = system_load("models/" .. modelname .. "/" .. modelname .. ".lua")();
	else
		rv = load_model_generic(modelname, shaderid);
	end
	
	return rv;
end
