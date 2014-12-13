-- orient3d_model
-- @short: Set the base orientation for the specified model.
-- @inargs: model, roll, pitch, yaw
-- @longdescr: While the active orientation of a model is dynamically changeable,
-- many models from external sources come with a different starting orientation.
-- Although it is possible to compensate for that, it may be easier to just rotate
-- the vertices once at a cost of O(n) in respect to the number of vertices in the model.
-- @group: 3d
-- @note: Since this operate on the vertex data itself, with a transformation that
-- can impose a loss of precision, it is not recommended that this is used more than
-- once for any model.
-- @related: rotate3d_model
-- @cfunction: orientmodel
function main()
#ifdef MAIN
	camera = null_surface(4, 4, 0, 0, 0);
	view = camtag_model(camera, 0);
	model = build_plane3d(-5.0, -5.0, 5.0, 5.0, -0.4, 1.0, 1.0, 0);
	show_image(model);

	orient3d_model(model, 10, 5, 2);
#endif
end
