-- provided with a gametable, try to populate a result-table with all kinds of resources
-- that may be used (e.g. snapshot, video, marquee, model, artwork, bezel, 
-- music, sample, ...)
--
-- Paths used (first tries path\target\setname.extension and thereafter path\setname.extension if there's no match)
-- (2D graphics)
--  screenshots
--  bezels
--  marquees
--  cabinet
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

-- reindex the result of a resource_glob to be a bitmap
local function glob(path)
	local lut = glob_resource(path, SHARED_RESOURCE);
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
	if (pathtbl == nil) then
		pathtbl = glob(pathkey .. "*");
		resourcefinder_cache[pathkey] = pathtbl;
	end

	return pathtbl;
end

local function resourcefinder_video(game, restbl, cache_results)
	local vidext  = {"mkv", "mp4", "mpg", "avi"};
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
	local audext = {"ogg", "wav"};
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
	local imgext = {"png", "jpg"};
	
	worktbl = {"screenshots", "bezels", "marquees", "controlpanels", "overlays", "cabinets"};

	for ind, val in ipairs(worktbl) do
		local tgtpath = val .. "/" .. game.target .. "/";
		local grppath = val .. "/";

		local tgttbl = cache_results and synch_cache(tgtpath) or glob(tgtpath .. game.setname .. ".*");
		if (not filter_ext(tgttbl, game.setname, tgtpath, restbl, imgext, val)) then
			tgttbl = cache_results and synch_cache(grppath) or glob(grppath .. game.setname .. ".*");
			filter_ext(tgttbl, game.setname, grppath, restbl, imgext, val);
		end
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
	if (gametable == nil) then return nil; end
	local restbl = {};

	resourcefinder_graphics(gametable, restbl, cache_results );
	resourcefinder_audio(gametable, restbl, cache_results );
	resourcefinder_video(gametable, restbl, cache_results );
	resourcefinder_misc(gametable, restbl, cache_results );
	
	return restbl;
end
