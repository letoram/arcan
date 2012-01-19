#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>

#include <openctm.h>
#include <SDL/SDL_opengl.h>
#include <SDL/SDL.h>

#include "arcan_general.h"
#include "arcan_event.h"
#include "arcan_video.h"
#include "arcan_videoint.h"

#define M_PI 3.14159265358979323846

extern struct arcan_video_display arcan_video_display;

/* since the 3d is planned as a secondary feature, rather than the primary one,
 * things work slightly different as each 3d object is essentially coupled to 1..n of 2D video objects */
typedef struct {
	union{
		struct {
			float x, y, z, w;
		};
		float xyzw[4];
	};
} quat;

typedef struct {
	CTMcontext ctmmodel; 
	quat orientation;

	arcan_vobject* parent;
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

quat build_quat(float angdeg, float vx, float vy, float vz)
{
	float res = sin( (angdeg / 18.0f * M_PI) / 2.0f);
	quat  ret = {.x = vx * res, .y = vy * res, .z = vz * res, .w = cos(res)};
	return ret;
}

quat inv_quat(quat src)
{
	quat res = {.x = -src.x, .y = -src.y, .z = -src.z, .w = src.w }; 
	
}

float len_quat(quat src)
{
	return sqrt(src.x * src.x + src.y * src.y + src.z * src.z + src.w * src.w);
}

quat norm_quat(quat src)
{
	float len = len_quat(src);
	quat res = {.x = src.x / len, .y = src.y / len, .z = src.z / len, .w = src.w / len };
	return res;
}

quat mul_quat(quat a, quat b)
{
	quat res;
	res.w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z;
	res.x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y;
	res.y = a.w * b.y + a.y * b.w + a.z * b.x - a.x * b.z;
	res.z = a.w * b.z + a.z * b.w + a.x * b.y - a.y * b.x;
	return res;
}

float* matr_quat(quat a, float* dmatr)
{
	if (dmatr){
		dmatr[0] = 1.0f - 2.0f * (a.y * a.y + a.z * a.z);
		dmatr[1] = 2.0f * (a.x * a.y + a.z * a.w);
		dmatr[2] = 2.0f * (a.x * a.z - a.y * a.w);
		dmatr[3] = 0.0f;
		dmatr[4] = 2.0f * (a.x * a.y - a.z * a.w);
		dmatr[5] = 1.0f - 2.0f * (a.x * a.x + a.z * a.z);
		dmatr[6] = 2.0f * (a.z * a.y + a.x * a.w);
		dmatr[7] = 0.0f;
		dmatr[8] = 2.0f * (a.x * a.z + a.y * a.w);
		dmatr[9] = 2.0f * (a.y * a.z - a.x * a.w);
		dmatr[10]= 1.0f - 2.0f * (a.x * a.x + a.y * a.y);
		dmatr[11]= 0.0f;
		dmatr[12]= 0.0f;
		dmatr[13]= 0.0f;
		dmatr[14]= 0.0f;
		dmatr[15]= 1.0f;
	}
	return dmatr;
}

static void orient_obj(float x, float y, float z, float roll, float pitch, float yaw)
{
	float matr[16];
	quat orient = mul_quat( mul_quat( build_quat(pitch, 1.0, 0.0, 0.0), build_quat(yaw, 0.0, 1.0, 0.0) ), build_quat(roll, 0.0, 0.0, 1.0));
	glTranslatef(x, y, z);
	matr_quat(orient, matr);
	
	glMultMatrixf(matr);
}

/* quatslerp:
 * a, b, t (framefrag) and eps (0.0001),
 * t < 0 (q1) t > 1 q2
 * copy q2 to a3
 * c is dot q1 q3
 * c < 0.0? neg q3, neg c
 * c > 1 - eps
 * 	normalize lerp(q1, q3, t)
 * a = acos(c)
 * quatret = sin(1 - t) * a) * q1 + sin(t * a * q3) / sin a */

/* quatlerp:
 * q1 + t * (q2 - a1) */

static void freemodel(arcan_3dmodel* src)
{
	if (src){
		
	}
}

static void rendermodel(arcan_3dmodel* src, surface_properties props)
{
// 		orient_obj(props.x, props.y
}

static const int8_t ffunc_3d(enum arcan_ffunc_cmd cmd, uint8_t* buf, uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, unsigned mode, vfunc_state state)
{
	if (state.tag == ARCAN_TAG_3DOBJ && state.ptr)
		switch (cmd){
			case ffunc_tick:
			break;
			
			case ffunc_render_direct:
				rendermodel( (arcan_3dmodel*) state.ptr, *(surface_properties*)buf );
			break;
				
			case ffunc_destroy:
				freemodel( (arcan_3dmodel*) state.ptr );
			break;
				
			default:
			break;
		}
		
	return 0;
}

arcan_vobj_id arcan_3d_loadmodel(const char* resource)
{
	arcan_vobj_id rv = ARCAN_EID;
	arcan_3dmodel* newmodel = NULL;
	arcan_vobject* vobj = NULL;
	
	CTMcontext ctx = ctmNewContext(CTM_IMPORT);
	ctmLoad(ctx, resource);

	if (ctmGetError(ctx) == CTM_NONE){
		CTMuint n_verts, n_tris, n_uvs;
		const CTMuint* indices;
		const CTMfloat* verts;
		const CTMfloat* normals;

		newmodel = (arcan_3dmodel*) calloc(sizeof(arcan_3dmodel), 1);
		vfunc_state state = {.tag = ARCAN_TAG_3DOBJ, .ptr = newmodel};

		img_cons empty = {0};
		rv = arcan_video_addfobject(ffunc_3d, state, empty, 1);

		if (rv == ARCAN_EID)
			goto error;

		arcan_vobject* obj = arcan_video_getobject(rv);
		newmodel->parent = obj;
		newmodel->ctmmodel = ctx;

		n_uvs   = ctmGetInteger(newmodel->ctmmodel, CTM_UV_MAP_COUNT);
		n_verts = ctmGetInteger(newmodel->ctmmodel, CTM_VERTEX_COUNT);
		
		/*verts   = ctmGetFloatArray(src->ctmmodel, CTM_VERTICES);
		 *	n_tris  = ctmGetInteger(src->ctmmodel, CTM_TRIANGLE_COUNT);
		 *	indices = ctmGetIntegerArray(src->ctmmodel, CTM_INDICES);
		 *	normals = ctmGetFloatArray(src->ctmmodel, CTM_NORMALS); */
		
		return rv;
	}

error:
	ctmFreeContext(ctx);
	if (vobj) /* if a feed object was set up, this will still call that part */
		arcan_video_deleteobject(rv);
	else if (newmodel)
		free(newmodel);
	
	arcan_warning("arcan_3d_loadmodel(), couldn't load 3dmodel (%s)\n", resource);
	return ARCAN_EID;
}


