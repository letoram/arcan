#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <assert.h>

#include <openctm.h>

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
#include "arcan_video.h"
#include "arcan_videoint.h"

#include "arcan_3dbase_synth.h"

// #define M_PI 3.14159265358979323846

extern struct arcan_video_display arcan_video_display;

/* since the 3d is planned as a secondary feature, rather than the primary one,
 * things work slightly different as each 3d object is essentially coupled to 1..n of 2D video objects */

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
	float* txcos;
    arcan_vobj_id vid;
} texture_set;

typedef struct {
	virtobj* perspectives;
} arcan_3dscene;

typedef struct {
/* Geometry */
    struct{
        unsigned nverts;
        float* verts;
        unsigned ntris;
        unsigned nindices;
		GLenum indexformat;
        void* indices;

        /* nnormals == nverts */
        float* normals;
    } geometry;

    unsigned char nsets;
    texture_set* textures;

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

/*
 * MODEL Control, generawtion and manipulation
 */

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

static void freemodel(arcan_3dmodel* src)
{
	if (src){

	}
}

/*
 * Render-loops, Pass control, Initialization
 */
static void rendermodel(arcan_3dmodel* src, surface_properties props, bool texture)
{
	if (props.opa < EPSILON)
		return;

	glPushMatrix();

	glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
	/* if there's texture coordsets and an associated vobj,
     * enable texture coord array, normal array etc. */
	if (src->flags.infinite){
        glLoadIdentity();
		glDepthMask(GL_FALSE);
		glEnable(GL_DEPTH_TEST);
	}

	float rotmat[16];
    glColor4f(1.0, 1.0, 1.0, props.opa);
	glTranslatef(props.position.x, props.position.y, props.position.z);
	matr_quatf(props.rotation, rotmat);
	glMultMatrixf(rotmat);

	if (src->geometry.normals){
		glEnableClientState(GL_NORMAL_ARRAY);
		glNormalPointer(GL_FLOAT, 0, src->geometry.normals);
	}
	
	glVertexPointer(3, GL_FLOAT, 0, src->geometry.verts);
	if (texture && src->nsets){
		unsigned counter = 0;
		for (unsigned i = 0; i < src->nsets && i < GL_MAX_TEXTURE_UNITS; i++)
			if (src->textures[i].vid != ARCAN_EID){
				glClientActiveTexture(counter++);
				glEnableClientState(GL_TEXTURE_COORD_ARRAY);
				glTexCoordPointer(2, GL_FLOAT, 0, src->textures[i].txcos);
				glBindTexture(GL_TEXTURE_2D, src->textures[i].vid);
			}
	}

    if (src->geometry.indices)
        glDrawElements(GL_TRIANGLES, src->geometry.nindices, src->geometry.indexformat, src->geometry.indices);
    else
        glDrawArrays(GL_TRIANGLES, 0, src->geometry.nverts);

	if (1 || src->flags.debug_vis){
		wireframe_box(src->bbmin.x, src->bbmin.y, src->bbmin.z, src->bbmax.x, src->bbmax.y, src->bbmax.z);
	}
    

/* and reverse transitions again for the next client */
	if (src->flags.infinite){
		glDepthMask(GL_TRUE);
		glEnable(GL_DEPTH_TEST);
	}

	if (texture && src->nsets){
		unsigned counter = 0;
		for (unsigned i = 0; i < src->nsets && i < GL_MAX_TEXTURE_UNITS; i++)
			if (src->textures[i].vid != ARCAN_EID){
				glClientActiveTexture(counter++);
				glDisableClientState(GL_TEXTURE_COORD_ARRAY);
				glBindTexture(GL_TEXTURE_2D, 0);
			}
 	}

	if (src->geometry.normals)
		glDisableClientState(GL_NORMAL_ARRAY);

	glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);

	glPopMatrix();
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
			break;

			default:
			break;
		}
	}

	return 0;
}

