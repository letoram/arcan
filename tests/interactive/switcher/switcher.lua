function switcher()
	symtable = system_load("builtin/keyboard.lua")();

	list = glob_resource("*", SYS_APPL_RESOURCE);
	a = render_text( [[\ffonts/default.ttf,18 ]] .. table.concat(list, [[\n\r]]) )
	show_image(a);
end

function switcher_input(iotbl)
	if (iotbl.translated) then
		local key = symtable.tolabel(iotbl.keysym)
		local num = tonumber(key)
		if (num and list[num]) then
			pop_video_context()
			system_collapse(list[num])
		end
	end
end
