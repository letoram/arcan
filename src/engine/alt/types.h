#ifndef HAVE_ALT_TYPES
#define HAVE_ALT_TYPES

/* Dynamically changable / random offset base for arcan video identifiers to
 * lua versions. Used to ensure a primitive sort of type detection. */
extern unsigned lua_vid_base;
extern unsigned lua_debug_level;

enum arcan_cb_source {
	CB_SOURCE_NONE        = 0,
	CB_SOURCE_FRAMESERVER = 1,
	CB_SOURCE_IMAGE       = 2,
	CB_SOURCE_TRANSFORM   = 3,
	CB_SOURCE_PREROLL     = 4,
	CB_SOURCE_AUDIO       = 5
};

arcan_vobj_id luaL_checkvid(lua_State*, int num, arcan_vobject**);
arcan_aobj_id luaaid_toaid(lua_Number innum);
arcan_vobj_id luavid_tovid(lua_Number innum);
lua_Number vid_toluavid(arcan_vobj_id innum);

/* generate a new base value to protect against statically coded vid
 * values in user-scripts */
void alt_types_rebase();
#endif
