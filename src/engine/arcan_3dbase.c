/*
 * Copyright 2009-2019, Björn Ståhl
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
#include <stdarg.h>
#include <inttypes.h>

#include <assert.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_shmif.h"
#include "arcan_event.h"
#include "arcan_video.h"
#include "arcan_videoint.h"
#include "arcan_3dbase.h"
#include "arcan_vr.h"

extern struct arcan_video_display arcan_video_display;

struct camtag_data {
	_Alignas(16) float projection[16];
	_Alignas(16) float mvm[16];
	_Alignas(16) vector wpos;
	float near;
	float far;
	float line_width;
	enum agp_mesh_flags flags;
	struct arcan_vr_ctx* vrref;
};

struct geometry {
	size_t nmaps;
	agp_shader_id program;

	struct agp_mesh_store store;

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

	struct arcan_vr_ctx* vrref;

	arcan_vobject* parent;
} arcan_3dmodel;

static void build_plane(point min, point max, point step,
	float** verts, unsigned** indices, float** txcos,
	size_t* nverts, size_t* nindices, bool vertical)
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
			if (vertical){
				(*verts)[vofs++] = min.z + (float)z*step.z;
				(*verts)[vofs++] = min.y;
			}
			else {
				(*verts)[vofs++] = min.y;
				(*verts)[vofs++] = min.z + (float)z*step.z;
			}
			(*txcos)[tofs++] = (float)x / (float)(nx-1);
			(*txcos)[tofs++] = (float)z / (float)(nz-1);
		}

	vofs = 0;
#define GETVERT(X,Z)( ( (X) * nz) + (Z))
	*indices = arcan_alloc_mem(
		sizeof(unsigned) * (nx-1) * (nz-1) * 6,
		ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_PAGE
	);

	for (size_t x = 0; x < nx-1; x++)
		for (size_t z = 0; z < nz-1; z++){
			(*indices)[vofs++] = GETVERT(x+1, z+1);
			(*indices)[vofs++] = GETVERT(x, z+1);
			(*indices)[vofs++] = GETVERT(x, z);

			(*indices)[vofs++] = GETVERT(x+1, z);
			(*indices)[vofs++] = GETVERT(x+1, z+1);
			(*indices)[vofs++] = GETVERT(x, z);
		}

	*nindices = vofs;
}

static void freemodel(arcan_3dmodel* src)
{
	if (!src)
		return;

	if (src->vrref){
		arcan_vr_release(src->vrref,
			src->parent ? src->parent->cellid : ARCAN_EID);
		src->vrref = NULL;
	}

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

/*
 * special case is where we share buffer between main and sub-geom,
 * as the agp mesh store has its own concept of a shared buffer, we
 * also need re-use between stores for various animation/modelling
 * options.
 * This means that the base geometry (first slot) can have a store
 * and subgeometry can alias at offsets for everything except the
 * shared pointer or vertex pointer
 **/
	uintptr_t base;
	if (geom->store.shared_buffer)
		base = (uintptr_t) geom->store.shared_buffer;
	else
		base = (uintptr_t) geom->store.verts;

/* save the base geometry slot for last */
	geom = geom->next;
	while(geom){
		uintptr_t base2;
		if (geom->store.shared_buffer)
			base2 = (uintptr_t) geom->store.shared_buffer;
		else
			base2 = (uintptr_t) geom->store.verts;

/* subgeom is its own geometry */
		if (base2 != base)
			agp_drop_mesh(&geom->store);

/* delink from list and free */
		struct geometry* last = geom;
		geom = geom->next;
		last->next = NULL;
		arcan_mem_free(last);
	}

	agp_drop_mesh(&src->geometry->store);
	arcan_mem_free(src->geometry);
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

static void dump_matr(float* matr, const char* pref)
{
	printf("%s = {\n"
"%.4f %.4f %.4f %.4f\n"
"%.4f %.4f %.4f %.4f\n"
"%.4f %.4f %.4f %.4f\n"
"%.4f %.4f %.4f %.4f\n"
"}\n", pref,
matr[0], matr[4], matr[8], matr[12],
matr[1], matr[5], matr[9], matr[13],
matr[2], matr[6], matr[10], matr[14],
matr[3], matr[7], matr[11], matr[15]);
}

