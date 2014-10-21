#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>
#include <string.h>
#include <stddef.h>

#include GL_HEADERS

#include <sys/stat.h>

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

	float opacity;
	float move;
	float rotate;
	float scale;

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
	offsetof(struct shader_envts, move),
	offsetof(struct shader_envts, rotate),
	offsetof(struct shader_envts, scale),

/* system values, don't change this order */
	offsetof(struct shader_envts, fract_timestamp),
	offsetof(struct shader_envts, timestamp)
};

static enum shdrutype typetbl[TBLSIZE] = {
	shdrmat4x4, /* modelview */
	shdrmat4x4, /* projection */
	shdrmat4x4, /* texturem */

	shdrfloat, /* obj_opacity */
	shdrfloat, /* obj_move */
	shdrfloat, /* obj_rotate */
	shdrfloat, /* obj_scale */

	shdrfloat, /* fract_timestamp */
	shdrint /* timestamp */
};

static int counttbl[TBLSIZE] = {
	0, 0, 0, 0, 0, 0, 0, 0, 0
};

static char* symtbl[TBLSIZE] = {
	"modelview",
	"projection",
	"texturem",
	"obj_opacity",
	"trans_move",
	"trans_scale",
	"trans_rotate",
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

static bool build_shader(const char*, GLuint*, GLuint*, GLuint*,
	const char*, const char*);
static void kill_shader(GLuint* dprg, GLuint* vprg, GLuint* fprg);

static void setv(GLint loc, enum shdrutype kind, void* val,
	const char* id, const char* program)
{
#ifdef SHADER_TRACE
	arcan_warning("[shader], location(%d), kind(%s:%d), id(%s), program(%s)\n",
			loc, symtbl[kind], kind, id, program);
#endif

/* add more as needed, just match the current shader_envts */
	switch (kind){
	case shdrbool:
	case shdrint:
	glUniform1i(loc, *(GLint*) val);
	break;

	case shdrfloat :
	glUniform1f(loc, ((GLfloat*) val)[0]);
	break;

	case shdrvec2 :
	glUniform2f(loc, ((GLfloat*) val)[0], ((GLfloat*) val)[1]);
	break;

	case shdrvec3 :
	glUniform3f(loc, ((GLfloat*) val)[0], ((GLfloat*) val)[1],
	((GLfloat*) val)[2]);
	break;

	case shdrvec4  :
	glUniform4f(loc, ((GLfloat*) val)[0], ((GLfloat*) val)[1],
	((GLfloat*) val)[2], ((GLfloat*) val)[3]);
	break;

	case shdrmat4x4:
	glUniformMatrix4fv(loc, 1, false, (GLfloat*) val);
	break;
	}
}

arcan_errc arcan_shader_activate(arcan_shader_id shid)
{
	if (!arcan_shader_valid(shid))
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	shid -= shdr_global.base;

 	if (shid != shdr_global.active_prg){
		struct shader_cont* cur = shdr_global.slots + shid;
		glUseProgram(cur->prg_container);
 		shdr_global.active_prg = shid;

#ifdef SHADER_TRACE
		arcan_warning("[shader] shid(%d) => (%d), activate %s\n",
			shid, cur->prg_container, cur->label);
#endif

/*
 * While we chould practically just update the uniforms that has
 * actually changed since the last push as we keep a cache,
 * the incentive is rather small (uniform- set on a bound shader
 * is among the cheaper state changes possible).
 */
		for (unsigned i = 0; i < sizeof(ofstbl) / sizeof(ofstbl[0]); i++){
			if (cur->locations[i] >= 0){
				setv(cur->locations[i], typetbl[i], (char*)(&shdr_global.context)
					+ ofstbl[i], symtbl[i], cur->label);
				counttbl[i]++;
			}
		}

/* activate any persistant values */
		struct shaderv* current = cur->persistvs;
		while (current){
			setv(current->loc, current->type, (void*) current->data,
				current->label, cur->label);
			current = current->next;
		}
	}

	return ARCAN_OK;
}

arcan_shader_id arcan_shader_lookup(const char* tag)
{
		for (int i = 0; i < sizeof(shdr_global.slots) /
			sizeof(shdr_global.slots[0]); i++){
			if (shdr_global.slots[i].label &&
				strcmp(tag, shdr_global.slots[i].label) == 0)
				return i + shdr_global.base;
		}

	return -1;
}

const char* arcan_shader_lookuptag(arcan_shader_id id)
{
	if (!arcan_shader_valid(id))
		return NULL;

	return shdr_global.slots[id - shdr_global.base].label;
}

bool arcan_shader_lookupprgs(arcan_shader_id id,
	const char** vert, const char** frag)
{
	if (!arcan_shader_valid(id))
		return false;

	if (vert)
		*vert = shdr_global.slots[id - shdr_global.base].vertex;

	if (frag)
		*frag = shdr_global.slots[id - shdr_global.base].fragment;

	return true;
}

bool arcan_shader_valid(arcan_shader_id id)
{
	id -= shdr_global.base;
	return (id >= 0 && id < sizeof(shdr_global.slots) /
		sizeof(shdr_global.slots[0]) && shdr_global.slots[id].label != NULL);
}

arcan_shader_id arcan_shader_build(const char* tag, const char* geom,
	const char* vert, const char* frag)
{
	int slot_lim = sizeof(shdr_global.slots) / sizeof(shdr_global.slots[0]);
	bool overwrite = false;
	int dstind = -1;

/* first, look for a preexisting tag */
	for (unsigned i = 0; i < slot_lim; i++)
		if (shdr_global.slots[i].label &&
			strcmp(shdr_global.slots[i].label, tag) == 0){
			dstind = i;
			overwrite = true;
			break;
		}

/* no match, find a free slot */
	if (dstind == -1){
		shdr_global.ofs = (shdr_global.ofs + 1) % slot_lim;
		if (!shdr_global.slots[shdr_global.ofs].label)
			dstind = shdr_global.ofs;
		else
			for (unsigned i = 0; i < slot_lim; i++)
				if (!shdr_global.slots[i].label){
					dstind = i;
					break;
				}
	}

/* still no match? means we're overallocated on shaders, bad program/script */
	if (dstind == -1)
		return ARCAN_EID;

	struct shader_cont* cur = &shdr_global.slots[dstind];

/* obliterate the last one first */
	if (overwrite){
		kill_shader(&cur->prg_container, &cur->obj_fragment, &cur->obj_vertex);
		free(cur->vertex);
		free(cur->fragment);
		free(cur->label);

/* drop all persistant values */
		struct shaderv* first = cur->persistvs;
		while (first){
			struct shaderv* last = first;
			free(first->label);
			first = first->next;
			memset(last, 0, sizeof(struct shaderv));
			free(last);
		}

/* reset everything to NULL */
		memset(cur, 0, sizeof(struct shader_cont));
	}

/* always reset locations tbl */
	int global_lim = sizeof(ofstbl) / sizeof(ofstbl[0]);
	for (int i = 0; i < global_lim; i++)
		cur->locations[i] = -1;

	if (build_shader(tag, &cur->prg_container, &cur->obj_vertex,
			&cur->obj_fragment, vert, frag) == false)
		return ARCAN_EID;

	cur->label    = strdup(tag);
	cur->vertex   = strdup(vert);
	cur->fragment = strdup(frag);

#ifdef _DEBUG
	arcan_warning("arcan_shader_build(%s) -- new ID : (%i)\n",
		tag, cur->prg_container);
#endif

/* preset global symbol mappings */
	glUseProgram(cur->prg_container);
	for (unsigned i = 0; i < global_lim; i++){
		assert(symtbl[i] != NULL);
		cur->locations[i] = glGetUniformLocation(cur->prg_container, symtbl[i]);
#ifdef _DEBUG
		if(cur->locations[i] != -1)
				arcan_warning("arcan_shader_build(%s)(%d), "
				"resolving uniform: %s to %i\n", tag, i, symtbl[i], cur->locations[i]);
#endif
	}

/* same treatment for attributes */
	for (unsigned i = 0; i < sizeof(attrsymtbl) / sizeof(attrsymtbl[0]); i++){
		cur->attributes[i] = glGetAttribLocation(cur->prg_container, attrsymtbl[i]);
#ifdef _DEBUG
	if (cur->attributes[i] != -1)
		arcan_warning("arcan_shader_build(%s)(%d), "
			"resolving attribute: %s to %i\n", tag, i, attrsymtbl[i], cur->attributes[i]);
#endif
	}

/* revert to last used program! */
	if (shdr_global.active_prg != -1){
		glUseProgram(shdr_global.slots[shdr_global.active_prg].prg_container);
	}

/* we use a variable base to prevent hardcoded values */
	return dstind + shdr_global.base;
}

int arcan_shader_envv(enum arcan_shader_envts slot, void* value, size_t size)
{
	memcpy((char*) (&shdr_global.context) + ofstbl[slot], value, size);
	int rv = counttbl[slot];
	counttbl[slot] = 0;

	if (-1  == shdr_global.active_prg)
		return rv;

	int glloc = shdr_global.slots[ shdr_global.active_prg].locations[slot];

#ifdef SHADER_TRACE
	arcan_warning("[shader] global envv global update.\n");
#endif

/*
 * reflect change in current active shader,
 * the others will be changed on activation
 */
	if (glloc != -1){
		assert(size == sizetbl[ typetbl[slot] ]);
		setv(glloc, typetbl[slot], value, symtbl[slot],
			shdr_global.slots[ shdr_global.active_prg].label );
		counttbl[slot]++;

		return rv;
	}

	return rv;
}

GLint arcan_shader_vattribute_loc(enum shader_vertex_attributes attr)
{
	return shdr_global.slots[ shdr_global.active_prg ].attributes[ attr ];
}

void arcan_shader_forceunif(const char* label, enum shdrutype type,
	void* value, bool persist)
{
	GLint loc;
	assert(shdr_global.active_prg != -1);
	struct shader_cont* slot = &shdr_global.slots[shdr_global.active_prg];
	FLAG_DIRTY();

/* try to find a matching label, if one is found, just replace
 * the loc and copy the value */
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
				arcan_warning("arcan_shader_forceunif(), type mismatch for "
					"persistant shader uniform (%s:%i=>%i), ignored.\n", label, loc, type);
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
		arcan_warning("arcan_shader_forceunif(): setting uniform %s in"
			"	shader: %s\n", label, shdr_global.slots[shdr_global.active_prg].label);
#endif
	}
#ifdef DEBUG
	else
		arcan_warning("arcan_shader_forceunif(): no matching location found for"
			"%s in shader: %s\n", label, shdr_global.slots[shdr_global.active_prg].label);
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

static bool build_shunit(GLint stage, const char* prg, GLuint* dprg)
{
	*dprg = glCreateShader(stage);
	glShaderSource(*dprg, 1, &prg, NULL);
	glCompileShader(*dprg);
	GLint status = 0;
	glGetShaderiv(*dprg, GL_COMPILE_STATUS, &status);
	return status != GL_FALSE;
}

static void dump_shaderlog(const char* label, const char* stage, GLuint prg)
{
	char buf[1024];
	int rlen;

	glGetShaderInfoLog(prg, 1024, &rlen, buf);
	if (rlen){
		arcan_warning("Warning: Couldn't compile shader (%s:%s)\n\t message:%s\n",
			label, stage, buf);
	}
}

static bool build_shader(const char* label, GLuint* dprg,
	GLuint* vprg, GLuint* fprg, const char* vprogram, const char* fprogram)
{
	bool failed = false;

#ifdef DEBUG
	bool force = true;
#else
	bool force = false;
#endif

	if (( failed = !build_shunit(GL_VERTEX_SHADER, vprogram, vprg)) || force)
		dump_shaderlog(label, "vertex", *vprg);

	if (( failed |= !build_shunit(GL_FRAGMENT_SHADER, fprogram, fprg)) || force)
		dump_shaderlog(label, "fragment", *fprg);

/*
 * driver issues make this validation step rather uncertain,
 * another option would be to use a reference shader that
 * should compile, resolve attributes and uniforms and if they
 * map to the same location, we know something is broken and
 * that it's not our fault.
 */

	*dprg = glCreateProgram();
	glAttachShader(*dprg, *fprg);
	glAttachShader(*dprg, *vprg);
	glLinkProgram(*dprg);

	int lstat = 0;
	glGetProgramiv(*dprg, GL_LINK_STATUS, &lstat);

	if (GL_FALSE == lstat){
		printf("LINK STAGE FAILED\n");
		failed = true;
		dump_shaderlog(label, "link", *dprg);
	}

	return !failed;
}

const char* arcan_shader_symtype(enum arcan_shader_envts env)
{
	return symtbl[env];
}

void arcan_shader_flush()
{
	for (unsigned i = 0; i < sizeof(shdr_global.slots)
		/ sizeof(shdr_global.slots[0]); i++){
		struct shader_cont* cur = shdr_global.slots + i;
		if (cur->label == NULL)
			continue;

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
	shdr_global.active_prg = -1;
}

void arcan_shader_rebuild_all()
{
	for (unsigned i = 0; i < sizeof(shdr_global.slots) /
			sizeof(shdr_global.slots[0]); i++){
		struct shader_cont* cur = shdr_global.slots + i;
		if (cur->label == NULL)
			continue;

		build_shader(cur->label, &cur->prg_container, &cur->obj_vertex,
			&cur->obj_fragment, cur->vertex, cur->fragment);
	}
}

