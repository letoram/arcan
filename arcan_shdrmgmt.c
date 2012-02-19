#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>

#ifdef POOR_GL_SUPPORT
#define GLEW_STATIC
#define NO_SDL_GLEXT
#include <glew.h>
#endif

#define GL_GLEXT_PROTOTYPES 1

#include <SDL.h>
#include <SDL_opengl.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_shdrmgmt.h"
#include "arcan_videoint.h"

#define TBLSIZE (1 + TIMESTAMP_D - MODELVIEW_MATR)

/* all current global shader settings,
 * updated whenever a vobj/3dobj needs a different state
 * each global */ 
struct shader_envts {
	float modelview[16];
	float projection[16];
	float texturemat[16];

	vector camera_view;
	vector camera_up;
	vector camera_pos;

	vector obj_scale;
	vector obj_pos;
	vector obj_orient;
	vector obj_view;
	float obj_opacity;

/* texture mapping */
	int map_generic;
	int map_displacement;
	int map_bump;
	int map_shadow;
	int map_reflection;
	int map_normal;
	int map_specular;
	int map_diffuse;

/* lighting */
	vector light_worlddir;
	
/* system values, don't change this order */
	arcan_tickv timestamp;
}; 

static int ofstbl[TBLSIZE] = {
/* packed matrices */
	offsetof(struct shader_envts, modelview),
	offsetof(struct shader_envts, projection),
	offsetof(struct shader_envts, texturemat),
	
/* current camera */
	offsetof(struct shader_envts, camera_view),
	offsetof(struct shader_envts, camera_up),
	offsetof(struct shader_envts, camera_pos),
	
/* current object */
	offsetof(struct shader_envts, obj_scale),
	offsetof(struct shader_envts, obj_pos),
	offsetof(struct shader_envts, obj_orient),
	offsetof(struct shader_envts, obj_view),
	offsetof(struct shader_envts, obj_opacity),

/* texture mapping */
	offsetof(struct shader_envts, map_generic),
	offsetof(struct shader_envts, map_displacement),
	offsetof(struct shader_envts, map_bump),
	offsetof(struct shader_envts, map_shadow),
	offsetof(struct shader_envts, map_reflection),
	offsetof(struct shader_envts, map_normal),
	offsetof(struct shader_envts, map_specular),
	offsetof(struct shader_envts, map_diffuse),

/* lighting */
	offsetof(struct shader_envts, light_worlddir),
	
/* system values, don't change this order */
	offsetof(struct shader_envts, timestamp)
};

static enum shdrutype typetbl[TBLSIZE] = {
	shdrmat4x4,
	shdrmat4x4,
	shdrmat4x4,
	shdrvec3, /* camera */
	shdrvec3,
	shdrvec3,
	shdrvec3, /* obj */
	shdrvec3,
	shdrvec3,
	shdrvec3,
	shdrfloat,
	shdrint, /* map */
	shdrint,
	shdrint,
	shdrint,
	shdrint,
	shdrint,
	shdrint,
	shdrint,
	shdrvec3, /* light worlddir */
	shdrint
};

static char* symtbl[TBLSIZE] = {
	"modelview",
	"projection",
	"texture",
	"camera_view",
	"camera_up",
	"camera_pos",
	"obj_scale",
	"obj_pos",
	"obj_orient",
	"obj_view",
	"obj_opacity",
	"map_generic",
	"map_displacement",
	"map_bump",
	"map_shadow",
	"map_reflection",
	"map_normal",
	"map_specular",
	"map_diffuse",
	"light_worlddir",
	"timestamp"
};

static char* attrsymtbl[4] = {
	"vertex",
	"normal",
	"color",
	"texcoord"
};

struct shader_cont {
	arcan_shader_id id;
	char* label;
	char (* vertex), (* fragment);
	GLuint prg_container, obj_vertex, obj_fragment;

	GLint locations[sizeof(ofstbl)];
/* match attrsymtbl */
	GLint attributes[4];
};

/* base is added as a controllable offset similarly to what is done
 * with video/audio IDs, i.e. in order to quickly shake out hard-coded
 * ID references */
static struct {
	struct shader_cont slots[256];
	unsigned ofs, base;
	arcan_shader_id active_prg;
	struct shader_envts context;
	char guard;
} shdr_global = {.base = 100, .active_prg = 256, .guard = 64};


static void build_shader(GLuint*, GLuint*, GLuint*, const char*, const char*);

static void setv(GLuint loc, enum shdrutype kind, void* val)
{
/* add more as needed, just match the current shader_envts */
	switch (kind){
		case shdrbool:
		case shdrint:
			glUniform1i(loc, *(GLint*) val); break;

		case shdrfloat: glUniform1f(loc, ((GLfloat*) val)[0]); break;
		case shdrvec2:  glUniform2f(loc, ((GLfloat*) val)[0], ((GLfloat*) val)[1]); break;
		case shdrvec3:  glUniform3f(loc, ((GLfloat*) val)[0], ((GLfloat*) val)[1], ((GLfloat*) val)[2]); break;
		case shdrvec4:  glUniform4f(loc, ((GLfloat*) val)[0], ((GLfloat*) val)[1], ((GLfloat*) val)[2], ((GLfloat*) val)[3]); break;

		case shdrmat4x4: glUniformMatrix4fv(loc, 1, false, (GLfloat*) val); break;
	}	
}

