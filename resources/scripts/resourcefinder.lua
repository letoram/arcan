-- provided with a gametable, try to populate a result-table with all kinds of resources
-- that may be used (e.g. snapshot, video, marquee, model, artwork, bezel, 
-- music, sample, ...)
--
-- Paths used (first tries path\target\setname.extension and thereafter path\setname.extension if there's no match)
-- (2D graphics)
--  screenshots
--  bezels
--  marquees
--  artwork (* special, acceptes anything that matches setname_wildcard.extension)
--  
-- (Audio)
--  music (.ogg)
--  sfx (.wav)
--
-- (Video extensions: .mpg, .avi, .mp4, .mkv)
--  movies  
-- 
-- (misc)
-- gamescripts has a gamescripts/setname/setname.lua
-- (models have not yet been included here, refer to 3dsupport.lua still)

-- iterate the result from a glob_resource resultset, put those that match extension into
-- dsttable under 'key'.
local function filter_ext(globres, basepath, dsttable, extensions, key )
	if (dsttable[key] == nil) then dsttable[key] = {}; end
	local count = 0;
	
	for ind, val in ipairs(globres) do
		local extension = string.match(val, ".(%w+)$");
		if (extensions[extension] ~= nil) then
			table.insert(dsttable[key], basepath .. val);
			count = count + 1;
		end
	end
	
	return count;
end

local function synch_cache(setname, pathkey)
	if (resourcefinder_cache == nil) then resourcefinder_cache = {}; end

	local pathtbl = resourcefinder_cache[pathkey];
	if (pathtbl == nil) then
		pathtbl = glob_resource(pathkey .. "*", SHARED_RESOURCE);
		resourcefinder_cache[pathkey] = pathtbl;
	end
	
	return pathtbl;
end

local function resourcefinder_video(game, restbl, cache_results)
	local vidext  = {mpg = true, avi = true, mkv = true, mp4 = true};
	local tgtpath = "movies/" .. game.target .. "/";
	local mvpath  = "movies/";

	local tgttbl = cache_results and synch_cache(game.setname, tgtpath) or glob_resource(tgtpath .. game.setname .. ".*", SHARED_RESOURCE);
	if (filter_ext(tgttbl, tgtpath, restbl, vidext, "movies") == 0) then
		tgttbl = cache_results and synch_cache(game.setname, mvpath) or glob_resource(mvpath .. game.setname .. ".*", SHARED_RESOURCE);
		filter_ext(tgttbl, mvpath, restbl, vidext, "movies");
	end
		
	return restbl;
end

local function resourcefinder_audio(game, restbl, cache_results)
	local audext = {ogg = true, wav = true};
	local worktbl = {"music", "sfx"};
	
	for ind, val in ipairs(worktbl) do
		local tgtpath = val .. "/" .. game.target .. "/";
		local grppath = val .. "/";

		local tgttbl = cache_results and synch_cache(game.setname, tgtpath) or glob_resource(tgtpath .. game.setname .. ".*", SHARED_RESOURCE);
		if (filter_ext(tgttbl, tgtpath, restbl, audext, val) == 0) then
			tgttbl = cache_results and synch_cache(game.setname, grppath) or glob_resource(grppath .. game.setname .. ".*", SHARED_RESOURCE);
			filter_ext(tgttbl, grppath, restbl, audext, val);
		end
	end

	return restbl;
end

local function resourcefinder_graphics(game, restbl, cache_results)
	local imgext = {jpg = true, png = true};
	
	worktbl = {"screenshots", "bezels", "marquees", "controlpanels", "overlays", "artwork"};

	for ind, val in ipairs(worktbl) do
		local tgtpath = val .. "/" .. game.target .. "/";
		local grppath = val .. "/";

		local tgttbl = cache_results and synch_cache(game.setname, tgtpath) or glob_resource(tgtpath .. game.setname .. ".*", SHARED_RESOURCE);
		if (filter_ext(tgttbl, tgtpath, restbl, imgext, val) == 0) then
			tgttbl = cache_results and synch_cache(game.setname, grppath) or glob_resource(grppath .. game.setname .. ".*", SHARED_RESOURCE);
			filter_ext(tgttbl, grppath, restbl, imgext, val);
		end
	end
	
	return restbl;
end

function resourcefinder_misc( game, restbl, cache_results ) 
	if (resource("gamescripts/" .. game.target .. "/" .. game.setname .. "/" .. game.setname .. ".lua")) then
		restbl.gamescript = "gamescripts/" .. game.target .. "/" .. game.setname .. "/" .. game.setname .. ".lua";

	elseif (resource("gamescripts/" .. game.setname .. "/" .. game.setname .. ".lua")) then 
		restbl.gamescript = "gamescripts/" .. game.setname .. "/" .. game.setname .. ".lua";
	end
end

function resourcefinder_search( gametable, cache_results )
	if (gametable == nil) then return nil; end
	cache_results = false;
	local restbl = {};

	resourcefinder_graphics(gametable, restbl, cache_results );
	resourcefinder_audio(gametable, restbl, cache_results );
	resourcefinder_video(gametable, restbl, cache_results );
	resourcefinder_misc(gametable, restbl, cache_results );
	
	return restbl;
end
