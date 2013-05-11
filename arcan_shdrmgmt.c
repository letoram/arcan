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
/*#define SHADER_TRACE*/

#include <SDL.h>
#include <SDL_opengl.h>

#include <sys/stat.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_shdrmgmt.h"
#include "arcan_videoint.h"

#define TBLSIZE (1 + TIMESTAMP_D - MODELVIEW_MATR)

extern int arcan_debug_pumpglwarnings(const char* src);

/* all current global shader settings,
 * updated whenever a vobj/3dobj needs a different state
 * each global */
struct shader_envts {
	float modelview[16];
	float projection[16];
	float texturemat[16];

	float opacity;
/* system values, don't change this order */
	float fract_timestamp;
	arcan_tickv timestamp;
};

static int ofstbl[TBLSIZE] = {
/* packed matrices */
	offsetof(struct shader_envts, modelview),
	offsetof(struct shader_envts, projection),
	offsetof(struct shader_envts, texturemat),

	offsetof(struct shader_envts, opacity),

/* system values, don't change this order */
	offsetof(struct shader_envts, fract_timestamp),
	offsetof(struct shader_envts, timestamp)
};

static enum shdrutype typetbl[TBLSIZE] = {
	shdrmat4x4, /* modelview */
	shdrmat4x4, /* projection */
	shdrmat4x4, /* texturem */

	shdrfloat, /* obj_opacity */
	shdrfloat, /* fract_timestamp */
	shdrint /* timestamp */
};

static char* typestrtbl[7] = {
	"shdrbool",
	"shdrint",
	"shdrfloat",
	"shdrvec2",
	"shdrvec3",
	"shdrvec4",
	"shdrmat4x4"
};

static char* symtbl[TBLSIZE] = {
	"modelview",
	"projection",
	"texturem",
	"obj_opacity",
	"fract_timestamp",
	"timestamp"
};

static char* attrsymtbl[4] = {
	"vertex",
	"normal",
	"color",
	"texcoord"
};

struct shaderv {
	GLint loc;
	char* label;
	enum shdrutype type;
	uint8_t data[64]; /* largest supported type, mat4x4 */
	struct shaderv* next;
};

struct shader_cont {
	char* label;
	char (* vertex), (* fragment);
	GLuint prg_container, obj_vertex, obj_fragment;

	GLint locations[sizeof(ofstbl) / sizeof(ofstbl[0])];
/* match attrsymtbl */
	GLint attributes[4];
	struct shaderv* persistvs;
};

static int sizetbl[7] = {
	sizeof(int),
	sizeof(int),
	sizeof(float),
	sizeof(float) * 2,
	sizeof(float) * 3,
	sizeof(float) * 4,
	sizeof(float) * 16
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
} shdr_global = {.base = 10000, .active_prg = -1, .guard = 64};


static bool build_shader(const char*, GLuint*, GLuint*, GLuint*, const char*, const char*);
static void kill_shader(GLuint* dprg, GLuint* vprg, GLuint* fprg);

static void setv(GLint loc, enum shdrutype kind, void* val, const char* id, const char* program)
{
#ifdef SHADER_TRACE
	arcan_warning("[shader], location(%d), kind(%s:%d), id(%s), program(%s)\n", loc, typestrtbl[kind], kind, id, program); 
#endif

#ifdef _DEBUG
	if (arcan_debug_pumpglwarnings("shdrmgmt.c:setv:pre") == -1){
		arcan_warning("setv() -> errors found when pumping context.\n");
        abort();
    }

#endif
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

#ifdef _DEBUG
    if (arcan_debug_pumpglwarnings("shdrmgmt.c:setv:post") == -1){
		int progno;
		glGetIntegerv(GL_CURRENT_PROGRAM, &progno);

		printf("failed operation: store type(%i:%s) into slot(%i:%s) on program(%i:%s)\n", kind, typestrtbl[kind], loc, id, progno, program);
		struct shader_cont* src = &shdr_global.slots[ shdr_global.active_prg ];
		printf("last active shader: (%s), locals: \n", src->label);
		for (unsigned i = 0; i < sizeof(ofstbl) / sizeof(ofstbl[0]); i++){
			printf("\t [%i] %s : %i\n", i, symtbl[i], src->locations[i]);
		}

      abort();
    }
#endif
}

arcan_errc arcan_shader_activate(arcan_shader_id shid)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	
	shid -= shdr_global.base;
 	if (shid < shdr_global.ofs && shid != shdr_global.active_prg){
		struct shader_cont* cur = shdr_global.slots + shid;
		glUseProgram(cur->prg_container);
 		shdr_global.active_prg = shid;

#ifdef SHADER_TRACE
		arcan_warning("[shader] shid(%d) => (%d), activate.\n", shid, cur->prg_container);
#endif

/* sweep the ofset table, for each ofset that has a set (nonnegative) ofset,
 * we use the index as a lookup for value and type */
		for (unsigned i = 0; i < sizeof(ofstbl) / sizeof(ofstbl[0]); i++){
			if (cur->locations[i] >= 0)
				setv(cur->locations[i], typetbl[i], (char*)(&shdr_global.context) + ofstbl[i], typestrtbl[i], cur->label);
		}

/* activate any persistant values */
		struct shaderv* current = cur->persistvs;
		while (current){
			setv(current->loc, current->type, (void*) current->data, current->label, cur->label);
			current = current->next;
		}

		rv = ARCAN_OK;
	}
