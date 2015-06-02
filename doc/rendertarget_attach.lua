-- rendertarget_attach
-- @short: Modify the attachment statement of a video object
-- @inargs: rendertarget, source, detach_state
-- @longdescr: Every video object has at least one (primary), but possibly
-- many (secondary) connections to different rendertargets. The primary
-- connection also defines lifespan, meaning that if the object which act
-- as a primary connection is deleted, so are any other objects that are
-- attached to it. This association can be changed either when creating
-- new rendertargets or dynamically using this function.
--
-- *rendertarget* specifies the attachment point, *source*
-- refers to the object that should be attached or detached and *detach_state*
-- determines if the primary attachment should be reassigned (RENDERTARGET_DETACH)
-- or kept (RENDERTARGET_NODETACH). Only WORLDID or a vid that has been
-- previously flagged as a rendertarget (using ref:define_rendertarget or
-- ref:define_calctarget or ref:define_recordtarget) are valid values for
-- *rendertraget*.
--
-- @note: Relative properties (scale, position etc.) are all defined against
-- the current primary rendertarget and are not recalculated on attach/detach
-- operations. The common pattern to handle objects that should have the same
-- storage but live inside different rendertargets is to use ref:null_surface
-- to create a new container, ref:image_sharestorage to make sure source and
-- new object has the same backing store and then finally
-- ref:rendertarget_attach the new object with RENDERTARGET_DETACH.
--
-- @note: Deleting an object also implies detaching it from all rendertargets.
-- @note: A rendertarget cannot be attached to itself.
-- @note: Objects that have been flagged as persistant cannot be part of
-- other rendertargets.
-- @group: targetcontrol
-- @cfunction: renderattach
-- @related: define_rendertarget, define_recordtarget, define_calctarget

function main()
	local rtgt = alloc_surface(VRESW, VRESH);
	resize_image(rtgt, 200, 200);
	local obj_a = color_surface(32, 32, 0, 255, 0);
	show_image({rtgt, obj_a});
	define_rendertarget(rtgt, {obj_a});

#ifdef MAIN
	local new_obj = color_surface(64, 64, 255, 0, 0);
	show_image(new_obj);
	move_image(new_obj, VRESW * 0.5, VRESH * 0.5);
	rendertarget_attach(rtgt, new_obj, RENDERTARGET_NODETACH);
#endif

#ifdef ERROR1
	local new_obj = color_surface(64, 64, 255, 0, 0);
	show_image(new_obj);
	move_image(new_obj, VRESW * 0.5, VRESH * 0.5);
	rendertarget_attach(rtgt, new_obj, "qumquat");
#endif
end
