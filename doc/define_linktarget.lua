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
-- ref:define_rendertarget, but the the pipeline is forcibly tied to *link*.
-- This setup may also prompt the engine to process linked rendertargets in
-- parallel, making it a more efficient solution for certain 3D effects.
-- @note: deleting the rendertarget referenced by *link* will also delete the the
-- object referenced by *dst*.
-- @note: since the attachement is shared, the targeted density (hppcm, vppcm) is
-- always forced to that of the *link* rendertarget.
-- @note: passing a vid that is not a qualified rendertarget as *link* is a terminal
-- state transition.
-- @note: if *link* is deleted, *dst* turns into a normal rendertarget.
-- @note: any attach or detach operations that are used with the new linktarget as
-- destination will be FORWARDED to the *link*.
-- @note: trying to link to a another linktarget will forward to its target.
-- @group: targetcontrol
-- @cfunction: linkset
-- @related: define_rendertarget
function main()
#ifdef MAIN
	local a = alloc_surface(640, 480);

#endif

#ifdef ERROR1
	define_linktarget(a, WORLDID);
#endif
end
