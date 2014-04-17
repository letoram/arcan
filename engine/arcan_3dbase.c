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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301,USA.
 *
 */

#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <stdint.h>
#include <stdbool.h>
#include <pthread.h>
#include <unistd.h>
#include <string.h>

#include <assert.h>

#include <openctm/openctm.h>

#include GL_HEADERS

#ifndef GL_MAX_TEXTURE_UNITS
#define GL_MAX_TEXTURE_UNITS 8 
#endif

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"
#include "arcan_shdrmgmt.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_3dbase.h"

extern struct arcan_video_display arcan_video_display;

enum camtag_facing
{
	FRONT = GL_FRONT,
	BACK  = GL_BACK,
	BOTH  = GL_NONE
};

struct camtag_data {
	enum camtag_facing facing;
	float projection[16];
};

struct geometry {
	unsigned nmaps;
	arcan_shader_id program;

	unsigned nverts;
	float* verts;
	float* txcos;
	unsigned ntris;
	unsigned nindices;
	GLenum indexformat;
	void* indices;

	volatile bool complete;

/* nnormals == nverts */
	float* normals;

	pthread_t worker;
	struct geometry* next;
};

typedef struct {
	pthread_mutex_t lock;
	int work_count;

	struct geometry* geometry;
	arcan_shader_id program;

/* AA-BB */
	vector bbmin;
	vector bbmax;

/* position, opacity etc. are inherited from parent */
	struct {
/* debug geometry (position, normals, bounding box, ...) */
		bool debug_vis;

/* unless this flag is set AND there are no pending
 * load operations, some operations will be deferred. */
		bool complete;

/* ignore projection matrix */
		bool infinite;
	} flags;

	struct {
		bool scale;
		bool swizzle;
		bool orient; 
		vector orientf;
	} deferred;
	
	arcan_vobject* parent;
} arcan_3dmodel;

/* 
static void build_quadbox(float n, float p, float** verts, 
	float** txcos, unsigned* nverts)
{
	float lut[6][12] = {
		{n,p,p,   n,p,n,   p,p,n,   p,p,p}, 
		{n,n,n,   n,n,p,   p,n,p,   p,n,n},
		{n,p,p,   n,n,p,   n,n,n,   n,p,n},
		{p,p,n,   p,n,n,   p,n,p,   p,p,p},
		{n,p,n,   n,n,n,   p,n,n,   p,p,n},
		{p,p,p,   p,n,p,   n,n,p,   n,p,p} 
	};

	*nverts = 24;
	*verts = malloc(sizeof(float) * (*nverts * 3));
	*txcos = malloc(sizeof(float) * (*nverts * 2));

	unsigned ofs = 0, tofs = 0;
	for (unsigned i = 0; i < 6; i++){
		*txcos[tofs++] = 1.0f; 
		*txcos[tofs++] = 0.0;
		*txcos[tofs++] = 1.0f; 
		*txcos[tofs++] = 1.0;
		*txcos[tofs++] = 0.0f; 
		*txcos[tofs++] = 1.0; 
		*txcos[tofs++] = 0.0f; 
		*txcos[tofs++] = 0.0; 
			
	 	*verts[ofs++] = lut[i][0]; 
		*verts[ofs++] = lut[i][1]; 
		*verts[ofs++] = lut[i][2]; 
	 	*verts[ofs++] = lut[i][3]; 
		*verts[ofs++] = lut[i][4]; 
		*verts[ofs++] = lut[i][5];
		*verts[ofs++] = lut[i][6];
	  *verts[ofs++] = lut[i][7]; 
		*verts[ofs++] = lut[i][8]; 
		*verts[ofs++] = lut[i][9]; 
		*verts[ofs++] = lut[i][10];
	 	*verts[ofs++] = lut[i][11]; 
	}
}
*/

