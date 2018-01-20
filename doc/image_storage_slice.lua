-- image_storage_slice
-- @short:
-- @inargs: vid:store int:type vidtbl:slices
-- @outargs: true or false
-- @longdescr: Some rendering effects require specialised storage
-- layouts that we refer to as 'sliced', from the fact  that they
-- represent slices of some geometry. Typical such layouts are
-- 'cubemaps' (SLICE_CUBEMAP) and '3D' textures (SLICE_3D).
-- This is not normally supported by the engine, but the backing store
-- of a video object can irreversibly be converted to such storage formats
-- with the use of this function. The function returns true if the backing
-- store was successfully converted. This property will then carry through
-- when using ref:image_sharestorage. Calling the function multiple times
-- with the same input set will update the slices that has a more recent
-- upload timestamp than the previous slice in the corresponding slot.
-- The performance characteristics of this function also vary with the
-- underlying hardware platform, the source format of the individual
-- slices and the GPU affinity of the individual slices. The default and
-- typically worst case requires a full GPU->CPU->GPU synchronous transfer
-- and is thus not suitable for high rate updates.
-- @note: the number of slices and the current backing store of *store*
-- should have a power-of-two base width (height will be ignored).
-- @group: image
-- @cfunction: slicestore
-- @related:
function main()
#ifdef MAIN
	local surf = alloc_surface(32, 32)
	local c1 = fill_surface(32, 32, 255, 0, 0)
	local c2 = fill_surface(32, 32, 255, 255, 0)
	local c3 = fill_surface(32, 32, 255, 0, 255)
	local c4 = fill_surface(32, 32, 255, 255, 255)
	local c5 = fill_surface(32, 32, 0, 255, 0)
	local c6 = fill_surface(32, 32, 0, 0, 255)
	image_storage_slice(surf, SLICE_CUBEMAP, {c1,c2,c3,c4,c5,c6})
#endif

#ifdef ERROR1
#endif
end
