-- image_tesselation
-- @short: alter the tesselation level of a vid
-- @inargs: vid, *s*, *t*, *func*
-- @outargs:
-- @longdescr: This function is used to convert a normal vid to a
-- pseudo-3D object in the sense that it becomes a tesselated quad
-- with *s* / w steps in one dimension, and *t* steps in the other.
-- The storage can be accessed through the optional *func* callback,
-- and has the signature of (reference, n_vertices, vertex_size)
-- where reference is a userdata table that supports:
--
--  :vertex(ind, *new_x*, *new_y*, *new_z*, *new_w) => x,y,z,w
--  for fetching and updating, with xyzw matching vertex_size
--  (=2, only xy, =3 only xyz).
--
--  :normals(ind, *new_x, new_y, new_z*) => x,y.z
--  for fetching, activating and updating nromals.
--
--  :colors(ind, *new_r, g, b, a*) => r,g,b,a
--  for fetching, activating and updating vertex colors.
--
--  :texco(ind, *new_s, new_t*) => s,t
--  for fetching and updating
--
--  :primitive_type(0 or 1) for switching between triangle soup (0)
--  or point-cloud (1) when rendering.
-- @group: image
-- @cfunction: imagetess
-- @related:
-- @flags: experimental
function main()
#ifdef MAIN
#endif

#ifdef ERROR1
#endif
end