static void build_hplane(point min, point max, point step,
						 float** verts, unsigned** indices, float** txcos,
						 unsigned* nverts, unsigned* nindices)
{
	point delta = {
		.x = max.x - min.x,
		.y = max.y,
		.z = max.z - min.z
	};

	unsigned nx = ceil(delta.x / step.x);
	unsigned nz = ceil(delta.z / step.z);
	
	*nverts = nx * nz;
	*verts = arcan_alloc_mem(sizeof(float) * (*nverts) * 3,
		ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_PAGE);

	*txcos = arcan_alloc_mem(sizeof(float) * (*nverts) * 2,
		ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_PAGE);
	
	unsigned vofs = 0, tofs = 0;
	for (unsigned x = 0; x < nx; x++)
		for (unsigned z = 0; z < nz; z++){
			(*verts)[vofs++] = min.x + (float)x*step.x;
			(*verts)[vofs++] = min.y;
			(*verts)[vofs++] = min.z + (float)z*step.z;
			(*txcos)[tofs++] = (float)x / (float)nx;
			(*txcos)[tofs++] = (float)z / (float)nz;
		}

	vofs = 0; tofs = 0;
#define GETVERT(X,Z)( ( (X) * nz) + Z)
	*indices = arcan_alloc_mem(sizeof(unsigned) * (*nverts) * 3 * 2,
			ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_PAGE);

		for (unsigned x = 0; x < nx-1; x++)
			for (unsigned z = 0; z < nz-1; z++){
				(*indices)[vofs++] = GETVERT(x, z);
				(*indices)[vofs++] = GETVERT(x, z+1);
				(*indices)[vofs++] = GETVERT(x+1, z+1);
				tofs++;
				
				(*indices)[vofs++] = GETVERT(x, z);
				(*indices)[vofs++] = GETVERT(x+1, z+1);
				(*indices)[vofs++] = GETVERT(x+1, z);
				tofs++;
			}
			
	*nindices = vofs;
}


static void freemodel(arcan_3dmodel* src)
{
	if (!src)
		return;
		
	struct geometry* geom = src->geometry;

/* always make sure the model is loaded before freeing */
	while(geom){
		pthread_join(geom->worker, NULL);
		geom = geom->next;
	}

	geom = src->geometry;

	while(geom){
		arcan_mem_free(geom->indices);
		arcan_mem_free(geom->verts);
		arcan_mem_free(geom->normals);
		arcan_mem_free(geom->txcos);
		struct geometry* last = geom;
		geom = geom->next;
		last->next = (struct geometry*) 0xdead;
		arcan_mem_free(last);
	}

	pthread_mutex_destroy(&src->lock);
	arcan_mem_free(src);
}

static void push_deferred(arcan_3dmodel* model)
{
	if (model->work_count > 0)
		return;

	if (!model->flags.complete)
		return;

	if (model->deferred.scale){
		arcan_3d_scalevertices(model->parent->cellid); 
		model->deferred.scale = false;
	}	

	if (model->deferred.swizzle){
		arcan_3d_swizzlemodel(model->parent->cellid);
		model->deferred.swizzle = false;
	}

	if (model->deferred.orient){
		arcan_3d_baseorient(model->parent->cellid,
			model->deferred.orientf.x, 
			model->deferred.orientf.y, 
			model->deferred.orientf.z
		);
		model->deferred.orient = false;
	}
}


/*
 * Render-loops, Pass control, Initialization
 */
