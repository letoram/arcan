-- instance_image
-- @short: Create an instanced clone of the specified object.
-- @inargs: parentvid
-- @outargs: newvid
-- @longdescr: To re-use most properties at a somewhat cheaper cost (particularly
-- for 3D scenarions where instancing can be used for complex models), instances
-- or "clones" can be used. These share most of its properties with its parent 
-- (at the cost of some additional restrictions, see the notes below) 
-- 
-- @note: Clones will always be targeted for cascaded deletion if its parent is
-- deleted, no matter what mask has been set.
-- @note: Clones cannot be persisted.
-- @note: Clones of a frameserver won't contribute to tick / render requests.
-- @note: Clones cannot be linked to another object.
-- @note: Clones cannot be part of- or have- a frameset,
-- use null objects and share storage for that.
-- @note: Calling instance_image using a clone as parentvid, 
-- will force a lookup of the clone's parent, which in turn will be instanced.
-- @note: Currently, clones can have individual shaders etc. it is planned, however,
-- that nothing which will incurr a costly gl state flush will be allowed (so rendering
-- order, shader, etc. will all be linked to the parent). 
-- @group: image 
-- @cfunction: arcan_lua_instanceimage
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	show_image(a);
	move_image(a, 100, 100, 100);
	for i = 1, 10 do
		inst = instance_image(a);
		move_image(inst, math.random(20) - 10, math.random(20) - 10);
		show_image(inst);
	end
#endif
end
