-- rendertarget_noclear
-- @short: Enable / Disable clearing a rendertarget before a renderpass.
-- @inargs: vid, noclear
-- @outargs: success
-- @longdescr: By default, each pass for a rendertarget begins by clearing
-- the buffer that will be drawn to. This may waste memory
-- bandwidth if we know that the entire rendertarget will be populated
-- with the objects that are to be drawn. rendertarget_noclear is used to
-- change this behavior by setting a true value to a vid that is connected
-- to a rendertarget.
-- @note: Setting WORLDID as vid will change the clear behavior for the
-- standard output rendertarget.
-- @note: If the background is not actually covered by valid VIDs, you
-- will leave trails of previous frames behind, as in the MAIN
-- example below.
-- @group: targetcontrol
-- @cfunction: rendernoclear
function main()
#ifdef MAIN
	rendertarget_noclear(WORLDID, true);
	a = color_surface(64, 64, 255, 0, 0, 0);
	show_image(a);
	move_image(a, 128, 128, 10);
#endif

#ifdef ERROR
	rendertarget_noclear(BADID, "potatoe");
#endif
end
