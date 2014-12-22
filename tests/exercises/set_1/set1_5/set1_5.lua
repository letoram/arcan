--
-- Chose a more complex solution here on purpose to
-- showcase some Lua techniques.
--

function set1_5()
		local args = {};

-- overkill to save on typing, function generates a random size/color
		local rf = function(i)
			return string.format([[\ffonts/default.ttf,%d\#%.2x%.2x%.2x]],
				 10 + math.random(20), math.random(255),
					math.random(255), math.random(255));
		end

		local tbl = {};
		local msg = "Hello World";

-- cheaper than the concat operator
		for i = 1, string.len(msg) do
			table.insert(tbl, string.format("%s%s", rf(i), string.sub(msg, i,i)));
		end

		local img = render_text(table.concat(tbl, ""));
		local props = image_surface_properties(img);

		show_image(img);
		move_image(img, 0.5 * (VRESW - props.width), 0.5 * (VRESH - props.height));
end