static void rendermodel(arcan_vobject* vobj, arcan_3dmodel* src, 
	arcan_shader_id baseprog, surface_properties props, float* modelview)
{
	assert(vobj);

	if (props.opa < EPSILON || !src->flags.complete || src->work_count > 0)
		return;
	
	unsigned cframe = 0;

	float _Alignas(16) wmvm[16];
	float _Alignas(16) dmatr[16];
	float _Alignas(16) omatr[16];
	
	memcpy(wmvm, modelview, sizeof(float) * 16);

/* reposition the current modelview, set it as the current shader data,
 * enable vertex attributes and issue drawcalls */
	translate_matrix(wmvm, props.position.x, props.position.y, props.position.z);
	matr_quatf(props.rotation.quaternion, omatr);

	multiply_matrix(dmatr, wmvm, omatr);
	arcan_shader_envv(MODELVIEW_MATR, dmatr, sizeof(float) * 16);
	arcan_shader_envv(OBJ_OPACITY, &props.opa, sizeof(float));

	struct geometry* base = src->geometry;

	while (base){
			if (-1 != base->program){
				arcan_shader_activate(base->program);
			}
			else{
				arcan_shader_activate(baseprog);
			}

/* make sure the current program actually uses the attributes from the mesh */
		int attribs[3] = {
			arcan_shader_vattribute_loc(ATTRIBUTE_VERTEX),
			arcan_shader_vattribute_loc(ATTRIBUTE_NORMAL),
			arcan_shader_vattribute_loc(ATTRIBUTE_TEXCORD)
		};

		if (attribs[0] == -1)
			goto step;
		else {
			glEnableVertexAttribArray(attribs[0]);
			glVertexAttribPointer(attribs[0], 3, GL_FLOAT, GL_FALSE, 0, base->verts);
		}

		if (attribs[1] != -1 && base->normals){
			glEnableVertexAttribArray(attribs[1]);
			glVertexAttribPointer(attribs[1], 3, GL_FLOAT, GL_FALSE,0, base->normals);
		} 
		else 
			attribs[1] = -1;

		if (attribs[2] != -1 && base->txcos){
			glEnableVertexAttribArray(attribs[2]);
			glVertexAttribPointer(attribs[2], 2, GL_FLOAT, GL_FALSE, 0, base->txcos);
		} 
		else 
			attribs[2] = -1;

/* It's up to arcan_shdrmgmt to determine if this will actually involve 
 * a program switch or not, blend states etc. are dictated by the images 
 * used as texture, and with the frameset_multitexture approach, 
 * the first one in the set */

/* Map up all texture-units required,
 * if there are corresponding frames and capacity in the parent vobj,
 * multiple meshes share the same frameset */
		bool blendstate    = false;

		for (unsigned i = 0; i < GL_MAX_TEXTURE_UNITS && (i+cframe) < 
			vobj->frameset_meta.capacity && i < base->nmaps; i++){
			arcan_vobject* frame = vobj->frameset[i+cframe];

			if (!frame)
				goto step;

			if (frame->feed.state.tag == ARCAN_TAG_ASYNCIMGLD)
				goto step;

			if (frame->feed.state.tag == ARCAN_TAG_ASYNCIMGRD)
				arcan_video_joinasynch(frame, true, false);

			if (frame->flags.clone)
				frame = frame->parent;

/* only allocate set a sampler if there's a map and a 
 * corresponding map- slot in the shader */
			glActiveTexture(GL_TEXTURE0 + i);
			glEnable(GL_TEXTURE_2D);
			glBindTexture(GL_TEXTURE_2D, frame->vstore->vinf.text.glid);

			if (blendstate == false){
				surface_properties dprops = {.opa = vobj->current.opa};
				arcan_video_setblend(&dprops, frame);
				blendstate = true;
			}
		}
		
/* Indexed, direct or VBO */
		if (base->indices)
			glDrawElements(GL_TRIANGLES, base->nindices,
				base->indexformat, base->indices);
		else
			glDrawArrays(GL_TRIANGLES, 0, base->nverts);

		for (int i = 0; i < sizeof(attribs) / sizeof(attribs[0]); i++)
			if (attribs[i] != -1)
				glDisableVertexAttribArray(attribs[i]);
	
step:
		cframe += base->nmaps;
		base = base->next;
	}
}

static int8_t ffunc_3d(enum arcan_ffunc_cmd cmd, uint8_t* buf, uint32_t s_buf, 
	uint16_t width, uint16_t height, uint8_t bpp, unsigned mode,vfunc_state state)
{
	if (state.tag == ARCAN_TAG_3DOBJ && state.ptr){
		switch (cmd){
		case ffunc_tick:
		break;

		case ffunc_destroy:
			freemodel( (arcan_3dmodel*) state.ptr );
		break;

		default:
		break;
		}
	}

	return 0;
}

/* normal scene process, except stops after no objects with infinite 
 * flag (skybox, skygeometry etc.) */
static arcan_vobject_litem* process_scene_infinite(
	arcan_vobject_litem* cell, float lerp, float* modelview)
{
	arcan_vobject_litem* current = cell;

	glDisable(GL_DEPTH_TEST);
	glDepthMask(GL_FALSE);

	while (current){
		arcan_vobject* cvo = current->elem;
		arcan_vobject* dvo = cvo->flags.clone ? cvo->parent : cvo;

		arcan_3dmodel* obj3d = dvo->feed.state.ptr;
	
		if (cvo->order >= 0 || obj3d->flags.infinite == false)
			break;

		surface_properties dprops;
		arcan_resolve_vidprop(cvo, lerp, &dprops);
		rendermodel(dvo, obj3d, dvo->program, dprops, modelview);

		current = current->next;
	}

	return current;
}

