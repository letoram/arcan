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

#ifdef LUA_51
	#define lua_rawlen(x, y) lua_objlen(x, y)
#endif

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>

#include <string.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <math.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <SDL.h>
#include <SDL_opengl.h>
#include <SDL_ttf.h>
#include <assert.h>

#include "lodepng/lodepng.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_shdrmgmt.h"
#include "arcan_3dbase.h"
#include "arcan_audio.h"
#include "arcan_event.h"
#include "arcan_db.h"
#include "arcan_framequeue.h"
#include "arcan_frameserver_backend.h"
#include "arcan_frameserver_shmpage.h"
#include "arcan_target_const.h"
#include "arcan_target_launcher.h"
#include "arcan_lua.h"
#include "arcan_led.h"


/* these take some explaining:
 * to enforce that actual constants are used in LUA scripts and not magic numbers
 * the corresponding binding functions check that the match these global constants (not defines
 * as we want them maintained in DWARF debug data as well), but their actual values are set by
 * defines so that they can be swizzled around by the build-system */
#ifndef CONST_ORDER_FIRST 
#define CONST_ORDER_FIRST 1
#endif
static const int ORDER_FIRST = CONST_ORDER_FIRST;

#ifndef CONST_ORDER_LAST
#define CONST_ORDER_LAST 0
#endif
static const int ORDER_LAST  = CONST_ORDER_LAST;

static const int FRAMESERVER_LOOP = 1;
static const int FRAMESERVER_NOLOOP = 0;

static const int FRAMESET_NODETACH = 11;
static const int FRAMESET_DETACH = 10;

static const int RENDERTARGET_DETACH = 10;
static const int RENDERTARGET_NODETACH = 11;
static const int RENDERTARGET_SCALE = 20;
static const int RENDERTARGET_NOSCALE = 21;

static const int BLEND_NONE     = blend_disable;
static const int BLEND_NORMAL   = blend_normal;
static const int BLEND_ADD      = blend_add;
static const int BLEND_MULTIPLY = blend_multiply;
static const int BLEND_FORCE    = blend_force;

static const int POSTFILTER_NTSC = 100;
static const int POSTFILTER_OFF  = 10;

extern char* arcan_themename;
extern arcan_dbh* dbhandle;

enum arcan_cb_source {
	CB_SOURCE_NONE = 0,
	CB_SOURCE_FRAMESERVER= 1,
	CB_SOURCE_IMAGE = 2
};

static struct {
	FILE* rfile;
	unsigned char debug;
	unsigned lua_vidbase;
	unsigned char grab;

	enum arcan_cb_source cb_source_kind;
	long long cb_source_tag;
	
} lua_ctx_store = {
	.lua_vidbase = 0,
	.rfile = NULL,
	.debug = false,
	.grab = 0
};

static void dump_stack(lua_State* ctx);
extern char* _n_strdup(const char* instr, const char* alt);

static inline char* findresource(const char* arg, int searchmask)
{
	char* res = arcan_find_resource(arg, searchmask);
/* since this is invoked extremely frequently and is involved in file-system related stalls,
 * maybe a sort of caching mechanism should be implemented (invalidate / refill every N ticks
 * or have a flag to side-step it, as a lot of resources are quite static and the rest of the
 * API have to handle missing / bad resources anyhow */

	if (lua_ctx_store.debug){
		arcan_warning("Debug, resource lookup for %s, yielded: %s\n", arg, res);
	}

	return res;
}

int arcan_lua_zapresource(lua_State* ctx)
{
	char* path = findresource(luaL_checkstring(ctx, 1), ARCAN_RESOURCE_THEME);

	if (path && unlink(path) != -1)
		lua_pushboolean(ctx, false);
	else
		lua_pushboolean(ctx, true);

	free(path);
	return 1;
}

int arcan_lua_rawresource(lua_State* ctx)
{
	char* path = findresource(luaL_checkstring(ctx, 1), ARCAN_RESOURCE_THEME | ARCAN_RESOURCE_SHARED);

	if (lua_ctx_store.rfile)
		fclose(lua_ctx_store.rfile);

	if (!path) {
		char* fname = arcan_expand_resource(luaL_checkstring(ctx, 1), false);
		lua_ctx_store.rfile = fopen(fname, "w+");
		free(fname);
	} else 
		lua_ctx_store.rfile = fopen(path, "r");

	lua_pushboolean(ctx, lua_ctx_store.rfile != NULL);
	free(path);
	return 1;
}

static char* chop(char* str)
{
    char* endptr = str + strlen(str) - 1;
    while(isspace(*str)) str++;
    
    if(!*str) return str;
    while(endptr > str && isspace(*endptr)) 
        endptr--;
    
    *(endptr+1) = 0;
    
    return str;
}

int arcan_lua_readrawresource(lua_State* ctx)
{
	if (lua_ctx_store.rfile){
		char line[256];
		if (fgets(line, sizeof(line), lua_ctx_store.rfile) != NULL){
			lua_pushstring(ctx, chop( line ));
			return 1;
		}
	}

	return 0;
}

void arcan_lua_setglobalstr(lua_State* ctx, const char* key, const char* val)
{
	lua_pushstring(ctx, val);
	lua_setglobal(ctx, key);
}

void arcan_lua_setglobalint(lua_State* ctx, const char* key, int val)
{
	lua_pushnumber(ctx, val);
	lua_setglobal(ctx, key);
}

const char* luaL_lastcaller(lua_State* ctx)
{
	return lua_tostring(ctx, lua_upvalueindex(2));
}

static inline arcan_aobj_id luaaid_toaid(lua_Number innum)
{
	return (arcan_aobj_id) innum;
}

static inline arcan_vobj_id luavid_tovid(lua_Number innum)
{
	arcan_vobj_id res = ARCAN_VIDEO_WORLDID;
	
	if (innum != ARCAN_EID && innum != ARCAN_VIDEO_WORLDID)
		res = (arcan_vobj_id) innum - lua_ctx_store.lua_vidbase;
	
	if (res < 0)
		res = ARCAN_EID;
	
	return res;
}

static inline lua_Number vid_toluavid(arcan_vobj_id innum)
{
	if (innum != ARCAN_EID && innum != ARCAN_VIDEO_WORLDID)
		innum += lua_ctx_store.lua_vidbase;

	return (double) innum;
}

static inline arcan_vobj_id luaL_checkvid(lua_State* ctx, int num)
{
	arcan_vobj_id res = luaL_checknumber(ctx, num);
	return luavid_tovid(res);
}

static inline arcan_vobj_id luaL_checkaid(lua_State* ctx, int num)
{
	return luaL_checknumber(ctx, num);
}

static inline void lua_pushvid(lua_State* ctx, arcan_vobj_id id)
{
	if (id != ARCAN_EID && id != ARCAN_VIDEO_WORLDID)
		id += lua_ctx_store.lua_vidbase;

	lua_pushnumber(ctx, (double) id);
}

static inline void lua_pushaid(lua_State* ctx, arcan_aobj_id id)
{
	lua_pushnumber(ctx, id);
}

int arcan_lua_rawclose(lua_State* ctx)
{
	bool res = false;

	if (lua_ctx_store.rfile) {
		res = fclose(lua_ctx_store.rfile);
		lua_ctx_store.rfile = NULL;
	}

	lua_pushboolean(ctx, res);
	return 1;
}

int arcan_lua_pushrawstr(lua_State* ctx)
{
	bool res = false;
	const char* mesg = luaL_checkstring(ctx, 1);

	if (lua_ctx_store.rfile) {
		size_t fs = fwrite(mesg, strlen(mesg), 1, lua_ctx_store.rfile);
		res = fs == 1;
	}

	lua_pushboolean(ctx, res);
	return 1;
}

/* Expects:
 * string - filename
 * adds ID unto the stack if successfull, ARCAN_EID otherwise
 */
int arcan_lua_loadimage(lua_State* ctx)
{
	arcan_vobj_id id = ARCAN_EID;
	char* path = findresource(luaL_checkstring(ctx, 1), ARCAN_RESOURCE_SHARED | ARCAN_RESOURCE_THEME);
	uint8_t prio = luaL_optint(ctx, 2, 0);
	unsigned desw = luaL_optint(ctx, 3, 0);
	unsigned desh = luaL_optint(ctx, 4, 0);

	if (path)
		id = arcan_video_loadimage(path, arcan_video_dimensions(desw, desh), prio);

	free(path);
	lua_pushvid(ctx, id);
	return 1;
}

int arcan_lua_loadimageasynch(lua_State* ctx)
{
	arcan_vobj_id id = ARCAN_EID;
	intptr_t ref = 0;

	char* path = findresource(luaL_checkstring(ctx, 1), ARCAN_RESOURCE_SHARED | ARCAN_RESOURCE_THEME);
	if (lua_isfunction(ctx, 2) && !lua_iscfunction(ctx, 2)){
		lua_pushvalue(ctx, 2);
		ref = luaL_ref(ctx, LUA_REGISTRYINDEX);
	}
	
	if (path && strlen(path) > 0){
		id = arcan_video_loadimageasynch(path, arcan_video_dimensions(0, 0), ref);
	}
	free(path);

	lua_pushvid(ctx, id);
	return 1;
}

int arcan_lua_imageloaded(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj)
		lua_pushnumber(ctx, vobj->feed.state.tag == ARCAN_TAG_IMAGE);
	else
		lua_pushnumber(ctx, false);
	
	return 1;
}

int arcan_lua_moveimage(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	float newx = luaL_optnumber(ctx, 2, 0);
	float newy = luaL_optnumber(ctx, 3, 0);
	int time = luaL_optint(ctx, 4, 0);
	if (time < 0) time = 0;
	
	arcan_video_objectmove(id, newx, newy, 1.0, time);
	return 0;
}

int arcan_lua_nudgeimage(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	float newx = luaL_optnumber(ctx, 2, 0);
	float newy = luaL_optnumber(ctx, 3, 0);

	surface_properties props = arcan_video_current_properties(id);
		
	int time = luaL_optint(ctx, 4, 0);
	if (time < 0) time = 0;
	
	arcan_video_objectmove(id, props.position.x + newx, props.position.y + newy, 1.0, time);
	return 0;
}

int arcan_lua_instanceimage(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	arcan_vobj_id newid = arcan_video_cloneobject(id);

	if (newid != ARCAN_EID){
		enum arcan_transform_mask lmask = MASK_SCALE | MASK_OPACITY | MASK_POSITION | MASK_ORIENTATION;
		arcan_video_transformmask(newid, lmask);

		lua_pushvid(ctx, newid);
		return 1;
	}
	
	return 0;
}

int arcan_lua_resettransform(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	arcan_video_zaptransform(id);

	return 0;
}

int arcan_lua_instanttransform(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	arcan_video_instanttransform(id);

	return 0;
}

int arcan_lua_cycletransform(lua_State* ctx)
{
	arcan_vobj_id sid = luaL_checkvid(ctx, 1);
	bool flag = luaL_checknumber(ctx, 2) != 0;
	
	arcan_video_transformcycle(sid, flag);

	return 0;
}

int arcan_lua_copytransform(lua_State* ctx)
{
	arcan_vobj_id sid = luaL_checkvid(ctx, 1);
	arcan_vobj_id did = luaL_checkvid(ctx, 2);
	
	arcan_video_copytransform(sid, did);
	
	return 0;
}

int arcan_lua_transfertransform(lua_State* ctx)
{
	arcan_vobj_id sid = luaL_checkvid(ctx, 1);
	arcan_vobj_id did = luaL_checkvid(ctx, 2);
	
	arcan_video_transfertransform(sid, did);
	
	return 0;
}

int arcan_lua_rotateimage(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	int ang = luaL_checkint(ctx, 2);
	int time = luaL_optint(ctx, 3, 0);

	arcan_video_objectrotate(id, ang, 0.0, 0.0, time);
	
	return 0;
}

/* Input is absolute values,
 * arcan_video_objectscale takes relative to initial size */
int arcan_lua_scaleimage2(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	float neww = luaL_checknumber(ctx, 2);
	float newh = luaL_checknumber(ctx, 3);
	int time = luaL_optint(ctx, 4, 0);
	if (time < 0) time = 0;

	if (neww < 0.0001 && newh < 0.0001)
		return 0;

	surface_properties prop = arcan_video_initial_properties(id);
	if (prop.scale.x < 0.001 && prop.scale.y < 0.001) {
		lua_pushnumber(ctx, 0);
		lua_pushnumber(ctx, 0);
	}
	else {
		/* retain aspect ratio in scale */
		if (neww < 0.0001 && newh > 0.0001)
			neww = newh * (prop.scale.x / prop.scale.y);
		else
			if (neww > 0.0001 && newh < 0.0001)
				newh = neww * (prop.scale.y / prop.scale.x);

		arcan_video_objectscale(id, neww / prop.scale.x, newh / prop.scale.y, 1.0, time);

		lua_pushnumber(ctx, neww);
		lua_pushnumber(ctx, newh);
	}

	return 2;
}

int arcan_lua_scaleimage(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);

	float desw = luaL_checknumber(ctx, 2);
	float desh = luaL_checknumber(ctx, 3);
	int time = luaL_optint(ctx, 4, 0);
	if (time < 0) time = 0;
	
	surface_properties cons = arcan_video_current_properties(id);
	surface_properties prop = arcan_video_initial_properties(id);

	/* retain aspect ratio in scale */
	if (desw < 0.0001 && desh > 0.0001)
		desw = desh * (prop.scale.x / prop.scale.y);
	else
		if (desw > 0.0001 && desh < 0.0001)
			desh = desw * (prop.scale.y / prop.scale.x);

	arcan_video_objectscale(id, desw, desh, 1.0, time);

	lua_pushnumber(ctx, desw);
	lua_pushnumber(ctx, desh);
	
	return 2;
}

int arcan_lua_orderimage(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	unsigned int zv = luaL_checknumber(ctx, 2);

	arcan_video_setzv(id, zv);
	
	return 0;
}

int arcan_lua_maxorderimage(lua_State* ctx)
{
	lua_pushnumber(ctx, arcan_video_maxorder());
	return 1;
}

int arcan_lua_showimage(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	arcan_video_objectopacity(id, 1.0f, 0);

	return 0;
}

int arcan_lua_hideimage(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	arcan_video_objectopacity(id, 0.0f, 0);

	return 0;
}

int arcan_lua_forceblend(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	enum arcan_blendfunc mode = luaL_optnumber(ctx, 2, BLEND_FORCE);
	
	if (mode == BLEND_FORCE || mode == BLEND_ADD || 
		mode == BLEND_MULTIPLY || mode == BLEND_NONE || mode == BLEND_NORMAL)
			arcan_video_forceblend(id, mode);

	return 0;
}

int arcan_lua_imageopacity(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	float val = luaL_checknumber(ctx, 2);
	uint16_t time = luaL_optint(ctx, 3, 0);

	arcan_video_objectopacity(id, val, time);
	return 0;
}

int arcan_lua_prepare_astream(lua_State* ctx)
{
	arcan_errc errc;
	char* path = findresource(
		luaL_checkstring(ctx, 1), 
		ARCAN_RESOURCE_SHARED | ARCAN_RESOURCE_THEME
	);

	arcan_aobj_id id = arcan_audio_stream(path, 0, &errc);
	lua_pushaid(ctx, id);
	free(path);
	return 1;
}

int arcan_lua_dropaudio(lua_State* ctx)
{
	arcan_audio_stop( luaL_checkaid(ctx, 1) );
	return 0;
}

int arcan_lua_gain(lua_State* ctx)
{
	arcan_aobj_id id = luaL_checkaid(ctx, 1);
	float gain = luaL_checknumber(ctx, 2);
	uint16_t time = luaL_optint(ctx, 3, 0);
	arcan_audio_setgain(id, gain, time);
	return 0;
}

int arcan_lua_pitch(lua_State* ctx)
{
	arcan_aobj_id id = luaL_checkaid(ctx, 1);
	float pitch = luaL_checknumber(ctx, 2);
	uint16_t time = luaL_optint(ctx, 3, 0);
	arcan_audio_setpitch(id, pitch, time);
	return 0;
}

int arcan_lua_playaudio(lua_State* ctx)
{
	arcan_aobj_id id = luaL_checkaid(ctx, 1);
	arcan_audio_play(id);
	return 0;
}

