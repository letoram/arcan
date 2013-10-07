--
-- Simple LRU cache with a few hard coded paths for icons
-- desw and desh are just hints, they can be ignored if
-- our local icon storage doesn't maintain different versions
-- for different resolutions (or, forcibly downscale on load).
--
local spath_cache = {};

local function iconcache_checkpath(n)
	if (spath_cache[n] == nil) then
		local tmptbl = {};

		for i, v in ipairs(glob_resource(n)) do
			tmptbl[v] = true; 
		end
	
		spath_cache[n] = tmptbl;
	end

	return spath_cache[n];
end

local function iconcache_get(self, iconname)
	if (iconname == nil) then
		iconname = self.default.name;
	end

	for i,v in ipairs(self.icons) do
		if (v.name == iconname) then
			local tbl = table.remove(self.icons, i);
			table.insert(self.icons, 1, tbl);
			return tbl;
		end
	end

-- sweep searchpaths, look for matching name.png
	for i, v in ipairs(self.searchpaths) do
		local path = iconcache_checkpath(v .. "/*.png", v);
		local icnname = iconname .. ".png";

		if (path and path[icnname]) then
			local vid = load_image(v .. "/" .. icnname);

-- got something, add it and, if needed, 
-- delete the least recently used entry
			if (valid_vid(vid)) then
				if (#self.icons >= self.limit) then
					delete_image(self.icons[#self.icons].vid);
					table.remove(self.icons, #self.icons);
				end

				local tbl = {name = iconname, icon = vid};
				table.insert(self.icons, 1, tbl);
				return tbl;
			end
		end
	end

	return self.default;
end

local function iconcache_kill(self)
	for i,v in pairs(self.icons) do
		delete_image(v.icon);
	end

	self.icons = {};
end

function awb_iconcache(lim, paths, defv)
	return {
		searchpaths = paths,
		limit = lim,
		icons = {},
		default = {
			name = "default",
			icon = defv
		},
		get = iconcache_get,
		destroy = iconcache_kill
	};
end

