function kbdtest()
	show_image(
		render_text([[\ffonts/default.ttf,18 KBDTest:
	\n\rF1 period(0), delay(0), F2 inc. period
	F3 dec. period, F4 inc. delay, F5 dec.delay]]));
	symtable = system_load("builtin/keyboard.lua")();
	last_event = 500;
	history = {};
	let = null_surface(1, 1);
	pertxt = null_surface(1, 1);
	himg = null_surface(1, 1);
	label = null_surface(1, 1);
	per, del = kbd_repeat(-1, -1);
	upd_period(per, del);
end

function upd_label()
	delete_image(label);
	label = render_text(string.format("shutdown in %d ticks", last_event));
	show_image(label);
	move_image(label, 0, 30);
end

function upd_list()
	local lines = {};
	for i,v in ipairs(history) do
		table.insert(lines, string.format("%d, %d, %d, %d, %s", v[1], v[2], v[3], v[4], v[5]));
	end

	delete_image(himg);
	himg = render_text(table.concat(lines, "\\n\\r"));
	show_image(himg);
	move_image(himg, 0, 70);
end

function upd_period()
	delete_image(pertxt);
	pertxt = render_text(string.format("period: %d, delay: %d", per, del));
	show_image(pertxt);
	local props = image_surface_properties(pertxt);
	move_image(pertxt, VRESW - props.width, VRESH - props.height);
end

function kbdtest_clock_pulse()
	last_event = last_event - 1;
	if (last_event == 0) then
		return shutdown("timed out");
	end
	delete_image(let);
	let = render_text("shutdown in " .. tostring(last_event));
	show_image(let);
	move_image(let, 0, VRESH - 20);
end

function kbdtest_input(inp)
	if (inp.translated and inp.active) then
		local label = symtable.tolabel(inp.keysym)
		last_event = 500;
		table.insert(history, {
			CLOCK, inp.devid, inp.subid, inp.keysym,
			label or ""
			}
		);
		if (#history > 10) then
			table.remove(history, 1);
		end
		upd_list();

		local uprd = function(da, db)
			per = per + da;
			del = del + db;
			kbd_repeat(per, del);
			upd_period();
		end

		if (label == "F1") then
			uprd(-per, -del);
		elseif (label == "F2") then
			uprd(20, 0);
		elseif (label == "F3") then
			uprd(-20, 0);
		elseif (label == "F4") then
			uprd(0, 20);
		elseif (label == "F5") then
			uprd(0, -20);
		end
	end
end
