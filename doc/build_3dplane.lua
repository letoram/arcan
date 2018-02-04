-- build_3dplane
-- @short: Build a model comprised of a tesselated plane.
-- @inargs: float:min_s, float:min_t, float:max_s, float:max_t, float:base, float:step_s, float:step_t
-- @inargs: float:min_s, float:min_t, float:max_s, float:max_t, float:base, float:step_s, float:step_t, int:nmaps=1
-- @inargs: float:min_s, float:min_t, float:max_s, float:max_t, float:base, float:step_s, float:step_t, int:nmaps, bool:vert=false
-- @outargs: VID or BADID
-- @longdescr: This function builds a tesselated plane mesh and attaches to a 3D
-- model that gets marked as completed and consumes *nmaps* texture slots from
-- the frameset of the model. Depending on if *vert* is set or not, the
-- plane will either be horizontal or vertical. If the plane is horizontal,
-- the vertices will range from (xyz) min_s,base,min_t to max_s,base,max_t with
-- step_s and step_t controlling the step size (must be smaller than the max-min for each axis).
-- If *vert* is set, the vertices will range from (xyz) min_s,min_t,base to max_s,max_t,base.
-- @group: 3d
-- @cfunction: buildplane
-- @flags:
function main()
#ifdef MAIN
#endif
end
