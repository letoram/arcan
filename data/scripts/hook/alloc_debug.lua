--
-- Expensive debugging script that intercepts all allocation functions,
-- attaches the backtrace as a tracetag to the image so that they are visible
-- in crash-logs even when no explicit tracetag has been set
--
system_load("builtin/debug.lua")()

local function hijack(sym)
	local old = _G[sym]

	_G[sym] =
	function(...)
		local res = {old(...)}

		if type(res[1]) == "number" and valid_vid(res[1]) then
			image_tracetag(res[1], sym .. ":" .. debug.traceback())
		end

		return unpack(res)
	end
end

for _, v in ipairs({
	"alloc_surface",
	"fill_surface",
	"color_surface",
	"null_surface",
	"random_surface",
	"raw_surface",
	"render_text",
	"target_alloc",
	"accept_target",
	"launch_avfeed",
	"launch_decode",
	"launch_target",
	"load_image",
	"net_listen",
	"load_image_asynch",
	"define_arcantarget",
	"define_calctarget",
	"define_feedtarget",
	"define_linktarget",
	"define_nulltarget",
	"define_recordtarget",
	"define_rendertarget",
	"new_3dmodel",
	"build_3dbox",
	"build_3dplane",
	"build_cylinder",
	"build_pointcloud",
	"build_sphere",
}) do
	hijack(v)
end
