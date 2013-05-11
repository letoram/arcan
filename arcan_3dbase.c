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

#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <assert.h>

#include "openctm/openctm.h"

#define GL_GLEXT_PROTOTYPES 1

#ifdef POOR_GL_SUPPORT
 #define GLEW_STATIC
 #define NO_SDL_GLEXT
 #include <glew.h>
#endif

#include <SDL/SDL.h>
#include <SDL/SDL_opengl.h>
#include <SDL/SDL_thread.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"
#include "arcan_shdrmgmt.h"
#include "arcan_video.h"
#include "arcan_videoint.h"

#include "arcan_3dbase_synth.h"

extern struct arcan_video_display arcan_video_display;
static arcan_shader_id default_3dprog;

/* since the 3d is planned as a secondary feature, rather than the primary one,
 * things work slightly different as each 3d object is essentially coupled to 1..n of 2D
 */
enum virttype{
	virttype_camera = 0,
	virttype_pointlight,
	virttype_dirlight,
	virttype_reflection,
	virttype_shadow
};

struct virtobj {
/* inherits orientation from this object (if it resolves else revert to cached) */
	arcan_vobj_id parent;

/* cached orientation */
	orientation direction;
	vector position;
	vector view;
	float projmatr[16];

	enum virttype type;
/* linked list arranged, sorted high-to-low
 * based on virttype */
	struct virtobj* next;
};

typedef struct virtobj virtobj;

typedef struct {
	/* ntxcos == nverts */
    arcan_vobj_id vid;
} texture_set;

typedef struct {
	virtobj* perspectives;
} arcan_3dscene;

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

	SDL_Thread* worker;
	struct geometry* next;
};

typedef struct {
	SDL_mutex* lock;
	struct geometry* geometry;
	arcan_shader_id program;

/* AA-BB */
	vector bbmin;
	vector bbmax;

/* position, opacity etc. are inherited from parent */
	struct {
/* debug geometry (position, normals, bounding box, ...) */
		bool debug_vis;
/* ignore projection matrix */
		bool infinite;
	} flags;

	arcan_vobject* parent;
} arcan_3dmodel;

static arcan_3dscene current_scene = {0};
/*
 * CAMERA Control, generation and manipulation
 */

static virtobj* find_perspective(unsigned camtag)
{
	virtobj* vobj = current_scene.perspectives;
	unsigned ofs = 0;

	while (vobj){
		if (vobj->type == virttype_camera && camtag == ofs){
			return vobj;
		} else ofs++;
		vobj = vobj->next;
	}
	return NULL;
}

static void freemodel(arcan_3dmodel* src)
{
	if (src){
		struct geometry* geom = src->geometry;

		while(geom){
			free(geom->indices);
			free(geom->verts);
			free(geom->normals);
			free(geom->txcos);

			struct geometry* last = geom;

		/* spinlock while loading model */
			while (!geom->complete);

			geom = geom->next;
			free(last);
		}

		SDL_DestroyMutex(src->lock);
		free(src);
	}
}

/*
 * Render-loops, Pass control, Initialization
 */
