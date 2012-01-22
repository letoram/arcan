#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>

#include <openctm.h>
#include <SDL/SDL_opengl.h>
#include <SDL/SDL.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_event.h"
#include "arcan_video.h"
#include "arcan_videoint.h"

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
	float fov;
	float near;
	float far;
	
	enum virttype type;
/* linked list arranged, sorted high-to-low
 * based on virttype */
	struct virtobj* next;
};

typedef struct virtobj virtobj;

typedef struct {
	virtobj* perspectives;
} arcan_3dscene;

typedef struct {
	CTMcontext ctmmodel; 
	orientation direction;
    point position;
    scalefactor scale;
/* position, opacity etc. are inherited from parent */
	
	struct {
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


static void freemodel(arcan_3dmodel* src)
{
	if (src){
		
	}
}

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

static void rendermodel(arcan_3dmodel* src, surface_properties props)
{
	glPushMatrix();
    const CTMfloat* verts   = ctmGetFloatArray(src->ctmmodel, CTM_VERTICES);
	glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    /* if there's texture coordsets and an associated vobj,
     * enable texture coord array, normal array etc. */
	if (src->flags.infinite){
		glDepthMask(GL_FALSE);
		glEnable(GL_DEPTH_TEST);
	}
	
    glColor4f(1.0, 1.0, 1.0, props.opa);
    int nverts = ctmGetInteger(src->ctmmodel, CTM_VERTEX_COUNT);
	glTranslatef(props.position.x, props.position.y, 0.0);
    glMultMatrixf(src->direction.matr);
    glVertexPointer(3, GL_FLOAT, 0, verts);
    glDrawArrays(GL_POINTS, 0, nverts);

	if (src->flags.infinite){
		glDepthMask(GL_TRUE);
		glEnable(GL_DEPTH_TEST);
	}
	
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
			
			case ffunc_render_direct:
				rendermodel( (arcan_3dmodel*) state.ptr, *(surface_properties*)buf );
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

void process_scene_normal(arcan_vobject_litem* cell, float lerp)
{
	glEnableClientState(GL_VERTEX_ARRAY);
    
	arcan_vobject_litem* current = cell;
	while (current){
		if (current->elem->order >= 0) break;
		surface_properties dprops;
		arcan_resolve_vidprop(cell->elem, lerp, &dprops);
		
		rendermodel((arcan_3dmodel*) current->elem->state.ptr, dprops);

		current = current->next;
	}

	glDisableClientState(GL_VERTEX_ARRAY);
}

arcan_vobject_litem* arcan_refresh_3d(arcan_vobject_litem* cell, float frag)
{
	virtobj* base = current_scene.perspectives;

	while(base){
		float matr[16];
		
		switch(base->type){
			case virttype_camera :
            glMatrixMode(GL_PROJECTION);
                glLoadIdentity();
                glMultMatrixf(base->direction.matr);
			glMatrixMode(GL_MODELVIEW);
				glPushMatrix();
				glLoadIdentity();
				process_scene_normal(cell, frag);
			glPopMatrix();
			
			case virttype_dirlight : break;
			case virttype_pointlight : break;
			case virttype_reflection : break;
			case virttype_shadow : break;
		}

		base = base->next;
	}
	
	return cell;
}

arcan_vobj_id arcan_3d_skybox(float base)
{

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
        update_view(&newmodel->direction, 0, 0, 0);

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

void arcan_3d_setdefaults()
{
	current_scene.perspectives = calloc( sizeof(virtobj), 1);
	virtobj* cam = current_scene.perspectives;
	cam->dynamic = true;
	cam->fov = 45.0;
	cam->rendertarget = 0;
    cam->type = virttype_camera;
	cam->position = build_vect(0, 0, 0); /* ret -x, y, +z */
	update_view(&cam->direction, 0, 0, 0);
}

