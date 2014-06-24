-- provided with a gametable, try to populate a result-table with all kinds of resources
-- that may be used (e.g. snapshot, video, marquee, model, artwork, bezel,
-- music, sample, ...)
--
-- Paths used (first tries path\target\setname.extension and thereafter path\setname.extension if there's no match)
-- (2D graphics)
--  screenshots
--  backdrops
--  bezels
--  marquees
--  cabinet
--  overlays
--  artwork (* special, accepts anything that matches setname_wildcard.extension)
--
-- (Audio)
--  music (.ogg, .mp3)
--  sfx (.wav)
--
-- (Video extensions: .webm, .mpg, .avi, .mp4, .mkv)
--  movies
--
-- (misc)
-- gamescripts has a gamescripts/setname/setname.lua
-- (models have not yet been included here, refer to 3dsupport.lua still)

-- iterate the result from a glob_resource resultset, put those that match extension into
-- dsttable under 'key'.

-- reindex the result of a resource_glob to be a bitmap
local function glob(path)
	local lut = glob_resource(path);
	local restbl = {};

	for ind, val in ipairs(lut) do
		restbl[val] = true;
	end

	return restbl;
end

-- take a bitmap table (globres)
-- look for (basename.{extensions}) add first result to globres as
-- basepath .. basename . .. extension as a subtable defined by 'key'
local function filter_ext(globres, basename, basepath, dsttable, extensions, key )
	if (basename == nil) then return; end
	if (dsttable[key] == nil) then dsttable[key] = {}; end

	for ind, val in ipairs(extensions) do
		if (globres[ basename .. "." .. val ] == true) then
			table.insert(dsttable[key], basepath .. basename .. "." .. val);
			return true;
		end

	end

	return false;
end

-- simple indirection to glob, keep a cache of previous glob results
local function synch_cache(pathkey)
	if (resourcefinder_cache == nil) then resourcefinder_cache = {}; end

	local pathtbl = resourcefinder_cache[pathkey];
	if (pathtbl == nil or resourcefinder_cache.invalidate) then
		pathtbl = glob(pathkey .. "*");
		resourcefinder_cache[pathkey] = pathtbl;
	end

	return pathtbl;
end

local function resourcefinder_video(game, restbl, cache_results)
	local vidext  = {"mkv", "webm", "mp4", "mpg", "avi"};
	local tgtpath = "movies/" .. game.target .. "/";
	local mvpath  = "movies/";

	local tgttbl = cache_results and synch_cache(tgtpath) or glob(tgtpath .. game.setname .. ".*");

	if (not filter_ext(tgttbl, game.setname, tgtpath, restbl, vidext, "movies")) then
		tgttbl = cache_results and synch_cache(mvpath) or glob(mvpath .. game.setname .. ".*");
		filter_ext(tgttbl, game.setname, mvpath, restbl, vidext, "movies");
	end

	return restbl;
end

local function resourcefinder_audio(game, restbl, cache_results)
	local audext = {"ogg", "mp3", "wav"};
	local worktbl = {"music", "sfx"};

	for ind, val in ipairs(worktbl) do
		local tgtpath = val .. "/" .. game.target .. "/";
		local grppath = val .. "/";

		local tgttbl = cache_results and synch_cache(tgtpath) or glob(tgtpath .. game.setname .. ".*");
		if ( not filter_ext(tgttbl, game.setname, tgtpath, restbl, audext, val)) then
			tgttbl = cache_results and synch_cache(grppath) or glob(grppath .. game.setname .. ".*");
			filter_ext(tgttbl, game.setname, grppath, restbl, audext, val);
		end
	end

	return restbl;
end

local function resourcefinder_graphics(game, restbl, cache_results)
-- the order is important here, as the first match will be added and only that
	local imgext = {"png", "jpg"};

-- paths to scan, although all results will be inserted, the find functions set up in the table
-- will take the first result matched
	paths = {};
	table.insert(paths, "/" .. game.target .."/");
	table.insert(paths, "/");

	worktbl = {"screenshots", "bezels", "marquees", "controlpanels", "backdrops", "overlays", "cabinets", "boxart"};

	for pind, path in ipairs(paths) do
		for ind, val in ipairs(worktbl) do
			local grppath = val .. path;
			local tgttbl = cache_results and synch_cache(grppath) or glob(grppath .. game.setname .. "*.*");
			filter_ext(tgttbl, game.setname, grppath, restbl, imgext, val);
			filter_ext(tgttbl, game.setname .. "_thumb", grppath, restbl, imgext, val);

			if (val == "boxart") then
				filter_ext(tgttbl, game.setname .. "_back", grppath, restbl, imgext, val)
				filter_ext(tgttbl, game.setname .. "_back_thumb", grppath, restbl, imgext, val);
			end
		end
	end

-- special hack just for screenshots taken by the screenshot function in gridle() and other themes
	local ss = "screenshots/" .. game.target .. "_" .. game.setname .. ".png";
	if (resource(ss)) then
		table.insert(restbl.screenshots, ss);
	end

	return restbl;
end

function resourcefinder_misc( game, restbl, cache_results )
	local fulln = "gamescripts/" .. game.setname .. "/" .. game.setname .. ".lua";

	if (cache_results) then
		tbl = synch_cache("gamescripts/");
		if (tbl[game.setname .. "/"]) then
			restbl.gamescript = fulln;
		end
	else
		if (resource(fulln)) then
			restbl.gamescript = fulln;
		else
			restbl.gamescript = nil;
		end
	end

end

function resourcefinder_search( gametable, cache_results )
	local restbl = {};

	if (gametable ~= nil) then
		resourcefinder_graphics(gametable, restbl, cache_results );
		resourcefinder_audio(gametable, restbl, cache_results );
		resourcefinder_video(gametable, restbl, cache_results );
		resourcefinder_misc(gametable, restbl, cache_results );
	end

-- the filter is used for a preferred filter, on no match, it still
-- will return whatever is there
	restbl.find_identity_image = function(self, filter)
		local res = self:find_boxart(true, filter);
		if (res == nil) then
			res = self:find_screenshot(filter);
		end
		return res;
	end

	restbl.find_boxart = function(self, front, thumb)
		if (self.boxart and #self.boxart > 0) then
			local filter = front and "" or "_back";

			if (type(front) == "string") then
				filter = front;
			else
				if (thumb) then
					filter = filter .. "_thumb";
				end
				filter = filter .. "[.](%a+)$";
			end

			for ind, val in ipairs(self.boxart) do
				if (string.match(val, filter)) then
					return val;
				end
			end

		end
	end

-- ugly and used often so hide 'em ;-)
	restbl.find_screenshot = function(self)
		if (self.screenshots and #self.screenshots > 0) then
			return self.screenshots[math.random(1, #self.screenshots)];
		end
	end

	restbl.find_movie = function(self)
		if (self.movies and #self.movies > 0) then
			return self.movies[1];
		end
	end

	return restbl;
end
