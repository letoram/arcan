--
-- Simple hook-script for allowing external input drivers
--
-- The default connection-point name is extio_1, extio_2 and
-- so on. In order to activate additional ones,
--
local connpoint_handler

local function open_connpoint(prefix, ind)
-- keep an external counter so that multiple -Hexternal_input can
-- cooperate and create extio_1, extio_2 etc.
	if not ind then
		ind = _G["_external_input_index"]
		_G["_external_input_index"] = _G["_external_input_index"] + 1
	end

	local key = prefix .. "_" .. tonumber(ind);
	local vid = target_alloc(key,
	function(source, status, iotbl)
		if status.kind == "terminated" then
			delete_image(source)
			open_connpoint(prefix, ind)
		elseif status.kind == "input" then
			local fun = _G[APPLID .. "_input"]
			if (fun) then
				fun(iotbl)
			end
		end
	end
	)

	if not valid_vid(vid) then
		warning("builtin/external_input: could not open '" .. key .. "'")
	end
end

if not _G["_external_input_index"] then
	_G["_external_input_index"] = 1
end

-- allow some database control over what the name of the connection
-- point would become, and a fallback default if that is not present
local prefix = get_key("ext_io");
if not prefix then
	prefix = "extio"
end

open_connpoint(prefix)
