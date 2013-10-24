-- camtag_model
-- @short: Set VID as perspective and (possible) recipient of the main 3D pipeline. 
-- @inargs: dstvid, *tagid 
-- @outargs: 
-- @longdescr: The 3D pipeline always has a main camera (tag 0), but several other ones can be defined (e.g. shadow casters, projectors, reflections, ...) and then needs a container object for intermediate storage, generation of transform matrices etc. This function allows you to tag an arbitrary VID as such a source.
-- @group: 3d 
-- @cfunction: arcan_lua_camtag
-- @related: define_3dview
-- @flags: 
function main()
#ifdef MAIN
	vid = fill_surface(4, 4, 0, 0, 0);
	camtag_model(vid, 0);
#endif
end