static void rendermodel(arcan_vobject* vobj, arcan_3dmodel* src, arcan_shader_id baseprog, surface_properties props, float* modelview)
{
	assert(vobj);

	if (props.opa < EPSILON)
		return;

	unsigned cframe = 0;
	float wmvm[16];

/* if there's texture coordsets and an associated vobj,
 * enable texture coord array, normal array etc. */
	if (src->flags.infinite){
		identity_matrix(wmvm);
		glDepthMask(GL_FALSE);
		glEnable(GL_DEPTH_TEST);
	} else
		memcpy(wmvm, modelview, sizeof(float) * 16);

	float dmatr[16], omatr[16];
	float opa   = 1.0;

/* reposition the current modelview, set it as the current shader data,
 * enable vertex attributes and issue drawcalls */
	translate_matrix(wmvm, props.position.x, props.position.y, props.position.z);
	matr_quatf(props.rotation.quaternion, omatr);

	multiply_matrix(dmatr, wmvm, omatr);
	arcan_shader_envv(MODELVIEW_MATR, dmatr, sizeof(float) * 16);

	struct geometry* base = src->geometry;

	while (base){
		if (!base->complete){
			base = base->next;
			continue;
		}

		unsigned counter = 0; /* keep track of how many TUs are in use */
			if (-1 != base->program)
				arcan_shader_activate(base->program);
			else
				arcan_shader_activate(baseprog);

	/* make sure the current program actually uses the attributes that the mesh has */
		int attribs[3] = {arcan_shader_vattribute_loc(ATTRIBUTE_VERTEX),
			arcan_shader_vattribute_loc(ATTRIBUTE_NORMAL),
			arcan_shader_vattribute_loc(ATTRIBUTE_TEXCORD)};

		if (attribs[0] == -1)
			continue;
		else {
			glEnableVertexAttribArray(attribs[0]);
			glVertexAttribPointer(attribs[0], 3, GL_FLOAT, GL_FALSE, 0, base->verts);
		}

		if (attribs[1] != -1 && base->normals){
			glEnableVertexAttribArray(attribs[1]);
			glVertexAttribPointer(attribs[1], 3, GL_FLOAT, GL_FALSE, 0, base->normals);
		} else attribs[1] = -1;

		if (attribs[2] != -1 && base->txcos){
			glEnableVertexAttribArray(attribs[2]);
			glVertexAttribPointer(attribs[2], 2, GL_FLOAT, GL_FALSE, 0, base->txcos);
		} else attribs[2] = -1;

/* It's up to arcan_shader to determine if this will actually involve a program switch or not,
 * blend states etc. are dictated by the images used as texture,
 * and with the frameset_multitexture approach, the first one in the set */

/* Map up all texture-units required,
 * if there are corresponding frames and capacity in the parent vobj,
 * multiple meshes share the same frameset */
		bool blendstate    = false;

		for (unsigned i = 0; i < GL_MAX_TEXTURE_UNITS && (i+cframe) < vobj->frameset_meta.capacity && i < base->nmaps; i++){
			arcan_vobject* frame = vobj->frameset[i+cframe];
			if (!frame)
				continue;

			if (frame->flags.clone)
				frame = frame->parent;

/* only allocate set a sampler if there's a map and a corresponding map- slot in the shader */
			glActiveTexture(GL_TEXTURE0 + i);
			glEnable(GL_TEXTURE_2D);
			glBindTexture(GL_TEXTURE_2D, frame->gl_storage.glid);

			if (blendstate == false){
				surface_properties dprops = {.opa = vobj->current.opa};
				arcan_video_setblend(&dprops, frame);
				blendstate = true;
			}
		}
		
/* Indexed- or direct mode? */
		if (base->indices)
			glDrawElements(GL_TRIANGLES, base->nindices, base->indexformat, base->indices);
		else
			glDrawArrays(GL_TRIANGLES, 0, base->nverts);

		for (int i = 0; i < sizeof(attribs) / sizeof(attribs[0]); i++)
			if (attribs[i] != -1)
				glDisableVertexAttribArray(attribs[i]);

		cframe += base->nmaps;
		base = base->next;
	}

/* revert from infinite geometry */
	if (src->flags.infinite){
		glDepthMask(GL_TRUE);
		glEnable(GL_DEPTH_TEST);
	}
}

static int8_t ffunc_3d(enum arcan_ffunc_cmd cmd, uint8_t* buf, uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, unsigned mode, vfunc_state state)
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

/* Simple one- off rendering pass, no exotic sorting, culling structures, projections or other */
static void process_scene_normal(arcan_vobject_litem* cell, float lerp, float* modelview, float* projection)
{
	glEnable(GL_DEPTH_TEST);
	glCullFace(GL_BACK);

	arcan_vobject_litem* current = cell;
	while (current){
		arcan_vobject* cvo = current->elem;

/* non-negative => 2D part of the pipeline, there's nothing more after this point */
		if (cvo->order >= 0)
			break;

		if (cvo->flags.clone){
			assert(cvo->parent);
		}

/* use parent if we have an instance.. */
		surface_properties dprops;
		arcan_vobject* dvo = cvo->flags.clone ? cvo->parent : cvo;
	
		arcan_resolve_vidprop(cvo, lerp, &dprops);
		rendermodel(dvo, dvo->feed.state.ptr, dvo->gl_storage.program, dprops, modelview);

		current = current->next;
	}
}

