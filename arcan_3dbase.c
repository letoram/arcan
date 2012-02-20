#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <assert.h>

#include <openctm.h>

#define GL_GLEXT_PROTOTYPES 1

#ifdef POOR_GL_SUPPORT
 #define GLEW_STATIC
 #define NO_SDL_GLEXT
 #include <glew.h>
#endif

#include <SDL/SDL.h>
#include <SDL/SDL_opengl.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"
#include "arcan_shdrmgmt.h"
#include "arcan_video.h"
#include "arcan_videoint.h"

#include "arcan_3dbase_synth.h"

// #define M_PI 3.14159265358979323846

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
/* for RTT - type scenarios */
	GLuint rendertarget;
	vector position;
    unsigned int updateticks;
	bool dynamic;

/* ignored by pointlight */
	orientation direction;
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
	unsigned nverts;
	float* verts;
	float* txcos;
	unsigned ntris;
	unsigned nindices;
	GLenum indexformat;
	void* indices;

	bool opaque;
	
/* nnormals == nverts */
	float* normals;
	struct geometry* next;
};

typedef struct {
	struct geometry geometry;
	arcan_shader_id program;
	
	unsigned char nsets;

/* Frustum planes */
	float frustum[6][4];

/* AA-BB */
    vector bbmin;
    vector bbmax;

/* position, opacity etc. are inherited from parent */
	struct {
        bool debug_vis;
		bool recv_shdw;
		bool cast_shdw;
		bool cast_refl;
/* used for skyboxes etc. should be rendered before anything else
 * without depth buffer writes enabled */
        bool infinite;
	} flags;

	arcan_vobject* parent;
} arcan_3dmodel;

static arcan_3dscene current_scene = {0};

/*
 * CAMERA Control, generation and manipulation
 */

static virtobj* find_camera(unsigned camtag)
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

void arcan_3d_movecamera(unsigned camtag, float px, float py, float pz, unsigned tv)
{
	virtobj* vobj = find_camera(camtag);
	if (vobj){
		vobj->position.x = px;
		vobj->position.y = py;
		vobj->position.z = pz;
	}
}

void arcan_3d_orientcamera(unsigned camtag, float roll, float pitch, float yaw, unsigned tv)
{
	unsigned ofs = 0;
	virtobj* cam = find_camera(camtag);
	if (cam){
		update_view(&cam->direction, roll, pitch, yaw);
		cam->view.x = -cam->direction.matr[2];
		cam->view.y = -cam->direction.matr[6];
		cam->view.z = -cam->direction.matr[10];
	}
}

void arcan_3d_strafecamera(unsigned camtag, float factor, unsigned tv)
{
	virtobj* vobj = find_camera(camtag);
	if (vobj){
		vector cpv = crossp_vector(vobj->view, build_vect(0.0, 1.0, 0.0));
		vobj->position.x += cpv.x * factor;
		vobj->position.y += cpv.y * factor;
	}
}

void arcan_3d_forwardcamera(unsigned camtag, float fact, unsigned tv)
{
	virtobj* vobj = find_camera(camtag);
	if (vobj){
		vobj->position.x += (vobj->view.x * fact);
		vobj->position.y += (vobj->view.y * fact);
		vobj->position.z += (vobj->view.z * fact);
	}
}

static void freemodel(arcan_3dmodel* src)
{
	if (src){
		free(src->geometry.indices);
		free(src->geometry.verts);
		free(src->geometry.normals);

		if (src->geometry.txcos)
			free(src->geometry.txcos);
	}
}

/*
 * Render-loops, Pass control, Initialization
 */
