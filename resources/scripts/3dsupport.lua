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
  
	local model  = {}
	model.labels = {} -- map frame # to filename
	model.images = {} -- map frame # to vid
	
	model.vid = load_3dmodel( basep .. meshes[1] );
	if (model.vid == BADID) then return nil end
	image_framesetsize(model.vid, #meshes);

	for i=1, #meshes do
		if (i > 1) then
			add_3dmesh(model.vid, basep .. meshes[i]);
		end

		switch_default_imageproc(IMAGEPROC_FLIPH);
		local vid = load_material(modelname, string.sub(meshes[i], 1, -5));
		switch_default_imageproc(IMAGEPROC_NORMAL);

		model.labels[string.sub(meshes[i], 1, -5)] = i-1;
		model.images[i-1] = vid;

		set_image_as_frame(model.vid, vid, i-1, 1);
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
