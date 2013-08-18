/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 */

#ifndef _HAVE_ARCAN_3DBASE
#define _HAVE_ARCAN_3DBASE

/* Loads a compressed triangle mesh and wrap it around a 
 video object */
void arcan_3d_setdefaults();

/* the camtag (0) is always available, that's the default view that will 
 * be rasterized, more can be defined for lights, shadows, etc.
 * by associating the camtag with a vobj parent, it will use that for 
 * resolving/interpolating position/orientation */
arcan_errc arcan_3d_camtag_parent(unsigned camtag, arcan_vobj_id parent);
arcan_vobj_id arcan_3d_buildplane(float minx, float minz, float maxx, 
	float maxz, float y, float wdens, float ddens, unsigned nmaps);
arcan_vobj_id arcan_3d_buildbox(point min, point max, unsigned nmaps);

arcan_errc arcan_3d_swizzlemodel(arcan_vobj_id model);

/* empty model allocates and populates a container,
 * then add a hierarchy of meshes to the model */
arcan_vobj_id arcan_3d_emptymodel();
arcan_errc arcan_3d_meshshader(arcan_vobj_id dst, 
	arcan_shader_id shid, unsigned slot);
arcan_errc arcan_3d_addmesh(arcan_vobj_id dst, 
	data_source resource, unsigned nmaps);

/* destructive transform,
 * apply the specified roll / pitch / yaw transform to all 
 * the vertices of the model */
arcan_errc arcan_3d_baseorient(arcan_vobj_id dst, 
	float roll, float pitch, float yaw);

/* scans through the specified model and all its' meshes,
 * rebuild the bounding volume and using that, maps all vertex values
 * into the -1..1 range */
arcan_errc arcan_3d_scalevertices(arcan_vobj_id vid);

#endif