/* Chained to the video-pass in arcan_video, stop at the first non-negative order value */
arcan_vobject_litem* arcan_refresh_3d(unsigned camtag, arcan_vobject_litem* cell, float frag, unsigned int destination)
{
	virtobj* base = find_perspective(camtag);

	glClear(GL_DEPTH_BUFFER_BIT);

	if (base){
		float matr[16], dmatr[16];
		arcan_vobject* parent = arcan_video_getobject(base->parent);
		surface_properties dprops = {0};
		if (parent){
			arcan_resolve_vidprop(parent, frag, &dprops);

/* update local cache */
			base->position  = dprops.position;
			matr_quatf(dprops.rotation.quaternion, base->direction.matr);
			base->direction.pitchf = dprops.rotation.pitch;
			base->direction.rollf  = dprops.rotation.roll;
			base->direction.yawf   = dprops.rotation.yaw;
		}

		switch(base->type){
			case virttype_camera :
				arcan_shader_envv(PROJECTION_MATR, base->projmatr, sizeof(float) * 16);
				identity_matrix(matr);
				multiply_matrix(dmatr, matr, base->direction.matr);
				translate_matrix(dmatr, base->position.x, base->position.y, base->position.z);
				process_scene_normal(cell, frag, dmatr, base->projmatr);

			case virttype_dirlight   : break;
			case virttype_pointlight : break;
/* camera with inverted Y, add a stencil at clipping plane and (optionally) render to texture (for water) */
			case virttype_reflection : break;
/* depends on caster source, treat pointlights separately, for infinite dirlights use ortographic projection, else
 * have a caster-specific perspective projection */
			case virttype_shadow : break;
		}
	}

	return cell;
}

static void minmax_verts(vector* minp, vector* maxp, const float* verts, unsigned nverts)
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

/* Go through the indices of a model and reverse the winding- order of its indices or verts so
 * that front/back facing attribute of each triangle is inverted */
arcan_errc arcan_3d_swizzlemodel(arcan_vobj_id dst)
{
	arcan_vobject* vobj = arcan_video_getobject(dst);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj && vobj->feed.state.tag == ARCAN_TAG_3DOBJ){
		arcan_3dmodel* model = (arcan_3dmodel*) vobj->feed.state.ptr;
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
	}

	return rv;
}

arcan_vobj_id arcan_3d_buildbox(float minx, float miny, float minz, float maxx, float maxy, float maxz){
	vfunc_state state = {.tag = ARCAN_TAG_3DOBJ};
	arcan_vobj_id rv = ARCAN_EID;
	img_cons empty = {0};

	rv = arcan_video_addfobject(ffunc_3d, state, empty, 1);

	arcan_3dmodel* newmodel = NULL;
	arcan_vobject* vobj = NULL;

	if (rv != ARCAN_EID){
		newmodel = (arcan_3dmodel*) calloc(sizeof(arcan_3dmodel), 1);
		state.ptr = (void*) newmodel;
		arcan_fatal("arcan_3d_buildbox() unfinished\n");
	}

	return rv;
}

arcan_vobj_id arcan_3d_buildplane(float minx, float minz, float maxx, float maxz, float y, float wdens, float ddens, unsigned nmaps){
	vfunc_state state = {.tag = ARCAN_TAG_3DOBJ};
	arcan_vobj_id rv = ARCAN_EID;
	img_cons empty = {0};

	rv = arcan_video_addfobject(ffunc_3d, state, empty, 1);

	arcan_3dmodel* newmodel = NULL;
	arcan_vobject* vobj = NULL;

	if (rv != ARCAN_EID){
		point minp = {.x = minx, .y = y, .z = minz};
		point maxp = {.x = maxx, .y = y, .z = maxz};
		point step = {.x = wdens, .y = 0, .z = ddens};

		newmodel = (arcan_3dmodel*) calloc(sizeof(arcan_3dmodel), 1);
		state.ptr = (void*) newmodel;
		arcan_video_alterfeed(rv, ffunc_3d, state);

		struct geometry** nextslot = &(newmodel->geometry);
		while (*nextslot)
			nextslot = &((*nextslot)->next);

		*nextslot = (struct geometry*) calloc(sizeof(struct geometry), 1);

		(*nextslot)->nmaps = nmaps;
		newmodel->geometry = *nextslot;
		build_hplane(minp, maxp, step, &newmodel->geometry->verts, (unsigned int**)&newmodel->geometry->indices,
					 &newmodel->geometry->txcos, &newmodel->geometry->nverts, &newmodel->geometry->nindices);

		newmodel->geometry->ntris = newmodel->geometry->nindices / 3;
		arcan_video_allocframes(rv, 1, ARCAN_FRAMESET_SPLIT);
		newmodel->geometry->indexformat = GL_UNSIGNED_INT;
		newmodel->geometry->program = -1;
		newmodel->geometry->complete = true;
	}

	return rv;
}

