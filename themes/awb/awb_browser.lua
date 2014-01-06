--
-- Browser component with icons etc.
--

local browse_ext = {
};

function awbbrowse_gamedata(tbl)
	local res  = resourcefinder_search(tbl, true);
	local list = {};

	for i,j in ipairs(res.movies) do
		local ment = {
			resource = j,
			name     = "video_" .. tostring(i),
			trigger  = function()
				local wnd, tfun = awbwman_mediawnd(menulbl("Media Player"));
				load_movie(j, FRAMESERVER_LOOP, tfun);
				if (wnd == nil) then
					return;
				end
			end,
			cols     = {"video_" .. tostring(i)} 
		};
		table.insert(list, ment);
	end

	local imgcat = {"screenshots", "bezels", "marquees", "controlpanels",
		"overlays", "cabinets", "boxart"};

	for ind, cat in ipairs(imgcat) do
		if (res[cat]) then
			for i, j in ipairs(res[cat]) do
				local ment = {
					resource = j,
					trigger = function()
						local wnd, tfun = awbwman_mediawnd(
							menulbl(cat), nil, {subtype = "static"});
						load_image_asynch(j, tfun);
						if (wnd == nil) then
							return;
						end
					end,
					name = cat .. "_" .. tostring(i),
					cols = {cat .. "_" .. tostring(i)}
				};
				table.insert(list, ment);
			end
		end
	end

	local mdl = find_cabinet_model(tbl);
	if (mdl) then
		local ment = {
			resource = mdl,
			trigger  = function()
				local model = setup_cabinet_model(mdl, tbl, {});
				if (model.vid) then
					move3d_model(model.vid, 0.0, -0.2, -2.0);
				else
					model = {};
				end
				awbwman_modelwnd(menulbl("3D Model"), "3d", model); 
			end,
			name = "model(" .. mdl ..")",
			cols = {"3D Model"}
		};
		table.insert(list, ment);
	end

-- resource-finder don't sub-categorize properly so we'll 
-- have to do that manually
	awbwman_listwnd(menulbl("Media:" .. tbl.title), deffont_sz, linespace,
	{1.0}, list, desktoplbl);
end

function awbbrowse_addhandler(extension, idicon, handlerfun)
	local newent = {};

	newent.ext  = extension;
	newent.icon = idicon;
	newent.handler = handlerfun;

	table.insert(browser_ext, newent);
end

local function exthandler(path, base, ext)
	if (ext == nil) then
		return false;
	end

	local hfun = handlers[string.upper(ext)];
	if (hfun ~= nil) then
		hfun(path, base, ext);
		return true;
	end

	return false;
end