int arcan_lua_loadasample(lua_State* ctx)
{
	const char* rname = luaL_checkstring(ctx, 1);
	char* resource = findresource(rname, ARCAN_RESOURCE_SHARED | ARCAN_RESOURCE_THEME);
	float gain = luaL_optnumber(ctx, 2, 1.0);
	arcan_aobj_id sid = arcan_audio_load_sample(resource, gain, NULL);
	free(resource);
	lua_pushaid(ctx, sid);
	return 1;
}

int arcan_lua_pauseaudio(lua_State* ctx)
{
	arcan_aobj_id id = luaL_checkaid(ctx, 1);
	arcan_audio_pause(id);
	return 0;
}

int arcan_lua_buildshader(lua_State* ctx)
{
	const char* vprog = luaL_checkstring(ctx, 1);
	const char* fprog = luaL_checkstring(ctx, 2);
	const char* label = luaL_checkstring(ctx, 3);
	
	arcan_shader_id rv = arcan_shader_build(label, NULL, vprog, fprog);
	lua_pushnumber(ctx, rv);
	return 1;
}

int arcan_lua_setshader(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	arcan_shader_id shid;
	bool stat;

	if (	lua_type(ctx, 2) == LUA_TSTRING){
		shid = arcan_shader_lookup(luaL_checkstring(ctx, 2), &stat);
		if (!stat){
			shid = arcan_shader_lookup("DEFAULT", &stat);
			arcan_warning("arcan_lua_setshader: shader lookup (%s) failed, reverting to DEFAULT.\n", luaL_checkstring(ctx, 2));
		}
	}
	else shid = luaL_checknumber(ctx, 2);
	
	arcan_video_setprogram(id, shid);

	return 0;
}

int arcan_lua_setmeshshader(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	arcan_shader_id shid = luaL_checknumber(ctx, 2);
	int slot = abs ( luaL_checknumber(ctx, 3) );

	arcan_3d_meshshader(id, shid, slot);

	return 0;
}

int arcan_lua_strsize(lua_State* ctx)
{
	unsigned int width = 0, height = 0;
	const char* message = luaL_checkstring(ctx, 1);
	int vspacing = luaL_optint(ctx, 2, 4);
	int tspacing = luaL_optint(ctx, 2, 64);
	
	arcan_video_stringdimensions(message, vspacing, tspacing, NULL, &width, &height);

	lua_pushnumber(ctx, width);
	lua_pushnumber(ctx, height);
	
	return 2;
}

int arcan_lua_buildstr(lua_State* ctx)
{
	arcan_vobj_id id = ARCAN_EID;
	const char* message = luaL_checkstring(ctx, 1);
	int vspacing = luaL_optint(ctx, 2, 4);
	int tspacing = luaL_optint(ctx, 2, 64);

	unsigned int nlines = 0;
	unsigned int* lineheights = NULL;

	id = arcan_video_renderstring(message, vspacing, tspacing, NULL, &nlines, &lineheights);
	lua_pushvid(ctx, id);

	lua_newtable(ctx);
	int top = lua_gettop(ctx);
	
	for (int i = 0; i < nlines; i++) {
		lua_pushnumber(ctx, i + 1);
		lua_pushnumber(ctx, lineheights[i]);
		lua_rawset(ctx, top);
	}

	if (lineheights)
		free(lineheights);

	return 2;
}

int arcan_lua_scaletxcos(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	float txs = luaL_checknumber(ctx, 2);
	float txt = luaL_checknumber(ctx, 3);

	arcan_video_scaletxcos(id, txs, txt);
	
	return 0;
}

int arcan_lua_settxcos(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	float txcos[8];

	if (arcan_video_retrieve_mapping(id, txcos) == ARCAN_OK){
		luaL_checktype(ctx, 2, LUA_TTABLE);
		int ncords = lua_rawlen(ctx, -1);
		if (ncords < 8){
			arcan_warning("Warning: lua_settxcos(), Too few elements in txco tables (expected 8, got %i)\n", ncords);
			return 0;
		}
		
		for (int i = 0; i < 8; i++){
			lua_rawgeti(ctx, -1, i+1);
			txcos[i] = lua_tonumber(ctx, -1);
			lua_pop(ctx, 1);
		}
		
		arcan_video_override_mapping(id, txcos);
	}
	
	return 0;
}

int arcan_lua_gettxcos(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	int rv = 0;
	float txcos[8] = {0};
	
	if (arcan_video_retrieve_mapping(id, txcos) == ARCAN_OK){
		lua_newtable(ctx);
		int top = lua_gettop(ctx);
		
		for (int i = 0; i < 8; i++){
			lua_pushnumber(ctx, i + 1);
			lua_pushnumber(ctx, txcos[i]);
			lua_rawset(ctx, top);
		}
		
		rv = 1;
	}
	
	return rv;
}

int arcan_lua_togglemask(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	unsigned val = luaL_checknumber(ctx, 2);
	
	if ( (val & !(MASK_ALL)) == 0){
		enum arcan_transform_mask mask = arcan_video_getmask(id);
		mask ^= ~val;
		arcan_video_transformmask(id, mask);
	}

	return 0;
}

int arcan_lua_clearall(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	if (id){
		arcan_video_transformmask(id, 0);
	}

	return 0;
}

int arcan_lua_clearmask(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	unsigned val = luaL_checknumber(ctx, 2);

	if ( (val & !(MASK_ALL)) == 0){
		enum arcan_transform_mask mask = arcan_video_getmask(id);
		mask &= ~val;
		arcan_video_transformmask(id, mask);
	}

	return 0;
}

int arcan_lua_setmask(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	unsigned val = luaL_checknumber(ctx, 2);

	if ( (val & !(MASK_ALL)) == 0){
		enum arcan_transform_mask mask = arcan_video_getmask(id);
		mask |= val;
		arcan_video_transformmask(id, mask);
	} else
		arcan_warning("Script Warning: image_mask_set(), bad mask specified (%i)\n", val);
	
	return 0;
}

int arcan_lua_clipon(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	arcan_video_setclip(id, true);
    return 0;
}

int arcan_lua_clipoff(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	arcan_video_setclip(id, false);
    return 0;
}

int arcan_lua_pick(lua_State* ctx)
{
	int x = luaL_checkint(ctx, 1);
	int y = luaL_checkint(ctx, 2);
	unsigned int limit = luaL_optint(ctx, 3, 8);
	arcan_vobj_id* pickbuf = (arcan_vobj_id*) malloc(limit * sizeof(arcan_vobj_id));
	unsigned int count = arcan_video_pick(pickbuf, limit, x, y);
	unsigned int ofs = 1;

	lua_newtable(ctx);
	int top = lua_gettop(ctx);

	while (count--) {
		lua_pushnumber(ctx, ofs);
		lua_pushvid(ctx, pickbuf[ofs-1]);
		lua_rawset(ctx, top);
		ofs++;
	}

	free(pickbuf);
	return 1;
}

int arcan_lua_hittest(lua_State* state)
{
	arcan_vobj_id id = luaL_checkvid(state, 1);
	unsigned int x = luaL_checkint(state, 2);
	unsigned int y = luaL_checkint(state, 3);

	lua_pushnumber(state, arcan_video_hittest(id, x, y));

	return 1;
}

int arcan_lua_deleteimage(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	double srcid = luaL_checknumber(ctx, 1);

	/* possibly long journey,
	 * for a vid with a movie associated (or any feedfunc),
	 * the feedfunc will be invoked with the cleanup cmd
	 * which in the movie cause will trigger a full movie cleanup */
	arcan_errc rv = arcan_video_deleteobject(id);
	if (rv != ARCAN_OK){
		if (lua_ctx_store.debug > 0){
			arcan_warning("%s => arcan_lua_deleteimage(%.0lf=>%d) -- Object could not be deleted, invalid object specified.\n", luaL_lastcaller(ctx), srcid, id);
		}
		else
			arcan_fatal("Theme tried to delete non-existing object (%.0lf=>%d) from (%s). Relaunch with debug flags (-g) to suppress.\n", srcid, id, luaL_lastcaller(ctx));
	}
	
	return 0;
}

int arcan_lua_setlife(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	int ttl = luaL_checkint(ctx, 2);

	if (ttl <= 0)
			return arcan_lua_deleteimage(ctx);
	else
			arcan_video_setlife(id, ttl);

	return 0;
}

/* to actually put this into effect, change value and pop the entire stack */
int arcan_lua_systemcontextsize(lua_State* ctx)
{
	unsigned newlim = luaL_checkint(ctx, 1);
	if (newlim > 1){
		arcan_video_contextsize(newlim);
	}

	return 0;
}

int arcan_lua_dofile(lua_State* ctx)
{
	const char* instr = luaL_checkstring(ctx, 1);
	char* fname = findresource(instr, ARCAN_RESOURCE_THEME | ARCAN_RESOURCE_SHARED);
	int res = 0;

	if (fname){
		luaL_loadfile(ctx, fname);
		res = 1;
	}
	else{
		free(fname);
		arcan_warning("Script Warning: system_load(), couldn't find resource (%s)\n", instr);
	}

	free(fname);
	return res;
}

int arcan_lua_pausemovie(lua_State* ctx)
{
	arcan_vobj_id vid = luaL_checkvid(ctx, 1);
	vfunc_state* state = arcan_video_feedstate(vid);

	if (state && state->tag == ARCAN_TAG_FRAMESERV && state->ptr)
		arcan_frameserver_pause((arcan_frameserver*) state->ptr, false);

	return 0;
}

int arcan_lua_resumemovie(lua_State* ctx)
{
	arcan_vobj_id vid = luaL_checkvid(ctx, 1);
	vfunc_state* state = arcan_video_feedstate(vid);

	if (state && state->tag == ARCAN_TAG_FRAMESERV && state->ptr)
		arcan_frameserver_resume((arcan_frameserver*) state->ptr);

	return 0;
}

int arcan_lua_playmovie(lua_State* ctx)
{
	arcan_vobj_id vid = luaL_checkvid(ctx, 1);
	vfunc_state* state = arcan_video_feedstate(vid);

	if (state && state->tag == ARCAN_TAG_FRAMESERV) {
		arcan_frameserver* movie = (arcan_frameserver*) state->ptr;
		arcan_frameserver_playback(movie);
		lua_pushvid(ctx, movie->vid);
		lua_pushaid(ctx, movie->aid);
		return 2;
	}
	else {
		arcan_vobject* vobj = arcan_video_getobject(vid);
		arcan_warning("arcan_lua_playmovie(%d) -- bad feed / no frameserver (%" PRIxPTR ",%d)\n", lua_ctx_store.lua_vidbase + vid, state, state ? state->tag : -1);
	}
		
	return 0;
}

int arcan_lua_loadmovie(lua_State* ctx)
{
	int loop = luaL_optint(ctx, 2, FRAMESERVER_NOLOOP);
	if (loop != FRAMESERVER_LOOP && loop != FRAMESERVER_NOLOOP){
		arcan_warning("arcan_lua_loadmovie() invalid second argument (%d) specified, should be FRAMESERVER_NOLOOP or FRAMESERVER_LOOP\n", loop);
		return 0;
	}
	
	char* fname = findresource(luaL_checkstring(ctx, 1), ARCAN_RESOURCE_THEME | ARCAN_RESOURCE_SHARED);
	intptr_t ref = (intptr_t) 0;

	if (!fname){
		arcan_warning("arcan_lua_loadmovie() -- unknown resource (%s) specified.\n", fname);
		return 0;
	}
	
/*  in order to stay backward compatible API wise, the load_movie with function callback
 *  will always need to specify loop condition. */
	if (lua_isfunction(ctx, 3) && !lua_iscfunction(ctx, 3)){
		lua_pushvalue(ctx, 3);
		ref = luaL_ref(ctx, LUA_REGISTRYINDEX);
	}
	
	arcan_frameserver* mvctx = (arcan_frameserver*) calloc(sizeof(arcan_frameserver), 1);
	mvctx->loop = loop == FRAMESERVER_LOOP; 
	
	struct frameserver_envp args = {
		.use_builtin = true,
		.args.builtin.mode = "movie",
		.args.builtin.resource = fname  
	};
	
	if ( arcan_frameserver_spawn_server(mvctx, args) == ARCAN_OK )
	{
		mvctx->tag = ref;
		
		arcan_video_objectopacity(mvctx->vid, 0.0, 0);
		lua_pushvid(ctx, mvctx->vid);
	} else {
		free(mvctx);
		lua_pushvid(ctx, ARCAN_EID);
	}

	free(fname);

	return 1;
}

int arcan_lua_n_leds(lua_State* ctx)
{
	uint8_t id = luaL_checkint(ctx, 1);
	led_capabilities cap = arcan_led_capabilities(id);

	lua_pushnumber(ctx, cap.nleds);
	return 1;
}

int arcan_lua_led_intensity(lua_State* ctx)
{
	uint8_t id = luaL_checkint(ctx, 1);
	int8_t led = luaL_checkint(ctx, 2);
	uint8_t intensity = luaL_checkint(ctx, 3);

	lua_pushnumber(ctx, arcan_led_intensity(id, led, intensity));
	return 1;
}

int arcan_lua_led_rgb(lua_State* ctx)
{
	uint8_t id = luaL_checkint(ctx, 1);
	int8_t led = luaL_checkint(ctx, 2);
	uint8_t r  = luaL_checkint(ctx, 3);
	uint8_t g  = luaL_checkint(ctx, 4);
	uint8_t b  = luaL_checkint(ctx, 5);

	lua_pushnumber(ctx, arcan_led_rgb(id, led, r, g, b));
	return 1;
}

int arcan_lua_setled(lua_State* ctx)
{
	int id = luaL_checkint(ctx, 1);
	int num = luaL_checkint(ctx, 2);
	int state = luaL_checkint(ctx, 3);

	lua_pushnumber(ctx, state ? arcan_led_set(id, num) : arcan_led_clear(id, num));

	return 1;
}

int arcan_lua_pushcontext(lua_State* ctx)
{
/* make sure that we save one context for launch_external */
	
	if (arcan_video_nfreecontexts() > 1)
		lua_pushinteger(ctx, arcan_video_pushcontext());
	else
		lua_pushinteger(ctx, -1);
	
	return 1;
}

int arcan_lua_popcontext(lua_State* ctx)
{
	lua_pushinteger(ctx, arcan_video_popcontext());
	return 1;
}

int arcan_lua_contextusage(lua_State* ctx)
{
	unsigned usecount;
	lua_pushinteger(ctx, arcan_video_contextusage(&usecount));
	lua_pushinteger(ctx, usecount);
	return 2;
}

static inline const char* intblstr(lua_State* ctx, int ind, const char* field){
	lua_getfield(ctx, ind, field);
	return lua_tostring(ctx, -1);
}

static inline int intblnum(lua_State* ctx, int ind, const char* field){
	lua_getfield(ctx, ind, field);
	return lua_tointeger(ctx, -1);
}

static inline bool intblbool(lua_State* ctx, int ind, const char* field){
	lua_getfield(ctx, ind, field);
	return lua_toboolean(ctx, -1);
}

/*
 * Next step in the input mess, take a properly formatted table,
 * convert it back into an arcan event, push that to the target_launcher or frameserver.
 * The targetr_launcher will serialise it to a hijack function which then decodes into a
 * native format (currently most likely SDL). All this hassle (instead 
 * of creating a custom LUA object, tag it with the raw event and be done with it)
 * is to allow the theme- to modify or even generate new ones based on in-theme actions.
 */

/* there is a slight API inconsistency here in that we had (iotbl, vid) in the first few versions
 * while other functions tend to lead with vid, which causes some confusion. So we check
 * whethere the table argument is first or second, and extract accordingly, so both will work */