static void invert_txcos(float* buf, unsigned bufs){
	for (unsigned i = 0; i < bufs; i+= 2){
		float a = buf[i+1];
		buf[i+1] = buf[i];
		buf[i] = a;
	}
}

/* undesired limits with this function is that it ignores
 * many possible vertex attributes (such as colour weighting)
 * and multiple UV maps. It should, furthermore, store these in an
 * interleaved way rather than planar. */
static void loadmesh(struct geometry* dst, CTMcontext* ctx)
{
/* figure out dimensions */
	dst->nverts = ctmGetInteger(ctx, CTM_VERTEX_COUNT);
	dst->ntris  = ctmGetInteger(ctx, CTM_TRIANGLE_COUNT);
	unsigned uvmaps = ctmGetInteger(ctx, CTM_UV_MAP_COUNT);
	unsigned vrtsize = dst->nverts * 3 * sizeof(float);
	dst->verts = (float*) malloc(vrtsize);
	dst->program = -1;

/*	arcan_warning("mesh loaded, %d vertices, %d triangles, %d texture maps\n", dst->nverts, dst->ntris, uvmaps); */
	const CTMfloat* verts   = ctmGetFloatArray(ctx, CTM_VERTICES);
	const CTMfloat* normals = ctmGetFloatArray(ctx, CTM_NORMALS);
	const CTMuint*  indices = ctmGetIntegerArray(ctx, CTM_INDICES);

/* copy and repack */
	if (normals){
		dst->normals = (float*) malloc(vrtsize);
		memcpy(dst->normals, normals, vrtsize);
	}

	memcpy(dst->verts, verts, vrtsize);

/* lots of memory to be saved, so worth the trouble */
	if (indices){
		dst->nindices = dst->ntris * 3;

		if (dst->nindices < 256){
			uint8_t* buf = (uint8_t*) malloc(dst->nindices * sizeof(uint8_t));
			dst->indexformat = GL_UNSIGNED_BYTE;

			for (unsigned i = 0; i < dst->nindices; i++)
				buf[i] = indices[i];

			dst->indices = (void*) buf;
		}
		else if (dst->nindices < 65536){
			uint16_t* buf = (uint16_t*) malloc(dst->nindices * sizeof(uint16_t));
			dst->indexformat = GL_UNSIGNED_SHORT;

			for (unsigned i = 0; i < dst->nindices; i++)
				buf[i] = indices[i];

			dst->indices = (void*) buf;
		}
		else{
			uint32_t* buf = (uint32_t*) malloc(dst->nindices * sizeof(uint32_t));
			dst->indexformat = GL_UNSIGNED_INT;
			for (unsigned i = 0; i < dst->nindices; i++)
				buf[i] = indices[i];

			dst->indices = (void*) buf;
		}
	}

/* we require the model to be presplit on texture,
 * so n maps but 1 set of txcos */
	if (uvmaps > 0){
        dst->nmaps = 1;
		unsigned txsize = sizeof(float) * 2 * dst->nverts;
		dst->txcos = (float*) malloc(txsize);
		memcpy(dst->txcos, ctmGetFloatArray(ctx, CTM_UV_MAP_1), txsize);
	}
}

arcan_errc arcan_3d_meshshader(arcan_vobj_id dst, arcan_shader_id shid, unsigned slot)
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
	char* resource;
};

static int threadloader(void* arg)
{
	struct threadarg* threadarg = (struct threadarg*) arg;
	CTMcontext ctx = ctmNewContext(CTM_IMPORT);
	ctmLoad(ctx, threadarg->resource);

	if (ctmGetError(ctx) == CTM_NONE){
		loadmesh(threadarg->geom, ctx);

//		SDL_mutexP(threadarg->model->lock);
//			minmax_verts(&threadarg->model->bbmin, &threadarg->model->bbmax, threadarg->geom->verts, threadarg->geom->nverts);
//		SDL_mutexV(threadarg->model->lock);
	}

/* nonetheless, unlock the slot for the main rendering loop,
 * or free ( which is locking deferred ) */
	threadarg->geom->complete = true;
	ctmFreeContext(ctx);
	free(threadarg->resource);
	free(threadarg);
	return 0;
}