arcan_errc arcan_shader_activate(arcan_shader_id shid)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	shid -= shdr_global.base;
	if (shid < shdr_global.ofs && shdr_global.active_prg != shid){
		struct shader_cont* cur = shdr_global.slots + shid;
		glUseProgram(cur->prg_container);
		shdr_global.active_prg = shid;

	/* sweep the ofset table, for each ofset that has a set (nonnegative) ofset,
	 * we use the index as a lookup for value and type */
		for (unsigned i = 0; i < sizeof(ofstbl); i++){
			if (cur->locations[i] >= 0)
				setv(cur->locations[i], typetbl[i], (char*)(&shdr_global.context) + ofstbl[i]);
		}
			
		rv = ARCAN_OK;
	}
}

arcan_shader_id arcan_shader_build(const char* tag, const char* geom, const char* vert, const char* frag)
{
	arcan_shader_id rv = ARCAN_EID;
	if (shdr_global.ofs < sizeof(shdr_global.slots)){
		struct shader_cont* cur = shdr_global.slots + shdr_global.ofs;
		cur->id = shdr_global.ofs;
		cur->label = strdup(tag);
		cur->vertex = strdup(vert);
		cur->fragment = strdup(frag);

		build_shader(&cur->prg_container, &cur->obj_vertex, &cur->obj_fragment, vert, frag);
		glUseProgram(cur->prg_container);
		for (unsigned i = 0; i < sizeof(ofstbl) / sizeof(ofstbl[0]); i++){
			assert(symtbl[i] != NULL);
			cur->locations[i] = glGetUniformLocation(cur->prg_container, symtbl[i]);
			printf("lookup for %s to %i\n", symtbl[i], cur->locations[i]);
		}

		for (unsigned i = 0; i < sizeof(attrsymtbl) / sizeof(attrsymtbl[0]); i++){
			cur->attributes[i] = glGetAttribLocation(cur->prg_container, attrsymtbl[i]);
			printf("lookup attribute(%s) resolved to: %i\n", attrsymtbl[i], cur->attributes[i]);
		}
		
		rv = shdr_global.ofs + shdr_global.base;
		shdr_global.ofs++;
	}

	return rv;
}

void arcan_shader_envv(enum arcan_shader_envts slot, void* value, size_t size)
{
	memcpy((char*) (&shdr_global.context) + ofstbl[slot], value, size);
	GLint loc;

/* update the value for the shader so we might avoid a full glUseProgram, ... cycle */
	if ( (loc = shdr_global.slots[ shdr_global.active_prg ].locations[slot]) >= 0 )
		setv(loc, typetbl[slot], value);
}

GLint arcan_shader_vattribute_loc(enum shader_vertex_attributes attr)
{
	return shdr_global.slots[ shdr_global.active_prg ].attributes[ attr ];
}

void arcan_shader_forceunif(const char* label, enum shdrutype type, void* value)
{
	GLint loc = glGetAttribLocation(shdr_global.active_prg, label);
	if (loc >= 0)
		setv(loc, type, value);
}

static void kill_shader(GLuint* dprg, GLuint* vprg, GLuint* fprg){
	if (*dprg)
		glDeleteProgram(*dprg);

	if (*vprg)
		glDeleteShader(*vprg);
	
	if (*fprg)
		glDeleteShader(*fprg);
	
	*dprg = *vprg = *fprg = 0;
}

static void build_shader(GLuint* dprg, GLuint* vprg, GLuint* fprg, const char* vprogram, const char* fprogram)
{
	char buf[256];
	int rlen;

	kill_shader(dprg, vprg, fprg);
	
	*dprg = glCreateProgram();
	*vprg = glCreateShader(GL_VERTEX_SHADER);
	*fprg = glCreateShader(GL_FRAGMENT_SHADER);

	glShaderSource(*vprg, 1, &vprogram, NULL);
	glShaderSource(*fprg, 1, &fprogram, NULL);

	glCompileShader(*vprg);
	glCompileShader(*fprg);
	
	glGetShaderInfoLog(*vprg, 256, &rlen, buf);
	if (rlen)
		arcan_warning("Warning: Couldn't compiler Shader vertex program: %s\n", buf);

	glGetShaderInfoLog(*fprg, 256, &rlen, buf);
	if (rlen)
		arcan_warning("Warning: Couldn't compiler Shader fragment Program: %s\n", buf);

	glAttachShader(*dprg, *fprg);
	glAttachShader(*dprg, *vprg);

	glLinkProgram(*dprg);

	glGetProgramInfoLog(*dprg, 256, &rlen, buf);
	if (rlen)
		arcan_warning("Warning: Problem linking Shader Program: %s\n", buf);
}

void arcan_shader_flush()
{
	for (unsigned i = 0; i < shdr_global.ofs; i++){
		struct shader_cont* cur = shdr_global.slots + i;
		
		free( cur->label );
		free( cur->vertex );
		free( cur->fragment );

		kill_shader(&cur->prg_container, &cur->obj_vertex, &cur->obj_fragment);
		cur->prg_container = cur->obj_vertex = cur->obj_fragment;
	}
	
	shdr_global.ofs = 0;
}

void arcan_shader_unload_all()
{
	for (unsigned i = 0; i < shdr_global.ofs; i++){
		struct shader_cont* cur = shdr_global.slots + i;
		kill_shader(&cur->prg_container, &cur->obj_vertex, &cur->obj_fragment);
	}
	
}

void arcan_shader_rebuild_all()
{
	for (unsigned i = 0; i < shdr_global.ofs; i++){
		struct shader_cont* cur = shdr_global.slots + i;

		build_shader(&cur->prg_container, &cur->obj_vertex, &cur->obj_fragment,
			cur->vertex, cur->fragment);
	}
}

