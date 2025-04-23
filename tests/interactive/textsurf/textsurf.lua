function textsurf()
	surf = text_surface(25, 80, {})
	fill_surf(surf, 80, 25)
	show_image(surf)
end

function fill_surf(vid, w, h)
	local tbl = {}
	local set = "abcdefghijklmnopqrstuvwxyz"
	local ind = 1

	for y=1,h do
		local crow = {}
		for x=1,w do
			table.insert(crow, string.sub(set, ind, ind))
			ind = (ind % #set) + 1
		end
		table.insert(tbl, crow)
	end

	text_surface(h, w, vid, tbl)
	local props = image_storage_properties(vid)
	for k,v in pairs(props) do
		print(k, v)
	end
	resize_image(vid, props.width, props.height)
end

local count = 100
function textsurf_clock_pulse()
	count = count - 1
	if count == 0 then
		fill_surf(surf, math.random(1, 100), math.random(1, 100))
		count = 100
	end
end