#ifdef SHADER_TRACE
	else if (shid != shdr_global.active_prg) {
		arcan_warning("[shader] couldn't map (%d) to a useful shader.\n", shid);
	}
#endif

	return rv;
}

arcan_shader_id arcan_shader_lookup(const char* tag)
{
		for (int i = 0; i < shdr_global.ofs; i++){
			if (shdr_global.slots[i].label && strcmp(tag, shdr_global.slots[i].label) == 0)
				return i + shdr_global.base;
		}

	return -1;
}

bool arcan_shader_valid(arcan_shader_id id)
{
	return (id - shdr_global.base < shdr_global.ofs && id >= 0);
}

arcan_shader_id arcan_shader_build(const char* tag, const char* geom, const char* vert, const char* frag)
{
	arcan_shader_id rv = ARCAN_EID;
	bool overwrite = false;
	int dstind = -1;

/* first, look for a preexisting tag */
	for (unsigned i = 0; i < sizeof(shdr_global.slots) / sizeof(shdr_global.slots[0]); i++)
		if ( !shdr_global.slots[i].label )
			break;
		else if (strcmp( shdr_global.slots[i].label, tag ) == 0){
			dstind = i;
			overwrite = true;
			break;
		}

/* didn't get a match? take the next free slot,
 * else deallocate the current shader and replace it with the new ones */
	if (-1 == dstind)
		dstind = shdr_global.ofs++;
	else{
		kill_shader(&shdr_global.slots[dstind].prg_container, &shdr_global.slots[dstind].obj_vertex, &shdr_global.slots[dstind].obj_fragment);
		free(shdr_global.slots[dstind].vertex);
		free(shdr_global.slots[dstind].fragment);
		free(shdr_global.slots[dstind].label);
		memset(&shdr_global.slots[dstind], 0, sizeof(struct shader_cont));
		memset(&shdr_global.slots[dstind].locations, -1, sizeof(ofstbl) / sizeof(ofstbl[0]) * sizeof(GLint));
	}

/* copy label, programs, send to GL, resolve shared uniforms etc.
 * keep the data even if the build fails */
	if (dstind >= 0 && dstind < sizeof(shdr_global.slots) / sizeof(shdr_global.slots[0])){
		struct shader_cont* cur = shdr_global.slots + dstind;
		memset(cur, 0, sizeof(struct shader_cont));
		cur->label = strdup(tag);
		cur->vertex = strdup(vert);
		cur->fragment = strdup(frag);

		if (build_shader(tag, &cur->prg_container, &cur->obj_vertex, &cur->obj_fragment, vert, frag) == false){
			if (overwrite == false)
				shdr_global.ofs--;
			return ARCAN_EID;
		}
#ifdef _DEBUG
			arcan_warning("arcan_shader_build(%s) -- new ID : (%i)\n", tag, cur->prg_container);
#endif

		glUseProgram(cur->prg_container);
		for (unsigned i = 0; i < sizeof(ofstbl) / sizeof(ofstbl[0]); i++){
			assert(symtbl[i] != NULL);
			cur->locations[i] = glGetUniformLocation(cur->prg_container, symtbl[i]);
#ifdef _DEBUG
            if(cur->locations[i] != -1)
				arcan_warning("arcan_shader_build(%s)(%d), resolving uniform: %s to %i\n", tag, i, symtbl[i], cur->locations[i]);
#endif
        }

		for (unsigned i = 0; i < sizeof(attrsymtbl) / sizeof(attrsymtbl[0]); i++){
			cur->attributes[i] = glGetAttribLocation(cur->prg_container, attrsymtbl[i]);
#ifdef _DEBUG
            if (cur->attributes[i] != -1)
				arcan_warning("arcan_shader_build(%s)(%d), resolving attribute: %s to %i\n", tag, i, attrsymtbl[i], cur->attributes[i]);
#endif
		}

		rv = dstind + shdr_global.base;
	}

	return rv;
}

bool arcan_shader_envv(enum arcan_shader_envts slot, void* value, size_t size)
{
	memcpy((char*) (&shdr_global.context) + ofstbl[slot], value, size);
	if (-1  == shdr_global.active_prg)
		return false;

	int glloc = shdr_global.slots[ shdr_global.active_prg].locations[slot];

#ifdef SHADER_TRACE
	arcan_warning("[shader] global envv global update.\n");
#endif
	
	/* reflect change in current active shader */
	if (glloc != -1){
		assert(size == sizetbl[ typetbl[slot] ]);
		setv(glloc, typetbl[slot], value, typestrtbl[slot], shdr_global.slots[ shdr_global.active_prg].label );
		return true;
	}

	return false;
}

