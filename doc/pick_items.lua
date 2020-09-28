-- pick_items
-- @short: Pick a number of objects based on a screen-space coordinate.
-- @inargs: number:x, number:y
-- @inargs: number:x, number:y, number:limit=8
-- @inargs: number:x, number:y, number:limit=8
-- @inargs: number:x, number:y, number:limit=8<=64, bool:reverse=false
-- @inargs: number:x, number:y, number:limit=8<=64, bool:reverse=false, vid:rtgt=WORLDID
-- @outargs: vidtbl:results
-- @longdescr: pick_items is a low level function for building user-interface
-- related picking tools. It takes a screen- or rendertarget- space coordinate
-- and sweeps through the pipeline based on their render order (see ref:order_image).
-- If *reverse* is provided it will sweep from high to low, otherwise from low to high.
-- It will early out once *limit* objects have been found.
-- It will always return an integer indexed table of zero to *limit* number of
-- VIDs. Limit is not allowed to exceed 64.
-- @note: All VIDs start out as eligible for picking. This can be controlled by
-- setting the MASK_UNPICKABLE mask, see ref:image_mask_set. This mask value is
-- not inherited by default through linking. This means it needs to be set for
-- each new object regardless of how ref:link_image is being used.
-- @note: Clipping and alpha channel is ignored and will need to be considered
-- manually by testing against any possible clipping parents.
-- @note: This function can be very costly based on the complexity of the scene
-- and some caching mechanism should be used if a high number of calls is expected,
-- for instance when tied to a touch or mouse- input device event handler.
-- @note: The cost progression is roughly (low to high) normal, rotated, linked,
-- 3d object, rotated-linked, rotated-linked-3d object.
-- @note: If an object is shader displayed or manually manipulated by skewing
-- vertices through ref:image_tesselation or a vertex stage shader, the picking
-- operation result is undefined.
-- @group: image
-- @related: image_hit
-- @cfunction: pick
-- @flags:
function main()
#ifdef MAIN
#endif
end
