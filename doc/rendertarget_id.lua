-- rendertarget_id
-- @short: Assign a numeric identifier to a rendertarget
-- @inargs: vid:rtgt
-- @inargs: vid:rtgt, int:id
-- @outargs: id or nil
-- @longdescr: This function is intended to be used for the rendering
-- cases where a shader need to distinguish between the destination
-- rendertarget, e.g. the case when stereoscopically rendering a
-- side-by-side packed textured source without manually managing multiple
-- pipelines.
-- To do this, create two rendertargets, one via ref:define_rendertarget
-- and the other via ref:define_linktarget. Give each a unique identifier
-- with the help of this function, and then write your shader so that it
-- does this distinction via the builtin int uniform rtgt_id.
-- The two forms of this function is simply one that retrieves the current
-- identifier, and another that updates. If the vid specified with *rtgt*
-- does not exist, nil will be returned.
-- @group: targetcontrol
-- @cfunction: rendertargetid
-- @related:
function main()
#ifdef MAIN
#endif

#ifdef ERROR1
#endif
end