static void process_scene_normal(arcan_vobject_litem* cell, float lerp, 
	float* modelview)
{
	glEnable(GL_DEPTH_TEST);
	glDepthMask(GL_TRUE);

	arcan_vobject_litem* current = cell;
	while (current){
		arcan_vobject* cvo = current->elem;

/* non-negative => 2D part of the pipeline, there's nothing 
 * more after this point */
		if (cvo->order >= 0)
			break;

/* use parent if we have an instance.. */
		surface_properties dprops;
		arcan_vobject* dvo = cvo->flags.clone ? cvo->parent : cvo;
		
		arcan_resolve_vidprop(cvo, lerp, &dprops);
		rendermodel(dvo, dvo->feed.state.ptr, dvo->program, 
			dprops, modelview);

		current = current->next;
	}
}

/* Chained to the video-pass in arcan_video, stop at the 
 * first non-negative order value */
arcan_vobject_litem* arcan_refresh_3d(arcan_vobj_id camtag, 
	arcan_vobject_litem* cell, float fract)
{
	arcan_vobject* camobj = arcan_video_getobject(camtag);

	glClear(GL_DEPTH_BUFFER_BIT);
	if (!camobj || camobj->feed.state.tag != ARCAN_TAG_3DCAMERA)
		return cell;	
	
	struct camtag_data* camera = camobj->feed.state.ptr;
	float _Alignas(16) matr[16];
	float _Alignas(16) dmatr[16];
	float _Alignas(16) omatr[16];

	surface_properties dprop;
	arcan_resolve_vidprop(camobj, fract, &dprop);

	arcan_shader_envv(PROJECTION_MATR, camera->projection, sizeof(float) * 16);

	identity_matrix(matr);
	scale_matrix(matr, dprop.scale.x, dprop.scale.y, dprop.scale.z);
	matr_quatf(norm_quat(dprop.rotation.quaternion), omatr);
	multiply_matrix(dmatr, matr, omatr);
		
	arcan_3dmodel* obj3d = cell->elem->feed.state.ptr;

	glEnable(GL_CULL_FACE);
	switch (camera->facing)
	{
	case FRONT: glCullFace(GL_BACK); break;
	case BACK:  glCullFace(GL_FRONT); break;
	case BOTH:  glDisable(GL_CULL_FACE);
	}

	if (obj3d->flags.infinite)
		cell = process_scene_infinite(cell, fract, dmatr);

	translate_matrix(dmatr, dprop.position.x, dprop.position.y, dprop.position.z);
	process_scene_normal(cell, fract, dmatr); 

	glDisable(GL_CULL_FACE);
	return cell;
}

static void minmax_verts(vector* minp, vector* maxp, 
	const float* verts, unsigned nverts)
{
	for (unsigned i = 0; i < nverts * 3; i += 3){
		vector a = {.x = verts[i], .y = verts[i+1], .z = verts[i+2]};
		if (a.x < minp->x) minp->x = a.x;
		if (a.y < minp->y) minp->y = a.y;
		if (a.z < minp->z) minp->z = a.z;
		if (a.x > maxp->x) maxp->x = a.x;
		if (a.y > maxp->y) maxp->y = a.y;
		if (a.z > maxp->z) maxp->z = a.z;
	}
}

/* Go through the indices of a model and reverse the winding- 
 * order of its indices or verts so that front/back facing attribute of 
 * each triangle is inverted */
