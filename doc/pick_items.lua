-- pick_items
-- @short: return a list of *limit* (default, 8) objects whose bounding
-- region overlap x,y in screen space.
-- @inargs: x, y, *limit*, *reverse*, *rtgt*
-- @outargs: res_table
-- @longdescr: pick_items can be used as a crude interface to implement
-- collision detection and response. The default behavior is to sweep the
-- pipeline based on the order value from lowest to highest, stopping after
-- *limit* objects have been found. If *reverse* is set to a !0 value, the scan
-- will instead start from the highest to the lowest order.
-- The optional *rtgt* argument specifies the rendertarget that should be
-- searched, with WORLDID being the default.
-- The return value will be an integer indexed table of 0..limit VIDs.
-- @note: by default, all VIDs are eligible for picking, this behavior can be
-- controlled with image_mask_set(vid, MASK_UNPICKABLE). This mask value is not
-- inherited.
-- @note: this function ignores clipping, alpha values and will only return
-- objects marked as visible by having an opacity value larger than an epsilon
-- lower limit.
-- @note: the cost for calling pick_items vary with the complexity of the
-- object in the scene, and increase noticeably with the progression (2D-
-- object) -> (x,y rotated 2D object) -> (x,y,z rotated 2D object / 3D object).
-- @note: unspecified limit defaults to 8, a limit larger than 64
-- elements is a terminal state transition.
-- @note: the behavior of pick_items is undefined if an object uses a
-- non-rectangular representation (e.g. custom defined 2D surface or
-- transformed with a vertex shader.
-- @group: image
-- @cfunction: pick
-- @flags:
function main()
#ifdef MAIN
#endif
end
