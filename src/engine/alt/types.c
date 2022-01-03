#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include <lua.h>

#include "platform.h"
#include "alt/opaque.h"

#include "arcan_lua.h"
#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"

#include "alt/types.h"

/* set on alt_setup_context call */
unsigned lua_vid_base;

/* The vidoffset thing here is an ugly layering violation that comes from
 * embedding other vobjs as part of a render_text format string call. Since
 * that needs to have our vid_base translation added, the value need to be
 * forwarded there. */
void arcan_renderfun_vidoffset(int64_t ofs);

void alt_types_rebase()
{
	uint32_t rv;
	arcan_random((uint8_t*)&rv, 4);
	lua_vid_base = 256 + (rv % 32768);
	arcan_renderfun_vidoffset(lua_vid_base);
}

arcan_vobj_id luavid_tovid(lua_Number innum)
{
	arcan_vobj_id res = ARCAN_VIDEO_WORLDID;

	if (innum != ARCAN_EID && innum != ARCAN_VIDEO_WORLDID)
		res = (arcan_vobj_id) innum - lua_vid_base;
	else if (innum != res)
		res = ARCAN_EID;

	return res;
}

arcan_aobj_id luaaid_toaid(lua_Number innum)
{
	return (arcan_aobj_id) innum;
}

lua_Number vid_toluavid(arcan_vobj_id innum)
{
	if (innum != ARCAN_EID && innum != ARCAN_VIDEO_WORLDID)
		innum += lua_vid_base;

	return (double) innum;
}
