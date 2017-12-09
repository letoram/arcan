-- define_rendertarget
-- @short: Create an offscreen rendering pipe
-- @inargs: vid:dst, t_vid:vtbl
-- @inargs: vid:dst, t_vid:vtbl, int:detach
-- @inargs: vid:dst, t_vid:vtbl, int:detach, int:scale
-- @inargs: vid:dst, t_vid:vtbl, int:detach, int:scale, int:rate
-- @inargs: vid:dst, t_vid:vtbl, int:detach, int:scale, int:rate, int:format
-- @inargs: vid:dst, t_vid:vtbl, int:detach, int:scale,
--                               int:rate, int:format, float:hppcm, float:vppcm
-- @outargs: bool:status
-- @longdescr: This function creates a separate rendering pipeline
-- that sends its output to the storage of another vid- connected
-- object. The preconditions is that the *dst* is not part
-- of the integer-indexed *vtbl* and that it has a textured
-- backing store. ref:alloc_surface is a particularly good function
-- for creating a surface that can be used as a valid *dst*.
-- This is an expensive yet powerful function that is the basis
-- for many advanced effects, but also for offscreen composition and
-- both synchronous and asynchronous GPU->CPU transfers.
--
-- The optional *detach* argument can be set to either RENDERTARGET_DETACH
-- or RENDERTARGET_NODETACH, and the default is RENDERTARGET_DETACH.
-- For RENDERTARGET_DETACH, all members of *vtbl* are disconnected from
-- the main pipeline and only used when updating *dst*, while their
-- association is kept in RENDERTARGET_NODETACH.
--
-- The optional *scale* argument determine how the various output-relative
-- properties e.g. object size should be handled in the case that *dst*
-- does not have the same dimensions as the current canvas. The default is
-- RENDERTARGET_NOSCALE where the object would simply be clipped if its final
-- positions fall outside the dimensions of the *dst*.
-- For RENDERTARGET_SCALE, a scale transform that maps coordinates in the
-- current canvas dimensions to those of the *dst*.
--
-- The optional *rate* argument determine how often the rendertarget
-- should be updated. A value of 0 disables automatic updates and
-- rendertarget_forceupdate needs to be called manually whenever the
-- rendertarget is to be updated. A value of INT_MIN < n < 0 means that the
-- rendertarget should only be updated every n video frames, and a value of
-- INT_MAX > n > 0 means that the contents should be updated very n logic
-- ticks. Default is -1 (every frame).
--
-- The optional *format* defines additional flags for the backing store of
-- *dst*. Possible values are RENDERTARGET_COLOR (default),
-- RENDERTARGET_DEPTH, RENDERTARGET_FULL and the additional bitfields
-- RENDERTARGET_MULTISAMPLE and RENDERTARGET_ALPHA.
-- The difference between COLOR and FULL is that a stencil buffer (for certain
-- clipping operations) is not always present in COLOR. DEPTH is a special case
-- primarily used when only the contents of the depth buffer is to be used.
-- This operation converts the backing store from having a textured backing to
-- a DEPTH one and makes a lot of other operations invalid. Its primary purpose
-- is depth-buffer based 3D effects (e.g. shadow mapping). Note that you can
-- control the format of the output through ref:alloc_surface.
--
-- MULTISAMPLE is a bitflag that can be set (bit.bor) for when you need higher
-- quality rendering/anti-aliasing and comes at a high cost when the
-- rendertarget is updated both from the process itself and from an additional
-- internal sampling of the multisample buffer into the datastore pointed to
-- by *dst*. It is also likely to break if you are running on weak/old hardware
-- on a GLES2 level of acceleration.
--
-- ALPHA is another bitflag that can be set in order for the alpha channel
-- contents to be kept rather than resolved.
--
-- @note: Using the same object or backing store for *dst* and as
-- a member of *vtbl* results in undefined contents in *dst*.
-- @note: RENDERTARGET_SCALE transform factors are not updated when/if the
-- default canvas is resized.
-- @note: WORLDID can not be immediately used as part of the *vid table*, but
-- it is possible to use ref:image_sharestorage to a ref:null_surface and then
-- use that as part of *vid table*. The two caveats in that case is that the
-- contents of the ref:null_surface will have its Y axis inverted and if the
-- new rendertarget is visible in the WORLDID, the contents will quickly
-- converge to an undefined state from the resulting feedback loop.
-- @external: yes
-- @related: define_recordtarget, alloc_surface, define_calctarget,
-- rendertarget_forceupdate, rendertarget_noclear, rendertarget_attach, define_linktarget
--
function main()
#ifdef MAIN
	local a = color_surface(64, 64, 0, 255, 0);
	local rtgt = alloc_surface(320, 200);
	define_rendertarget(rtgt, {a});
	show_image({rtgt, a});
	move_image(rtgt, 100, 100, 100);
	move_image(rtgt, 0, 0, 100);
	image_transform_cycle(rtgt, true);
#endif
end
