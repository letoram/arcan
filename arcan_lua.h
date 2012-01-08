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

#ifndef _HAVE_ARCAN_LUA
#define _HAVE_ARCAN_LUA

/* add a set of wrapper functions exposing arcan_video_ to the LUA state */
arcan_errc arcan_lua_exposefuncs(lua_State* dst, bool debugfuncs);

/* wrap lua_pcalls with this (set errc to pcall result) */
void arcan_lua_wraperr(lua_State* ctx, int errc, const char* src);
void arcan_lua_setglobalint(lua_State* ctx, const char* key, int val);
void arcan_lua_setglobalstr(lua_State* ctx, const char* key, const char* val);
void arcan_lua_pushevent(lua_State* ctx, arcan_event ev);
void arcan_lua_callvoidfun(lua_State* ctx, const char* fun);
void arcan_lua_pushargv(lua_State* ctx, char** argv);
void arcan_lua_pushglobalconsts(lua_State* ctx);
#endif