/*
 * Render-loops, Pass control, Initialization
 */
static void rendermodel(arcan_vobject* vobj, arcan_3dmodel* src,
	agp_shader_id baseprog, surface_properties props, float* view,
	enum agp_mesh_flags flags)
{
	assert(vobj);

	if (props.opa < EPSILON || !src->flags.complete || src->work_count > 0)
		return;

/* transform order: scale */
	float _Alignas(16) scale[16] = {
		props.scale.x, 0.0, 0.0, 0.0,
		0.0, props.scale.y, 0.0, 0.0,
		0.0, 0.0, props.scale.z, 0.0,
		0.0, 0.0, 0.0,           1.0
	};

  float ox = vobj->origo_ofs.x;
	float oy = vobj->origo_ofs.y;
	float oz = vobj->origo_ofs.z;

/* point-translation to origo_ofs */
	translate_matrix(scale, ox, oy, oz);

/* rotate */
	float _Alignas(16) orient[16];
	matr_quatf(props.rotation.quaternion, orient);
	float _Alignas(16) model[16];
	multiply_matrix(model, orient, scale);

/* object translation */
	translate_matrix(model,
		props.position.x - ox,
		props.position.y - oy,
		props.position.z - oz
	);

	float _Alignas(16) out[16];
	multiply_matrix(out, view, model);

	agp_shader_envv(MODELVIEW_MATR, out, sizeof(float) * 16);
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
				struct agp_vstore* backing[base->nmaps];
				for (size_t i = 0; i < base->nmaps; i++){
					backing[i] = vobj->frameset->frames[fset_ofs].frame;
					fset_ofs = (fset_ofs + 1) % vobj->frameset->n_frames;
				}
				agp_activate_vstore_multi(backing, base->nmaps);
			}
			else
				;
		}

		agp_shader_envv(MODELVIEW_MATR, out, sizeof(float) * 16);
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
			if (state.tag == ARCAN_TAG_3DOBJ)
				freemodel( (arcan_3dmodel*) state.ptr );
			else {
				arcan_vobject* camobj = arcan_video_getobject(srcid);
				struct camtag_data* camera = state.ptr;
				if (camera->vrref){
					arcan_vr_release(camera->vrref, camobj->cellid);
					camera->vrref = NULL;
				}
				arcan_mem_free(camera);
				camobj->feed.state.ptr = NULL;
			}
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
	arcan_vobject_litem* cell, float lerp, float* view,
	enum agp_mesh_flags flags)
{
	arcan_vobject_litem* current = cell;
	struct rendertarget* rtgt = arcan_vint_current_rt();
	ssize_t min = 0, max = 65536;
	if (rtgt){
		min = rtgt->min_order;
		max = rtgt->max_order;
	}

	while (current){
		arcan_vobject* cvo = current->elem;
		arcan_3dmodel* obj3d = cvo->feed.state.ptr;

		if (cvo->order >= 0 || obj3d->flags.infinite == false)
			break;

		ssize_t abs_o = cvo->order * -1;
		if (abs_o < min){
			current = current->next;
			continue;
		}

		if (abs_o > max)
			break;

		surface_properties dprops;

		arcan_resolve_vidprop(cvo, lerp, &dprops);
		rendermodel(cvo,
			obj3d, cvo->program, dprops, view, flags | MESH_FACING_NODEPTH);

		current = current->next;
	}

	return current;
}

static void process_scene_normal(arcan_vobject_litem* cell,
	float lerp, float* modelview, enum agp_mesh_flags flags)
{
	arcan_vobject_litem* current = cell;
	struct rendertarget* rtgt = arcan_vint_current_rt();
	ssize_t min = 0, max = 65536;
	if (rtgt){
		min = rtgt->min_order;
		max = rtgt->max_order;
	}

	while (current){
		arcan_vobject* cvo = current->elem;

/* non-negative => 2D part of the pipeline, there's nothing
 * more after this point */
		if (cvo->order >= 0)
			break;

		ssize_t abs_o = cvo->order * -1;
		if (abs_o < min){
			current = current->next;
			continue;
		}

		if (abs_o > max)
			break;

		surface_properties dprops;
		arcan_3dmodel* model = cvo->feed.state.ptr;
		if (model->vrref)
			dprops = cvo->current;
		else
			arcan_resolve_vidprop(cvo, lerp, &dprops);
		rendermodel(cvo, model, cvo->program, dprops, modelview, flags);

		current = current->next;
	}
}