int arcan_lua_targetinput(lua_State* ctx)
{
	arcan_event ev = {.kind = 0, .category = EVENT_IO };
	int vidind, tblind;

/* swizzle if necessary */
	if (lua_type(ctx, 1) == LUA_TTABLE){
		vidind = 2;
		tblind = 1;
	} else {
		tblind = 2;
		vidind = 1;
	}
	
	arcan_vobj_id vid = luaL_checkvid(ctx, vidind);
	luaL_checktype(ctx, tblind, LUA_TTABLE);
	
	vfunc_state* vstate = arcan_video_feedstate(vid);
	
	if (!vstate || vstate->tag != ARCAN_TAG_FRAMESERV){
		lua_pushnumber(ctx, false);
		return 1;
	}

	const char* label = intblstr(ctx, tblind, "label");
	if (label)
		snprintf(ev.label, 16, "%s", label);

	/* populate all arguments */
	const char* kindlbl = intblstr(ctx, tblind, "kind");
	
	if ( strcmp( kindlbl, "analog") == 0 ){
		ev.kind = EVENT_IO_AXIS_MOVE;
		ev.data.io.devkind = strcmp( intblstr(ctx, tblind, "source"), "mouse") == 0 ? EVENT_IDEVKIND_MOUSE : EVENT_IDEVKIND_GAMEDEV;
		ev.data.io.input.analog.devid = intblnum(ctx, tblind, "devid");
		ev.data.io.input.analog.subid = intblnum(ctx, tblind, "subid");
		ev.data.io.input.analog.gotrel = ev.data.io.devkind == EVENT_IDEVKIND_MOUSE;
		
	/*  sweep the samples subtable, add as many as present (or possible) */
		lua_getfield(ctx, tblind, "samples");
		size_t naxiss = lua_rawlen(ctx, -1);
		for (int i = 0; i < naxiss && i < sizeof(ev.data.io.input.analog.axisval); i++){
			lua_rawgeti(ctx, -1, i+1);
			ev.data.io.input.analog.axisval[i] = lua_tointeger(ctx, -1);
			lua_pop(ctx, 1);
		}
		
	} 
	else if (strcmp(kindlbl, "digital") == 0){
		if (intblbool(ctx, tblind, "translated")){
			ev.data.io.datatype = EVENT_IDATATYPE_TRANSLATED;
			ev.data.io.devkind  = EVENT_IDEVKIND_KEYBOARD;
			ev.data.io.input.translated.active    = intblbool(ctx, tblind, "active");
			ev.data.io.input.translated.scancode  = intblnum(ctx, tblind, "number");
			ev.data.io.input.translated.keysym    = intblnum(ctx, tblind, "keysym");
			ev.data.io.input.translated.modifiers = intblnum(ctx, tblind, "modifiers");
			ev.data.io.input.translated.devid     = intblnum(ctx, tblind, "devid");
			ev.data.io.input.translated.subid     = intblnum(ctx, tblind, "subid");
			ev.kind = ev.data.io.input.translated.active ? EVENT_IO_KEYB_PRESS : EVENT_IO_KEYB_RELEASE;
		}
		else {
			ev.data.io.devkind = strcmp( intblstr(ctx, tblind, "source"), "mouse") == 0 ? EVENT_IDEVKIND_MOUSE : EVENT_IDEVKIND_GAMEDEV; 
			ev.data.io.datatype = EVENT_IDATATYPE_DIGITAL;
			ev.data.io.input.digital.active= intblbool(ctx, tblind, "active");
			ev.data.io.input.digital.devid = intblnum(ctx, tblind, "devid");
			ev.data.io.input.digital.subid = intblnum(ctx, tblind, "subid");
		}
	} 
	else {
		arcan_warning("Script Warning: target_input(), unkown \"kind\" field in table.\n");
		lua_pushnumber(ctx, false);
		return 1;
	}
		
	if (vstate->tag == ARCAN_TAG_FRAMESERV)
		arcan_frameserver_pushevent( (arcan_frameserver*) vstate->ptr, &ev );

	lua_pushnumber(ctx, true);
	return 1;
}

static int arcan_lua_targetsuspend(lua_State* ctx){
	arcan_vobj_id vid = luaL_checkvid(ctx, 1);

	if (vid != ARCAN_EID){
		vfunc_state* state = arcan_video_feedstate(vid);
		if (state && state->ptr && state->tag == ARCAN_TAG_FRAMESERV){
			arcan_event ev = {
				.kind = TARGET_COMMAND_PAUSE,
				.category = EVENT_TARGET
			};
			
			arcan_frameserver_pushevent( (arcan_frameserver*) state->ptr, &ev);
		}
	}

	return 0;
}

static int arcan_lua_targetresume(lua_State* ctx){
	arcan_vobj_id vid = luaL_checkvid(ctx, 1);
	if (vid != ARCAN_EID){
		vfunc_state* state = arcan_video_feedstate(vid);
		if (state && state->ptr && state->tag == ARCAN_TAG_FRAMESERV){
			arcan_event ev = {
				.kind = TARGET_COMMAND_UNPAUSE,
				.category = EVENT_TARGET
			};
			
			arcan_frameserver_pushevent( (arcan_frameserver*) state->ptr, &ev);
		}
	}

	return 0;
}

static bool arcan_lua_grabthemefunction(lua_State* ctx, const char* funame)
{
	if (strcmp(arcan_themename, funame) == 0)
		lua_getglobal(ctx, arcan_themename);
	else {
		char* tmpname = (char*) malloc(strlen(arcan_themename) + strlen(funame) + 2);
			sprintf(tmpname, "%s_%s", arcan_themename, funame);
			lua_getglobal(ctx, tmpname);
		free(tmpname);
	}
	
	if (!lua_isfunction(ctx, -1)){
		lua_pop(ctx, 1);
		return false;
	}
		
	return true;
}

static inline int arcan_lua_funtable(lua_State* ctx, uint32_t kind){
	lua_newtable(ctx);
	int top = lua_gettop(ctx);
	lua_pushstring(ctx, "kind");
	lua_pushnumber(ctx, kind);
	lua_rawset(ctx, top);

	return top;
}

static inline void arcan_lua_tblstr(lua_State* ctx, char* key, char* value, int top){
	lua_pushstring(ctx, key);
	lua_pushstring(ctx, value);
	lua_rawset(ctx, top);
}

static inline void arcan_lua_tblnum(lua_State* ctx, char* key, double value, int top){
	lua_pushstring(ctx, key);
	lua_pushnumber(ctx, value);
	lua_rawset(ctx, top);
}

static inline void arcan_lua_tblbool(lua_State* ctx, char* key, bool value, int top){
	lua_pushstring(ctx, key);
	lua_pushboolean(ctx, value);
	lua_rawset(ctx, top);
}

static char* to_utf8(uint16_t utf16)
{
	static char utf8buf[6] = {0};
	int count = 1, ofs = 0;
	uint32_t mask = 0x800;

	if (utf16 >= 0x80)
		count++;

	for (int i=0; i < 5; i++){
		if ( (uint32_t) utf16 >= mask )
			count++;

		mask <<= 5;
	}

	if (count == 1){
		utf8buf[0] = (char) utf16;
		utf8buf[1] = 0x00;
	} else {
		for (int i = count-1; i >= 0; i--){
			unsigned char ch = ( utf16 >> (6 * i)) & 0x3f;
			ch |= 0x80;
			if (i == count-1)
				ch |= 0xff << (8-count);
			utf8buf[ofs++] = ch;
		}
		utf8buf[ofs++] = 0x00;
	}
	
	return (char*) utf8buf;
}

int arcan_lua_scale3dverts(lua_State* ctx)
{
    arcan_vobj_id vid = luaL_checkvid(ctx, 1);
    arcan_3d_scalevertices(vid);
    return 0;
}

/* emitt input() call based on a arcan_event,
 * uses a separate format and translation to make it easier
 * for the user to modify. Perhaps one field should've been used
 * to store the actual event, but it wouldn't really help extration. */
void arcan_lua_pushevent(lua_State* ctx, arcan_event* ev)
{
	if (ev->category == EVENT_SYSTEM && arcan_lua_grabthemefunction(ctx, "system")){
		lua_newtable(ctx);
		int top = arcan_lua_funtable(ctx, ev->kind);
	}
	if (ev->category == EVENT_IO && arcan_lua_grabthemefunction(ctx, "input")){
		int naxis;
		int top = arcan_lua_funtable(ctx, ev->kind);
		
		lua_pushstring(ctx, "kind");

		switch (ev->kind) {
			case EVENT_IO_AXIS_MOVE:
				lua_pushstring(ctx, "analog");
				lua_rawset(ctx, top);

				arcan_lua_tblstr(ctx, "source", ev->data.io.devkind == EVENT_IDEVKIND_MOUSE ? "mouse" : "joystick", top);
				arcan_lua_tblnum(ctx, "devid", ev->data.io.input.analog.devid, top);
				arcan_lua_tblnum(ctx, "subid", ev->data.io.input.analog.subid, top);
				arcan_lua_tblbool(ctx, "active", true, top); /* always active, just saves a conditional here and there */

			/* "stateful" data? */
				arcan_lua_tblbool(ctx, "relative", ev->data.io.input.analog.gotrel, top);

				lua_pushstring(ctx, "samples");
				lua_newtable(ctx);
					int top2 = lua_gettop(ctx);
					for (int i = 0; i < ev->data.io.input.analog.nvalues; i++) {
						lua_pushnumber(ctx, i + 1);
						lua_pushnumber(ctx, ev->data.io.input.analog.axisval[i]);
						lua_rawset(ctx, top2);
					}
				lua_rawset(ctx, top);
			break;

			case EVENT_IO_BUTTON_PRESS:
			case EVENT_IO_BUTTON_RELEASE:
			case EVENT_IO_KEYB_PRESS:
			case EVENT_IO_KEYB_RELEASE:
				lua_pushstring(ctx, "digital");
				lua_rawset(ctx, top);

				if (ev->data.io.devkind == EVENT_IDEVKIND_KEYBOARD) {
					arcan_lua_tblbool(ctx, "translated", true, top);
					arcan_lua_tblnum(ctx, "number", ev->data.io.input.translated.scancode, top);
					arcan_lua_tblnum(ctx, "keysym", ev->data.io.input.translated.keysym, top);
					arcan_lua_tblnum(ctx, "modifiers", ev->data.io.input.translated.modifiers, top);
					arcan_lua_tblnum(ctx, "devid", ev->data.io.input.translated.devid, top);
					arcan_lua_tblnum(ctx, "subid", ev->data.io.input.translated.subid, top);
					arcan_lua_tblstr(ctx, "utf8", to_utf8(ev->data.io.input.translated.subid), top);
					arcan_lua_tblbool(ctx, "active", ev->kind == EVENT_IO_KEYB_PRESS ? true : false, top);
					arcan_lua_tblstr(ctx, "device", "translated", top);
					arcan_lua_tblstr(ctx, "subdevice", "keyboard", top);
				}
				else if (ev->data.io.devkind == EVENT_IDEVKIND_MOUSE || ev->data.io.devkind == EVENT_IDEVKIND_GAMEDEV) {
					arcan_lua_tblstr(ctx, "source", ev->data.io.devkind == EVENT_IDEVKIND_MOUSE ? "mouse" : "joystick", top);
					arcan_lua_tblbool(ctx, "translated", false, top);
					arcan_lua_tblnum(ctx, "devid", ev->data.io.input.digital.devid, top);
					arcan_lua_tblnum(ctx, "subid", ev->data.io.input.digital.subid, top);
 					arcan_lua_tblbool(ctx, "active", ev->data.io.input.digital.active, top);
				}
				else;
			break;

			default:
				arcan_warning("Engine -> Script Warning: ignoring IO event: %i\n", ev->kind);
		}

		arcan_lua_wraperr(ctx, lua_pcall(ctx, 1, 0, 0), "push event( input )");
	}
	else if (ev->category == EVENT_TIMER){
		arcan_lua_setglobalint(ctx, "CLOCK", ev->tickstamp);

		if (arcan_lua_grabthemefunction(ctx, "clock_pulse")) {
			lua_pushnumber(ctx, ev->tickstamp);
			lua_pushnumber(ctx, ev->data.timer.pulse_count);
			arcan_lua_wraperr(ctx, lua_pcall(ctx, 2, 0, 0), "event loop: clock pulse");
		}
	}
	else if (ev->category == EVENT_FRAMESERVER){
		bool gotfun;
		intptr_t dst_cb = 0;
		
		if (arcan_lua_grabthemefunction(ctx, "frameserver_event"))
			gotfun = true;
		else
			gotfun = (lua_pushnumber(ctx, 0), false);
		
		lua_pushvid(ctx, ev->data.frameserver.video);
		lua_newtable(ctx);
		int top = lua_gettop(ctx);
	
		switch(ev->kind){
#ifdef _DEBUG
/* this little hack will emit (in debug builds) high frequent status events each time a video or audio frame is requested */
			case EVENT_FRAMESERVER_BUFFERSTATUS: 
				arcan_lua_tblstr(ctx, "kind", "bufferstatus", top);
				arcan_lua_tblnum(ctx, "maxv", ev->data.frameserver.l_vbuffer, top);
				arcan_lua_tblnum(ctx, "maxa", ev->data.frameserver.l_abuffer, top);
				arcan_lua_tblnum(ctx, "curv", ev->data.frameserver.c_vbuffer, top);
				arcan_lua_tblnum(ctx, "cura", ev->data.frameserver.c_abuffer, top);
			break;
#endif

			case EVENT_FRAMESERVER_LOOPED :
				arcan_lua_tblstr(ctx, "kind", "frameserver_loop", top);
				dst_cb = ev->data.frameserver.otag;
			break;

			case EVENT_FRAMESERVER_TERMINATED : 
				arcan_lua_tblstr(ctx, "kind", "frameserver_terminated", top);
				dst_cb = ev->data.frameserver.otag;
			break;

			case EVENT_FRAMESERVER_RESIZED :
				arcan_lua_tblstr(ctx, "kind", "resized", top);
				arcan_lua_tblnum(ctx, "width", ev->data.frameserver.width, top); 
				arcan_lua_tblnum(ctx, "height", ev->data.frameserver.height, top);
				arcan_lua_tblnum(ctx, "mirrored", ev->data.frameserver.glsource, top);
				arcan_lua_tblnum(ctx, "source_audio", ev->data.frameserver.audio, top);
					
				dst_cb = ev->data.frameserver.otag;
			break;
		}

		if (dst_cb){
			lua_ctx_store.cb_source_tag = ev->data.frameserver.video;
			lua_ctx_store.cb_source_kind = CB_SOURCE_FRAMESERVER;
			lua_rawgeti(ctx, LUA_REGISTRYINDEX, dst_cb);
			lua_replace(ctx, 1);
			gotfun = true;
		}

		if (gotfun)
			arcan_lua_wraperr(ctx, lua_pcall(ctx, 2, 0, 0), "frameserver_event");
		else
			lua_settop(ctx, 0);
		
		lua_ctx_store.cb_source_kind = CB_SOURCE_NONE;
	}
	else if (ev->category == EVENT_VIDEO){
		intptr_t dst_cb = 0;
		arcan_vobject* srcobj;
		const char* evmsg = "video_event";
		const char* srcres = "";
		bool gotfun;
		
		if (arcan_lua_grabthemefunction(ctx, "video_event"))
/* due to the asynch- callback approach some additional checks are needed before bailing */
			gotfun = true;
		else
/* add placeholder if we find another function to call through */
			gotfun = (lua_pushnumber(ctx, 0), false);

		lua_pushvid(ctx, ev->data.video.source);
		lua_newtable(ctx);
		int top = lua_gettop(ctx);
			
		switch (ev->kind) {
		case EVENT_VIDEO_EXPIRE  : arcan_lua_tblstr(ctx, "kind", "expired", top); evmsg = "video_event(expire)"; break;
		case EVENT_VIDEO_SCALED  : arcan_lua_tblstr(ctx, "kind", "scaled", top); evmsg = "video_event(scale)"; break;
		case EVENT_VIDEO_MOVED   : arcan_lua_tblstr(ctx, "kind", "moved", top); evmsg = "video_event(move))"; break; 
		case EVENT_VIDEO_BLENDED : arcan_lua_tblstr(ctx, "kind", "blended", top); evmsg = "video_event(blend)"; break;
		case EVENT_VIDEO_ROTATED : arcan_lua_tblstr(ctx, "kind", "rotated", top); evmsg = "video_event(rotate)"; break;

		case EVENT_VIDEO_ASYNCHIMAGE_LOADED:
			evmsg = "video_event(asynchimg_loaded)";
			arcan_lua_tblstr(ctx, "kind", "loaded", top);
			arcan_lua_tblnum(ctx, "width", ev->data.video.constraints.w, top); 
			arcan_lua_tblnum(ctx, "height", ev->data.video.constraints.h, top); 
			dst_cb = (intptr_t) ev->data.video.data;

			if (dst_cb){
				evmsg = "video_event(asynchimg_loaded), callback";
				lua_ctx_store.cb_source_kind = CB_SOURCE_IMAGE;
			}
		break;
                
		case EVENT_VIDEO_ASYNCHIMAGE_LOAD_FAILED: 
			srcobj = arcan_video_getobject(ev->data.video.source);
			evmsg = "video_event(asynchimg_load_fail), callback";
			arcan_lua_tblstr(ctx, "kind", "load_failed", top); 
			arcan_lua_tblstr(ctx, "resource", srcobj && srcobj->default_frame.source ? srcobj->default_frame.source : "unknown", top); 
			arcan_lua_tblnum(ctx, "width", ev->data.video.constraints.w, top); 
			arcan_lua_tblnum(ctx, "height", ev->data.video.constraints.h, top);    
			dst_cb = (intptr_t) ev->data.video.data;

			if (dst_cb){
				evmsg = "video_event(asynchimg_load_fail), callback";
				lua_ctx_store.cb_source_kind = CB_SOURCE_IMAGE;
			}
		break;

		default:
			arcan_warning("Engine -> Script Warning: arcan_lua_pushevent(), unknown video event (%i)\n", ev->kind);
		}

		if (lua_ctx_store.cb_source_kind != CB_SOURCE_NONE){
			lua_ctx_store.cb_source_tag = ev->data.video.source;
			lua_rawgeti(ctx, LUA_REGISTRYINDEX, dst_cb);
			lua_replace(ctx, 1);
			gotfun = true;
		}

		if (gotfun)
			arcan_lua_wraperr(ctx, lua_pcall(ctx, 2, 0, 0), evmsg); 
		else
			lua_settop(ctx, 0);
		
		lua_ctx_store.cb_source_kind = CB_SOURCE_NONE;
	}
	else if (ev->category == EVENT_AUDIO && arcan_lua_grabthemefunction(ctx, "audio_event")){
		lua_pushaid(ctx, ev->data.video.source);
		lua_newtable(ctx);

		int top = lua_gettop(ctx);
		switch (ev->kind){
			case EVENT_AUDIO_BUFFER_UNDERRUN: arcan_lua_tblstr(ctx, "kind", "audio buffer underrun", top); break;
			case EVENT_AUDIO_GAIN_TRANSFORMATION_FINISHED: arcan_lua_tblstr(ctx, "kind", "gain transformed", top); break;
			case EVENT_AUDIO_PLAYBACK_FINISHED: arcan_lua_tblstr(ctx, "kind", "playback finished", top); break;
			case EVENT_AUDIO_PLAYBACK_ABORTED: arcan_lua_tblstr(ctx, "kind", "playback aborted", top); break;
			case EVENT_AUDIO_OBJECT_GONE: arcan_lua_tblstr(ctx, "kind", "gone", top); break;
			default:
				arcan_warning("Engine -> Script Warning: arcan_lua_pushevent(), unknown audio event (%i)\n", ev->kind);
		}
		arcan_lua_wraperr(ctx, lua_pcall(ctx, 2, 0, 0), "event loop: audio_event");
	}
}

