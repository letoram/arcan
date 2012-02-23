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

#ifndef _HAVE_ARCAN_SHADERMGMT
#define _HAVE_ARCAN_SHADERMGMT

enum shdrutype {
	shdrbool  = 0,
	shdrint   = 1,
	shdrfloat = 2,
	shdrvec2  = 3,
	shdrvec3  = 4,
	shdrvec4  = 5,
	shdrmat4x4 = 6
};

/* all the currently supported value slots,
 * type- encoded in name, the 'n' prefix used
 * means it supports multiple slots for that type */ 
enum arcan_shader_envts{
/* packed matrices */
	MODELVIEW_MATR  = 0,
	PROJECTION_MATR,
	TEXTURE_MATR,

/* current camera */
	VIEW_UP_V,
	VIEW_V,
	VIEW_POS_V,

/* current object */
	OBJ_SCALE_V,
	OBJ_POS_V,
	OBJ_ORIENT_V,
	OBJ_VIEW_V,
	OBJ_OPACITY_F,

/* texture mapping */
	MAP_DISPLACEMENT_D,
	MAP_BUMP_D,
	MAP_SHADOW_D,
	MAP_REFLECTION_D,
	MAP_NORMAL_D,
	MAP_SPECULAR_D,
	MAP_DIFFUSE_D,

/* lighting */
	LIGHT_WORLD_DIR_V,
	LIGHT_WORLD_DIFFUSE_V,
	LIGHT_WORLD_AMBIENT_V,

/* system values, don't change this order */
	FRACT_TIMESTAMP_F, 
	TIMESTAMP_D,
};

enum shader_vertex_attributes {
	ATTRIBUTE_VERTEX,
	ATTRIBUTE_NORMAL,
	ATTRIBUTE_COLOR,
	ATTRIBUTE_TEXCORD
};

/* delete and forget all allocated shaders */
void arcan_shader_flush();

/* keep the meta-structure, but delete all OpenGL resources associated with a shader */
void arcan_shader_unload_all();

/* allocate new OpenGL resources for all allocated shaders, when reinitializing visual context etc. */
void arcan_shader_rebuild_all();

/* set a specific shader as the current active one,
 * and map all used envvs */
arcan_errc arcan_shader_activate(arcan_shader_id shid);

/* pack into a new texture and just return an index to use */
arcan_shader_id arcan_shader_build(const char* tag, const char* geom, const char* vert, const char* frag);

int arcan_shader_vattribute_loc(enum shader_vertex_attributes attr);

/* subid ignreod for (! n*) types,
 * value assumed to have type specified in enumlabel,
 * true if this matched something in the current active shader */
bool arcan_shader_envv(enum arcan_shader_envts slot, void* value, size_t size);

const char* arcan_shader_symtype(enum arcan_shader_envts env);

/* update a specific uniformslot that will map to whatever shader is active,
 * discarded when another shader is deactivated */
void arcan_shader_forceunif(const char* label, enum shdrutype type, void* value);

#endif
