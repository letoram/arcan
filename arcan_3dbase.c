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
    quat rotation;
	orientation direction;
    float projmatr[16];
	
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

static void build_hplane(point min, point max, point step, 
                         float** verts, unsigned** indices, float** txcos,
                         unsigned* nverts, unsigned* nindices, unsigned* ntxcos)
{
    point delta = {
        .x = max.x - min.x,
        .y = max.y,
        .z = max.z - min.z
    };
    
    unsigned nx = ceil(delta.x / step.x);
    unsigned ny = ceil(delta.z / step.z);
    
    *nverts = nx * ny;
    *verts = (float*) malloc(sizeof(float) * (*nverts) * 3);
    
    unsigned ofs = 0;
    for (unsigned row = 0; row < ny; row++)
        for (unsigned col = 0; col < nx; col++){
            *verts[ofs++] = min.x + ((float)col * step.x);
            *verts[ofs++] = max.y;
            *verts[ofs++] = min.z + ((float)row * step.z);
        }
}

static void build_projmatr(float near, float far, float aspect, float fov, float m[16]){
    const float h = 1.0f / tan(fov * (M_PI / 360.0));
    float neg_depth = near - far;
    
    m[0]  = h / aspect; m[1]  = 0; m[2]  = 0;  m[3] = 0;
    m[4]  = 0; m[5]  = h; m[6]  = 0;  m[7] = 0;
    m[8]  = 0; m[9]  = 0; m[10] = (far + near) / neg_depth; m[11] =-1;
    m[12] = 0; m[13] = 0; m[14] = 2.0f * (near * far) / neg_depth; m[15] = 0;
}

static inline void wireframe_box(float minx, float miny, float minz, float maxx, float maxy, float maxz)
{
    glColor3f(0.2, 1.0, 0.2);
    glBegin(GL_LINES);

    glVertex3f(minx, miny, minz);
    glVertex3f(minx, miny, maxz);
    
    glVertex3f(minx, miny, minz);
    glVertex3f(minx, maxy, minz);
    
    glVertex3f(minx, miny, maxz);
    glVertex3f(maxx, miny, maxz);

    glVertex3f(minx, miny, maxz);
    glVertex3f(minx, maxy, maxz);
    
    glVertex3f(maxx, miny, maxz);
    glVertex3f(maxx, miny, minz);
    
    glVertex3f(maxx, miny, maxz);
    glVertex3f(maxx, maxy, maxz);

    glVertex3f(maxx, miny, maxz);
    glVertex3f(maxx, miny, minz);

    glVertex3f(maxx, miny, maxz);
    glVertex3f(maxx, maxy, maxz);
        
    glVertex3f(minx, maxy, minz);
    glVertex3f(minx, maxy, maxz);
    
    glVertex3f(minx, maxy, maxz);
    glVertex3f(maxx, maxy, maxz);
    
    glVertex3f(maxx, maxy, maxz);
    glVertex3f(maxx, maxy, minz);
    
    glVertex3f(maxx, maxy, maxz);
    glVertex3f(maxx, maxy, minz);
    
    glEnd();
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

	if (1 || src->flags.debug_vis){
        wireframe_box(src->bbmin.x, src->bbmin.y, src->bbmin.z, src->bbmax.x, src->bbmax.y, src->bbmax.z);
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
                glLoadMatrixf(base->projmatr);

                glMatrixMode(GL_MODELVIEW);
                    glMultMatrixf(base->direction.matr);
                    glTranslatef(base->position.x, base->position.y, base->position.z);
                
				process_scene_normal(cell, frag);
			
			case virttype_dirlight : break;
			case virttype_pointlight : break;
			case virttype_reflection : break;
			case virttype_shadow : break;
		}

		base = base->next;
	}
	
	return cell;
}


static void minmax_verts(vector* minp, vector* maxp, const float* verts, unsigned nverts)
{
    vector empty = {0};
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

void arcan_3d_movecamera(unsigned camtag, float px, float py, float pz, unsigned tv)
{
    virtobj* vobj = current_scene.perspectives;
    unsigned ofs = 0;
    
    while (vobj){
        if (vobj->type == virttype_camera && camtag == ofs){
            vobj->position.x = px;
            vobj->position.y = py;
            vobj->position.z = pz;
            break;
        } else ofs++;
        vobj = vobj->next;
    }
}

void arcan_3d_orientcamera(unsigned camtag, float roll, float pitch, float yaw, unsigned tv)
{
    virtobj* vobj = current_scene.perspectives;
    unsigned ofs = 0;
    
    while (vobj){
        if (vobj->type == virttype_camera && camtag == ofs){
            vobj->rotation = build_quat_euler(roll, pitch, yaw);
            break;
        } else ofs++;
        vobj = vobj->next;
    }    
}

arcan_vobj_id arcan_3d_buildplane(float minx, float minz, float maxx, float maxz, float y){
    return ARCAN_OK;
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
		
		verts   = ctmGetFloatArray(newmodel->ctmmodel, CTM_VERTICES);
        minmax_verts(&newmodel->bbmin, &newmodel->bbmax, verts, n_verts); 
        
		 /*	n_tris  = ctmGetInteger(src->ctmmodel, CTM_TRIANGLE_COUNT);
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

void arcan_3d_movemodel(arcan_vobj_id src, float x, float y, float z, unsigned dt)
{
}

void arcan_3d_setdefaults()
{
	current_scene.perspectives = calloc( sizeof(virtobj), 1);
	virtobj* cam = current_scene.perspectives;
	cam->dynamic = true;

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    gluPerspective(60.0, (float)arcan_video_display.width / (float)arcan_video_display.height, 0.0, 100.0);
    glGetFloatv(GL_PROJECTION_MATRIX, cam->projmatr);
    glLoadIdentity();
    
    cam->rendertarget = 0;
    cam->type = virttype_camera;
	cam->position = build_vect(0, 0, 0); /* ret -x, y, +z */
	update_view(&cam->direction, 0, 0, 0);
}