/* item:image_parent, vid, vid */
int arcan_lua_imageparent(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	lua_pushnumber( ctx, arcan_video_findparent(id) );
	return 1;
}

/* item: image_parent, vid, vid */
int arcan_lua_validvid(lua_State* ctx)
{
	arcan_vobj_id res = (arcan_vobj_id) luaL_optnumber(ctx, 1, ARCAN_EID);
	
	if (res != ARCAN_EID && res != ARCAN_VIDEO_WORLDID)
		res -= lua_ctx_store.lua_vidbase;

	if (res < 0)
		res = ARCAN_EID;

	lua_pushboolean(ctx, arcan_video_findparent(res) != ARCAN_EID);
	return 1;
}

int arcan_lua_imagechildren(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	arcan_vobj_id child;
	unsigned ofs = 0, count = 1;


	lua_newtable(ctx);
	int top = lua_gettop(ctx);

	while( (child = arcan_video_findchild(id, ofs++)) != ARCAN_EID){
		lua_pushnumber(ctx, count++);
		lua_pushnumber(ctx, child);
		lua_rawset(ctx, top);
	}
	
	return 1;
}

int arcan_lua_framesetalloc(lua_State* ctx)
{
	arcan_vobj_id sid = luaL_checkvid(ctx, 1);
	unsigned num = luaL_checkint(ctx, 2);
	unsigned mode = luaL_optint(ctx, 3, ARCAN_FRAMESET_SPLIT);
	
	if (num > 0 && num < 256){
		arcan_video_allocframes(sid, num, mode);
	}
	
	return 0;
}

int arcan_lua_framesetcycle(lua_State* ctx)
{
	arcan_vobj_id sid = luaL_checkvid(ctx, 1);
	unsigned num = luaL_optint(ctx, 2, 0);
	arcan_video_framecyclemode(sid, num);
	return 0;
}

int arcan_lua_pushasynch(lua_State* ctx)
{
	arcan_vobj_id sid = luaL_checkvid(ctx, 1);
	arcan_video_pushasynch(sid);
	return 0;
}

int arcan_lua_activeframe(lua_State* ctx)
{
	arcan_vobj_id sid = luaL_checkvid(ctx, 1);
	unsigned num = luaL_checkint(ctx, 2);
	
	arcan_video_setactiveframe(sid, num);

	return 0;
}

int arcan_lua_imageasframe(lua_State* ctx)
{
	arcan_vobj_id sid = luaL_checkvid(ctx, 1);
	arcan_vobj_id did = luaL_checkvid(ctx, 2);
	unsigned num = luaL_checkint(ctx, 3);
	unsigned detach = luaL_optint(ctx, 4, FRAMESET_NODETACH);
	
	if (detach != FRAMESET_DETACH && detach != FRAMESET_NODETACH)
		arcan_fatal("set_image_as_frame() -- invalid 4th argument (should be FRAMESET_DETACH or FRAMESET_NODETACH)\n");

	arcan_errc errc;
	arcan_vobj_id vid = arcan_video_setasframe(sid, did, num, detach == FRAMESET_DETACH, &errc);

	if (errc == ARCAN_OK)
		lua_pushvid(ctx, vid != sid ? vid : ARCAN_EID);
	else
		lua_pushvid(ctx, ARCAN_EID);
	
	return 1;
}

int arcan_lua_linkimage(lua_State* ctx)
{
	arcan_vobj_id sid = luaL_checkvid(ctx, 1);
	arcan_vobj_id did = luaL_checkvid(ctx, 2);
	enum arcan_transform_mask lmask = MASK_SCALE | MASK_OPACITY | MASK_POSITION | MASK_ORIENTATION | MASK_LIVING;

	arcan_errc rv = arcan_video_linkobjs(sid, did, lmask);
	lua_pushboolean(ctx, rv == ARCAN_OK);
	
	return 1;
}

static inline int pushprop(lua_State* ctx, surface_properties prop, unsigned short zv)
{
	lua_createtable(ctx, 0, 6);

	lua_pushstring(ctx, "x");
	lua_pushnumber(ctx, prop.position.x);
	lua_rawset(ctx, -3);

	lua_pushstring(ctx, "y");
	lua_pushnumber(ctx, prop.position.y);
	lua_rawset(ctx, -3);

	lua_pushstring(ctx, "z");
	lua_pushnumber(ctx, prop.position.z);
	lua_rawset(ctx, -3);

	lua_pushstring(ctx, "width");
	lua_pushnumber(ctx, prop.scale.x);
	lua_rawset(ctx, -3);

	lua_pushstring(ctx, "height");
	lua_pushnumber(ctx, prop.scale.y);
	lua_rawset(ctx, -3);

	lua_pushstring(ctx, "angle");
	lua_pushnumber(ctx, prop.rotation.roll);
	lua_rawset(ctx, -3);

	lua_pushstring(ctx, "roll");
	lua_pushnumber(ctx, prop.rotation.roll);
	lua_rawset(ctx, -3);
	
	lua_pushstring(ctx, "pitch");
	lua_pushnumber(ctx, prop.rotation.pitch);
	lua_rawset(ctx, -3);
	
	lua_pushstring(ctx, "yaw");
	lua_pushnumber(ctx, prop.rotation.yaw);
	lua_rawset(ctx, -3);
	
	lua_pushstring(ctx, "opacity");
	lua_pushnumber(ctx, prop.opa);
	lua_rawset(ctx, -3);

	lua_pushstring(ctx, "order");
	lua_pushnumber(ctx, zv);
	lua_rawset(ctx, -3);

	return 1;
}

int arcan_lua_loadmesh(lua_State* ctx)
{
    arcan_vobj_id did = luaL_checkvid(ctx, 1);
    unsigned nmaps = luaL_optnumber(ctx, 3, 1);
    char* path = findresource(luaL_checkstring(ctx, 2), ARCAN_RESOURCE_SHARED | ARCAN_RESOURCE_THEME);

    if (path)
        arcan_3d_addmesh(did, path, nmaps);
    
    free(path);
    return 0;
}

int arcan_lua_buildmodel(lua_State* ctx)
{
	arcan_vobj_id id = ARCAN_EID;
	id = arcan_3d_emptymodel();
	
	if (id != ARCAN_EID)
		arcan_video_objectopacity(id, 0, 0);
	
	lua_pushvid(ctx, id);
	return 1;
}

/* item:build_3dplane, minx, mind, endx, endd, hdens, ddens, nil */
int arcan_lua_buildplane(lua_State* ctx)
{
	float minx = luaL_checknumber(ctx, 1);
	float mind = luaL_checknumber(ctx, 2);
	float endx = luaL_checknumber(ctx, 3);
	float endd = luaL_checknumber(ctx, 4);
	float starty = luaL_checknumber(ctx, 5);
	float hdens = luaL_checknumber(ctx, 6);
	float ddens = luaL_checknumber(ctx, 7);
	unsigned nmaps = luaL_optnumber(ctx, 8, 1);
	
	lua_pushvid(ctx, arcan_3d_buildplane(minx, mind, endx, endd, starty, hdens, ddens, nmaps));
	return 1;
}

int arcan_lua_camtag(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	unsigned camtag = luaL_optnumber(ctx, 2, 0);
	arcan_errc rv = arcan_3d_camtag_parent(camtag, id);

	if (rv == ARCAN_OK)
		lua_pushboolean(ctx, true);
	else
		lua_pushboolean(ctx, false);
	
	return 1;
}

int arcan_lua_getimageprop(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	unsigned dt = luaL_optnumber(ctx, 2, 0);
	surface_properties prop;
	prop = dt > 0 ? arcan_video_properties_at(id, dt) : arcan_video_current_properties(id);

	return pushprop(ctx, prop, arcan_video_getzv(id));
}

int arcan_lua_getimageresolveprop(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	unsigned dt = luaL_optnumber(ctx, 2, 0);
	surface_properties prop = arcan_video_resolve_properties(id);

	return pushprop(ctx, prop, arcan_video_getzv(id));
}

int arcan_lua_getimageinitprop(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	surface_properties prop = arcan_video_initial_properties(id);

	return pushprop(ctx, prop, arcan_video_getzv(id));
}

int arcan_lua_getimagestorageprop(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	img_cons cons = arcan_video_storage_properties(id);
	lua_createtable(ctx, 0, 6);

	lua_pushstring(ctx, "bpp");
	lua_pushnumber(ctx, cons.bpp);
	lua_rawset(ctx, -3);

	lua_pushstring(ctx, "height");
	lua_pushnumber(ctx, cons.h);
	lua_rawset(ctx, -3);
	
	lua_pushstring(ctx, "width");
	lua_pushnumber(ctx, cons.w);
	lua_rawset(ctx, -3);
	
	return 1;
}

int arcan_lua_storekey(lua_State* ctx)
{
	const char* key = luaL_checkstring(ctx, 1);
	const char* name = luaL_checkstring(ctx, 2);

	arcan_db_theme_kv(dbhandle, arcan_themename, key, name);

	return 0;
}

int arcan_lua_getkey(lua_State* ctx)
{
	const char* key = luaL_checkstring(ctx, 1);
	char* val = arcan_db_theme_val(dbhandle, arcan_themename, key);

	if (val) {
		lua_pushstring(ctx, val);
		free(val);
	}
	else
		lua_pushnil(ctx);

	return 1;
}

static int get_linenumber(lua_State* ctx)
{
	lua_Debug ar;
  lua_getstack(ctx, 1, &ar);
	lua_getinfo(ctx, "Sln", &ar);
	return -1;
}

static void dump_call_trace(lua_State* ctx)
{
#ifdef LUA_51
		printf("-- call trace -- \n");
		lua_getfield(ctx, LUA_GLOBALSINDEX, "debug");
		if (!lua_istable(ctx, -1))
			lua_pop(ctx, 1);
		else {
			lua_getfield(ctx, -1, "traceback");
			if (!lua_isfunction(ctx, -1))
				lua_pop(ctx, 2);
			else {
				lua_pushvalue(ctx, 1);
				lua_pushinteger(ctx, 2);
				lua_call(ctx, 2, 1);
			}
	}
#endif
}

/* dump argument stack, stack trace are shown only when --debug is set */
static void dump_stack(lua_State* ctx)
{
	int top = lua_gettop(ctx);
	printf("-- stack dump --\n");
	
	for (int i = 1; i <= top; i++) {
		int t = lua_type(ctx, i);

		switch (t) {
			case LUA_TBOOLEAN:
				fprintf(stdout, lua_toboolean(ctx, i) ? "true" : "false");
				break;
			case LUA_TSTRING:
				fprintf(stdout, "`%s'", lua_tostring(ctx, i));
				break;
			case LUA_TNUMBER:
				fprintf(stdout, "%g", lua_tonumber(ctx, i));
				break;
			default:
				fprintf(stdout, "%s", lua_typename(ctx, t));
				break;
		}
		fprintf(stdout, "  ");
	}
	
	fprintf(stdout, "\n");
}

int arcan_lua_gamefamily(lua_State* ctx)
{
	const int gameid = luaL_checkinteger(ctx, 1);
	arcan_dbh_res res = arcan_db_game_siblings(dbhandle, NULL, gameid);
	int rv = 0;

	if (res.kind == 0 && res.data.strarr) {
		char** curr = res.data.strarr;
		unsigned int count = 1; /* 1 indexing, seriously LUA ... */

		curr = res.data.strarr;

		lua_newtable(ctx);
		int top = lua_gettop(ctx);

		while (*curr) {
			lua_pushnumber(ctx, count++);
			lua_pushstring(ctx, *curr++);
			lua_rawset(ctx, top);
		}

		rv = 1;
		arcan_db_free_res(dbhandle, res);
	}

	return rv;
}

static int push_stringres(lua_State* ctx, arcan_dbh_res res)
{
	int rv = 0;

	if (res.kind == 0 && res.data.strarr) {
		char** curr = res.data.strarr;
		unsigned int count = 1; /* 1 indexing, seriously LUA ... */

		curr = res.data.strarr;

		lua_newtable(ctx);
		int top = lua_gettop(ctx);

		while (*curr) {
			lua_pushnumber(ctx, count++);
			lua_pushstring(ctx, *curr++);
			lua_rawset(ctx, top);
		}

		rv = 1;
	}

	return rv;
}

int arcan_lua_kbdrepeat(lua_State* ctx)
{
	unsigned rrate = luaL_checknumber(ctx, 1);
	arcan_event_keyrepeat(arcan_event_defaultctx(), rrate);
	return 0;
}

int arcan_lua_3dorder(lua_State* ctx)
{
	unsigned first = luaL_checknumber(ctx, 1) == ORDER_FIRST;
	arcan_video_3dorder(-first);
	return 0;
}

int arcan_lua_mousegrab(lua_State* ctx)
{
	lua_ctx_store.grab = !lua_ctx_store.grab;
	SDL_WM_GrabInput( lua_ctx_store.grab ? SDL_GRAB_ON : SDL_GRAB_OFF );
	return 0;
}

int arcan_lua_gettargets(lua_State* ctx)
{
	int rv = 0;

	arcan_dbh_res res = arcan_db_targets(dbhandle);
	rv += push_stringres(ctx, res);
	arcan_db_free_res(dbhandle, res);

	return rv;
}

