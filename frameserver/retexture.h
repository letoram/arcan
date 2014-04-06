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
/
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,MA 02110-1301,USA.
 *
 */

/*
 * will be used to lookup dynamic symbols that is overridden internally.
 */
#ifndef GLSYM_FUNCTION
#define GLSYM_FUNCTION(X) SDL_GL_GetProcAddress(X)
#endif

/*
 * reserve / setup a specific translation
 */
void arcan_retexture_alloc(unsigned long djbv, int* bucket, int* id);

/*
 * Using the internal ID numbering scheme (bucket:id), 
 * update a preexisting slot
 */
void arcan_retexture_update(int bucket, int id,
	int w, int h, int bpp, int stride, void* buf);

/*
 * Using the internal ID numbering scheme (bucket:id), retrieve a pointer to
 * the currently active storage copy for a texture object.
 */
void* arcan_retexture_fetchp(int bucket, int id,
	int* w, int* h, int* bpp, int* stride);

/*
 * Retrieve the local copy for the specified GLID, only if 
 * arcan_retexture_init has been setup with 'local' copies activated.
 */
void* arcan_retexture_fetchid(unsigned tid, 
	int* w, int* h, int* bpp, int* stride);

/*
 * ann is an output event-queue where new discoveries
 * etc. will be announced (bucket:id + hash), can be set to NULL.
 *
 * If local is defined, a local memory copy will be maintained
 * for supported texture formats.
 */
void arcan_retexture_init(arcan_event* ann, bool local);

/*
 * Disable or enable collection / manipulation 
 * based on what's currently running. 
 */
void arcan_retexture_disable();
void arcan_retexture_enable();