arcan_errc arcan_3d_swizzlemodel(arcan_vobj_id dst)
{
	arcan_vobject* vobj = arcan_video_getobject(dst);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj->feed.state.tag != ARCAN_TAG_3DOBJ)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	arcan_3dmodel* model = (arcan_3dmodel*) vobj->feed.state.ptr;
	pthread_mutex_lock(&model->lock);
	if (model->work_count != 0 || !model->flags.complete){
		model->deferred.swizzle = true;
		pthread_mutex_unlock(&model->lock);
		return ARCAN_OK;
	}

	struct geometry* curr = model->geometry;
	while (curr) {
		if (curr->indices){
			unsigned* indices = curr->indices;
			for (unsigned i = 0; i <curr->nindices * 3; i+= 3){
				unsigned t1[3] = { indices[i], indices[i+1], indices[i+2] };
				unsigned tmp = t1[0];
				t1[0] = t1[2]; t1[2] = tmp;
			}
		} else {
			float* verts = curr->verts;

			for (unsigned i = 0; i < curr->nverts * 9; i+= 9){
				vector v1 = { .x = verts[i  ], .y = verts[i+1], .z = verts[i+2] };
				vector v3 = { .x = verts[i+6], .y = verts[i+7], .z = verts[i+8] };
				verts[i  ] = v3.x; verts[i+1] = v3.y; verts[i+2] = v3.z;
				verts[i+6] = v1.x; verts[i+7] = v1.y; verts[i+8] = v1.z;
			}
		}

		curr = curr->next;
	}

	pthread_mutex_unlock(&model->lock);
	return rv;
}

arcan_vobj_id arcan_3d_buildbox(point min, point max, unsigned nmaps)
{
	vfunc_state state = {.tag = ARCAN_TAG_3DOBJ};
	arcan_vobj_id rv = ARCAN_EID;
	img_cons empty = {0};

	rv = arcan_video_addfobject(ffunc_3d, state, empty, 1);
	arcan_fatal("arcan_3d_buildbox() incomplete \n");
	
	return rv;
}

arcan_vobj_id arcan_3d_buildcube(float mpx, float mpy, 
	float mpz, float base, unsigned nmaps)
{
	vfunc_state state = {.tag = ARCAN_TAG_3DOBJ};
	img_cons empty = {0};
	arcan_vobj_id rv = arcan_video_addfobject(ffunc_3d, state, empty, 1);
	if (rv == ARCAN_EID)
		return rv;
	
	arcan_fatal("arcan_3d_buildcube() incomplete \n");

	return rv;
}

arcan_vobj_id arcan_3d_buildplane(float minx, float minz, float maxx,float maxz,
	float y, float wdens, float ddens, unsigned nmaps){
	vfunc_state state = {.tag = ARCAN_TAG_3DOBJ};
	arcan_vobj_id rv = ARCAN_EID;
	img_cons empty = {0};

	rv = arcan_video_addfobject(ffunc_3d, state, empty, 1);

	arcan_3dmodel* newmodel = NULL;

	if (rv != ARCAN_EID){
		point minp = {.x = minx, .y = y, .z = minz};
		point maxp = {.x = maxx, .y = y, .z = maxz};
		point step = {.x = wdens, .y = 0, .z = ddens};

		newmodel = arcan_alloc_mem(sizeof(arcan_3dmodel), ARCAN_MEM_VTAG,
			ARCAN_MEM_BZERO, ARCAN_MEMALIGN_PAGE);
	
		pthread_mutex_init(&newmodel->lock, NULL);

		state.ptr = (void*) newmodel;
		arcan_video_alterfeed(rv, ffunc_3d, state);

		struct geometry** nextslot = &(newmodel->geometry);
		while (*nextslot)
			nextslot = &((*nextslot)->next);

		*nextslot = arcan_alloc_mem(sizeof(struct geometry), ARCAN_MEM_VTAG,
			ARCAN_MEM_BZERO, ARCAN_MEMALIGN_PAGE);

		(*nextslot)->nmaps = nmaps;
		newmodel->geometry = *nextslot;
		build_hplane(minp, maxp, step, &newmodel->geometry->verts, 
			(unsigned int**)&newmodel->geometry->indices,
					 &newmodel->geometry->txcos, &newmodel->geometry->nverts, 
					 &newmodel->geometry->nindices);

		newmodel->geometry->ntris = newmodel->geometry->nindices / 3;
		arcan_video_allocframes(rv, 1, ARCAN_FRAMESET_SPLIT);
		newmodel->geometry->indexformat = GL_UNSIGNED_INT;
		newmodel->geometry->program = -1;
		newmodel->geometry->complete = true;
	}

	return rv;
}

/*
static void invert_txcos(float* buf, unsigned bufs){
	for (unsigned i = 0; i < bufs; i+= 2){
		float a = buf[i+1];
		buf[i+1] = buf[i];
		buf[i] = a;
	}
}
*/