int arcan_lua_getgenres(lua_State* ctx)
{
	int rv = 0;
	arcan_dbh_res res = arcan_db_genres(dbhandle, false);
	rv = push_stringres(ctx, res);
	arcan_db_free_res(dbhandle, res);

	res = arcan_db_genres(dbhandle, true);
	rv += push_stringres(ctx, res);
	arcan_db_free_res(dbhandle, res);

	return rv;
}

int arcan_lua_togglefs(lua_State* ctx)
{
	arcan_video_fullscreen();
	return 0;
}

int arcan_lua_fillsurface(lua_State* ctx)
{
	img_cons cons = {.w = 32, .h = 32, .bpp = 4};

	int desw = luaL_checknumber(ctx, 1);
	int desh = luaL_checknumber(ctx, 2);

	uint8_t r = luaL_checknumber(ctx, 3);
	uint8_t g = luaL_checknumber(ctx, 4);
	uint8_t b = luaL_checknumber(ctx, 5);
	
	cons.w = luaL_optnumber(ctx, 6, 8);
	cons.h = luaL_optnumber(ctx, 7, 8);

	uint8_t* buf = (uint8_t*) malloc(cons.w * cons.h * 4);
	uint32_t* cptr = (uint32_t*) buf;

	for (int y = 0; y < cons.h; y++)
		for (int x = 0; x < cons.w; x++)
			RGBPACK(b, g, r, cptr++);

	arcan_vobj_id id = arcan_video_rawobject(buf, cons.w * cons.h * 4, cons, desw, desh, 0);
	lua_pushvid(ctx, id);

	return 1;
}

#if _WIN32
/* mingw headers miss this one for some reason, but it's still in the header */
int random(void);
#endif

/* not intendend to be used as a low-frequency noise function (duh) */
int arcan_lua_randomsurface(lua_State* ctx)
{
	int desw = abs( luaL_checknumber(ctx, 1) );
	int desh = abs( luaL_checknumber(ctx, 2) );
	img_cons cons = {.w = desw, .h = desh, .bpp = 4};

	uint32_t* cptr = (uint32_t*) malloc(desw * desh * 4);
	uint8_t* buf = (uint8_t*) cptr;
	
	for (int y = 0; y < cons.h; y++)
		for (int x = 0; x < cons.w; x++){
			unsigned char val = 20 + random() % 235;
			RGBPACK(val, val, val, cptr++);
		}

	arcan_vobj_id id = arcan_video_rawobject(buf, desw * desh * 4, cons, desw, desh, 0);
	lua_pushvid(ctx, id);

	return 1;
}

int arcan_lua_getcmdline(lua_State* ctx)
{
	int gameid = 0;
	arcan_errc status = ARCAN_OK;
	
	if (lua_isstring(ctx, 1)){
		gameid = arcan_db_gameid(dbhandle, luaL_checkstring(ctx, 1), &status); 
	}
	else
		gameid = luaL_checknumber(ctx, 1); 
	
	if (status != ARCAN_OK)
		return 0;
	
	int internal = luaL_optnumber(ctx, 2, 1);

	arcan_dbh_res res = arcan_db_launch_options(dbhandle, gameid, internal == 0);
	int rv = push_stringres(ctx, res);

	arcan_db_free_res(dbhandle, res);
	return rv;
}


void pushgame(lua_State* ctx, arcan_db_game* curr)
{
	int top = lua_gettop(ctx);
	
	lua_pushstring(ctx, "gameid");
	lua_pushnumber(ctx, curr->gameid);
	lua_rawset(ctx, top);
	lua_pushstring(ctx, "targetid");
	lua_pushnumber(ctx, curr->targetid);
	lua_rawset(ctx, top);
	lua_pushstring(ctx, "title");
	lua_pushstring(ctx, curr->title);
	lua_rawset(ctx, top);
	lua_pushstring(ctx, "genre");
	lua_pushstring(ctx, curr->genre);
	lua_rawset(ctx, top);
	lua_pushstring(ctx, "subgenre");
	lua_pushstring(ctx, curr->subgenre);
	lua_rawset(ctx, top);
	lua_pushstring(ctx, "setname");
	lua_pushstring(ctx, curr->setname);
	lua_rawset(ctx, top);
	lua_pushstring(ctx, "buttons");
	lua_pushnumber(ctx, curr->n_buttons);
	lua_rawset(ctx, top);
	lua_pushstring(ctx, "manufacturer");
	lua_pushstring(ctx, curr->manufacturer);
	lua_rawset(ctx, top);
	lua_pushstring(ctx, "players");
	lua_pushnumber(ctx, curr->n_players);
	lua_rawset(ctx, top);
	lua_pushstring(ctx, "input");
	lua_pushnumber(ctx, curr->input);
	lua_rawset(ctx, top);
	lua_pushstring(ctx, "year");
	lua_pushnumber(ctx, curr->year);
	lua_rawset(ctx, top);
	lua_pushstring(ctx, "target");
	lua_pushstring(ctx, curr->targetname);
	lua_rawset(ctx, top);
	lua_pushstring(ctx, "launch_counter");
	lua_pushnumber(ctx, curr->launch_counter);
	lua_rawset(ctx, top);
	lua_pushstring(ctx, "system");
	lua_pushstring(ctx, curr->system);
	lua_rawset(ctx, top);
}

/* sort-order (asc or desc),
 * year
 * n_players
 * n_buttons
 * genre
 * subgenre
 * manufacturer */
int arcan_lua_filtergames(lua_State* ctx)
{
	int year = -1;
	int n_players = -1;
	int n_buttons = -1;
	int input = 0;
	char* title = NULL;
	char* genre = NULL;
	char* subgenre = NULL;
	char* target = NULL;
	char* manufacturer = NULL;
	char* system = NULL;
	
	int rv = 0;
	int limit = 0;
	int offset = 0;

/* reason for all this is that lua_tostring MAY return NULL,
 * and if it doesn't, the string can be subject to garbage collection after POP,
 * thus need a working copy */
	luaL_checktype(ctx, 1, LUA_TTABLE);
	char* tv;
	/* populate all arguments */
	lua_pushstring(ctx, "year");
	lua_gettable(ctx, -2);
	year = lua_tonumber(ctx, -1);
	lua_pop(ctx, 1);

	lua_pushstring(ctx, "limit");
	lua_gettable(ctx, -2);
	limit = lua_tonumber(ctx, -1);
	lua_pop(ctx, 1);
	
	lua_pushstring(ctx, "offset");
	lua_gettable(ctx, -2);
	offset= lua_tonumber(ctx, -1);
	lua_pop(ctx, 1);
	
	lua_pushstring(ctx, "input");
	lua_gettable(ctx, -2);
	input = lua_tonumber(ctx, -1);
	lua_pop(ctx, 1);

	lua_pushstring(ctx, "players");
	lua_gettable(ctx, -2);
	n_players = lua_tonumber(ctx, -1);
	lua_pop(ctx, 1);

	lua_pushstring(ctx, "buttons");
	lua_gettable(ctx, -2);
	n_buttons = lua_tonumber(ctx, -1);
	lua_pop(ctx, 1);

	lua_pushstring(ctx, "title");
	lua_gettable(ctx, -2);
	title = _n_strdup(lua_tostring(ctx, -1), NULL);
	lua_pop(ctx, 1);

	lua_pushstring(ctx, "genre");
	lua_gettable(ctx, -2);
	genre = _n_strdup(lua_tostring(ctx, -1), NULL);
	lua_pop(ctx, 1);

	lua_pushstring(ctx, "subgenre");
	lua_gettable(ctx, -2);
	subgenre = _n_strdup(lua_tostring(ctx, -1), NULL);
	lua_pop(ctx, 1);

	lua_pushstring(ctx, "target");
	lua_gettable(ctx, -2);
	target = _n_strdup(lua_tostring(ctx, -1), NULL);
	lua_pop(ctx, 1);
	
	lua_pushstring(ctx, "system");
	lua_gettable(ctx, -2);
	system = _n_strdup(lua_tostring(ctx, -1), NULL);
	lua_pop(ctx, 1);

	lua_pushstring(ctx, "manufacturer");
	lua_gettable(ctx, -2);
	manufacturer = _n_strdup(lua_tostring(ctx, -1), NULL);
	lua_pop(ctx, 1);
	
	arcan_dbh_res dbr = arcan_db_games(dbhandle, year, input, n_players, n_buttons, title, genre, subgenre, target, system, manufacturer, offset, limit);
	free(genre);
	free(subgenre);
	free(title);
	free(target);
	free(system);
	free(manufacturer);

	if (dbr.kind == 1 && dbr.count > 0) {
		arcan_db_game** curr = dbr.data.gamearr;
		int count = 1;

		rv = 1;
	/* table of tables .. wtb ruby yield */
		lua_newtable(ctx);
		int rtop = lua_gettop(ctx);

		while (*curr) {
			lua_pushnumber(ctx, count++);
			lua_newtable(ctx);
			pushgame(ctx, *curr);
			lua_rawset(ctx, rtop);
			curr++;
		}
	}
	else {
		arcan_lua_wraperr(ctx, 0, "arcan_lua_filtergames(), requires argument table");
	}

	arcan_db_free_res(dbhandle, dbr);
	return rv;
}

int arcan_lua_warning(lua_State* ctx)
{
	char* msg = (char*) luaL_checkstring(ctx, 1);
	if (strlen(msg) > 0)
		arcan_warning("%s\n", msg);
	
	return 0;
}

int arcan_lua_shutdown(lua_State *ctx)
{
	arcan_event ev = {.category = EVENT_SYSTEM, .kind = EVENT_SYSTEM_EXIT};
	arcan_event_enqueue(arcan_event_defaultctx(), &ev);

	const char* str = luaL_optstring(ctx, 1, "");
	if (strlen(str) > 0)
		arcan_warning("%s\n", str);
	
	return 0;
}

int arcan_lua_getgame(lua_State* ctx)
{
	const char* game = luaL_checkstring(ctx, 1);
	int rv = 0;

	arcan_dbh_res dbr = arcan_db_games(dbhandle, 
		0, 0, 0, 0, /* year, input, players, buttons */
		game, NULL, NULL, NULL, NULL, NULL, /*title, genre, subgenre, target, system, manufacturer */
		0, 0); /* offset, limit */
	
	if (dbr.kind == 1 && dbr.count > 0 && dbr.data.gamearr && (*dbr.data.gamearr)) {
		arcan_db_game** curr = dbr.data.gamearr;
	/* table of tables .. wtb ruby yield */
		lua_newtable(ctx);
		int rtop = lua_gettop(ctx);
		int count = 1;
		
		while (*curr) {
			lua_pushnumber(ctx, count++);
			lua_newtable(ctx);
			pushgame(ctx, *curr);
			lua_rawset(ctx, rtop);
			curr++;
		}

		rv = 1;
		arcan_db_free_res(dbhandle, dbr);
	}

	return rv;
}

void arcan_lua_panic(lua_State* ctx)
{
	lua_ctx_store.debug = 2;

	if (!lua_ctx_store.cb_source_kind == CB_SOURCE_NONE){
		char vidbuf[64];
		sprintf(vidbuf, "script error in callback for VID (%lld)", lua_ctx_store.lua_vidbase + lua_ctx_store.cb_source_tag);
		arcan_lua_wraperr(ctx, -1, vidbuf); 
	} else 
		arcan_lua_wraperr(ctx, -1, "(panic)");
	
	arcan_fatal("LUA VM is in an unrecoverable panic state.\n");
}


extern void arcan_debug_tracetag_dump();

void arcan_lua_wraperr(lua_State* ctx, int errc, const char* src)
{
	if (errc == 0)
		return;

	const char* mesg = luaL_optstring(ctx, 1, "unknown");
	if (lua_ctx_store.debug){
		arcan_warning("Warning: arcan_lua_wraperr((), %s, from %s\n", mesg, src);

		arcan_debug_tracetag_dump();
		
		if (lua_ctx_store.debug > 1)
			dump_call_trace(ctx);
		
		if (lua_ctx_store.debug > 0)
			dump_stack(ctx);

		if (!(lua_ctx_store.debug > 2))
			arcan_fatal("Fatal: arcan_lua_wraperr()\n");
		
	}
	else{
		while ( arcan_video_popcontext() < CONTEXT_STACK_LIMIT -1);
		arcan_fatal("Fatal: arcan_lua_wraperr(), %s, from %s\n", mesg, src);
	}
}

struct globs{
	lua_State* ctx;
	int top;
	int index;
};

static void globcb(char* arg, void* tag)
{
	struct globs* bptr = (struct globs*) tag;
	lua_pushnumber(bptr->ctx, bptr->index++);
	lua_pushstring(bptr->ctx, arg);
	lua_rawset(bptr->ctx, bptr->top);
}

int arcan_lua_globresource(lua_State* ctx)
{
	struct globs bptr = {
		.ctx = ctx,
		.index = 1
	};

	char* label = (char*) luaL_checkstring(ctx, 1);
	int mask = luaL_optinteger(ctx, 2, ARCAN_RESOURCE_THEME | ARCAN_RESOURCE_SHARED);

	lua_newtable(ctx);
	bptr.top = lua_gettop(ctx);
	arcan_glob(label, mask, globcb, &bptr);

	return 1;
}

int arcan_lua_resource(lua_State* ctx)
{
	const char* label = luaL_checkstring(ctx, 1);
	int mask = luaL_optinteger(ctx, 2, ARCAN_RESOURCE_THEME | ARCAN_RESOURCE_SHARED);
	char* res = findresource(label, mask);
	lua_pushstring(ctx, res);
	free(res);
	return 1;
}

void arcan_lua_callvoidfun(lua_State* ctx, const char* fun)
{
	if ( arcan_lua_grabthemefunction(ctx, fun) )
		arcan_lua_wraperr(ctx,
	                  lua_pcall(ctx, 0, 0, 0),
	                  fun);
}

int arcan_lua_getqueueopts(lua_State* ctx)
{
	unsigned short rv[4];
	arcan_frameserver_queueopts( &rv[0], &rv[1], &rv[2], &rv[3] );
	lua_pushnumber(ctx, rv[0]);
	lua_pushnumber(ctx, rv[1]);
	lua_pushnumber(ctx, rv[2]);
	lua_pushnumber(ctx, rv[3]);

	return 3;
}

int arcan_lua_setqueueopts(lua_State* ctx)
{
	unsigned short vcellc = luaL_checknumber(ctx, 1);
	unsigned short acellc = luaL_checknumber(ctx, 2);
	unsigned short abufs = luaL_checknumber(ctx, 3);
	unsigned short presilence = luaL_optnumber(ctx, 4, ARCAN_FRAMESERVER_PRESILENCE);
	
	arcan_frameserver_queueopts_override( vcellc, acellc, abufs, presilence );
	return 0;
}

static bool use_loader(char* fname)
{
	char* ext = strrchr( fname, '.' );
	if (!ext) return false;
	
/* there are prettier ways to do this . . . */
	return (strcasecmp(ext, ".so") == 0) || (strcasecmp(ext, ".dll") == 0) ? true : false;
}

int arcan_lua_targetlaunch_capabilities(lua_State* ctx)
{
	char* targetname = strdup( luaL_checkstring(ctx, 1) );
	char* targetexec = arcan_db_targetexec(dbhandle, targetname);
	char* resourcestr = targetexec ? arcan_find_resource_path(targetexec, "targets", ARCAN_RESOURCE_SHARED) : NULL;

	unsigned rv = 0;

	if (resourcestr){
		lua_newtable(ctx);
		int top = lua_gettop(ctx);
		
/* currently, this means frameserver / libretro interface
 * so these capabilities are hard-coded rather than queried */
		if (use_loader(resourcestr)){
			arcan_lua_tblbool(ctx, "external_launch", false, top);
			arcan_lua_tblbool(ctx, "internal_launch", true, top);
			arcan_lua_tblbool(ctx, "snapshot", true, top);
			arcan_lua_tblbool(ctx, "rewind", false, top);
			arcan_lua_tblbool(ctx, "suspend", false, top);
			arcan_lua_tblbool(ctx, "reset", true, top);
			arcan_lua_tblnum(ctx, "ports", 4, top);
		} else {
/* the plan is to extend the internal launch support with a probe (sortof prepared for in the build-system)
 * to check how the target is linked, which dependencies it has etc. */
			arcan_lua_tblbool(ctx, "external_launch", true, top);
			if (strcmp(internal_launch_support(), "NO SUPPORT") == 0 ||
				(strcmp(internal_launch_support(), "PARTIAL SUPPORT") == 0 && arcan_libpath == NULL))
				arcan_lua_tblbool(ctx, "internal_launch", false, top);
			else
				arcan_lua_tblbool(ctx, "internal_launch", true, top);
			
			arcan_lua_tblbool(ctx, "reset", false, top);
			arcan_lua_tblbool(ctx, "snapshot", false, top);
			arcan_lua_tblbool(ctx, "rewind", false, top);
			arcan_lua_tblbool(ctx, "suspend", false, top);
			arcan_lua_tblnum(ctx, "ports", 0, top);
		}
		
		rv = 1;
	}
	
	free(targetname);
	free(targetexec);
	free(resourcestr);

	return rv;
}

