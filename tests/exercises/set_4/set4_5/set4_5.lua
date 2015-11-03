function show_parents(me)
	print("showing parents of", image_tracetag(me));
	local parent = image_parent(me);

	while valid_vid(parent) do
		print("parent", parent, me, image_tracetag(parent));
		parent = image_parent(parent);
	end
end

function show_children(me)
	print("showing descendants to ", me);
	local desc = function(node, fun)
		local lst = image_children(node)
		if (lst == nil) then
			return;
		end

		for k,v in ipairs(lst) do
			print(image_tracetag(v));
			fun(v, fun);
		end
	end

	desc(me, desc);
end

function set4_5()
	local rbox = color_surface(200, 200, 255, 0, 0);
	local bbox = color_surface(200, 200, 0, 0, 255);
	local gbox = color_surface(200, 200, 0, 255, 0);

	link_image(rbox, bbox);
	link_image(bbox, gbox);

	image_tracetag(rbox, "red");
	image_tracetag(bbox, "blue");
	image_tracetag(gbox, "green");

	show_parents(rbox);
	show_children(gbox);
end
