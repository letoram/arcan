#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <stdint.h>
#include <stdbool.h>

#include <openctm.h>
#include <SDL/SDL_opengl.h>

#include "arcan_general.h"
#include "arcan_event.h"
#include "arcan_video.h"
/* include arcan_videoint.h */

typedef struct {
	float xyzw[4];
} quat;

struct {
	quat orientation;
	arcan_vobj_id parent;	
} arcan_3dobj;

static void 3d_switch(unsigned long frameno){
 /* if we haven't switched to 3d this frame, do so now,
  * don't forget to revert back */
}

static arcan_errc ctmload(const char* file)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	CTMcontext ctx = ctmNewContext(CTM_IMPORT);
	ctmLoad(ctx, file);
	if (ctmGetError(ctx) == CTM_NONE){
		CTMuint n_verts, n_tris; 
		CTMuint* indices;
		CTMfloat* verts;

		n_verts = ctmGetInteger(ctx, CTM_VERTEX_COUNT);
		verts   = ctmGetFloatArray(ctx, CTM_VERTICES);
		n_tris  = ctmGetInteger(ctx, CTM_TRIANGLE_COUNT);
		indices = ctmGetIntegerArray(ctx, CTM_INDICES);
	}

	ctmFreeContext(ctx);
	return rv;
}