static inline bool tgtevent(arcan_vobj_id dst, arcan_event ev)
{
	vfunc_state* state = arcan_video_feedstate(dst);

	if (state && state->tag == ARCAN_TAG_FRAMESERV && state->ptr){
		arcan_frameserver* fsrv = (arcan_frameserver*) state->ptr;
		arcan_frameserver_pushevent( fsrv, &ev );
		return true;
	}
	
	return false;
}

int arcan_lua_targetportcfg(lua_State* ctx)
{
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1);
	unsigned tgtport  = luaL_checkinteger(ctx, 2);
	unsigned tgtkind  = luaL_checkinteger(ctx, 3);
	
	arcan_event ev = {
		.category = EVENT_TARGET,
		.kind = TARGET_COMMAND_SETIODEV};

	ev.data.target.ioevs[0].iv = tgtport;
	ev.data.target.ioevs[1].iv = tgtkind;
	
	tgtevent(tgt, ev);
	
	return 0;
}

int arcan_lua_targetskipmodecfg(lua_State* ctx)
{
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1);
	int skipval       = luaL_checkinteger(ctx, 2);
	if (skipval < -1) return 0;	
	
	arcan_event ev = {
		.category = EVENT_TARGET,
		.kind = TARGET_COMMAND_FRAMESKIP
	};

	ev.data.target.ioevs[0].iv = skipval;
	tgtevent(tgt, ev);
	
	return 0;
}

int arcan_lua_targetrestore(lua_State* ctx)
{
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1);
	const char* snapkey = luaL_checkstring(ctx, 2);

	vfunc_state* state = arcan_video_feedstate(tgt);
	if (state && state->tag == ARCAN_TAG_FRAMESERV && state->ptr){
		int fd = fmt_open(O_RDONLY, S_IRWXU, "%s/savestates/%s", arcan_resourcepath, snapkey);
		if (-1 != fd){
			arcan_frameserver* fsrv = (arcan_frameserver*) state->ptr;
			
			if ( ARCAN_OK == arcan_frameserver_pushfd( fsrv, fd ) ){
				arcan_event ev = {
					.category = EVENT_TARGET,
					.kind = TARGET_COMMAND_RESTORE };
				arcan_frameserver_pushevent( fsrv, &ev );
			
				lua_pushboolean(ctx, true);
				return 1;
			}
			else; /* note that this will leave an empty statefile in the filesystem */
		}
	}
	lua_pushboolean(ctx, false);

	return 1;
}

int arcan_lua_targetlinewidth(lua_State* ctx)
{
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1);

	float lsz = luaL_checknumber(ctx, 2);
	
	arcan_event ev = {
			.category = EVENT_TARGET,
			.kind = TARGET_COMMAND_VECTOR_LINEWIDTH,
			.data.target.ioevs[0].fv = lsz
	};
	
	tgtevent(tgt, ev);
	
	return 0;
}

int arcan_lua_targetpointsize(lua_State* ctx)
{
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1);

	float psz = luaL_checknumber(ctx, 2);
	
	arcan_event ev = {
			.category = EVENT_TARGET,
			.kind = TARGET_COMMAND_VECTOR_POINTSIZE,
			.data.target.ioevs[0].fv = psz
	};
	
	tgtevent(tgt, ev);
	
	return 0;
}

int arcan_lua_targetpostfilter(lua_State* ctx)
{
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1);
	int filtertype = luaL_checknumber(ctx, 2);
	
	if (filtertype != POSTFILTER_NTSC && filtertype != POSTFILTER_OFF)
		arcan_warning("arcan_lua_targetpostfilter() -- unknown filter (%d) specified.\n", filtertype);
	else {
		arcan_event ev = {
			.category    = EVENT_TARGET,
			.kind        = TARGET_COMMAND_NTSCFILTER
		};
	
		ev.data.target.ioevs[0].iv = filtertype == POSTFILTER_NTSC;
		
		tgtevent(tgt, ev);
	}
	
	return 0;
}

int arcan_lua_targetpostfilterargs(lua_State* ctx)
{
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1);
	int group = luaL_checknumber(ctx, 2);
	float v1  = luaL_optnumber(ctx, 3, 0.0);
	float v2  = luaL_optnumber(ctx, 3, 0.0);
	float v3  = luaL_optnumber(ctx, 3, 0.0);
		
	arcan_event ev = {
		.category    = EVENT_TARGET,
		.kind        = TARGET_COMMAND_NTSCFILTER_ARGS
	};
	
	ev.data.target.ioevs[0].iv = group;
	ev.data.target.ioevs[1].fv = v1;
	ev.data.target.ioevs[2].fv = v2;
	ev.data.target.ioevs[3].fv = v3;
		
	tgtevent(tgt, ev);
	
	return 0;
}

int arcan_lua_targetstepframe(lua_State* ctx)
{
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1);
	int nframes = luaL_checknumber(ctx, 2);
	if (nframes == 0) return 0;
	
	arcan_event ev = {
			.category = EVENT_TARGET,
			.kind = TARGET_COMMAND_STEPFRAME
	};
	ev.data.target.ioevs[0].iv = nframes;
	
	tgtevent(tgt, ev);
	
	return 0;
}

int arcan_lua_targetsnapshot(lua_State* ctx)
{
	arcan_vobj_id tgt = luaL_checkvid(ctx, 1);
	const char* snapkey = luaL_checkstring(ctx, 2);
	bool gotval = false;

	vfunc_state* state = arcan_video_feedstate(tgt);
	if (state && state->tag == ARCAN_TAG_FRAMESERV && state->ptr){

		int fd = fmt_open(O_CREAT | O_WRONLY | O_TRUNC, S_IRWXU, "%s/savestates/%s", arcan_resourcepath, snapkey);
		if (-1 != fd){
			if ( ARCAN_OK == arcan_frameserver_pushfd( (arcan_frameserver*) state->ptr, fd ) ){
				arcan_event ev = {
					.category = EVENT_TARGET,
					.kind = TARGET_COMMAND_STORE };
				arcan_frameserver_pushevent( (arcan_frameserver*) state->ptr, &ev );
	
				lua_pushboolean(ctx, true);
				gotval = true;
			}
		}
	}

	if (!gotval)
		lua_pushboolean(ctx, false);

	return 1;
}

int arcan_lua_targetreset(lua_State* ctx)
{
	arcan_vobj_id vid = luaL_checkvid(ctx, 1);
	arcan_event ev = {
		.kind = TARGET_COMMAND_RESET,
		.category = EVENT_TARGET
	};

	tgtevent(vid, ev);
	
	return 0;
}

int arcan_lua_targetlaunch(lua_State* ctx)
{
	int gameid = luaL_checknumber(ctx, 1);
	arcan_errc status = ARCAN_OK;
	
	if (status != ARCAN_OK)
		return 0;
	
	int internal = luaL_checkint(ctx, 2) == 1;
	intptr_t ref = (intptr_t) 0;
	int rv = 0;

	if (lua_isfunction(ctx, 3) && !lua_iscfunction(ctx, 3)){
		lua_pushvalue(ctx, 3);
		ref = luaL_ref(ctx, LUA_REGISTRYINDEX);
	}

	/* see if we know what the game is */
	arcan_dbh_res cmdline = arcan_db_launch_options(dbhandle, gameid, internal);
	if (cmdline.kind == 0){
		char* resourcestr = arcan_find_resource_path(cmdline.data.strarr[0], "targets", ARCAN_RESOURCE_SHARED);
		if (!resourcestr)
			goto cleanup;
		
		if (lua_ctx_store.debug > 0){
			char** argbase = cmdline.data.strarr;
				while(*argbase)
					arcan_warning("\t%s\n", *argbase++);
		}
	
		if (internal && resourcestr)
			if (use_loader(resourcestr)){
				char* metastr = resourcestr; /* for lib / frameserver targets, we assume that the argumentlist is just [romsetfull] */
				if ( cmdline.data.strarr[0] && cmdline.data.strarr[1] ){ /* launch_options adds exec path first, we already know that one */
					size_t arglen = strlen(resourcestr) + 1 + strlen(cmdline.data.strarr[1]) + 1;
					
					metastr = (char*) malloc( arglen );
					snprintf(metastr, arglen, "%s:%s", resourcestr, cmdline.data.strarr[1]);
				}
			
				arcan_frameserver* intarget = (arcan_frameserver*) calloc(sizeof(arcan_frameserver), 1);
				intarget->tag = ref;
				intarget->nopts = true;
				intarget->autoplay = true;
				
				struct frameserver_envp args = {
					.use_builtin = true,
					.args.builtin.resource = metastr,
					.args.builtin.mode = "libretro"
				};
				
				if (arcan_frameserver_spawn_server(intarget, args) == ARCAN_OK){
					lua_pushvid(ctx, intarget->vid);
					arcan_db_launch_counter_increment(dbhandle, gameid);
				}
				else {
					lua_pushvid(ctx, ARCAN_EID);
					free(intarget);
				}
				free(metastr);

				rv = 1;
			}
			else {
				arcan_frameserver* intarget = arcan_target_launch_internal( resourcestr, cmdline.data.strarr);
				if (intarget) {
					intarget->tag = ref;
					lua_pushvid(ctx, intarget->vid);
					arcan_db_launch_counter_increment(dbhandle, gameid);
					rv = 1;
				} else {
					arcan_db_failed_launch(dbhandle, gameid);
				}
			}
		else {
			unsigned long elapsed = arcan_target_launch_external(resourcestr, cmdline.data.strarr);
			
			if (elapsed / 1000 < 3){
				char** argvp = cmdline.data.strarr;
				arcan_db_failed_launch(dbhandle, gameid);
				arcan_warning("Script Warning: launch_external(), possibly broken target/game combination. %s\n\tArguments:", *argvp++);
				while(*argvp){
					arcan_warning("%s \n", *argvp++);
				}
			} else
				arcan_db_launch_counter_increment(dbhandle, gameid);
		}
		
		free(resourcestr);
	}
	else
		arcan_warning("arcan_lua_targetlaunch(%i, %i) failed, no match in database.\n", gameid, internal);

cleanup:
	arcan_db_free_res(dbhandle, cmdline);
	return rv;
}

int arcan_lua_renderset(lua_State* ctx)
{
	arcan_vobj_id did = luaL_checkvid(ctx, 1);
	int nvids         = lua_rawlen(ctx, 2);
	int detach        = luaL_checkint(ctx, 3);
	int scale         = luaL_checkint(ctx, 4); 

	if (detach != RENDERTARGET_DETACH && detach != RENDERTARGET_NODETACH){
		arcan_warning("arcan_lua_renderset(%d) invalid arg 3, expected RENDERTARGET_DETACH or RENDERTARGET_NODETACH\n", detach);
		return 0;
	}
	
	if (scale != RENDERTARGET_SCALE && scale != RENDERTARGET_NOSCALE){
		arcan_warning("arcan_lua_renderset(%d) invalid arg 4, expected RENDERTARGET_SCALE or RENDERTARGET_NOSCALE\n", scale);
		return 0;
	}
	
	if (nvids > 0){
		arcan_video_setuprendertarget(did, 0, scale == RENDERTARGET_SCALE);

		for (int i = 0; i < nvids; i++){
			lua_rawgeti(ctx, 2, i+1);
			arcan_vobj_id setvid = luavid_tovid( lua_tonumber(ctx, -1) );
			arcan_video_attachtorendertarget(did, setvid, detach == RENDERTARGET_DETACH);
		}
		
	}
	else
		arcan_warning("arcan_lua_renderset(%d, %d) - refusing to define empty renderset.\n");
		
	return 0;
}

int arcan_lua_recordset(lua_State* ctx)
{
	arcan_vobj_id did = luaL_checkvid(ctx, 1);
	const char* resf  = luaL_checkstring(ctx, 2);
	const char* argl  = luaL_checkstring(ctx, 3);
	int nvids         = lua_rawlen(ctx, 4);
	int naids         = lua_rawlen(ctx, 5);
	int detach        = luaL_checkint(ctx, 6);
	int scale         = luaL_checkint(ctx, 7);
	int pollrate      = luaL_checkint(ctx, 8);

	intptr_t ref = (intptr_t) 0;

	if (detach != RENDERTARGET_DETACH && detach != RENDERTARGET_NODETACH){
		arcan_warning("arcan_lua_recordset(%d) invalid arg 6, expected RENDERTARGET_DETACH or RENDERTARGET_NODETACH\n", detach);
		return 0;
	}
	
	if (scale != RENDERTARGET_SCALE && scale != RENDERTARGET_NOSCALE){
		arcan_warning("arcan_lua_recordset(%d) invalid arg 7, expected RENDERTARGET_SCALE or RENDERTARGET_NOSCALE\n", scale);
		return 0;
	}
	
	if (pollrate == 0){
		arcan_warning("arcan_lua_recordset(%d) invalid arg 8, expected n < 0 (every n frame) or n > 0 (every n tick)\n");
		return 0;
	}
	
	if (nvids > 0){
		arcan_video_setuprendertarget(did, pollrate, scale == RENDERTARGET_SCALE);

		for (int i = 0; i < nvids; i++){
			lua_rawgeti(ctx, 4, i+1);
			arcan_vobj_id setvid = luavid_tovid( lua_tonumber(ctx, -1) );
			arcan_video_attachtorendertarget(did, setvid, detach == RENDERTARGET_DETACH);
		}
	}
	else{
		/* FIXME: empty recordset, attach as colour to stdout */
		return 0;
	}

	arcan_aobj_id* aidlocks = NULL;
	unsigned n_aidlocks = abs(naids);
	
	if (naids > 0){
		aidlocks = malloc(sizeof(arcan_aobj_id) * naids + 1);
		aidlocks[naids] = 0; /* terminate */

/* can't hook the monitors until we have the frameserver in place */
		for (int i = 0; i < naids; i++){
			lua_rawgeti(ctx, 5, i+1);
			arcan_aobj_id setaid = luaaid_toaid( lua_tonumber(ctx, -1) );
			aidlocks[i] = setaid;
		}
	}
	
/*  in order to stay backward compatible API wise, the load_movie with function callback
 *  will always need to specify loop condition. */
	if (lua_isfunction(ctx, 8) && !lua_iscfunction(ctx, 8)){
		lua_pushvalue(ctx, 8);
		ref = luaL_ref(ctx, LUA_REGISTRYINDEX);
	}
	
	arcan_frameserver* mvctx = (arcan_frameserver*) calloc(sizeof(arcan_frameserver), 1);
	mvctx->loop = FRAMESERVER_NOLOOP;
	mvctx->vid  = did;
	
	struct frameserver_envp args = {
		.use_builtin = true,
		.custom_feed = true,
		.args.builtin.mode = "record",
		.args.builtin.resource = argl 
	};

/* we use a special feed function meant to flush audiobuffer + a single video frame for encoding */
	vfunc_state fftag = {
		.tag = ARCAN_TAG_FRAMESERV,
		.ptr = mvctx};
	arcan_video_alterfeed(did, arcan_frameserver_avfeedframe, fftag);
	
	if ( arcan_frameserver_spawn_server(mvctx, args) == ARCAN_OK ){
		arcan_vobject* dobj = arcan_video_getobject(did);

/* we define the size of the recording to be that of the storage of the rendertarget vid,
 * this should be allocated through fill_surface */
		struct frameserver_shmpage* shmpage = mvctx->shm.ptr;
		shmpage->storage.w = dobj->gl_storage.w;
		shmpage->storage.h = dobj->gl_storage.h;
		
/* separate storage and display dimensions to allow for scaling hints, or cropping */
		shmpage->display.w = dobj->gl_storage.w;
		shmpage->display.h = dobj->gl_storage.h;
		shmpage->storage.bpp = 4;
		shmpage->channels = 2;
		shmpage->samplerate = 44100;
		
		frameserver_shmpage_calcofs(shmpage, &(mvctx->vidp), &(mvctx->audp));

/* pushing the file descriptor signals the frameserver to start receiving (and use the proper dimensions),
 * it is permitted to close and push another one to the same session */
		int fd = fmt_open(O_CREAT | O_WRONLY, S_IRWXU, "%s/%s/%s", arcan_themepath, arcan_themename, resf);
		if (fd){
			arcan_frameserver_pushfd( mvctx, fd );
			mvctx->alocks = aidlocks;
			arcan_aobj_id* base = mvctx->alocks;
			while(base && *base){
				void* hookfun;
				arcan_audio_hookfeed(*base++, mvctx, arcan_frameserver_avfeedmon, &hookfun);
			}
		}
		else
			arcan_warning("arcan_lua_recordset(%s/%s/%s) -- couldn't create output.\n", arcan_themepath, arcan_themename, resf);
	} 
	else 
		free(mvctx);

	return 0;
}