arcan_errc arcan_3d_addmesh(arcan_vobj_id dst, const char* resource, unsigned nmaps)
{
	arcan_vobject* vobj = arcan_video_getobject(dst);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

/* 2d frameset and set of vids associated as textures with models are weakly linked */
	if (vobj && vobj->feed.state.tag == ARCAN_TAG_3DOBJ)
	{
		arcan_3dmodel* dst = (arcan_3dmodel*) vobj->feed.state.ptr;
		struct threadarg* arg = (struct threadarg*) malloc(sizeof(struct threadarg));
		arg->model = dst;
		arg->resource = strdup(resource);

/* find last elem and add */
		struct geometry** nextslot = &(dst->geometry);
		while (*nextslot)
			nextslot = &((*nextslot)->next);

		*nextslot = (struct geometry*) calloc(sizeof(struct geometry), 1);

		(*nextslot)->nmaps = nmaps;
		arg->geom = *nextslot;
		SDL_CreateThread(threadloader, (void*) arg);

		rv = ARCAN_OK;
	} else
		rv = ARCAN_ERRC_BAD_RESOURCE;

	return rv;
}

arcan_errc arcan_3d_scalevertices(arcan_vobj_id vid)
{
	arcan_vobject* vobj = arcan_video_getobject(vid);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	/* 2d frameset and set of vids associated as textures with models are weakly linked */
	if (vobj && vobj->feed.state.tag == ARCAN_TAG_3DOBJ)
	{
		arcan_3dmodel* dst = (arcan_3dmodel*) vobj->feed.state.ptr;
		struct geometry* geom = dst->geometry;

		while (geom){
			while (!geom->complete);
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
	}

    return rv;
}

arcan_vobj_id arcan_3d_emptymodel()
{
	arcan_vobj_id rv = ARCAN_EID;
	img_cons econs = {0};
	arcan_3dmodel* newmodel = (arcan_3dmodel*) calloc(sizeof(arcan_3dmodel), 1);
	vfunc_state state = {.tag = ARCAN_TAG_3DOBJ, .ptr = newmodel};

	rv = arcan_video_addfobject(ffunc_3d, state, econs, 1);

	if (rv != ARCAN_EID){
		newmodel->parent = arcan_video_getobject(rv);
		newmodel->lock = SDL_CreateMutex();

	} else
		free(newmodel);

	return rv;
}

arcan_errc arcan_3d_baseorient(arcan_vobj_id dst, float roll, float pitch, float yaw)
{
	arcan_vobject* vobj = arcan_video_getobject(dst);
	arcan_errc rv       = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj && vobj->feed.state.tag == ARCAN_TAG_3DOBJ){
		arcan_3dmodel* model = vobj->feed.state.ptr;
		struct geometry* geom = model->geometry;

/* 1. create the rotation matrix by mapping to a quaternion */
		quat repr = build_quat_taitbryan(roll, pitch, yaw);
		float matr[16];
		matr_quatf(repr, matr);

/* 2. iterate all geometries connected to the model */
		while (geom){
			while (!geom->complete);
	
			float*  verts = geom->verts;

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

		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_3d_camtag_parent(unsigned camtag, arcan_vobj_id vid)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(vid);
	virtobj* vrtobj = find_perspective(camtag);

	if (vrtobj && vobj){
		vrtobj->parent    = vid;
		vrtobj->position  = vobj->current.position;

		matr_quatf(vobj->current.rotation.quaternion, vrtobj->direction.matr);
		vrtobj->direction.pitchf = vobj->current.rotation.pitch;
		vrtobj->direction.rollf  = vobj->current.rotation.roll;
		vrtobj->direction.yawf   = vobj->current.rotation.yaw;
	}

	return rv;
}

void arcan_3d_setdefaults()
{
	current_scene.perspectives = calloc( sizeof(virtobj), 1);
	virtobj* cam = current_scene.perspectives;

	float aspect = (float) arcan_video_display.width / (float) arcan_video_display.height;
	if (aspect < 1.0)
		aspect = (float) arcan_video_display.height / (float) arcan_video_display.width;

	build_projection_matrix(cam->projmatr, 0.1, 100.0, aspect, 45.0);

	cam->type = virttype_camera;
	cam->position = build_vect(0, 0, 0);
}