static void rendermodel(arcan_vobject* vobj, arcan_3dmodel* src, surface_properties props, bool texture, float* modelview, unsigned txofs)
{
	if (props.opa < EPSILON)
		return;

	unsigned cframe = 0;
	float wmvm[16];
	
//	glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
	/* if there's texture coordsets and an associated vobj,
     * enable texture coord array, normal array etc. */
	if (src->flags.infinite){
		identity_matrix(wmvm);
		glDepthMask(GL_FALSE);
		glEnable(GL_DEPTH_TEST);
	} else
		memcpy(wmvm, modelview, sizeof(float) * 16);

	float dmatr[16], omatr[16];

    float opa = 1.0;
    arcan_shader_envv(OBJ_OPACITY_F, &opa, sizeof(float));

/* reposition the current modelview, set it as the current shader data,
 * enable vertex attributes and issue drawcalls */
	translate_matrix(wmvm, props.position.x, props.position.y, props.position.z);
	matr_quatf(props.rotation, omatr);
	multiply_matrix(dmatr, wmvm, omatr);
	arcan_shader_envv(MODELVIEW_MATR, dmatr, sizeof(float) * 16);
	
	struct geometry* base = &src->geometry;

	while (base){
		unsigned counter = 0;
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

		if (attribs[2] != -1){
			glEnableVertexAttribArray(attribs[2]);
			glVertexAttribPointer(attribs[2], 2, GL_FLOAT, GL_FALSE, 0, base->txcos);
		} else attribs[2] = -1;
		
/* Map up all texture-units required,
 * if there are corresponding frames and capacity in the parent vobj */
		if (texture){
			for (unsigned i = 0; i+txofs < GL_MAX_TEXTURE_UNITS && (i+cframe) < vobj->frameset_capacity && i < base->nmaps; i++){
				arcan_vobject* frame = vobj->frameset[i+cframe];

				if (frame && frame->gl_storage.glid){
					glClientActiveTexture(GL_TEXTURE0 + txofs + counter++);
					glEnable(GL_TEXTURE_2D);
					glBindTexture(GL_TEXTURE_2D, frame->gl_storage.glid);
					arcan_shader_envv(frame->gl_storage.maptype, &counter, sizeof(counter)); 
				}
			}	
		}

/* Indexed- or direct mode? */
		if (base->indices)
			glDrawElements(GL_TRIANGLES, base->nindices, base->indexformat, base->indices);
		else
			glDrawArrays(GL_TRIANGLES, 0, base->nverts);

        
/* and reverse transitions again for the next client */
		while (counter-- > 0){
			glClientActiveTexture(GL_TEXTURE0 + txofs + counter);
			glBindTexture(GL_TEXTURE_2D, 0);
		}

		for (unsigned i=cframe; i < vobj->frameset_capacity && i < base->nmaps; i++){
			arcan_vobject* frame = vobj->frameset[i];
			if (frame && frame->gl_storage.glid){
				unsigned zero = 0;
				arcan_shader_envv(frame->gl_storage.maptype, &zero, sizeof(zero));
			}
		}

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

/* the current model uses the associated scaling / blending
 * of the associated vid and applies it uniformly */
static const int8_t ffunc_3d(enum arcan_ffunc_cmd cmd, uint8_t* buf, uint32_t s_buf, uint16_t width, uint16_t height, uint8_t bpp, unsigned mode, vfunc_state state)
{
	if (state.tag == ARCAN_TAG_3DOBJ && state.ptr){
		switch (cmd){
			case ffunc_tick:
			break;

			case ffunc_destroy:
				freemodel( (arcan_3dmodel*) state.ptr );
				free(state.ptr);
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
		if (current->elem->order >= 0) break;
		surface_properties dprops;
 		arcan_resolve_vidprop(cell->elem, lerp, &dprops);
        
        arcan_shader_activate(current->elem->gl_storage.program);
		rendermodel(current->elem, (arcan_3dmodel*) current->elem->state.ptr, dprops, true, modelview, 0);

		current = current->next;
	}
}

/* Chained to the video-pass in arcan_video, stop at the first non-negative order value */
arcan_vobject_litem* arcan_refresh_3d(arcan_vobject_litem* cell, float frag)
{
	virtobj* base = current_scene.perspectives;
	glClear(GL_DEPTH_BUFFER_BIT);
	glColor4f(1.0, 1.0, 1.0, 1.0);
	
	while(base){
		float matr[16], dmatr[16];

		switch(base->type){
			case virttype_camera :
				arcan_shader_envv(PROJECTION_MATR, base->projmatr, sizeof(float) * 16);
				identity_matrix(matr);
				multiply_matrix(dmatr, matr, base->direction.matr);
				translate_matrix(dmatr, base->position.x, base->position.y, base->position.z);
				process_scene_normal(cell, frag, dmatr, base->projmatr);

/* curious about deferred shading and forward shadow mapping, thus likely the first "hightech" renderpath */
			case virttype_dirlight   : break;
			case virttype_pointlight : break;
/* camera with inverted Y, add a stencil at clipping plane and (optionally) render to texture (for water) */
			case virttype_reflection : break;
/* depends on caster source, treat pointlights separately, for infinite dirlights use ortographic projection, else
 * have a caster-specific perspective projection */
			case virttype_shadow : break;
		}

		base = base->next;
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
	
	if (vobj && vobj->state.tag == ARCAN_TAG_3DOBJ){
		arcan_3dmodel* model = (arcan_3dmodel*) vobj->state.ptr;
        struct geometry* curr = &model->geometry;
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
		arcan_video_alterfeed(rv, ffunc_3d, state);
		newmodel->geometry.indexformat = GL_UNSIGNED_INT;
	}

	return rv;
}

arcan_vobj_id arcan_3d_buildplane(float minx, float minz, float maxx, float maxz, float y, float wdens, float ddens){
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

		newmodel->geometry.indexformat = GL_UNSIGNED_INT;
		
		build_hplane(minp, maxp, step, &newmodel->geometry.verts, (unsigned int**)&newmodel->geometry.indices,
					 &newmodel->geometry.txcos, &newmodel->geometry.nverts, &newmodel->geometry.nindices);

		newmodel->geometry.ntris = newmodel->geometry.nindices / 3;
		arcan_video_allocframes(rv, 1);
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

static void loadmesh(struct geometry* dst, CTMcontext* ctx)
{	
/* figure out dimensions */
	dst->nverts = ctmGetInteger(ctx, CTM_VERTEX_COUNT);
	dst->ntris  = ctmGetInteger(ctx, CTM_TRIANGLE_COUNT);
	unsigned uvmaps = ctmGetInteger(ctx, CTM_UV_MAP_COUNT);
	unsigned vrtsize = dst->nverts * 3 * sizeof(float);
	dst->verts = (float*) malloc(vrtsize);
	
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



void arcan_3d_addmesh(arcan_vobj_id dst, const char* resource, unsigned nmaps)
{
	arcan_vobject* vobj = arcan_video_getobject(dst);	
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	
	/* 2d frameset and set of vids associated as textures with models are weakly linked */
	if (vobj && vobj->state.tag == ARCAN_TAG_3DOBJ)
	{
		CTMcontext ctx = ctmNewContext(CTM_IMPORT);
		ctmLoad(ctx, resource);
		
		if (ctmGetError(ctx) == CTM_NONE){
			arcan_3dmodel* dst = (arcan_3dmodel*) vobj->state.ptr;

		/* find last elem and add */
			struct geometry** nextslot = &(dst->geometry.next);
			while (*nextslot)
				nextslot = &((*nextslot)->next);

			*nextslot = (struct geometry*) calloc(sizeof(struct geometry), 1);

		/* load / parsedata into geometry slot */
			loadmesh(*nextslot, ctx);
            (*nextslot)->nmaps = nmaps;
			
			minmax_verts(&dst->bbmin, &dst->bbmax, (*nextslot)->verts, (*nextslot)->nverts);
		}

		ctmFreeContext(ctx);
	}
}
	
arcan_errc arcan_3d_scalevertices(arcan_vobj_id vid)
{
	arcan_vobject* vobj = arcan_video_getobject(vid);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	
	/* 2d frameset and set of vids associated as textures with models are weakly linked */
	if (vobj && vobj->state.tag == ARCAN_TAG_3DOBJ)
	{
		arcan_3dmodel* dst = (arcan_3dmodel*) vobj->state.ptr;
		struct geometry* geom = &dst->geometry;

		while (geom){
			minmax_verts(&dst->bbmin, &dst->bbmax, geom->verts, geom->nverts);
			geom = geom->next;
		}

		geom = &dst->geometry;
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

arcan_vobj_id arcan_3d_loadmodel(const char* resource)
{
	arcan_vobj_id rv = ARCAN_EID;
	arcan_3dmodel* newmodel = NULL;
	arcan_vobject* vobj = NULL;

	CTMcontext ctx = ctmNewContext(CTM_IMPORT);
	ctmLoad(ctx, resource);

	if (ctmGetError(ctx) == CTM_NONE){
/* create container object and proxy vid */
		newmodel = (arcan_3dmodel*) calloc(sizeof(arcan_3dmodel), 1);
		vfunc_state state = {.tag = ARCAN_TAG_3DOBJ, .ptr = newmodel};
		img_cons econs = {0};
		rv = arcan_video_addfobject(ffunc_3d, state, econs, 1);

		if (rv == ARCAN_EID)
			goto error;

		arcan_vobject* obj = arcan_video_getobject(rv);
		newmodel->parent = obj;
		loadmesh(&newmodel->geometry, ctx);

/* set initial bounding box */
		vector empty = {0};
		if (newmodel->geometry.nverts){
			empty.x = newmodel->geometry.verts[0];
			empty.y = newmodel->geometry.verts[1];
			empty.z = newmodel->geometry.verts[2];
		}
		newmodel->bbmin = empty;
		newmodel->bbmax = empty;
		
		minmax_verts(&newmodel->bbmin, &newmodel->bbmax, newmodel->geometry.verts, newmodel->geometry.nverts);
		
		ctmFreeContext(ctx);
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



void arcan_3d_setdefaults()
{
	current_scene.perspectives = calloc( sizeof(virtobj), 1);
	virtobj* cam = current_scene.perspectives;
	cam->dynamic = true;

    build_projection_matrix(cam->projmatr, 0.1, 100.0, (float)arcan_video_display.width / (float) arcan_video_display.height, 45.0);

    cam->rendertarget = 0;
    cam->type = virttype_camera;
	cam->position = build_vect(0, 0, 0); /* ret -x, y, +z */

	arcan_3d_orientcamera(0, 0, 0, 0, 0);
}