int arcan_lua_borderscan(lua_State* ctx)
{
	int x1, y1, x2, y2;
	x1 = y1 = 0;
	x2 = arcan_video_screenw();
	y2 = arcan_video_screenh();
	
	arcan_vobj_id vid = luaL_checkvid(ctx, 1);
	arcan_vobject* vobj = arcan_video_getobject(vid);

/* since GLES doesn't support texture readback, the option would be to render then readback pixels
 * as there is limited use for this feature, we'll stick to the cheap route, i.e. assume we don't
 * use memory- conservative mode and just grab the buffer from the cached storage. */
	if (vobj && vobj->default_frame.raw && vobj->default_frame.s_raw > 0
		&& vobj->origw > 0 && vobj->origh > 0){
	
#define sample(x,y) ( vobj->default_frame.raw[ ((y) * vobj->origw + (x)) * 4 + 3 ] )
		
			for (x1 = vobj->origw >> 1; x1 >= 0 && sample(x1, vobj->origh >> 1) < 128; x1--);
			for (x2 = vobj->origw >> 1; x2 < vobj->origw && sample(x2, vobj->origh >> 1) < 128; x2++);
			for (y1 = vobj->origh >> 1; y1 >= 0 && sample(vobj->origw >> 1, y1) < 128; y1--);
			for (y2 = vobj->origh >> 1; y2 < vobj->origh && sample(vobj->origw >> 1, y2) < 128; y2++);
#undef sample
		}
	
	lua_pushnumber(ctx, x1);
	lua_pushnumber(ctx, y1);
	lua_pushnumber(ctx, x2);
	lua_pushnumber(ctx, y2);
	return 4;
}

int arcan_lua_decodemod(lua_State* ctx)
{
	int modval = luaL_checkint(ctx, 1);

	lua_newtable(ctx);
	int top = lua_gettop(ctx);

	int count = 1;
	if ((modval & KMOD_LSHIFT) > 0){
		lua_pushnumber(ctx, count++);
		lua_pushstring(ctx, "lshift");
		lua_rawset(ctx, top);
	}

	if ((modval & KMOD_RSHIFT) > 0){
		lua_pushnumber(ctx, count++);
		lua_pushstring(ctx, "rshift");
		lua_rawset(ctx, top);
	}

	if ((modval & KMOD_LALT) > 0){
		lua_pushnumber(ctx, count++);
		lua_pushstring(ctx, "lalt");
		lua_rawset(ctx, top);
	}

	if ((modval & KMOD_RALT) > 0){
		lua_pushnumber(ctx, count++);
		lua_pushstring(ctx, "ralt");
		lua_rawset(ctx, top);
	}

	if ((modval & KMOD_LCTRL) > 0){
		lua_pushnumber(ctx, count++);
		lua_pushstring(ctx, "lctrl");
		lua_rawset(ctx, top);
	}

	if ((modval & KMOD_RCTRL) > 0){
		lua_pushnumber(ctx, count++);
		lua_pushstring(ctx, "rctrl");
		lua_rawset(ctx, top);
	}
	
	if ((modval & KMOD_LMETA) > 0){
		lua_pushnumber(ctx, count++);
		lua_pushstring(ctx, "lmeta");
		lua_rawset(ctx, top);
	}
	
	if ((modval & KMOD_RMETA) > 0){
		lua_pushnumber(ctx, count++);
		lua_pushstring(ctx, "rmeta");
		lua_rawset(ctx, top);
	}

	if ((modval & KMOD_NUM) > 0){
		lua_pushnumber(ctx, count++);
		lua_pushstring(ctx, "num");
		lua_rawset(ctx, top);
	}

	if ((modval & KMOD_CAPS) > 0){
		lua_pushnumber(ctx, count++);
		lua_pushstring(ctx, "caps");
		lua_rawset(ctx, top);
	}

	return 1;
}

int arcan_lua_movemodel(lua_State* ctx)
{
	arcan_vobj_id vid = luaL_checkvid(ctx, 1);
	float x = luaL_checknumber(ctx, 2);
	float y = luaL_checknumber(ctx, 3);
	float z = luaL_checknumber(ctx, 4);
	unsigned int dt = luaL_optint(ctx, 5, 0);

	arcan_video_objectmove(vid, x, y, z, dt);
	return 0;
}

int arcan_lua_scalemodel(lua_State* ctx)
{
	arcan_vobj_id vid = luaL_checkvid(ctx, 1);
	float sx = luaL_checknumber(ctx, 2);
	float sy = luaL_checknumber(ctx, 3);
	float sz = luaL_checknumber(ctx, 4);
	unsigned int dt = luaL_optint(ctx, 5, 0);

	arcan_video_objectscale(vid, sx, sy, sz, 0);
	return 0;
}

int arcan_lua_orientmodel(lua_State* ctx)
{
	arcan_vobj_id vid = luaL_checkvid(ctx, 1);
	double roll = luaL_checknumber(ctx, 2);
	double pitch = luaL_checknumber(ctx, 3);
	double yaw = luaL_checknumber(ctx, 4);
	unsigned int dt = luaL_optnumber(ctx, 5, 0);

	arcan_video_objectrotate(vid, roll, pitch, yaw, dt);
	return 0;
}

/* map a format string to the arcan_shdrmgmt.h different datatypes */
int arcan_lua_shader_uniform(lua_State* ctx)
{
	float fbuf[16];
	
	unsigned sid = luaL_checknumber(ctx, 1);
	const char* label = luaL_checkstring(ctx, 2);
	const char* fmtstr = luaL_checkstring(ctx, 3);
	bool persist = luaL_checknumber(ctx, 4) != 0;
	arcan_shader_activate(sid);

	if (fmtstr[0] == 'b'){
		bool fmt = luaL_checknumber(ctx, 5) != 0;
		arcan_shader_forceunif(label, shdrbool, &fmt, persist);
	} else if (fmtstr[0] == 'i'){
		int fmt = luaL_checknumber(ctx, 5);
		arcan_shader_forceunif(label, shdrint, &fmt, persist);
	} else {
		unsigned i = 0;
		while(fmtstr[i] == 'f') i++;
		if (i)
			switch(i){
				case 1:
					fbuf[0] = luaL_checknumber(ctx, 5);
					arcan_shader_forceunif(label, shdrfloat, fbuf, persist);
				break;
				
				case 2:
					fbuf[0] = luaL_checknumber(ctx, 5);
					fbuf[1] = luaL_checknumber(ctx, 6);
					arcan_shader_forceunif(label, shdrvec2, fbuf, persist);
				break;
				
				case 3:
					fbuf[0] = luaL_checknumber(ctx, 5);
					fbuf[1] = luaL_checknumber(ctx, 6);
					fbuf[2] = luaL_checknumber(ctx, 7);
					arcan_shader_forceunif(label, shdrvec3, fbuf, persist);
				break;
				
				case 4:
					fbuf[0] = luaL_checknumber(ctx, 5);
					fbuf[1] = luaL_checknumber(ctx, 6);
					fbuf[2] = luaL_checknumber(ctx, 7);
					fbuf[3] = luaL_checknumber(ctx, 8);
					arcan_shader_forceunif(label, shdrvec3, fbuf, persist);
				break;

				case 16:
						while(i--)
							fbuf[i] = luaL_checknumber(ctx, 5 + i);
						
						arcan_shader_forceunif(label, shdrmat4x4, fbuf, persist);
						
				break;
				default:
					arcan_warning("arcan_lua_shader_uniform(), unsupported format string accepted f counts are 1..4 and 16\n");
		}
		else
			arcan_warning("arcan_lua_shader_uniform(), unspported format string (%s)\n", fmtstr);
	}
	
	/* shdrbool : b
	 *  shdrint : i
	 *shdrfloat : f
	 *shdrvec2  : ff
	 *shdrvec3  : fff
	 *shdrvec4  : ffff
	 *shdrmat4x4: ffff.... */

	/* check for the special ones, b and i */
	/* count number of f:s, map that to the appropriate subtype */
	
	return 0;
}

int arcan_lua_rotatemodel(lua_State* ctx)
{
	arcan_vobj_id vid = luaL_checkvid(ctx, 1);
	double roll = luaL_checknumber(ctx, 2);
	double pitch = luaL_checknumber(ctx, 3);
	double yaw = luaL_checknumber(ctx, 4);
	unsigned int dt = luaL_optnumber(ctx, 5, 0);
	
	surface_properties prop = arcan_video_current_properties(vid);
	arcan_video_objectrotate(vid, prop.rotation.roll + roll, prop.rotation.pitch + pitch, prop.rotation.yaw + yaw, dt);
	return 0;
}

int arcan_lua_setimageproc(lua_State* ctx)
{
	int num = luaL_checknumber(ctx, 1);
	
	if (num >= 0 && num < 2){
		arcan_video_default_imageprocmode(num);
	}

	return 0;
}

int arcan_lua_settexfilter(lua_State* ctx)
{
	enum arcan_vfilter_mode mode = luaL_checknumber(ctx, 1);

	if (mode == ARCAN_VFILTER_TRILINEAR || 
			mode == ARCAN_VFILTER_BILINEAR || 
		  mode == ARCAN_VFILTER_LINEAR ||
		  mode == ARCAN_VFILTER_NONE){
		arcan_video_default_texfilter(mode);	
	}
	
	return 0;
}

int arcan_lua_changetexfilter(lua_State* ctx)
{
	enum arcan_vfilter_mode mode = luaL_checknumber(ctx, 2);
	arcan_vobj_id vid = luaL_checkvid(ctx, 1);
	
	if (mode == ARCAN_VFILTER_TRILINEAR || 
			mode == ARCAN_VFILTER_BILINEAR ||
		  mode == ARCAN_VFILTER_LINEAR || 
		  mode == ARCAN_VFILTER_NONE){
		arcan_video_objectfilter(vid, mode);
	}
	
	return 0;
}

int arcan_lua_settexmode(lua_State* ctx)
{
	int numa = luaL_checknumber(ctx, 1);
	int numb = luaL_checknumber(ctx, 2);
	
	if ( (numa == ARCAN_VTEX_CLAMP || numa == ARCAN_VTEX_REPEAT) &&
		(numb == ARCAN_VTEX_CLAMP || numb == ARCAN_VTEX_REPEAT) ){
		arcan_video_default_texmode(numa, numb);
	}

	return 0;
}

int arcan_lua_tracetag(lua_State* ctx)
{
	arcan_vobj_id id = luaL_checkvid(ctx, 1);
	const char* const msg = luaL_checkstring(ctx, 2);
	
	arcan_video_tracetag(id, msg);
	
	return 0;
}

int arcan_lua_setscalemode(lua_State* ctx)
{
	int num = luaL_checknumber(ctx, 1);
	
	if (num >= 0 && num < 3){
		arcan_video_default_scalemode(num);
	}

	return 0;
}

/* 0 => 7 bit char,
 * 1 => start of char,
 * 2 => in the middle of char */
int arcan_lua_utf8kind(lua_State* ctx)
{
	char num = luaL_checkint(ctx, 1);

	if (num & (1 << 7)){
		lua_pushnumber(ctx, num & (1 << 6) ? 1 : 2);
	} else
		lua_pushnumber(ctx, 0);
	
	return 1;
}

int arcan_lua_screenshot(lua_State* ctx)
{
	const char* const resstr = luaL_checkstring(ctx, 1);
	void* databuf;
	size_t bufs;
	
	if (arcan_video_screenshot(&databuf, &bufs)){
/* FIXME(sandboxing) */
		char* fname = arcan_find_resource(resstr, ARCAN_RESOURCE_THEME);
		if (!fname){
			fname = arcan_expand_resource(resstr, false);
			
			if (lodepng_encode32_file(fname, databuf, arcan_video_screenw(), arcan_video_screenh()))
				arcan_warning("arcan_lua_screenshot() -- write failed, empty or truncated screenshot.\n");
			
		}
		else{
			arcan_warning("arcan_lua_screenshot() -- refusing to overwrite existing (%s)\n", fname);
		}
		free(fname);
		free(databuf);
	}
	else
		arcan_warning("arcan_lua_screenshot() -- request failed, couldn't allocate memory.\n");
	
	return 0;
}

void arcan_lua_cleanup()
{
}

void arcan_lua_pushargv(lua_State* ctx, char** argv)
{
	int argc = 0;

	lua_newtable(ctx);
	int top = lua_gettop(ctx);

	while(argv[argc]){
		lua_pushnumber(ctx, argc + 1);
		lua_pushstring(ctx, argv[argc]);
		lua_rawset(ctx, top);
		argc++;
	}

	lua_setglobal(ctx, "arguments");
}

static void arcan_lua_register(lua_State* ctx, const char* name, lua_CFunction fun)
{
	lua_pushstring(ctx, name);
	lua_pushcclosure(ctx, fun, 1);
	lua_setglobal(ctx, name);
}