arcan_errc arcan_3d_bindvr(arcan_vobj_id id, struct arcan_vr_ctx* vrref)
{
	arcan_vobject* model = arcan_video_getobject(id);
	if (!model)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (model->feed.state.tag == ARCAN_TAG_3DOBJ){
		((arcan_3dmodel*)model->feed.state.ptr)->vrref = vrref;
		return ARCAN_OK;
	}
	else if (model->feed.state.tag == ARCAN_TAG_3DCAMERA){
		struct camtag_data* camera = model->feed.state.ptr;
		camera->vrref = vrref;
		return ARCAN_OK;
	}
	else
		return ARCAN_ERRC_UNACCEPTED_STATE;
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

	struct camtag_data* camera = camobj->feed.state.ptr;
	float _Alignas(16) matr[16];
	float _Alignas(16) dmatr[16];
	float _Alignas(16) omatr[16];

	agp_pipeline_hint(PIPELINE_3D);
	agp_render_options((struct agp_render_options){
		.line_width = camera->line_width
	});

	surface_properties dprop;
	arcan_resolve_vidprop(camobj, fract, &dprop);
	if (camera->vrref){
		dprop.rotation = camobj->current.rotation;
	}

	agp_shader_activate(agp_default_shader(BASIC_3D));
	agp_shader_envv(PROJECTION_MATR, camera->projection, sizeof(float) * 16);

/* scale */
	identity_matrix(matr);
	scale_matrix(matr, dprop.scale.x, dprop.scale.y, dprop.scale.z);

/* rotate */
	matr_quatf(norm_quat(dprop.rotation.quaternion), omatr);
	multiply_matrix(dmatr, matr, omatr);
	arcan_3dmodel* obj3d = cell->elem->feed.state.ptr;

/* "infinite geometry" (skybox) */
	if (obj3d->flags.infinite)
		cell = process_scene_infinite(cell, fract, dmatr, camera->flags);

/* object translate */
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
			for (size_t i = 0; i <curr->store.n_indices; i+= 3){
				unsigned iv = indices[i];
				indices[i] = indices[i+2];
				indices[i+2] = iv;
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
	newmodel->geometry->store.vertex_size = 3;
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

arcan_vobj_id arcan_3d_buildcylinder(float r,
	float hh, size_t steps, size_t nmaps, int fill_mode)
{
	vfunc_state state = {.tag = ARCAN_TAG_3DOBJ};
	img_cons empty = {0};

	if (hh < EPSILON || steps < 1)
		return ARCAN_EID;

	arcan_vobj_id rv = arcan_video_addfobject(FFUNC_3DOBJ, state, empty, 1);
	if (rv == ARCAN_EID)
		return rv;

/* control structure */
	arcan_3dmodel* newmodel = arcan_alloc_mem(sizeof(arcan_3dmodel),
		ARCAN_MEM_VTAG, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
	state.ptr = (void*) newmodel;
	arcan_video_alterfeed(rv, FFUNC_3DOBJ, state);
	pthread_mutex_init(&newmodel->lock, NULL);
	arcan_video_allocframes(rv, 1, ARCAN_FRAMESET_SPLIT);

/* metadata / geometry source */
	newmodel->geometry = arcan_alloc_mem(
		sizeof(struct geometry), ARCAN_MEM_VTAG, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

/* total number of verts, normals, textures and indices */
	int caps = fill_mode > CYLINDER_FILL_HALF;
	size_t n_verts = 3 * (steps * 3 + caps * steps * 2);
	size_t n_txcos = 3 * (steps * 2 + caps * steps * 2);
	size_t n_normals = 3 * (steps * 3 + caps * steps * 2);
	size_t n_indices = 1 * (steps * 6 + caps * steps * 6);
	size_t buf_sz =
		sizeof(float) * (n_verts + n_normals + n_txcos) + n_indices * sizeof(unsigned);

/* build our storage buffers */
	float* dbuf = arcan_alloc_mem(buf_sz, ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_SIMD);
	float* vp = dbuf;
	float* np = &dbuf[n_verts];
	float* tp = &dbuf[n_txcos + n_verts];
	float* nn = &dbuf[n_normals + n_txcos + n_verts];
	unsigned* ip = (unsigned*) (&dbuf[n_verts + n_txcos + n_normals]);

/* map it all into our model */
	newmodel->geometry->store.vertex_size = 3;
	newmodel->geometry->store.type = AGP_MESH_TRISOUP;
	newmodel->geometry->store.shared_buffer_sz = buf_sz;
	newmodel->geometry->store.shared_buffer = (uint8_t*) dbuf;
	newmodel->geometry->store.verts = vp;
	newmodel->geometry->store.txcos = tp;
	newmodel->geometry->store.normals = np;
	newmodel->geometry->store.indices = ip;
	newmodel->geometry->store.n_indices = n_indices;
	newmodel->geometry->store.n_vertices = n_verts / 3;
	newmodel->geometry->nmaps = nmaps;
	newmodel->geometry->complete = true;
	newmodel->radius = r > (2.0 * hh) ? r : 2.0 * hh;
	newmodel->bbmin = (vector){.x = -r, .y = -hh, .z = -r};
	newmodel->bbmax = (vector){.x =  r, .y =  hh, .z =  r};
	newmodel->flags.complete = true;

/* pass one, base data */
	float step_sz = 2 * M_PI / (float) steps;
	float txf = 2 * M_PI;

	if (fill_mode == CYLINDER_FILL_HALF || fill_mode == CYLINDER_FILL_HALF_CAPS){
		step_sz = M_PI / (float) steps;
		txf = M_PI;
	}

	for (size_t i = 0; i <= steps; i++){
		float p = (float) i * step_sz;
		float x = cosf(p);
		float z = sinf(p);

/* top */
		*vp++ = r * x; *vp++ = hh; *vp++ = r * z;
		*tp++ = p / txf; *tp++ = 0;
		*np++ = x; *np++ = 0; *np++ = z;

/* bottom */
		*vp++ = r * x; *vp++ = -hh; *vp++ = r * z;
		*tp++ = p / txf; *tp++ = 1;
		*np++ = x; *np++ = 0; *np++ = z;
	}

/* pass two, index buffer */
	size_t ic = 0;
	int ofs = 0;

	if (fill_mode == CYLINDER_FILL_HALF || fill_mode == CYLINDER_FILL_HALF_CAPS)
		ofs = -1;

	for (size_t i = 0; i < steps + ofs; i++){
		unsigned i1 = (i * 2 + 0);
		unsigned i2 = (i * 2 + 1);
		unsigned i3 = (i * 2 + 2);
		unsigned i4 = (i * 2 + 3);
		ic += 6;
		*ip++ = i2;
		*ip++ = i3;
		*ip++ = i1;
		*ip++ = i4;
		*ip++ = i3;
		*ip++ = i2;
	}

/*
	*ip++ = (steps-1)*2+2;
	*ip++ = (steps-1)*2+1;
	*ip++ = (steps-1)*2+0;
	*ip++ = 2;
	*ip++ = 3;
	*ip++ = 1;
	ic += 6;
*/

	newmodel->geometry->store.n_indices = ic;

/* pass three, endcaps - only weird bit is that we don't really texture */
	if (caps){
		*vp++ = 0;
		*vp++ = hh;
		*vp++ = 0;
		*tp++ = 0;
		*tp++ = 0;
		*np++ = 0;
		*np++ = 1;
		*np++ = 0;
		*vp++ = 0;
		*vp++ = -hh;
		*vp++ = 0;
		*tp++ = 0;
		*tp++ = 0;
		*np++ = 0;
		*np++ = 1;
		*np++ = 0;
	}

	return rv;
}

arcan_vobj_id arcan_3d_buildsphere(
	float r, unsigned l, unsigned m, bool hemi, size_t nmaps)
{
	vfunc_state state = {.tag = ARCAN_TAG_3DOBJ};
	img_cons empty = {0};

	if (l <= 1 || m <= 1)
		return ARCAN_EID;

	arcan_vobj_id rv = arcan_video_addfobject(FFUNC_3DOBJ, state, empty, 1);
	if (rv == ARCAN_EID)
		return rv;

	arcan_3dmodel* newmodel = arcan_alloc_mem(sizeof(arcan_3dmodel),
		ARCAN_MEM_VTAG, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
	state.ptr = (void*) newmodel;
	arcan_video_alterfeed(rv, FFUNC_3DOBJ, state);
	pthread_mutex_init(&newmodel->lock, NULL);
	arcan_video_allocframes(rv, 1, ARCAN_FRAMESET_SPLIT);

/* total number of verts, normals, textures and indices */
	size_t nv = l * m * 3;
	size_t nn = l * m * 3;
	size_t nt = l * m * 2;
	size_t ni = (l-1) * (m-1) * 6;
	size_t buf_sz = (nv + nn + nt) * sizeof(float) + ni * sizeof(unsigned);

/* build our storage buffers */
	float* dbuf = arcan_alloc_mem(buf_sz, ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_SIMD);
	float* vp = dbuf;
	float* np = &dbuf[nv];
	float* tp = &dbuf[nv + nn];
	unsigned* ip = (unsigned*) (&dbuf[nv + nn + nt]);

/* map it all into our model */
	newmodel->geometry = arcan_alloc_mem(
		sizeof(struct geometry), ARCAN_MEM_VTAG, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
	newmodel->geometry->store.vertex_size = 3;
	newmodel->geometry->store.type = AGP_MESH_TRISOUP;
	newmodel->geometry->store.shared_buffer_sz = buf_sz;
	newmodel->geometry->store.shared_buffer = (uint8_t*) dbuf;
	newmodel->geometry->store.verts = vp;
	newmodel->geometry->store.txcos = tp;
	newmodel->geometry->store.normals = np;
	newmodel->geometry->store.indices = ip;
	newmodel->geometry->store.n_indices = ni;
	newmodel->geometry->store.n_vertices = nv / 3;
	newmodel->geometry->complete = true;
	newmodel->radius = r;
	newmodel->geometry->nmaps = nmaps;
	newmodel->flags.complete = true;
/* bbmin, bbmax */

/* pass one, base data */
	float step_l = 1.0f / (float)(l - 1);
	float step_m = 1.0f / (float)(m - 1);
	float hcons;
	float yofs;
	if (hemi){
		hcons = 0;
		yofs = -0.5*r;
	}
	else{
		hcons = -M_PI_2;
		yofs = 0.0;
	}

	for (int L = 0; L < l; L++){
		for (int M = 0; M < m; M++){
			float y = sinf( hcons + M_PI * L * step_l ) + yofs;
			float x = cosf(2.0f*M_PI*(float)M*step_m) * sinf(M_PI*(float)L*step_l);
			float z = sinf(2.0f*M_PI*(float)M*step_m) * sinf(M_PI*(float)L*step_l);
			*tp++ = (float)M * step_m;
			*tp++ = 1.0 - (float)L * step_l;
			*vp++ = x * r;
			*vp++ = y * r;
			*vp++ = z * r;
			*np++ = x;
			*np++ = y;
			*np++ = z;
		}
	}

/* pass two, indexing primitives, take out 4 points on the quad and split */
	for (int L = 0; L < l - 1; L++){
		for (int M = 0; M < m - 1; M++){
			unsigned i1 = L * m + M;
			unsigned i2 = L * m + M + 1;
			unsigned i3 = (L+1) * m + M + 1;
			unsigned i4 = (L+1) * m + M;
			*ip++ = i1; *ip++ = i2; *ip++ = i3;
			*ip++ = i1; *ip++ = i3; *ip++ = i4;
		}
	}

	return rv;
}

arcan_vobj_id arcan_3d_buildbox(float w, float h, float d, size_t nmaps, bool s)
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

/* winding order: clockwise */
	float verts[] = {
		-w, h,-d, /* TOP */
		-w, h, d,
		 w, h, d,
		 w, h,-d,
		-w, h, d, /* LEFT */
		-w,-h, d,
		-w,-h,-d,
		-w, h,-d,
		 w, h, d, /* RIGHT */
		 w,-h, d,
		 w,-h,-d,
		 w, h,-d,
		 w, h, d, /* FRONT */
		 w,-h, d,
		-w,-h, d,
		-w, h, d,
		 w, h,-d, /* BACK */
		 w,-h,-d,
		-w,-h,-d,
		-w, h,-d,
		-w,-h,-d, /* BOTTOM */
		-w,-h, d,
		 w,-h, d,
		 w,-h,-d
	};

	float txcos[] = {
		0, 1, /* TOP */
		0, 0,
		1, 0,
		1, 1,
		0, 0, /* LEFT */
		0, 1,
		1, 1,
		1, 0,
		1, 0, /* RIGHT */
		1, 1,
		0, 1,
		0, 0,
		0, 0, /* FRONT */
		0, 1,
		1, 1,
		1, 0,
		1, 0, /* BACK */
		1, 1,
		0, 1,
		0, 0,
		0, 0, /* BOTTOM */
		0, 1,
		1, 1,
		1, 0
	};

	float normals[] = {
		 0,  1,  0, /* TOP */
		 0,  1,  0,
		 0,  1,  0,
		 0,  1,  0,
		-1,  0,  0, /* LEFT */
		-1,  0,  0,
		-1,  0,  0,
		-1,  0,  0,
		 1,  0,  0, /* RIGHT */
		 1,  0,  0,
		 1,  0,  0,
		 1,  0,  0,
		 0,  0, -1, /* FRONT */
		 0,  0, -1,
		 0,  0, -1,
		 0,  0, -1,
		 0,  0,  1, /* FRONT */
		 0,  0,  1,
		 0,  0,  1,
		 0,  0,  1,
		 0, -1,  0, /* BOTTOM */
		 0, -1,  0,
		 0, -1,  0,
		 0, -1,  0
	};

	unsigned indices[] = {
		10, 9, 8, /* right */
		11, 10, 8,
		6, 4, 5, /* left */
		7, 4, 6,
		2, 1, 0, /* top */
		3, 2, 0,
		22, 20, 21, /* bottom */
		23, 20, 22,
		18, 17, 16, /* back */
		19, 18, 16,
		14, 12, 13, /* front */
		12, 14, 15,
	};

	vector bbmin = {.x = -w, .y = -h, .z = -d};
	vector bbmax = {.x =  w, .y =  h, .z =  d};

/* one big allocation for everything */
	size_t buf_sz =
		sizeof(verts) + sizeof(txcos) + sizeof(indices) + sizeof(normals);

	float* dbuf = arcan_alloc_mem(buf_sz, ARCAN_MEM_MODELDATA, 0, ARCAN_MEMALIGN_SIMD);
	size_t nofs = COUNT_OF(verts);
	size_t tofs = nofs + COUNT_OF(normals);
	size_t iofs = tofs + COUNT_OF(txcos);

	memcpy(dbuf, verts, sizeof(verts));
	memcpy(&dbuf[nofs], normals, sizeof(normals));
	memcpy(&dbuf[tofs], txcos, sizeof(txcos));
	memcpy(&dbuf[iofs], indices, sizeof(indices));

	if (s){
		struct geometry** geom = &newmodel->geometry;
		struct geometry* last = NULL;

		unsigned* indices = (unsigned*) &dbuf[iofs];

		for (size_t i = 0; i < 6; i++){
			*geom = arcan_alloc_mem(
				sizeof(struct geometry), ARCAN_MEM_MODELDATA, ARCAN_MEM_BZERO, 0);
			(*geom)->store.shared_buffer = (uint8_t*) dbuf;
			(*geom)->store.shared_buffer_sz = buf_sz;
			(*geom)->store.verts = dbuf;
			(*geom)->store.txcos = &dbuf[tofs];
			(*geom)->store.normals = &dbuf[nofs];
			(*geom)->store.indices = &indices[i*6];
			(*geom)->store.n_indices = 6;
			(*geom)->store.vertex_size = 3;
			(*geom)->store.n_vertices = COUNT_OF(verts);
			(*geom)->nmaps = nmaps;
			(*geom)->complete = true;
			geom = &(*geom)->next;
		}
	}
	else{
		newmodel->geometry = arcan_alloc_mem(
			sizeof(struct geometry), ARCAN_MEM_VTAG, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
		newmodel->geometry->nmaps = nmaps;
		newmodel->geometry->store.vertex_size = 3;
		newmodel->geometry->store.type = AGP_MESH_TRISOUP;
		newmodel->geometry->store.shared_buffer_sz = buf_sz;
		newmodel->geometry->store.verts = dbuf;
		newmodel->geometry->store.txcos = &dbuf[tofs];
		newmodel->geometry->store.normals = &dbuf[nofs];
		newmodel->geometry->store.indices = (unsigned*) &dbuf[iofs];
		newmodel->geometry->store.n_indices = COUNT_OF(indices);
		newmodel->geometry->store.n_vertices = COUNT_OF(verts);
		newmodel->geometry->store.shared_buffer = (uint8_t*) dbuf;
		newmodel->geometry->complete = true;
	}

	newmodel->radius = d;
	newmodel->bbmin = bbmin;
	newmodel->bbmax = bbmax;
	newmodel->flags.complete = true;

	return rv;
}

arcan_vobj_id arcan_3d_buildplane(
	float mins, float mint, float maxs, float maxt,
	float base, float wdens, float ddens, size_t nmaps, bool vert)
{
	vfunc_state state = {.tag = ARCAN_TAG_3DOBJ};
	arcan_vobj_id rv = ARCAN_EID;
	img_cons empty = {0};

/* fail on unsolvable dimension constraints */
	if ( (maxs < mins || wdens <= 0 || wdens >= maxs - mins) ||
		(maxt < mint || ddens <= 0 || ddens >= maxt - mint) )
		return ARCAN_ERRC_BAD_ARGUMENT;

	rv = arcan_video_addfobject(FFUNC_3DOBJ, state, empty, 1);
	arcan_3dmodel* newmodel = NULL;

	if (rv == ARCAN_EID)
		return rv;

/* if [vert] we flip y and z axis when setting vertices */
	point minp = {.x = mins,  .y = base, .z = mint};
	point maxp = {.x = maxs,  .y = base, .z = maxt};
	point step = {.x = wdens, .y = 0,    .z = ddens};

	newmodel = arcan_alloc_mem(sizeof(arcan_3dmodel),
		ARCAN_MEM_VTAG, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_PAGE);

	pthread_mutex_init(&newmodel->lock, NULL);

	state.ptr = (void*) newmodel;
	arcan_video_alterfeed(rv, FFUNC_3DOBJ, state);

	struct geometry** nextslot = &(newmodel->geometry);
	while (*nextslot)
		nextslot = &((*nextslot)->next);

	*nextslot = arcan_alloc_mem(sizeof(struct geometry),
		ARCAN_MEM_VTAG, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_PAGE);

	(*nextslot)->nmaps = nmaps;
	newmodel->geometry = *nextslot;
	newmodel->geometry->store.type = AGP_MESH_TRISOUP;
	newmodel->geometry->store.vertex_size = 3;

	struct geometry* dst = newmodel->geometry;

	build_plane(minp, maxp, step, &dst->store.verts, &dst->store.indices,
		&dst->store.txcos, &dst->store.n_vertices, &dst->store.n_indices, vert);

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

arcan_errc arcan_3d_addraw(arcan_vobj_id dst,
	float* vertices, size_t n_vertices,
	unsigned* indices, size_t n_indices,
	float* txcos, float* txcos2,
	float* normals, float* tangents,
	float* colors,
	uint16_t bones[4], float weights[4],
	unsigned nmaps)
{
	arcan_vobject* vobj = arcan_video_getobject(dst);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	arcan_3dmodel* model = vobj->feed.state.ptr;

	if (vobj->feed.state.tag != ARCAN_TAG_3DOBJ ||
		model->flags.complete == true)
		return ARCAN_ERRC_UNACCEPTED_STATE;

/* find last elem and add */
	struct geometry** nextslot = &(model->geometry);
	while (*nextslot)
		nextslot = &((*nextslot)->next);

	*nextslot = arcan_alloc_mem(sizeof(struct geometry),
		ARCAN_MEM_VTAG, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
	struct geometry* dg = *nextslot;

	if (!dg)
		return ARCAN_ERRC_OUT_OF_SPACE;

	dg->nmaps = nmaps;
	dg->store.type = AGP_MESH_TRISOUP;
	dg->store.verts = vertices;
	dg->store.indices = indices;
	dg->store.normals = normals;
	dg->store.tangents = tangents;
/* FIXME: spawn thread to calculate tangents if missing, and calculate
 * bitangents after that - cprod(normal, tangent.wyz) * tangent.w
 */
	dg->store.txcos = txcos;
	dg->store.txcos2 = txcos2;
	dg->store.colors = colors;
	dg->store.joints = bones;
	dg->store.weights = weights;
	dg->store.n_vertices = n_vertices;
	dg->store.vertex_size = 3;
	dg->store.n_indices = n_indices;

	return ARCAN_OK;
}

arcan_errc arcan_3d_addmesh(arcan_vobj_id dst,
	data_source resource, unsigned nmaps)
{
	arcan_vobject* vobj = arcan_video_getobject(dst);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	arcan_3dmodel* model = vobj->feed.state.ptr;

	if (1 ||
		vobj->feed.state.tag != ARCAN_TAG_3DOBJ ||
		model->flags.complete == true)
		return ARCAN_ERRC_UNACCEPTED_STATE;

/*
 * commented out for now until we can add the model parsing to fsrv_decode
 *
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
*/

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

arcan_errc arcan_3d_camproj(arcan_vobj_id vid, float proj[static 16])
{
	arcan_vobject* vobj = arcan_video_getobject(vid);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	struct camtag_data* camera = vobj->feed.state.ptr;
	if (vobj->feed.state.tag != ARCAN_TAG_3DCAMERA)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	memcpy(camera->projection, proj, sizeof(float) * 16);
	return ARCAN_OK;
}

arcan_errc arcan_3d_camtag(arcan_vobj_id tgtid,
	arcan_vobj_id vid, float near, float far, float ar, float fov, int flags, ...)
{
	arcan_vobject* vobj = arcan_video_getobject(vid);
	struct rendertarget* tgt = NULL;
	struct camtag_data* camobj = NULL;

	if (tgtid != ARCAN_EID){
		arcan_vobject* tgtobj = arcan_video_getobject(tgtid);
		tgt = arcan_vint_findrt(tgtobj);
	}

	va_list vl;
	va_start(vl, flags);

	if (vobj->feed.state.ptr){
		if (vobj->feed.state.tag != ARCAN_TAG_3DCAMERA)
			return ARCAN_ERRC_UNACCEPTED_STATE;
		camobj = vobj->feed.state.ptr;
	}

	if (tgt)
		tgt->camtag = vobj->cellid;
	else
		vobj->owner->camtag = vobj->cellid;

	if (!camobj)
		camobj =
			arcan_alloc_mem(
				sizeof(struct camtag_data),
				ARCAN_MEM_VTAG, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_SIMD
			);

	camobj->near = near;
	camobj->far = far;
	camobj->flags = flags;
	if (flags & MESH_FILL_LINE){
		camobj->line_width = va_arg(vl, double);
	}
	else
		camobj->line_width = 1.0;

	build_projection_matrix(camobj->projection, near, far, ar, fov);

	vfunc_state state = {.tag = ARCAN_TAG_3DCAMERA, .ptr = camobj};
	arcan_video_alterfeed(vid, FFUNC_3DOBJ, state);

	FL_SET(vobj, FL_FULL3D);

	va_end(vl);
	return ARCAN_OK;
}
