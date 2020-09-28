local function case_1()
-- 1. 'shallow simple'
	local root = fill_surface(64, 64, 255, 0, 0)
	image_tracetag(root, "root_1")
	local child = fill_surface(64, 64, 0, 255, 0)
	image_tracetag(child, "child_1")
	link_image(child, root)
	move_image(child, 32, 32)
	image_clip_on(child, CLIP_SHALLOW)
	show_image({root, child})
end

local function case_2()
-- 2. 'rotate simple'
	local root2 = fill_surface(64, 64, 255, 0, 0)
	image_tracetag(root2, "root_2")
	local child2 = fill_surface(64, 64, 0, 255, 0)
	image_tracetag(child2, "child_2")
	move_image(root2, 100, 100)
	rotate_image(root2, 145, 100)
	link_image(child2, root2)
	move_image(child2, 32, 32)
	image_clip_on(child2, CLIP_SHALLOW)
	show_image({root2, child2})
end

local function case_3()
-- 3 'complex'
	local root3 = fill_surface(64, 64, 255, 0, 0)
	image_tracetag(root3, "root_3")
	local child2 = fill_surface(64, 64, 0, 0, 255)
	image_tracetag(child2, "child1_3")
	local child3 = fill_surface(64, 64, 0, 255, 0)
	image_tracetag(child3, "child2_3")
	move_image(root3, 200, 0)
	rotate_image(root3, 145, 100)
	link_image(child3, child2)
	link_image(child2, root3)
	move_image(child2, 16, 16)
	move_image(child3, 16, 16)

	image_clip_on(child2)
	image_clip_on(child3)
	show_image({root3, child2, child3})
end

local function case_4()
-- 4 'other clipping reference'
	local obja = fill_surface(64, 64, 255, 0, 0)
	image_tracetag(obja, "obj_a")
	local objb = fill_surface(64, 64, 0, 255, 0)
	image_tracetag(objb, "obj_b")
	show_image({obja, objb})
	move_image(obja, 300, 200)
	move_image(objb, 200, 200)
	move_image(obja, 200, 200, 100)
	move_image(objb, 300, 200, 100)
	move_image(obja, 300, 200, 100)
	move_image(objb, 200, 200, 100)
	image_transform_cycle(obja, true)
	image_transform_cycle(objb, true)
	image_clip_on(objb, CLIP_SHALLOW, obja)
end

function clip()
 case_1()
 case_2()
 case_3()
 case_4()
end