arcan_errc arcan_lua_exposefuncs(lua_State* ctx, unsigned char debugfuncs)
{
	if (!ctx)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	lua_ctx_store.debug = debugfuncs;
	lua_atpanic(ctx, (lua_CFunction) arcan_lua_panic);
	
#ifdef _DEBUG
	lua_ctx_store.lua_vidbase = rand() % 32768;
	arcan_warning("lua_exposefuncs() -- videobase is set to %d\n", lua_ctx_store.lua_vidbase);
#endif
	
	arcan_lua_register(ctx, "resource", arcan_lua_resource);
	arcan_lua_register(ctx, "glob_resource", arcan_lua_globresource);
	arcan_lua_register(ctx, "zap_resource", arcan_lua_zapresource);
	arcan_lua_register(ctx, "open_rawresource", arcan_lua_rawresource);
	arcan_lua_register(ctx, "write_rawresource", arcan_lua_pushrawstr);
	arcan_lua_register(ctx, "close_rawresource", arcan_lua_rawclose);
	arcan_lua_register(ctx, "read_rawresource", arcan_lua_readrawresource);
	arcan_lua_register(ctx, "save_screenshot", arcan_lua_screenshot);
	arcan_lua_register(ctx, "launch_target", arcan_lua_targetlaunch);
	arcan_lua_register(ctx, "launch_target_capabilities", arcan_lua_targetlaunch_capabilities);
	arcan_lua_register(ctx, "target_input", arcan_lua_targetinput);
	arcan_lua_register(ctx, "input_target", arcan_lua_targetinput);
	arcan_lua_register(ctx, "suspend_target", arcan_lua_targetsuspend);
	arcan_lua_register(ctx, "resume_target", arcan_lua_targetresume);
	arcan_lua_register(ctx, "target_portconfig", arcan_lua_targetportcfg);
	arcan_lua_register(ctx, "target_framemode", arcan_lua_targetskipmodecfg);
	arcan_lua_register(ctx, "target_pointsize", arcan_lua_targetpointsize);
	arcan_lua_register(ctx, "target_linewidth", arcan_lua_targetlinewidth);
	arcan_lua_register(ctx, "target_postfilter", arcan_lua_targetpostfilter);
	arcan_lua_register(ctx, "target_postfilter_args", arcan_lua_targetpostfilterargs);
	arcan_lua_register(ctx, "stepframe_target", arcan_lua_targetstepframe);
	arcan_lua_register(ctx, "snapshot_target", arcan_lua_targetsnapshot);
	arcan_lua_register(ctx, "restore_target", arcan_lua_targetrestore);
	arcan_lua_register(ctx, "reset_target", arcan_lua_targetreset);
	arcan_lua_register(ctx, "kbd_repeat", arcan_lua_kbdrepeat);
	arcan_lua_register(ctx, "video_3dorder", arcan_lua_3dorder);
 	arcan_lua_register(ctx, "toggle_mouse_grab", arcan_lua_mousegrab);
	arcan_lua_register(ctx, "system_load", arcan_lua_dofile);
	arcan_lua_register(ctx, "system_context_size", arcan_lua_systemcontextsize);
	arcan_lua_register(ctx, "default_movie_queueopts", arcan_lua_getqueueopts);
	arcan_lua_register(ctx, "default_movie_queueopts_override", arcan_lua_setqueueopts);
	arcan_lua_register(ctx, "switch_default_scalemode", arcan_lua_setscalemode);
	arcan_lua_register(ctx, "switch_default_texmode", arcan_lua_settexmode);
	arcan_lua_register(ctx, "switch_default_imageproc", arcan_lua_setimageproc);
	arcan_lua_register(ctx, "switch_default_texfilter", arcan_lua_settexfilter);
	arcan_lua_register(ctx, "shutdown", arcan_lua_shutdown);
	arcan_lua_register(ctx, "warning", arcan_lua_warning);
	arcan_lua_register(ctx, "valid_vid", arcan_lua_validvid);
	arcan_lua_register(ctx, "store_key", arcan_lua_storekey);
	arcan_lua_register(ctx, "get_key", arcan_lua_getkey);
	arcan_lua_register(ctx, "game_cmdline", arcan_lua_getcmdline);
	arcan_lua_register(ctx, "list_games", arcan_lua_filtergames);
	arcan_lua_register(ctx, "list_targets", arcan_lua_gettargets);
	arcan_lua_register(ctx, "game_info", arcan_lua_getgame);
	arcan_lua_register(ctx, "game_family", arcan_lua_gamefamily);
	arcan_lua_register(ctx, "game_genres", arcan_lua_getgenres);
	arcan_lua_register(ctx, "stream_audio", arcan_lua_prepare_astream);
	arcan_lua_register(ctx, "play_audio", arcan_lua_playaudio);
	arcan_lua_register(ctx, "pause_audio", arcan_lua_pauseaudio);
	arcan_lua_register(ctx, "delete_audio", arcan_lua_dropaudio);
	arcan_lua_register(ctx, "load_asample", arcan_lua_loadasample);
	arcan_lua_register(ctx, "audio_gain", arcan_lua_gain);
	arcan_lua_register(ctx, "load_image", arcan_lua_loadimage);
	arcan_lua_register(ctx, "load_image_asynch", arcan_lua_loadimageasynch);
	arcan_lua_register(ctx, "image_loaded", arcan_lua_imageloaded);
	arcan_lua_register(ctx, "delete_image", arcan_lua_deleteimage);
	arcan_lua_register(ctx, "show_image", arcan_lua_showimage);
	arcan_lua_register(ctx, "hide_image", arcan_lua_hideimage);
	arcan_lua_register(ctx, "move_image", arcan_lua_moveimage);
	arcan_lua_register(ctx, "nudge_image", arcan_lua_nudgeimage);
	arcan_lua_register(ctx, "rotate_image", arcan_lua_rotateimage);
	arcan_lua_register(ctx, "scale_image", arcan_lua_scaleimage);
	arcan_lua_register(ctx, "resize_image", arcan_lua_scaleimage2);
	arcan_lua_register(ctx, "blend_image", arcan_lua_imageopacity);
	arcan_lua_register(ctx, "image_parent", arcan_lua_imageparent);
	arcan_lua_register(ctx, "image_children", arcan_lua_imagechildren);
	arcan_lua_register(ctx, "order_image", arcan_lua_orderimage);
	arcan_lua_register(ctx, "max_current_image_order", arcan_lua_maxorderimage);
	arcan_lua_register(ctx, "instance_image", arcan_lua_instanceimage);
	arcan_lua_register(ctx, "link_image", arcan_lua_linkimage);
	arcan_lua_register(ctx, "set_image_as_frame", arcan_lua_imageasframe);
	arcan_lua_register(ctx, "image_framesetsize", arcan_lua_framesetalloc);
	arcan_lua_register(ctx, "image_framecyclemode", arcan_lua_framesetcycle);
	arcan_lua_register(ctx, "image_pushasynch", arcan_lua_pushasynch);
	arcan_lua_register(ctx, "image_active_frame", arcan_lua_activeframe);
	arcan_lua_register(ctx, "expire_image", arcan_lua_setlife);
	arcan_lua_register(ctx, "reset_image_transform", arcan_lua_resettransform);
	arcan_lua_register(ctx, "instant_image_transform", arcan_lua_instanttransform);
	arcan_lua_register(ctx, "image_transform_cycle", arcan_lua_cycletransform);
	arcan_lua_register(ctx, "copy_image_transform", arcan_lua_copytransform);
	arcan_lua_register(ctx, "transfer_image_transform", arcan_lua_transfertransform);
	arcan_lua_register(ctx, "image_set_txcos", arcan_lua_settxcos);
	arcan_lua_register(ctx, "image_get_txcos", arcan_lua_gettxcos);
	arcan_lua_register(ctx, "image_texfilter", arcan_lua_changetexfilter);
	arcan_lua_register(ctx, "image_scale_txcos", arcan_lua_scaletxcos);
	arcan_lua_register(ctx, "image_clip_on", arcan_lua_clipon);
	arcan_lua_register(ctx, "image_clip_off", arcan_lua_clipoff);
	arcan_lua_register(ctx, "image_mask_toggle", arcan_lua_togglemask);
	arcan_lua_register(ctx, "image_mask_set", arcan_lua_setmask);
	arcan_lua_register(ctx, "image_mask_clear", arcan_lua_clearmask);
	arcan_lua_register(ctx, "image_tracetag", arcan_lua_tracetag);
	arcan_lua_register(ctx, "image_mask_clearall", arcan_lua_clearall);
	arcan_lua_register(ctx, "image_surface_properties", arcan_lua_getimageprop);
	arcan_lua_register(ctx, "image_surface_initial_properties", arcan_lua_getimageinitprop);
	arcan_lua_register(ctx, "image_surface_resolve_properties", arcan_lua_getimageresolveprop);
	arcan_lua_register(ctx, "image_storage_properties", arcan_lua_getimagestorageprop);
	arcan_lua_register(ctx, "image_shader", arcan_lua_setshader);
	arcan_lua_register(ctx, "mesh_shader", arcan_lua_setmeshshader);
	arcan_lua_register(ctx, "build_shader", arcan_lua_buildshader);
	arcan_lua_register(ctx, "shader_uniform", arcan_lua_shader_uniform);
	arcan_lua_register(ctx, "render_text", arcan_lua_buildstr);
	arcan_lua_register(ctx, "text_dimensions", arcan_lua_strsize);
	arcan_lua_register(ctx, "fill_surface", arcan_lua_fillsurface);
	arcan_lua_register(ctx, "define_rendertarget", arcan_lua_renderset);
	arcan_lua_register(ctx, "define_recordtarget", arcan_lua_recordset);
	arcan_lua_register(ctx, "image_borderscan", arcan_lua_borderscan);
	arcan_lua_register(ctx, "random_surface", arcan_lua_randomsurface);
	arcan_lua_register(ctx, "force_image_blend", arcan_lua_forceblend);
	arcan_lua_register(ctx, "push_video_context", arcan_lua_pushcontext);
	arcan_lua_register(ctx, "pop_video_context", arcan_lua_popcontext);
	arcan_lua_register(ctx, "current_context_usage", arcan_lua_contextusage);
  arcan_lua_register(ctx, "new_3dmodel", arcan_lua_buildmodel);
	arcan_lua_register(ctx, "add_3dmesh", arcan_lua_loadmesh);
	arcan_lua_register(ctx, "move3d_model", arcan_lua_movemodel);
	arcan_lua_register(ctx, "rotate3d_model", arcan_lua_rotatemodel);
	arcan_lua_register(ctx, "orient3d_model", arcan_lua_orientmodel);
	arcan_lua_register(ctx, "scale3d_model", arcan_lua_scalemodel);
	arcan_lua_register(ctx, "camtag_model", arcan_lua_camtag);
	arcan_lua_register(ctx, "build_3dplane", arcan_lua_buildplane);
	arcan_lua_register(ctx, "scale_3dvertices", arcan_lua_scale3dverts);
	arcan_lua_register(ctx, "play_movie", arcan_lua_playmovie);
	arcan_lua_register(ctx, "load_movie", arcan_lua_loadmovie);
	arcan_lua_register(ctx, "pause_movie", arcan_lua_pausemovie);
	arcan_lua_register(ctx, "resume_movie", arcan_lua_resumemovie);
	arcan_lua_register(ctx, "image_hit", arcan_lua_hittest);
	arcan_lua_register(ctx, "pick_items", arcan_lua_pick);
	arcan_lua_register(ctx, "set_led", arcan_lua_setled);
	arcan_lua_register(ctx, "led_intensity", arcan_lua_led_intensity);
	arcan_lua_register(ctx, "set_led_rgb", arcan_lua_led_rgb);
	arcan_lua_register(ctx, "controller_leds", arcan_lua_n_leds);
	arcan_lua_register(ctx, "utf8kind", arcan_lua_utf8kind);
	arcan_lua_register(ctx, "decode_modifiers", arcan_lua_decodemod);
	
	atexit(arcan_lua_cleanup);
	
	return ARCAN_OK;
}

/* category: tableformats */
/* table: */
/* table: */

/* category: constants */

void arcan_lua_pushglobalconsts(lua_State* ctx){
	arcan_lua_setglobalint(ctx, "VRESH", arcan_video_screenh());
	arcan_lua_setglobalint(ctx, "VRESW", arcan_video_screenw());
	arcan_lua_setglobalint(ctx, "STACK_MAXCOUNT", CONTEXT_STACK_LIMIT);
	arcan_lua_setglobalint(ctx, "FRAMESET_SPLIT", ARCAN_FRAMESET_SPLIT);
	arcan_lua_setglobalint(ctx, "FRAMESET_MULTITEXTURE", ARCAN_FRAMESET_MULTITEXTURE);
	arcan_lua_setglobalint(ctx, "FRAMESET_NODETACH", FRAMESET_NODETACH);
	arcan_lua_setglobalint(ctx, "FRAMESET_DETACH", FRAMESET_DETACH);
	arcan_lua_setglobalint(ctx, "BLEND_NONE", BLEND_NONE);
	arcan_lua_setglobalint(ctx, "BLEND_ADD", BLEND_ADD);	
	arcan_lua_setglobalint(ctx, "BLEND_MULTIPLY", BLEND_MULTIPLY);
	arcan_lua_setglobalint(ctx, "BLEND_NORMAL", BLEND_NORMAL);
	arcan_lua_setglobalint(ctx, "RENDERTARGET_NOSCALE", RENDERTARGET_NOSCALE);
	arcan_lua_setglobalint(ctx, "RENDERTARGET_SCALE", RENDERTARGET_SCALE);
	arcan_lua_setglobalint(ctx, "RENDERTARGET_NODETACH", RENDERTARGET_NODETACH);
	arcan_lua_setglobalint(ctx, "RENDERTARGET_DETACH", RENDERTARGET_DETACH);
	arcan_lua_setglobalint(ctx, "TEX_REPEAT", ARCAN_VTEX_REPEAT);
	arcan_lua_setglobalint(ctx, "TEX_CLAMP", ARCAN_VTEX_CLAMP);
	arcan_lua_setglobalint(ctx, "FILTER_NONE", ARCAN_VFILTER_NONE);
	arcan_lua_setglobalint(ctx, "FILTER_LINEAR", ARCAN_VFILTER_LINEAR);
	arcan_lua_setglobalint(ctx, "FILTER_BILINEAR", ARCAN_VFILTER_BILINEAR);
	arcan_lua_setglobalint(ctx, "FILTER_TRILINEAR", ARCAN_VFILTER_TRILINEAR);
	arcan_lua_setglobalint(ctx, "SCALE_NOPOW2", ARCAN_VIMAGE_NOPOW2);
	arcan_lua_setglobalint(ctx, "SCALE_TXCOORD", ARCAN_VIMAGE_TXCOORD);
	arcan_lua_setglobalint(ctx, "SCALE_POW2", ARCAN_VIMAGE_SCALEPOW2);
	arcan_lua_setglobalint(ctx, "IMAGEPROC_NORMAL", imageproc_normal);
	arcan_lua_setglobalint(ctx, "IMAGEPROC_FLIPH", imageproc_fliph);
	arcan_lua_setglobalint(ctx, "BLEND_NORMAL", BLEND_NORMAL);
	arcan_lua_setglobalint(ctx, "WORLDID", ARCAN_VIDEO_WORLDID);
	arcan_lua_setglobalint(ctx, "BADID", ARCAN_EID);
	arcan_lua_setglobalint(ctx, "CLOCKRATE", ARCAN_TIMER_TICK);
	arcan_lua_setglobalint(ctx, "CLOCK", 0);
	arcan_lua_setglobalint(ctx, "JOYSTICKS", SDL_NumJoysticks());
	arcan_lua_setglobalint(ctx, "THEME_RESOURCE", ARCAN_RESOURCE_THEME);
	arcan_lua_setglobalint(ctx, "SHARED_RESOURCE", ARCAN_RESOURCE_SHARED);
	arcan_lua_setglobalint(ctx, "ALL_RESOURCES", ARCAN_RESOURCE_THEME | ARCAN_RESOURCE_SHARED);
	arcan_lua_setglobalint(ctx, "API_VERSION_MAJOR", 0);
	arcan_lua_setglobalint(ctx, "API_VERSION_MINOR", 5);
	arcan_lua_setglobalint(ctx, "LAUNCH_EXTERNAL", 0);
	arcan_lua_setglobalint(ctx, "LAUNCH_INTERNAL", 1);
	arcan_lua_setglobalint(ctx, "MASK_LIVING", MASK_LIVING);
	arcan_lua_setglobalint(ctx, "MASK_ORIENTATION", MASK_ORIENTATION);
	arcan_lua_setglobalint(ctx, "MASK_OPACITY", MASK_OPACITY);
	arcan_lua_setglobalint(ctx, "MASK_POSITION", MASK_POSITION);
	arcan_lua_setglobalint(ctx, "MASK_SCALE", MASK_SCALE);
	arcan_lua_setglobalint(ctx, "MASK_UNPICKABLE", MASK_UNPICKABLE);
	arcan_lua_setglobalint(ctx, "MASK_FRAMESET", MASK_FRAMESET);
	arcan_lua_setglobalint(ctx, "MASK_MAPPING", MASK_MAPPING);
	arcan_lua_setglobalint(ctx, "ORDER_FIRST", ORDER_FIRST);
	arcan_lua_setglobalint(ctx, "ORDER_LAST", ORDER_LAST);
	arcan_lua_setglobalint(ctx, "FRAMESERVER_LOOP", FRAMESERVER_LOOP);
	arcan_lua_setglobalint(ctx, "FRAMESERVER_NOLOOP", FRAMESERVER_NOLOOP);
	arcan_lua_setglobalint(ctx, "POSTFILTER_NTSC", POSTFILTER_NTSC);
	arcan_lua_setglobalint(ctx, "POSTFILTER_OFF", POSTFILTER_OFF);
	arcan_lua_setglobalstr(ctx, "THEMENAME", arcan_themename);
	arcan_lua_setglobalstr(ctx, "RESOURCEPATH", arcan_resourcepath);
	arcan_lua_setglobalstr(ctx, "THEMEPATH", arcan_themepath);
	arcan_lua_setglobalstr(ctx, "BINPATH", arcan_binpath);
	arcan_lua_setglobalstr(ctx, "LIBPATH", arcan_libpath);
	arcan_lua_setglobalstr(ctx, "INTERNALMODE", internal_launch_support());
	arcan_lua_setglobalint(ctx, "LEDCONTROLLERS", arcan_led_controllers());
	arcan_lua_setglobalint(ctx, "NOW", 0);
	arcan_lua_setglobalint(ctx, "NOPERSIST", 0);
	arcan_lua_setglobalint(ctx, "PERSIST", 1);
}