GLint arcan_shader_vattribute_loc(enum shader_vertex_attributes attr)
{
	return shdr_global.slots[ shdr_global.active_prg ].attributes[ attr ];
}

void arcan_shader_forceunif(const char* label, enum shdrutype type, void* value, bool persist)
{
	GLint loc;
	assert(shdr_global.active_prg != -1);
	struct shader_cont* slot = &shdr_global.slots[shdr_global.active_prg];

/* try to find a matching label, if one is found, just replace the loc and copy the value */
	if (persist) {
/* linear search */
		struct shaderv** current = &(slot->persistvs);
		for (current = &(slot->persistvs); *current; current = &(*current)->next)
			if (strcmp((*current)->label, label) == 0)
				break;

/* found? then continue, else allocate new and return that loc */
		if (*current){
			loc = (*current)->loc;
			if ((*current)->type != type)
				arcan_warning("arcan_shader_forceunif(), type mismatch for persistant shader uniform (%s:%i=>%i), ignored.\n", label, loc, type);
		}
		else {
			loc = glGetUniformLocation(slot->prg_container, label);
			*current = (struct shaderv*) malloc( sizeof(struct shaderv) );
			(*current)->label = strdup(label);
			(*current)->loc   = loc;
			(*current)->type  = type;
			(*current)->next  = NULL;
		}

		memcpy((*current)->data, value, sizetbl[type]);
	}
/* or, we just want to update the uniform ONCE (disappear on push/pop etc.) */
	else
		loc = glGetUniformLocation(slot->prg_container, label);

	if (loc >= 0){
		setv(loc, type, value, label, slot->label);
#ifdef DEBUG
		arcan_warning("arcan_shader_forceunif(): setting uniform %s in shader: %s\n", label, shdr_global.slots[shdr_global.active_prg].label);
#endif
	}
#ifdef DEBUG
	else
		arcan_warning("arcan_shader_forceunif(): no matching location found for %s in shader: %s\n", label, shdr_global.slots[shdr_global.active_prg].label);
#endif
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

static bool build_shader(const char* label, GLuint* dprg, GLuint* vprg, GLuint* fprg, const char* vprogram, const char* fprogram)
{
	char buf[256];
	int rlen;

	*dprg = glCreateProgram();
	*vprg = glCreateShader(GL_VERTEX_SHADER);
	*fprg = glCreateShader(GL_FRAGMENT_SHADER);

	if (arcan_debug_pumpglwarnings("shdrmgmt:pre:build_shader") == -1){
		arcan_warning("|--> When attempting to build (%s)\n", label);
	}

	glShaderSource(*vprg, 1, &vprogram, NULL);
	glShaderSource(*fprg, 1, &fprogram, NULL);

	glCompileShader(*vprg);
	glCompileShader(*fprg);

	glGetShaderInfoLog(*vprg, 256, &rlen, buf);

	if (rlen){
		arcan_warning("Warning: Couldn't compile Shader vertex program(%s): %s\n", label, buf);
		arcan_warning("Vertex Program: %s\n", vprogram);
	}
	glGetShaderInfoLog(*fprg, 256, &rlen, buf);

	if (rlen){
		arcan_warning("Warning: Couldn't compile Shader fragment Program(%s): %s\n", label, buf);
		arcan_warning("Fragment Program: %s\n", fprogram);
	}

	if (arcan_debug_pumpglwarnings("shdrmgmt:post:build_shader") == -1){
		arcan_warning("Warning: Error while compiling (%s)\n", label);

		kill_shader(dprg, vprg, fprg);
		return false;
	} else {
		glAttachShader(*dprg, *fprg);
		glAttachShader(*dprg, *vprg);
		glLinkProgram(*dprg);

		if (arcan_debug_pumpglwarnings("shdrmgmt:post:link_shader") == -1){
			glGetProgramInfoLog(*dprg, 256, &rlen, buf);

			if (rlen)
				arcan_warning("Warning: Problem linking Shader Program(%s): %s\n", label, buf);

			kill_shader(dprg, vprg, fprg);
			return false;
		}
	}

	return true;
}

const char* arcan_shader_symtype(enum arcan_shader_envts env)
{
	return symtbl[env];
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
		
		struct shaderv* first = cur->persistvs;
		while (first){
			struct shaderv* last = first;
			free(first->label);
			first = first->next;
			memset(last, 0, sizeof(struct shaderv));
			free(last);
		}
		
		memset(cur, 0, sizeof(struct shader_cont));
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

		build_shader(cur->label, &cur->prg_container, &cur->obj_vertex, &cur->obj_fragment,
			cur->vertex, cur->fragment);
	}
}

