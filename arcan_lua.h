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

#ifndef _HAVE_ARCAN_LUA
#define _HAVE_ARCAN_LUA

/* add a set of wrapper functions exposing arcan_video and friends to the LUA state,
 * debugfuncs corresponds to desired debug level / behavior */
arcan_errc arcan_lua_exposefuncs(lua_State* dst, unsigned char debugfuncs);

/* wrap lua_pcalls with this (set errc to pcall result) */
void arcan_lua_wraperr(lua_State* ctx, int errc, const char* src);
void arcan_lua_setglobalint(lua_State* ctx, const char* key, int val);
void arcan_lua_setglobalstr(lua_State* ctx, const char* key, const char* val);
void arcan_lua_pushevent(lua_State* ctx, arcan_event* ev);
void arcan_lua_callvoidfun(lua_State* ctx, const char* fun);
void arcan_lua_pushargv(lua_State* ctx, char** argv);

/* used to implement an interactive shell,
 * iterate the global (_G) table for a matching prefix, yield callback for each hit,
 * with (key, type, tag) as the callback arguments */
void arcan_lua_eachglobal(lua_State* ctx, char* prefix, 
	int (*callback)(const char*, const char*, void*), void* tag);

/* for initialization, update / push all the global constants used */
void arcan_lua_pushglobalconsts(lua_State* ctx);

/* serialize a LUA- parseable snapshot of the various mapped subsystems 
 * and resources into the (dst) filestream. Since it's streaming, the blocks
 * will be separated with a #ENDBLOCK\n tag and fsynched. */ 
void arcan_lua_statesnap(FILE* dst);

/* nonblock/read from (dst) filestream until an #ENDBLOCK\n tag is encountered,
 * parse this and push it into the lua_State as the first and only argument
 * to the function pointed out with (dstfun). */
void arcan_lua_stategrab(lua_State* ctx, char* dstfun, int fd);
#endif

