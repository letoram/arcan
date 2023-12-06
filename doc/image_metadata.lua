-- image_metadata
-- @short: Set / update image contents metadata
-- @inargs: vid:tgt, string:model=drmv1, numtbl[8]:coords, number:mmin, number:mmax, number:cll, number:fll, string:eotf
-- @outargs: bool:ok
-- @longdescr:
-- HDR rendering, computer vision, compression and similar processes all can
-- benefit about added information about what the pixels represents or other
-- kind of contextual detail such as motion vectors.
--
-- This function is used to attach/update/define a metadata model for the
-- target vid. The currently support model is "drmv1" used for HDR scanout
-- if the *tgt* is mapped to a display supporting it, the metadata will be
-- be forwarded to that screen accordingly.
--
-- The arguments for *model=drmv1* are 8 coordinates for red, green, blue
-- chromacities and whitepoint. These coordinates will be clamped to range from
-- 0 to 1.3107.
--
-- *mmin* sets the master minimum luminance, in cd/m2 from 1 to 65535.
-- *mmax* sets the master max luminance, in cd/m2 from 1 to 65535.
-- *cll* sets the max content light level and *fll* the frame average light
-- level, both in cd/m2 from 1 to 65535.
--
-- The *eotf* (electro-optical transfer function) should be one out of 'sdr'
-- (sRGB), 'hdr' (linear), 'pq' or 'hlg' and corresponds to the CTA-861-G.
--
-- @group: image
-- @cfunction: imagemetadata
-- @flags: debugbuild
function main()
#ifdef MAIN
#endif
end
