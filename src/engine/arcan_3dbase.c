/*
 * Copyright 2009-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
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

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_shmif.h"
#include "arcan_event.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_3dbase.h"

extern struct arcan_video_display arcan_video_display;

struct camtag_data {
	_Alignas(16) float projection[16];
	_Alignas(16) float mvm[16];
	_Alignas(16) vector wpos;
	float near;
	float far;
	enum agp_mesh_flags flags;
};

struct geometry {
	size_t nmaps;
	agp_shader_id program;

	struct mesh_storage_t store;

	bool complete;
	bool threaded;

	pthread_t worker;
	struct geometry* next;
};

typedef struct {
	pthread_mutex_t lock;
	int work_count;

	struct geometry* geometry;

/* AA-BB */
	vector bbmin;
	vector bbmax;
	float radius;

/* position, opacity etc. are inherited from parent */
	struct {
/* debug geometry (position, normals, bounding box, ...) */
		bool debug;

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

static void build_hplane(point min, point max, point step,
	float** verts, unsigned** indices, float** txcos,
	size_t* nverts, size_t* nindices)
{
	point delta = {
		.x = max.x - min.x,
		.y = max.y,
		.z = max.z - min.z
	};

	size_t nx = ceil(delta.x / step.x);
	size_t nz = ceil(delta.z / step.z);

	*nverts = nx * nz;
	*verts = arcan_alloc_mem(sizeof(float) * (*nverts) * 3,
		ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_PAGE);

	*txcos = arcan_alloc_mem(sizeof(float) * (*nverts) * 2,
		ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_PAGE);

	size_t vofs = 0, tofs = 0;
	for (size_t x = 0; x < nx; x++)
		for (size_t z = 0; z < nz; z++){
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

	for (size_t x = 0; x < nx-1; x++)
		for (size_t z = 0; z < nz-1; z++){
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
		if (geom->threaded){
			pthread_join(geom->worker, NULL);
			geom->threaded = false;
		}
		geom = geom->next;
	}

	geom = src->geometry;

	while(geom){
		arcan_mem_free(geom->store.indices);
		arcan_mem_free(geom->store.verts);
		arcan_mem_free(geom->store.normals);
		arcan_mem_free(geom->store.txcos);
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
	agp_shader_id baseprog, surface_properties props, float* modelview,
	enum agp_mesh_flags flags)
{
	assert(vobj);

	if (props.opa < EPSILON || !src->flags.complete || src->work_count > 0)
		return;

	float _Alignas(16) wmvm[16];
	float _Alignas(16) dmatr[16];
	float _Alignas(16) omatr[16];

	memcpy(wmvm, modelview, sizeof(float) * 16);

/* reposition the current modelview, set it as the current shader data,
 * enable vertex attributes and issue drawcalls */
	translate_matrix(wmvm, props.position.x, props.position.y, props.position.z);
	matr_quatf(props.rotation.quaternion, omatr);

	multiply_matrix(dmatr, wmvm, omatr);
	agp_shader_envv(MODELVIEW_MATR, dmatr, sizeof(float) * 16);
	agp_shader_envv(OBJ_OPACITY, &props.opa, sizeof(float));

	struct geometry* base = src->geometry;

	agp_blendstate(vobj->blendmode);
	int fset_ofs = vobj->frameset ? vobj->frameset->index : 0;

	while (base){
		agp_shader_activate(base->program > 0 ? base->program : baseprog);

		if (!vobj->frameset)
			agp_activate_vstore(vobj->vstore);
		else {
			if (base->nmaps == 1){
				agp_activate_vstore(vobj->frameset->frames[fset_ofs].frame);
				fset_ofs = (fset_ofs + 1) % vobj->frameset->n_frames;
			}
			else if (base->nmaps > 1){
				struct storage_info_t* backing[base->nmaps];
				for (size_t i = 0; i < base->nmaps; i++){
					backing[i] = vobj->frameset->frames[fset_ofs].frame;
					fset_ofs = (fset_ofs + 1) % vobj->frameset->n_frames;
				}
				agp_activate_vstore_multi(backing, base->nmaps);
			}
			else
				;
		}

/* NOTE: we do not currently manage multiple texture coordinate sets for
 * meshes with multiple maps, slated for 0.7 */
		agp_submit_mesh(&base->store, flags);
		base = base->next;
	}
}

enum arcan_ffunc_rv arcan_ffunc_3dobj FFUNC_HEAD
{
	if ( (state.tag == ARCAN_TAG_3DOBJ ||
		state.tag == ARCAN_TAG_3DCAMERA) && state.ptr){

		switch (cmd){
		case FFUNC_TICK:
		break;

		case FFUNC_DESTROY:
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
	arcan_vobject_litem* cell, float lerp, float* modelview,
	enum agp_mesh_flags flags)
{
	arcan_vobject_litem* current = cell;

	while (current){
		arcan_vobject* cvo = current->elem;

		arcan_3dmodel* obj3d = cvo->feed.state.ptr;

		if (cvo->order >= 0 || obj3d->flags.infinite == false)
			break;

		surface_properties dprops;

		arcan_resolve_vidprop(cvo, lerp, &dprops);
		rendermodel(cvo, obj3d, cvo->program,
				dprops, modelview, flags & MESH_FACING_NODEPTH);

		current = current->next;
	}

	return current;
}

static void process_scene_normal(arcan_vobject_litem* cell,
	float lerp, float* modelview, enum agp_mesh_flags flags)
{
	arcan_vobject_litem* current = cell;
	while (current){
		arcan_vobject* cvo = current->elem;

/* non-negative => 2D part of the pipeline, there's nothing
 * more after this point */
		if (cvo->order >= 0)
			break;

		surface_properties dprops;

		arcan_resolve_vidprop(cvo, lerp, &dprops);
		rendermodel(cvo, cvo->feed.state.ptr, cvo->program,
			dprops, modelview, flags);

		current = current->next;
	}
}

arcan_errc arcan_3d_projectbb(arcan_vobj_id modelid,
	arcan_vobj_id camid, vector* dst){

	arcan_vobject* cam = arcan_video_getobject(camid);
	arcan_vobject* model = arcan_video_getobject(modelid);

	if (!cam || !model || cam->feed.state.tag != ARCAN_TAG_3DCAMERA ||
		model->feed.state.tag != ARCAN_TAG_3DOBJ)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	return ARCAN_OK;
}

void arcan_3d_viewray(arcan_vobj_id camtag,
	int x, int y, float fract, vector* pos, vector* ang)
{
	float z;
	arcan_vobject* camobj = arcan_video_getobject(camtag);
	if(!camobj || camobj->feed.state.tag != ARCAN_TAG_3DCAMERA)
		return;
	struct camtag_data* camera = camobj->feed.state.ptr;
	struct monitor_mode mode = platform_video_dimensions();

	dev_coord(&pos->x, &pos->y, &z,
		x, y, mode.width, mode.height, camera->near, camera->far);

	vector p1 = unproject_matrix(pos->x, pos->y, 0.0,
		camera->mvm, camera->projection);

	vector p2 = unproject_matrix(pos->x, pos->y, 1.0,
		camera->mvm, camera->projection);

	p1.z = camera->wpos.z + camera->near;
	p2.z = camera->wpos.z + camera->far;

	*pos = p1;
	*ang = norm_vector( sub_vector(p2, p1) );
}

bool arcan_3d_obj_bb_intersect(arcan_vobj_id cam,
	arcan_vobj_id obj, int x, int y)
{
	arcan_vobject* model = arcan_video_getobject(obj);
	if (!model || model->feed.state.tag != ARCAN_TAG_3DOBJ)
		return false;

	vector ray_pos;
	vector ray_dir;

	float rad = ((arcan_3dmodel*)model->feed.state.ptr)->radius;
	arcan_3d_viewray(cam, x, y, arcan_video_display.c_lerp, &ray_pos, &ray_dir);

	float d1, d2;

	return ray_sphere(&ray_pos, &ray_dir,
		&model->current.position, rad, &d1, &d2);
}

/* Chained to the video-pass in arcan_video, stop at the
 * first non-negative order value */
arcan_vobject_litem* arcan_3d_refresh(arcan_vobj_id camtag,
	arcan_vobject_litem* cell, float fract)
{
	arcan_vobject* camobj = arcan_video_getobject(camtag);

	if (!camobj || camobj->feed.state.tag != ARCAN_TAG_3DCAMERA)
		return cell;

	agp_pipeline_hint(PIPELINE_3D);

	struct camtag_data* camera = camobj->feed.state.ptr;
	float _Alignas(16) matr[16];
	float _Alignas(16) dmatr[16];
	float _Alignas(16) omatr[16];

	surface_properties dprop;
	arcan_resolve_vidprop(camobj, fract, &dprop);

	agp_shader_activate(agp_default_shader(BASIC_3D));
	agp_shader_envv(PROJECTION_MATR, camera->projection, sizeof(float) * 16);

	identity_matrix(matr);
	scale_matrix(matr, dprop.scale.x, dprop.scale.y, dprop.scale.z);
	matr_quatf(norm_quat(dprop.rotation.quaternion), omatr);
	multiply_matrix(dmatr, matr, omatr);

	arcan_3dmodel* obj3d = cell->elem->feed.state.ptr;

	if (obj3d->flags.infinite)
		cell = process_scene_infinite(cell, fract, dmatr, camera->flags);

	struct camtag_data* cdata = camobj->feed.state.ptr;
	cdata->wpos = dprop.position;
	translate_matrix(dmatr, dprop.position.x, dprop.position.y, dprop.position.z);
	memcpy(cdata->mvm, dmatr, sizeof(float) * 16);

	process_scene_normal(cell, fract, dmatr, camera->flags);

	return cell;
}

static void minmax_verts(vector* minp, vector* maxp,
	const float* verts, unsigned nverts)
{
	for (size_t i = 0; i < nverts * 3; i += 3){
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
		if (curr->store.indices){
			unsigned* indices = curr->store.indices;
			for (size_t i = 0; i <curr->store.n_indices * 3; i+= 3){
				unsigned t1[3] = { indices[i], indices[i+1], indices[i+2] };
				unsigned tmp = t1[0];
				t1[0] = t1[2]; t1[2] = tmp;
			}
		} else {
			float* verts = curr->store.verts;

			for (size_t i = 0; i < curr->store.n_vertices * 9; i+= 9){
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

arcan_vobj_id arcan_3d_pointcloud(size_t count, size_t nmaps)
{
	if (count == 0)
		return ARCAN_EID;

	vfunc_state state = {.tag = ARCAN_TAG_3DOBJ};
	img_cons empty = {0};
	arcan_vobj_id rv = arcan_video_addfobject(FFUNC_3DOBJ, state, empty, 1);

	if (rv == ARCAN_EID)
		return ARCAN_EID;

	arcan_3dmodel* newmodel = arcan_alloc_mem(sizeof(arcan_3dmodel),
		ARCAN_MEM_VTAG, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
	state.ptr = newmodel;
	arcan_video_alterfeed(rv, FFUNC_3DOBJ, state);
	pthread_mutex_init(&newmodel->lock, NULL);

	newmodel->geometry = arcan_alloc_mem(sizeof(struct geometry), ARCAN_MEM_VTAG,
		ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
	newmodel->geometry->store.n_vertices = count;
	newmodel->geometry->nmaps = nmaps;
	newmodel->geometry->store.verts = arcan_alloc_mem(sizeof(float) * count * 3,
		ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_PAGE);
	newmodel->geometry->store.txcos = arcan_alloc_mem(sizeof(float) * count * 2,
		ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_PAGE);

	float step = 2.0f / sqrtf(count);

	float cz = -1;
	float cx = -1;
	float* dbuf = newmodel->geometry->store.verts;
	float* tbuf = newmodel->geometry->store.txcos;

/* evenly distribute texture coordinates, randomly distribute vertices */
	while(count--){
		cx = cx + step;
		if (cx > 1){
			cx = -1;
			cz = cz + step;
			}

		float x = 1.0 - (float)rand()/(float)(RAND_MAX/2.0);
		float y = 1.0 - (float)rand()/(float)(RAND_MAX/2.0);
		float z = 1.0 - (float)rand()/(float)(RAND_MAX/2.0);

		*dbuf++ = x;
		*dbuf++ = y;
		*dbuf++ = z;
		*tbuf++ = (cx + 1.0) / 2.0;
		*tbuf++ = (cz + 1.0) / 2.0;
	}

	newmodel->radius = 1.0;

	vector bbmin = {-1, -1, -1};
	vector bbmax = { 1,  1,  1};
	newmodel->bbmin = bbmin;
	newmodel->bbmax = bbmax;
	newmodel->flags.complete = true;
	newmodel->flags.debug = true;
	newmodel->geometry->nmaps = nmaps;
	newmodel->geometry->store.type = AGP_MESH_POINTCLOUD;

	return rv;
}

arcan_vobj_id arcan_3d_buildbox(float w, float h, float d, size_t nmaps)
{
	vfunc_state state = {.tag = ARCAN_TAG_3DOBJ};
	img_cons empty = {0};
	arcan_vobj_id rv = arcan_video_addfobject(FFUNC_3DOBJ, state, empty, 1);

	if (rv == ARCAN_EID)
		return rv;

/* wait with setting the full model until we know we have a fobject */
	arcan_3dmodel* newmodel = arcan_alloc_mem(sizeof(arcan_3dmodel),
		ARCAN_MEM_VTAG, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
	state.ptr = (void*) newmodel;
	arcan_video_alterfeed(rv, FFUNC_3DOBJ, state);
	pthread_mutex_init(&newmodel->lock, NULL);
	arcan_video_allocframes(rv, 1, ARCAN_FRAMESET_SPLIT);
	newmodel->geometry = arcan_alloc_mem(sizeof(struct geometry), ARCAN_MEM_VTAG,
		ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

	newmodel->geometry->store.type = AGP_MESH_TRISOUP;
	newmodel->geometry->nmaps = nmaps;
	newmodel->geometry->complete = true;
	newmodel->geometry->store.n_triangles = 2 * 6;

	float verts[] = {
		 w, h, d,  -w,  h,  d,  -w, -h,  d,   w, -h,  d,
		 w, h, d,   w, -h,  d,   w, -h, -d,   w,  h, -d,
		 w, h, d,   w,  h, -d,  -w,  h, -d,  -w,  h,  d,
		-w, h, d,  -w,  h, -d,  -w, -h, -d,  -w, -h,  d,
		-w,-h,-d,   w, -h, -d,   w, -h,  d,  -w, -h,  d,
		 w,-h,-d,  -w, -h, -d,  -w,  h, -d,   w,  h, -d
	};
	newmodel->geometry->store.verts = arcan_alloc_fillmem(verts, sizeof(verts),
		ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_SIMD);
	newmodel->geometry->store.n_vertices = sizeof(verts) / sizeof(verts[0]) / 3;

	float normals[] = {
		 0, 0, 1,  0, 0, 1,  0, 0, 1,  0, 0, 1,
		 1, 0, 0,  1, 0, 0,  1, 0, 0,  1, 0, 0,
		 0, 1, 0,  0, 1, 0,  0, 1, 0,  0, 1, 0,
		-1, 0, 0,-1, 0, 0, -1, 0, 0, -1, 0, 0,
		 0,-1, 0,  0,-1, 0,  0,-1, 0,  0,-1, 0,
		 0, 0,-1,  0, 0,-1,  0, 0,-1,  0, 0,-1
	};
	newmodel->geometry->store.normals = arcan_alloc_fillmem(
		normals, sizeof(normals), ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_SIMD);

	unsigned int indices[] = {
	 0, 1, 2,  2, 3, 0,
	 4, 5, 6,  6, 7, 4,
	 8, 9,10, 10,11, 8,
	 12,13,14,14,15,12,
	 16,17,18,18,19,16,
	 20,21,22,22,23,20
	};
	newmodel->geometry->store.indices = arcan_alloc_fillmem(
		indices, sizeof(indices), ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_SIMD);
	newmodel->geometry->store.n_vertices = sizeof(verts) / sizeof(verts[0]) / 3;
	newmodel->geometry->store.n_indices = 36;

	float txcos[] = {
		0, 0, 1, 0, 1, 1, 0, 1,
		0, 0, 1, 0, 1, 0, 0, 1,
		0, 0, 1, 0, 1, 1, 0, 1,
		0, 0, 1, 0, 1, 1, 0, 0,
		0, 0, 1, 0, 1, 1, 0, 1,
		0, 0, 1, 0, 1, 1, 0, 1
	};
	newmodel->geometry->store.txcos = arcan_alloc_fillmem(txcos, sizeof(txcos),
		ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_SIMD);

	vector bbmin = {.x = -w, .y = -h, .z = -d};
	vector bbmax = {.x =  w, .y =  h, .z =  d};

	newmodel->radius = d;
	newmodel->bbmin = bbmin;
	newmodel->bbmax = bbmax;
	newmodel->geometry->complete = true;
	newmodel->flags.complete = true;

	return rv;
}

arcan_vobj_id arcan_3d_buildplane(float minx, float minz, float maxx,float maxz,
	float y, float wdens, float ddens, size_t nmaps)
{
	vfunc_state state = {.tag = ARCAN_TAG_3DOBJ};
	arcan_vobj_id rv = ARCAN_EID;
	img_cons empty = {0};

/* fail on unsolvable dimension constraints */
	if ( (maxx < minx || wdens <= 0 || wdens >= maxx - minx) ||
		(maxz < minz || ddens <= 0 || ddens >= maxz - minz) )
		return ARCAN_ERRC_BAD_ARGUMENT;

	rv = arcan_video_addfobject(FFUNC_3DOBJ, state, empty, 1);
	arcan_3dmodel* newmodel = NULL;

	if (rv == ARCAN_EID)
		return rv;

	point minp = {.x = minx,  .y = y, .z = minz};
	point maxp = {.x = maxx,  .y = y, .z = maxz};
	point step = {.x = wdens, .y = 0, .z = ddens};

	newmodel = arcan_alloc_mem(sizeof(arcan_3dmodel), ARCAN_MEM_VTAG,
		ARCAN_MEM_BZERO, ARCAN_MEMALIGN_PAGE);

	pthread_mutex_init(&newmodel->lock, NULL);

	state.ptr = (void*) newmodel;
	arcan_video_alterfeed(rv, FFUNC_3DOBJ, state);

	struct geometry** nextslot = &(newmodel->geometry);
	while (*nextslot)
		nextslot = &((*nextslot)->next);

	*nextslot = arcan_alloc_mem(sizeof(struct geometry), ARCAN_MEM_VTAG,
		ARCAN_MEM_BZERO, ARCAN_MEMALIGN_PAGE);

	(*nextslot)->nmaps = nmaps;
	newmodel->geometry = *nextslot;
	newmodel->geometry->store.type = AGP_MESH_TRISOUP;

	struct geometry* dst = newmodel->geometry;

	build_hplane(minp, maxp, step, &dst->store.verts, &dst->store.indices,
		&dst->store.txcos, &dst->store.n_vertices, &dst->store.n_indices);

	dst->store.n_triangles = newmodel->geometry->store.n_indices / 3;
	arcan_video_allocframes(rv, 1, ARCAN_FRAMESET_SPLIT);

/* though we do know the bounding box and shouldn't need to calculate
 * or iterate, plan is to possibly add transform / lookup functions
 * during creation step, so this is a precaution */
	minmax_verts(&newmodel->bbmin, &newmodel->bbmax,
			dst->store.verts, dst->store.n_vertices);
	dst->complete = true;
	newmodel->flags.complete = true;

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
/* figure out dimensions */
	dst->store.n_vertices = ctmGetInteger(ctx, CTM_VERTEX_COUNT);
	dst->store.n_triangles = ctmGetInteger(ctx, CTM_TRIANGLE_COUNT);
	unsigned uvmaps = ctmGetInteger(ctx, CTM_UV_MAP_COUNT);
	unsigned vrtsize = dst->store.n_vertices * 3 * sizeof(float);

	const CTMfloat* verts   = ctmGetFloatArray(ctx, CTM_VERTICES);
	const CTMfloat* normals = ctmGetFloatArray(ctx, CTM_NORMALS);
	const CTMuint*  indices = ctmGetIntegerArray(ctx, CTM_INDICES);

/* copy and repack */
	if (normals)
		dst->store.normals = arcan_alloc_fillmem(normals, vrtsize,
		ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_PAGE);

	dst->store.verts = arcan_alloc_fillmem(verts, vrtsize,
		ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_PAGE);

/* lots of memory to be saved, so worth the trouble */
	if (indices){
		dst->store.n_indices = dst->store.n_triangles * 3;
		uint32_t* buf = arcan_alloc_mem( dst->store.n_indices * sizeof(unsigned),
			ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_PAGE);

		for (unsigned i = 0; i < dst->store.n_indices; i++)
			buf[i] = indices[i];

		dst->store.indices = buf;
	}

/* we require the model to be presplit on texture,
 * so n maps but 1 set of txcos */
	if (uvmaps > 0){
		dst->nmaps = 1;
		unsigned txsize = sizeof(float) * 2 * dst->store.n_vertices;
		dst->store.txcos = arcan_alloc_fillmem(ctmGetFloatArray(ctx, CTM_UV_MAP_1),
			txsize, ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_PAGE);
	}
}

arcan_errc arcan_3d_meshshader(arcan_vobj_id dst,
	agp_shader_id shid, unsigned slot)
{
	arcan_vobject* vobj = arcan_video_getobject(dst);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj->feed.state.tag != ARCAN_TAG_3DOBJ)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	struct geometry* cur = ((arcan_3dmodel*)vobj->feed.state.ptr)->geometry;
	while (cur && slot){
		cur = cur->next;
		slot--;
	}

	if (cur && slot <= 0)
		cur->program = shid;
	else
		return ARCAN_ERRC_BAD_ARGUMENT;

	return ARCAN_OK;
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
	(*nextslot)->store.type = AGP_MESH_TRISOUP;

	arg->geom = *nextslot;

	pthread_mutex_lock(&model->lock);
	model->work_count++;
	pthread_mutex_unlock(&model->lock);

	arg->geom->threaded = true;
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
		minmax_verts(&dst->bbmin, &dst->bbmax,
				geom->store.verts, geom->store.n_vertices);
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
		for (unsigned i = 0; i < geom->store.n_vertices * 3; i += 3){
			geom->store.verts[i]   = tx + geom->store.verts[i]   * sf;
			geom->store.verts[i+1] = ty + geom->store.verts[i+1] * sf;
			geom->store.verts[i+2] = tz + geom->store.verts[i+2] * sf;
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

	if (dstobj->flags.complete == false){
		dstobj->flags.complete = true;
		push_deferred(dstobj);
	}

	return ARCAN_OK;
}

arcan_vobj_id arcan_3d_emptymodel()
{
	arcan_vobj_id rv = ARCAN_EID;
	img_cons econs = {0};
	arcan_3dmodel* newmodel = arcan_alloc_mem(sizeof(arcan_3dmodel),
		ARCAN_MEM_VTAG, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
	vfunc_state state = {.tag = ARCAN_TAG_3DOBJ, .ptr = newmodel};

	rv = arcan_video_addfobject(FFUNC_3DOBJ, state, econs, 1);

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
	_Alignas(16) float matr[16];
	matr_quatf(repr, matr);

/* 2. iterate all geometries connected to the model */
	while (geom){
		float* verts = geom->store.verts;

/* 3. sweep through all the vertexes in the model */
		for (unsigned i = 0; i < geom->store.n_vertices * 3; i += 3){
			_Alignas(16) float xyz[4] = {verts[i], verts[i+1], verts[i+2], 1.0};
			_Alignas(16) float out[4];

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
	float near, float far, float ar, float fov, bool front, bool back)
{
	arcan_vobject* vobj = arcan_video_getobject(vid);

	if (vobj->feed.state.ptr)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	vobj->owner->camtag = vobj->cellid;

	struct camtag_data* camobj = arcan_alloc_mem(
		sizeof(struct camtag_data), ARCAN_MEM_VTAG, 0, ARCAN_MEMALIGN_SIMD);

	camobj->near = near;
	camobj->far = far;
	build_projection_matrix(camobj->projection, near, far, ar, fov);

/* we cull the inverse */
	if (front && back)
		camobj->flags = MESH_FACING_BOTH;
	else if (front)
		camobj->flags = MESH_FACING_FRONT;
	else
		camobj->flags = MESH_FACING_BACK;

	vfunc_state state = {.tag = ARCAN_TAG_3DCAMERA, .ptr = camobj};
	arcan_video_alterfeed(vid, FFUNC_3DOBJ, state);

	FL_SET(vobj, FL_FULL3D);

	return ARCAN_OK;
}