/* undesired limits with this function is that it ignores
 * many possible vertex attributes (such as colour weighting)
 * and multiple UV maps. It should, furthermore, store these in an
 * interleaved way rather than planar. */
static void loadmesh(struct geometry* dst, CTMcontext* ctx)
{
	dst->program = -1;

/* figure out dimensions */
	dst->nverts = ctmGetInteger(ctx, CTM_VERTEX_COUNT);
	dst->ntris  = ctmGetInteger(ctx, CTM_TRIANGLE_COUNT);
	unsigned uvmaps = ctmGetInteger(ctx, CTM_UV_MAP_COUNT);
	unsigned vrtsize = dst->nverts * 3 * sizeof(float);

	const CTMfloat* verts   = ctmGetFloatArray(ctx, CTM_VERTICES);
	const CTMfloat* normals = ctmGetFloatArray(ctx, CTM_NORMALS);
	const CTMuint*  indices = ctmGetIntegerArray(ctx, CTM_INDICES);

/* copy and repack */
	if (normals)
		dst->normals = arcan_alloc_fillmem(normals, vrtsize,
		ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_PAGE);

	dst->verts = arcan_alloc_fillmem(verts, vrtsize,
		ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_PAGE);

/* lots of memory to be saved, so worth the trouble */
	if (indices){
		dst->nindices = dst->ntris * 3;
		if (dst->nindices < 256){
			uint8_t* buf = arcan_alloc_mem(dst->nindices,
				ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_PAGE);

			dst->indexformat = GL_UNSIGNED_BYTE;

			for (unsigned i = 0; i < dst->nindices; i++)
				buf[i] = indices[i];

			dst->indices = buf;
		}
		else if (dst->nindices < 65536){
			uint16_t* buf = arcan_alloc_mem(dst->nindices * sizeof(GLushort),
				ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_PAGE);

			dst->indexformat = GL_UNSIGNED_SHORT;

			for (unsigned i = 0; i < dst->nindices; i++)
				buf[i] = indices[i];

			dst->indices = buf;
		}
		else{
			uint32_t* buf = arcan_alloc_mem( dst->nindices * sizeof(GLuint),
				ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_PAGE);

				dst->indexformat = GL_UNSIGNED_INT;

			for (unsigned i = 0; i < dst->nindices; i++)
				buf[i] = indices[i];

			dst->indices = buf;
		}
	}

/* we require the model to be presplit on texture,
 * so n maps but 1 set of txcos */
	if (uvmaps > 0){
        dst->nmaps = 1;
		unsigned txsize = sizeof(float) * 2 * dst->nverts;
		dst->txcos = arcan_alloc_fillmem(ctmGetFloatArray(ctx, CTM_UV_MAP_1),
			txsize, ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_PAGE); 
	}
}

arcan_errc arcan_3d_meshshader(arcan_vobj_id dst, 
	arcan_shader_id shid, unsigned slot)
{
	arcan_vobject* vobj = arcan_video_getobject(dst);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj && vobj->feed.state.tag == ARCAN_TAG_3DOBJ){
		struct geometry* cur = ((arcan_3dmodel*)vobj->feed.state.ptr)->geometry;
		while (cur && slot){
			cur = cur->next;
			slot--;
		}

		if (cur && slot == 0){
			cur->program = shid;
			rv = ARCAN_OK;
		}
		else rv = ARCAN_ERRC_BAD_ARGUMENT;
	}

	return rv;
}

struct threadarg{
	arcan_3dmodel* model;
	struct geometry* geom;
	data_source resource;
	map_region datamap;
	off_t readofs;
};

static CTMuint ctm_readfun(void* abuf, CTMuint acount, void* userdata)
{
	struct threadarg* reg = userdata;
	size_t ntr = acount > reg->datamap.sz - reg->readofs ? 
		reg->datamap.sz - reg->readofs : acount;

	memcpy(abuf, reg->datamap.ptr + reg->readofs, ntr);
	reg->readofs += ntr;

	return ntr;
}

