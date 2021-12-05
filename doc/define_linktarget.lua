-- define_linktarget
-- @short: Create a linked offscreen rendering pipe
-- @inargs: vid:dst, vid:link
-- @inargs: vid:dst, vid:link, int:scale
-- @inargs: vid:dst, vid:link, int:scale, int:rate
-- @inargs: vid:dst, vid:link, int:scale, int:rate, int:format
-- @outargs: bool:status
-- @longdescr: Rendertargets and related functions (calctargets, recordtargets etc.)
-- all have their own attachment pipelines with the vids that are part of the related
-- renderpass. They have the restriction that there is only one object that is allowed
-- to be tagged as the camera or view for that rendertarget. This resulted in a lot of
-- manual management to be able to process the same set of objects with different view
-- and storage parameters since either two identical sets needed to be managed, leading
-- to a high vid allocation count with all the adverse performance considerations that
-- follows. This function creates a rendertarget that renders into *dst* just like
-- ref:define_rendertarget, but the pipeline is combined with *link*.
-- This setup may also prompt the engine to process linked rendertargets in
-- parallel, making it a more efficient solution for certain 3D effects.
-- @note: if *dst* already is a rendertarget its link target will be updated and the
-- original pipeline in *dst* will be kept.
-- @note: the densities of objects respect their primary attachment
-- @note: passing a vid that is not a qualified rendertarget as *link* is a terminal
-- state transition.
-- @note: if *link* is deleted, *dst* reverts into a normal rendertarget.
-- @note: creating cycles by chaining linktargets together will go through, but the
-- processing will be stopped when the first cycle reference is found.
-- @group: targetcontrol
-- @cfunction: linkset
-- @related: define_rendertarget
function main()
#ifdef MAIN
	local halfw = math.floor(VRESW * 0.5);
	local mt = alloc_surface(halfw, VRESH);
	local link = alloc_surface(halfw, VRESH);
	move_image(link, halfw, 0);
	show_image({mt, link});

-- create example surfaces and bind to rendertarget
	local a = fill_surface(64, 64, 255, 0, 0);
	local b = fill_surface(64, 64, 0, 255, 0);
	local c = fill_surface(64, 64, 0, 0, 255);
	define_rendertarget(mt, {a,b,c}, RENDERTARGET_DETACH);

-- update the linktarget at a lower rate than the parent
	define_linktarget(link, mt,  RENDERTARGET_NOSCALE, a, 2);

-- set up some nonsens animation
	move_image(a, halfw - 64, VRESH - 64, 100);
	move_image(a, 0, 0, 100);
	move_image(b, halfw - 64, 0, 100);
	move_image(b, 0, 0, 100);
	move_image(c, 0, VRESW - 64, 100);
	move_image(c, 0, 0, 100);
	image_transform_cycle(a, true);
	image_transform_cycle(b, true);
	image_transform_cycle(c, true);

	show_image({a, b, c});
#endif

#ifdef ERROR1
	define_linktarget(a, WORLDID);
#endif
end
