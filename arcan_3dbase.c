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
#include "arcan_videoint.h"

/* since the 3d is planned as a secondary feature, rather than the primary one,
 * things work slightly different as each 3d object is essentially coupled to 1..n of 2D video objects */
typedef struct {
	float xyzw[4];
} quat;

struct {
	quat orientation;
	arcan_vobj_id parent;
} arcan_3dmodel;

/* take advantage of the "vid as frame" feature to allow multiple video sources to be
 * associated with the texture- coordinaet sets definedin the model source */ 
arcan_errc arcan_3d_modelmaterial(arcan_vobj_id model, unsigned frameno, unsigned txslot)
{
	arcan_vobject* vobj = arcan_video_getobject(model);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	
	if (vobj){
		
	}

	return rv;
}

arcan_vobj_id arcan_3d_loadmodel(const char* resource)
{
	arcan_vobj_id rv = ARCAN_EID;
	CTMcontext ctx = ctmNewContext(CTM_IMPORT);
	ctmLoad(ctx, resource);

	if (ctmGetError(ctx) == CTM_NONE){
		CTMuint n_verts, n_tris, n_uvs;
		const CTMuint* indices;
		const CTMfloat* verts;
		const CTMfloat* normals;

		n_uvs   = ctmGetInteger(ctx, CTM_UV_MAP_COUNT);
		n_verts = ctmGetInteger(ctx, CTM_VERTEX_COUNT);
		verts   = ctmGetFloatArray(ctx, CTM_VERTICES);
		n_tris  = ctmGetInteger(ctx, CTM_TRIANGLE_COUNT);
		indices = ctmGetIntegerArray(ctx, CTM_INDICES);
		normals = ctmGetFloatArray(ctx, CTM_NORMALS);

	}
	
	ctmFreeContext(ctx);
	return rv;
}