static void* threadloader(void* arg)
{
	struct threadarg* threadarg = (struct threadarg*) arg;

	CTMcontext ctx = ctmNewContext(CTM_IMPORT);
	ctmLoadCustom(ctx, ctm_readfun, threadarg); 
	arcan_3dmodel* model = threadarg->model;

	if (ctmGetError(ctx) == CTM_NONE){
		loadmesh(threadarg->geom, ctx);
	}

/* nonetheless, unlock the slot for the main rendering loop,
 * or free ( which is locking deferred ) */
	pthread_mutex_lock(&model->lock);
	threadarg->geom->complete = true;
	model->work_count--;
	pthread_mutex_unlock(&threadarg->model->lock);

	push_deferred(model);
	ctmFreeContext(ctx);

	arcan_mem_free(threadarg);
	
	return NULL;
}

arcan_errc arcan_3d_addmesh(arcan_vobj_id dst, 
	data_source resource, unsigned nmaps)
{
	arcan_vobject* vobj = arcan_video_getobject(dst);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;
		
	arcan_3dmodel* model = vobj->feed.state.ptr;

	if (vobj->feed.state.tag != ARCAN_TAG_3DOBJ ||
		model->flags.complete == true)
		return ARCAN_ERRC_UNACCEPTED_STATE;

/* 2d frameset and set of vids associated as textures 
 * with models are weakly linked */
	struct threadarg* arg = arcan_alloc_mem(sizeof(struct threadarg),
		ARCAN_MEM_THREADCTX, 0, ARCAN_MEMALIGN_NATURAL);

	arg->model = model;
	arg->resource = resource;
	arg->readofs = 0;
	arg->datamap = arcan_map_resource(&arg->resource, false);
	if (arg->datamap.ptr == NULL){
		arcan_mem_free(arg);
		return ARCAN_ERRC_BAD_RESOURCE;
	}

/* find last elem and add */
	struct geometry** nextslot = &(model->geometry);
	while (*nextslot)
		nextslot = &((*nextslot)->next);

	*nextslot = arcan_alloc_mem(sizeof(struct geometry), ARCAN_MEM_VTAG,
		ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

	(*nextslot)->nmaps = nmaps;
	arg->geom = *nextslot;
	
	pthread_mutex_lock(&model->lock);
	model->work_count++;
	pthread_mutex_unlock(&model->lock);

	pthread_create(&arg->geom->worker, NULL, threadloader, (void*) arg);

	return ARCAN_OK;
}

arcan_errc arcan_3d_scalevertices(arcan_vobj_id vid)
{
	arcan_vobject* vobj = arcan_video_getobject(vid);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;
	
	if (vobj->feed.state.tag != ARCAN_TAG_3DOBJ){
			return ARCAN_ERRC_UNACCEPTED_STATE;
	}
	
	arcan_3dmodel* dst = (arcan_3dmodel*) vobj->feed.state.ptr;
	
	pthread_mutex_lock(&dst->lock);
	if (dst->work_count != 0 || !dst->flags.complete){
		dst->deferred.scale = true;
		pthread_mutex_unlock(&dst->lock);
		return ARCAN_OK;
	}
	struct geometry* geom = dst->geometry;

	while (geom){
		minmax_verts(&dst->bbmin, &dst->bbmax, geom->verts, geom->nverts);
		geom = geom->next;
	}

	geom = dst->geometry;
	float sf, tx, ty, tz;

	float dx = dst->bbmax.x - dst->bbmin.x;
	float dy = dst->bbmax.y - dst->bbmin.y;
	float dz = dst->bbmax.z - dst->bbmin.z;

	if (dz > dy && dz > dx)
		sf = 2.0 / dz;
	else if (dy > dz && dy > dx)
		sf = 2.0 / dy;
	else
		sf = 2.0 / dx;

	dst->bbmax = mul_vectorf(dst->bbmax, sf);
	dst->bbmin = mul_vectorf(dst->bbmin, sf);

	tx = (0.0 - dst->bbmin.x) - (dst->bbmax.x - dst->bbmin.x) * 0.5;
	ty = (0.0 - dst->bbmin.y) - (dst->bbmax.y - dst->bbmin.y) * 0.5;
	tz = (0.0 - dst->bbmin.z) - (dst->bbmax.z - dst->bbmin.z) * 0.5;

	dst->bbmax.x += tx; dst->bbmin.x += tx;
	dst->bbmax.y += ty; dst->bbmin.y += ty;
	dst->bbmax.z += tz; dst->bbmin.z += tz;

	while(geom){
		for (unsigned i = 0; i < geom->nverts * 3; i += 3){
			geom->verts[i]   = tx + geom->verts[i]   * sf;
			geom->verts[i+1] = ty + geom->verts[i+1] * sf;
			geom->verts[i+2] = tz + geom->verts[i+2] * sf;
		}

		geom = geom->next;
	}

	pthread_mutex_unlock(&dst->lock);
	return ARCAN_OK;
}

arcan_errc arcan_3d_infinitemodel(arcan_vobj_id id, bool state)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	if (!vobj)
	 return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj->feed.state.tag != ARCAN_TAG_3DOBJ)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	arcan_3dmodel* dstobj = vobj->feed.state.ptr;
	dstobj->flags.infinite = state;

	return ARCAN_OK;	
}

