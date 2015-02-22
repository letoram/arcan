-- define_feedtarget
-- @short: Create a direct copy association between two frameservers.
-- @inargs: dstvid, srcvid, cbfun
-- @outargs: subseg
-- @longdescr: In rare cases, the recordtarget approach for creating
-- output segments in connected frameservers is too expensive or complex.
-- The define_feedtarget function is intended for situations where
-- the input data from one frameserver should be copied exactly over
-- to another without the possible GPU roundtrip. As such, no shaders,
-- transformations or audio will carry over to the output.
-- For this to work, target_flags(srcvid, TARGET_VSTORE_SYNCH) should
-- also be toggled so there is a local data buffer to work with.
-- @note: define_feedtarget does not handle dynamic resizes inside the srcvid.
-- If source dimensions change, the subseg frameserver connection will be
-- terminated.
-- @note: This can also be used for debugging issues with recordtargets,
-- calctargets, streaming textures and graphics drivers as it creates a
-- synchronized copy that is treated separately from regular textures.
-- @group: targetcontrol
-- @cfunction: feedtarget
-- @related: target_flags
function main()
#ifdef MAIN
#endif

#ifdef ERROR1
#endif
end
