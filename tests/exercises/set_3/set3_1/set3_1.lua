function set3_1()
end

function dump_table(inp, out, indent)
	for k,v in pairs(inp) do
		if (type(v) == "table") then
			table.insert(out, string.format("%s%s:", indent, k, v));
			dump_table(v, out, indent .. "\t");
		else
			table.insert(out, string.format(
				"%s%s=%s", indent, k, string.gsub(tostring(v), "\\", "\\\\")));
		end
	end
end

function set3_1_input(iotbl)
	local tbl = {};
	dump_table(iotbl, tbl, "\t");
	print(table.concat(tbl, "\n"))
	print("--------");

	if (valid_vid(last_msg)) then
		delete_image(last_msg);
	end

	last_msg = render_text([[\ffonts/default.ttf,18 ]] ..
		table.concat(tbl, "\\r\\n"));
	if (valid_vid(last_msg)) then
		show_image(last_msg);
	end
end