arcan_errc arcan_3d_finalizemodel(arcan_vobj_id id)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj->feed.state.tag != ARCAN_TAG_3DOBJ)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	arcan_3dmodel* dstobj = vobj->feed.state.ptr;
	dstobj->flags.complete = true;
	
	push_deferred(dstobj);
	return ARCAN_OK;
}

arcan_vobj_id arcan_3d_emptymodel()
{
	arcan_vobj_id rv = ARCAN_EID;
	img_cons econs = {0};
	arcan_3dmodel* newmodel = arcan_alloc_mem(sizeof(arcan_3dmodel),
		ARCAN_MEM_VTAG, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
	vfunc_state state = {.tag = ARCAN_TAG_3DOBJ, .ptr = newmodel};

	rv = arcan_video_addfobject(ffunc_3d, state, econs, 1);

	if (rv != ARCAN_EID){
		newmodel->parent = arcan_video_getobject(rv);
		pthread_mutex_init(&newmodel->lock, NULL);
	} else
		arcan_mem_free(newmodel);

	return rv;
}

arcan_errc arcan_3d_baseorient(arcan_vobj_id dst, 
	float roll, float pitch, float yaw)
{
	arcan_vobject* vobj = arcan_video_getobject(dst);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj->feed.state.tag != ARCAN_TAG_3DOBJ)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	arcan_3dmodel* model = vobj->feed.state.ptr;
	pthread_mutex_lock(&model->lock);

	if (model->work_count != 0 || !model->flags.complete){
		model->deferred.orient = true;
		model->deferred.orientf.x = roll;
		model->deferred.orientf.y = pitch;
		model->deferred.orientf.z = yaw;
		pthread_mutex_unlock(&model->lock);
		return ARCAN_OK;
	}

	struct geometry* geom = model->geometry;

/* 1. create the rotation matrix by mapping to a quaternion */
	quat repr = build_quat_taitbryan(roll, pitch, yaw);
	float matr[16];
	matr_quatf(repr, matr);

/* 2. iterate all geometries connected to the model */
	while (geom){
		float* verts = geom->verts;

/* 3. sweep through all the vertexes in the model */
		for (unsigned i = 0; i < geom->nverts * 3; i += 3){
			float xyz[4] = {verts[i], verts[i+1], verts[i+2], 1.0};
			float out[4];

/* 4. transform the current vertex */
			mult_matrix_vecf(matr, xyz, out);
			verts[i] = out[0]; verts[i+1] = out[1]; verts[i+2] = out[2];
		}

		geom = geom->next;
	}

	pthread_mutex_unlock(&model->lock);
	return ARCAN_OK;
}

arcan_errc arcan_3d_camtag(arcan_vobj_id vid, 
	float projection[16], bool front, bool back) 
{
	arcan_vobject* vobj = arcan_video_getobject(vid);

	vobj->owner->camtag = vobj->cellid;
	struct camtag_data* camobj = arcan_alloc_mem(sizeof(struct camtag_data),
		ARCAN_MEM_VTAG, 0, ARCAN_MEMALIGN_NATURAL);
	
	memcpy(camobj->projection, projection, sizeof(float) * 16);

/* we cull the inverse */
	if (front && back)
		camobj->facing = BOTH;
	else if (front)
		camobj->facing = FRONT;
	else
		camobj->facing = BACK;

	vobj->feed.state.ptr = camobj;
	vobj->feed.state.tag = ARCAN_TAG_3DCAMERA; 

	return ARCAN_OK;
}
