/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
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

void arcan_3d_movecamera(unsigned camtag, float px, float py, float pz, unsigned tv);
void arcan_3d_orientcamera(unsigned camtag, float roll, float pitch, float yaw, unsigned tv);
arcan_vobj_id arcan_3d_loadmodel(const char* resource);


#endif