/* Simple one- off rendering pass, no exotic sorting, culling structures, projections or other */
static void process_scene_normal(arcan_vobject_litem* cell, float lerp)
{
	glEnableClientState(GL_VERTEX_ARRAY);
	glEnable(GL_DEPTH_TEST);

	arcan_vobject_litem* current = cell;
	while (current){
		if (current->elem->order >= 0) break;
		surface_properties dprops;
 		arcan_resolve_vidprop(cell->elem, lerp, &dprops);

		rendermodel((arcan_3dmodel*) current->elem->state.ptr, dprops, true);

		current = current->next;
	}

	glDisableClientState(GL_VERTEX_ARRAY);
}

/* Chained to the video-pass in arcan_video, stop at the first non-negative order value */
arcan_vobject_litem* arcan_refresh_3d(arcan_vobject_litem* cell, float frag)
{
	virtobj* base = current_scene.perspectives;
	glClear(GL_DEPTH_BUFFER_BIT);
	glColor4f(1.0, 1.0, 1.0, 1.0);
	
	while(base){
		float matr[16];

		switch(base->type){
			case virttype_camera :
            glMatrixMode(GL_PROJECTION);
                glLoadMatrixf(base->projmatr);

                glMatrixMode(GL_MODELVIEW);
					glLoadIdentity();
                    glMultMatrixf(base->direction.matr);
                    glTranslatef(base->position.x, base->position.y, base->position.z);

                    process_scene_normal(cell, frag);

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
    vector empty = {0};
    if (nverts){
        empty.x = verts[0];
        empty.y = verts[1];
        empty.z = verts[2];
    }
    *minp = *maxp = empty;

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

		if (model->geometry.indices){

		} else {
			float* verts = model->geometry.verts;
			assert(model->geometry.nverts % 3 == 0);
			
			for (unsigned i = 0; i < model->geometry.nverts * 9; i+= 9){
				vector v1 = { .x = verts[i  ], .y = verts[i+1], .z = verts[i+2] };
				vector v3 = { .x = verts[i+6], .y = verts[i+7], .z = verts[i+8] };
				verts[i  ] = v3.x; verts[i+1] = v3.y; verts[i+2] = v3.z;
				verts[i+6] = v1.x; verts[i+7] = v1.y; verts[i+8] = v1.z;
			}
		}
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
		newmodel->textures = (texture_set*) calloc(sizeof(texture_set), 1);
		newmodel->textures[0].vid = ARCAN_EID;
		newmodel->nsets = 1;
		
		build_hplane(minp, maxp, step, &newmodel->geometry.verts, (unsigned int**)&newmodel->geometry.indices,
					 &newmodel->textures->txcos, &newmodel->geometry.nverts, &newmodel->geometry.nindices);

		newmodel->geometry.ntris = newmodel->geometry.nindices / 3;
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

		img_cons empty = {0};
		rv = arcan_video_addfobject(ffunc_3d, state, empty, 1);

		if (rv == ARCAN_EID)
			goto error;

		arcan_vobject* obj = arcan_video_getobject(rv);
		newmodel->parent = obj;

/* figure out dimensions */
		newmodel->geometry.nverts = ctmGetInteger(ctx, CTM_VERTEX_COUNT);
		newmodel->geometry.ntris  = ctmGetInteger(ctx, CTM_TRIANGLE_COUNT);
		unsigned uvmaps = ctmGetInteger(ctx, CTM_UV_MAP_COUNT);

		unsigned vrtsize = newmodel->geometry.nverts * 3 * sizeof(float);

		newmodel->geometry.verts = (float*) malloc(vrtsize);

		const CTMfloat* verts   = ctmGetFloatArray(ctx, CTM_VERTICES);
		const CTMfloat* normals = ctmGetFloatArray(ctx, CTM_NORMALS);
		const CTMuint*  indices = ctmGetIntegerArray(ctx, CTM_INDICES);

/* copy and repack */
		if (normals){
			newmodel->geometry.normals = (float*) malloc(vrtsize);
			memcpy(newmodel->geometry.normals, normals, vrtsize);
		}

/* lots of memory to be saved, so worth the trouble */
		if (indices){
            newmodel->geometry.nindices = newmodel->geometry.ntris * 3;
            
			if (newmodel->geometry.nindices < 256){
				uint8_t* buf = (uint8_t*) malloc(newmodel->geometry.nindices * sizeof(uint8_t));
				newmodel->geometry.indexformat = GL_UNSIGNED_BYTE;

				for (unsigned i = 0; i < newmodel->geometry.nindices; i++)
					buf[i] = indices[i];

				newmodel->geometry.indices = (void*) buf;
			}
			else if (newmodel->geometry.nindices < 65536){
				uint16_t* buf = (uint16_t*) malloc(newmodel->geometry.nindices * sizeof(uint16_t));
				newmodel->geometry.indexformat = GL_UNSIGNED_SHORT;

				for (unsigned i = 0; i < newmodel->geometry.nindices; i++)
					buf[i] = indices[i];

				newmodel->geometry.indices = (void*) buf;
			}
			else{ 
				uint32_t* buf = (uint32_t*) malloc(newmodel->geometry.nindices * sizeof(uint32_t));
				newmodel->geometry.indexformat = GL_UNSIGNED_INT;
				for (unsigned i = 0; i < newmodel->geometry.nindices; i++)
					buf[i] = indices[i];
				
				newmodel->geometry.indices = (void*) buf;
			}
		}

/* rerange vertex values to -1..1 */
        minmax_verts(&newmodel->bbmin, &newmodel->bbmax, verts, newmodel->geometry.nverts);

        float dx = newmodel->bbmax.x - newmodel->bbmin.x;
        float dy = newmodel->bbmax.y - newmodel->bbmin.y;
        float dz = newmodel->bbmax.z - newmodel->bbmin.z;

        float sfx = 2.0 / dx, sfy = 2.0 / dy, sfz = 2.0 / dz;
        float tx = -1.0 - (newmodel->bbmin.x * sfx), ty = -1.0 - (newmodel->bbmin.y * sfy), tz = -1.0 - (newmodel->bbmin.z * sfz);
        
		for (unsigned i = 0; i < newmodel->geometry.nverts * 3; i += 3){
            newmodel->geometry.verts[i]   = tx + verts[i]   * sfx;
			newmodel->geometry.verts[i+1] = ty + verts[i+1] * sfy;
			newmodel->geometry.verts[i+2] = tz + verts[i+2] * sfz;
        }

        newmodel->bbmin.x = -1.0; newmodel->bbmin.y = -1.0; newmodel->bbmin.z = -1.0;
        newmodel->bbmax.x =  1.0; newmodel->bbmax.y =  1.0; newmodel->bbmax.z =  1.0;

        /* each txco set can have a different vid associated with it (multitexturing stuff),
 * possibly also specify filtermode, "mapname" and some other data currently ignored */
		if (uvmaps > 0){
			unsigned txsize = sizeof(float) * 2 * newmodel->geometry.nverts;
			newmodel->textures = calloc(sizeof(texture_set), uvmaps);

			for (int i = 0; i < uvmaps; i++){
				newmodel->textures[i].vid = ARCAN_EID;
				newmodel->textures[i].txcos = (float*) malloc(txsize);
				memcpy(newmodel->textures[i].txcos, ctmGetFloatArray(ctx, CTM_UV_MAP_1 + i), txsize);
			}
		}

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

    build_projection_matrix(0.1, 100.0, (float)arcan_video_display.width / (float) arcan_video_display.height, 45.0, cam->projmatr);

    cam->rendertarget = 0;
    cam->type = virttype_camera;
	cam->position = build_vect(0, 0, 0); /* ret -x, y, +z */

	arcan_3d_orientcamera(0, 0, 0, 0, 0);
	arcan_3d_buildplane(-1.0, -1.0, 5.0, 5.0, 0.0, 1.0, 1.0);
}

