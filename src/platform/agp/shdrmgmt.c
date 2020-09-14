/*
 * Copyright 2014-2020, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdbool.h>
#include <assert.h>
#include <string.h>
#include <stddef.h>
#include <unistd.h>

#include "glfun.h"

#include "platform.h"

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"

#ifdef HEADLESS_NOARCAN
#undef FLAG_DIRTY
#define FLAG_DIRTY()
#endif

#define TBLSIZE (1 + TIMESTAMP_D - MODELVIEW_MATR)

/* all current global shader settings,
 * updated whenever a vobj/3dobj needs a different state
 * each global */
struct shader_envts {
	float modelview[16];
	float projection[16];
	float texturemat[16];

	float opacity;
	float blend;
	float move;
	float rotate;
	float scale;

	float sz_input[2];
	float sz_output[2];
	float sz_storage[2];

	int rtgt_id;

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

	offsetof(struct shader_envts, blend),
	offsetof(struct shader_envts, move),
	offsetof(struct shader_envts, rotate),
	offsetof(struct shader_envts, scale),

	offsetof(struct shader_envts, sz_input),
	offsetof(struct shader_envts, sz_output),
	offsetof(struct shader_envts, sz_storage),

	offsetof(struct shader_envts, rtgt_id),

/* system values, don't change this order */
	offsetof(struct shader_envts, fract_timestamp),
	offsetof(struct shader_envts, timestamp)
};

static enum shdrutype typetbl[TBLSIZE] = {
	shdrmat4x4, /* modelview */
	shdrmat4x4, /* projection */
	shdrmat4x4, /* texturem */

	shdrfloat, /* obj_opacity */
	shdrfloat, /* trans_blend */
	shdrfloat, /* trans_move */
	shdrfloat, /* trans_scale */
	shdrfloat, /* trans_rotate */

	shdrvec2, /* obj_input_sz */
	shdrvec2, /* obj_output_sz */
	shdrvec2, /* obj_storage_sz */

	shdrint, /* rtgt_id */

	shdrfloat, /* fract_timestamp */
	shdrint /* timestamp */
};

static int counttbl[TBLSIZE] = {
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
};

static char* symtbl[TBLSIZE] = {
	"modelview",
	"projection",
	"texturem",
	"obj_opacity",
	"trans_blend",
	"trans_move",
	"trans_scale",
	"trans_rotate",
	"obj_input_sz",
	"obj_output_sz",
	"obj_storage_sz",
	"rtgt_id",
	"fract_timestamp",
	"timestamp"
};

static char* attrsymtbl[9] = {
	"vertex",
	"normal",
	"color",
	"texcoord",
	"texcoord1",
	"tangent",
	"bitangent",
	"joints",
	"weights"
};

/* REFACTOR:
 * representing shader uniform tracking in this way is rather disgusting,
 * parsing the shader and allocating a tightly packed uniform list would
 * be much better. */
struct shaderv {
	GLint loc;
	char* label;
	enum shdrutype type;
	uint8_t data[64];
	struct shaderv* next;
};

/*
 * SLOTS allocation is terrible; we should replace this with a more
 * normal grow-by-n.
 */

struct shader_cont {
	uint8_t shmask;
	char* label;
	char (* vertex), (* fragment);
	GLuint prg_container, obj_vertex, obj_fragment;
	GLint locations[sizeof(ofstbl) / sizeof(ofstbl[0])];
/* match attrsymtbl */
	GLint attributes[9];

	struct arcan_strarr ugroups;
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

static struct {
	struct shader_cont slots[256];
	size_t ofs;
	agp_shader_id active_prg;
	struct shader_envts context;
	char guard;
} shdr_global = {.active_prg = BROKEN_SHADER, .guard = 64};

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
	struct agp_fenv* env = agp_env();

/* add more as needed, just match the current shader_envts */
	switch (kind){
	case shdrbool:
	case shdrint:
		env->unif_1i(loc, *(GLint*) val);
	break;

	case shdrfloat :
	env->unif_1f(loc, ((GLfloat*) val)[0]);
	break;

	case shdrvec2 :
	env->unif_2f(loc, ((GLfloat*) val)[0], ((GLfloat*) val)[1]);
	break;

	case shdrvec3 :
	env->unif_3f(loc, ((GLfloat*) val)[0], ((GLfloat*) val)[1],
	((GLfloat*) val)[2]);
	break;

	case shdrvec4  :
	env->unif_4f(loc, ((GLfloat*) val)[0], ((GLfloat*) val)[1],
	((GLfloat*) val)[2], ((GLfloat*) val)[3]);
	break;

	case shdrmat4x4:
	env->unif_m4fv(loc, 1, false, (GLfloat*) val);
	break;
	}
}

static void destroy_shader(struct shader_cont* cur)
{
	if (!cur->label)
		return;

	free( cur->label );
	free( cur->vertex );
	free( cur->fragment );

	kill_shader(&cur->prg_container, &cur->obj_vertex, &cur->obj_fragment);
	cur->prg_container = cur->obj_vertex = cur->obj_fragment;

	for (size_t j = 0; j < cur->ugroups.limit; j++){
		struct shaderv* first = cur->ugroups.cdata[j];
		while (first){
			struct shaderv* last = first;
			free(first->label);
			first = first->next;
			memset(last, 0, sizeof(struct shaderv));
			arcan_mem_free(last);
		}
	}

/* since we've manually free:ed the first member, we do not call
 * arcan_mem_freearr here as that would be a double-free, just free
 * the array */
	arcan_mem_free(cur->ugroups.data);
	memset(cur, 0, sizeof(struct shader_cont));
}

bool agp_shader_destroy(agp_shader_id shid)
{
/* don't permit removing default shaders */
	if (!agp_shader_valid(shid) ||
		shid == agp_default_shader(BASIC_2D) ||
		shid == agp_default_shader(BASIC_3D) ||
		shid == agp_default_shader(COLOR_2D))
		return false;

	struct shader_cont* cur = &shdr_global.slots[SHADER_INDEX(shid)];

/* destroy the whole shader or just a ugroup? */
	if (GROUP_INDEX(shid) == 0){
		destroy_shader(cur);
		return true;
	}

/* just ugroup, first bound-check and then step/free */
	uint16_t ind = GROUP_INDEX(shid);
	if (ind >= cur->ugroups.limit){
		printf("attempted delete of bad index: %d\n", ind);
		return false;
	}

	struct shaderv* sv = cur->ugroups.cdata[ind];
	if (!sv){
		printf("attempted destroy of empty group\n");
		return false;
	}

	cur->ugroups.count--;
	while(sv){
		struct shaderv* last = sv;
		free(sv->label);
		sv = sv->next;
		memset(last, 0, sizeof(struct shaderv));
		arcan_mem_free(last);
	}
	cur->ugroups.cdata[ind] = NULL;
	return true;
}

int agp_shader_activate(agp_shader_id shid)
{
	if (!agp_shader_valid(shid))
		return ARCAN_ERRC_NO_SUCH_OBJECT;

 	if (shid != shdr_global.active_prg){
		struct shader_cont* cur = &shdr_global.slots[SHADER_INDEX(shid)];
		if (SHADER_INDEX(shdr_global.active_prg) != SHADER_INDEX(shid))
			agp_env()->use_program(cur->prg_container);

 		shdr_global.active_prg = shid;

#ifdef SHADER_TRACE
		arcan_warning("[shader] shid(%d) => (%d), activate %s\n",
			SHADER_INDEX(shid), cur->prg_container, cur->label);
#endif

/*
 * While we chould practically just update the uniforms that has actually
 * changed since the last push as we keep a cache, the incentive is rather
 * small (uniform- set on a bound shader is among the cheaper state changes
 * possible).
 */
		for (size_t i = 0; i < sizeof(ofstbl) / sizeof(ofstbl[0]); i++){
			if (cur->locations[i] >= 0){
				setv(cur->locations[i], typetbl[i], (char*)(&shdr_global.context)
					+ ofstbl[i], symtbl[i], cur->label);
				counttbl[i]++;
			}
		}

/* activate any persistant values */
		if (cur->ugroups.limit < GROUP_INDEX(shid)){
			arcan_warning("attempt to activate shader(%d)(%d) failed: "
				"broken group\n", (int)SHADER_INDEX(shid),(int)GROUP_INDEX(shid));
			return -1;
		}
		struct shaderv* current = cur->ugroups.cdata[GROUP_INDEX(shid)];

		while (current){
			setv(current->loc, current->type, (void*) current->data,
				current->label, cur->label);
			current = current->next;
		}
	}

	return ARCAN_OK;
}

agp_shader_id agp_shader_lookup(const char* tag)
{
	for (size_t i=0; i<sizeof(shdr_global.slots)/
		sizeof(shdr_global.slots[0]); i++){
		if (shdr_global.slots[i].label &&
			strcmp(tag, shdr_global.slots[i].label) == 0)
			return i;
	}

	return BROKEN_SHADER;
}

const char* agp_shader_lookuptag(agp_shader_id id)
{
	if (!agp_shader_valid(id))
		return NULL;

	return shdr_global.slots[SHADER_INDEX(id)].label;
}

bool agp_shader_lookupprgs(agp_shader_id id,
	const char** vert, const char** frag)
{
	if (!agp_shader_valid(id))
		return false;

	if (vert)
		*vert = shdr_global.slots[SHADER_INDEX(id)].vertex;

	if (frag)
		*frag = shdr_global.slots[SHADER_INDEX(id)].fragment;

	return true;
}

bool agp_shader_valid(agp_shader_id id)
{
	return (id != BROKEN_SHADER && SHADER_INDEX(id) <
		sizeof(shdr_global.slots) / sizeof(shdr_global.slots[0]) &&
		shdr_global.slots[SHADER_INDEX(id)].label != NULL
	);
}

agp_shader_id agp_shader_build(const char* tag,
	const char* geom, const char* vert, const char* frag)
{
	int slot_lim = sizeof(shdr_global.slots) / sizeof(shdr_global.slots[0]);
	bool overwrite = false;
	int dstind = -1;
	uint8_t shmask = 0;

/* track which ones get default slots so we can know if we have a
 * 2D pipeline with on-GPU vertex displacement or not, this affects
 * damage tracking */
	if (!vert || !frag){
		const char* defvprg, (* deffprg);
		agp_shader_source(BASIC_2D, &defvprg, &deffprg);
		if (!vert){
			vert = defvprg;
			shmask |= 1;
		}
		if (!frag){
			frag = deffprg;
			shmask |= 2;
		}
	}

/* first, look for a preexisting tag */
	for (size_t i = 0; i < slot_lim; i++)
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
			for (size_t i = 0; i < slot_lim; i++)
				if (!shdr_global.slots[i].label){
					dstind = i;
					break;
				}
	}

/* still no match? means we're overallocated on shaders, bad program/script */
	if (dstind == -1)
		return BROKEN_SHADER;

	struct shader_cont* cur = &shdr_global.slots[dstind];

/* obliterate the last one first */
	if (overwrite){
		kill_shader(&cur->prg_container, &cur->obj_fragment, &cur->obj_vertex);
		free(cur->vertex);
		free(cur->fragment);
		free(cur->label);

/* drop all uniform groups */
		for (size_t i = 0; i < cur->ugroups.limit; i++){
			struct shaderv* first = cur->ugroups.cdata[i];
			while (first){
				struct shaderv* last = first;
				free(first->label);
				first = first->next;
				arcan_mem_free(last);
			}

/* reset everything to NULL */
		}
		arcan_mem_free(cur->ugroups.data);
		*cur = (struct shader_cont){};
	}

/* always reset locations tbl */
	int global_lim = sizeof(ofstbl) / sizeof(ofstbl[0]);
	for (int i = 0; i < global_lim; i++)
		cur->locations[i] = -1;

	if (build_shader(tag, &cur->prg_container, &cur->obj_vertex,
		&cur->obj_fragment, vert, frag) == false)
		return ARCAN_EID;

	cur->shmask = shmask;
	cur->label = strdup(tag);
	cur->vertex = strdup(vert);
	cur->fragment = strdup(frag);

#ifdef SHADER_DEBUG
	arcan_warning("agp_shader_build(%s) -- new ID : (%i)\n",
		tag, cur->prg_container);
#endif

/* preset global symbol mappings */
	struct agp_fenv* env = agp_env();
	env->use_program(cur->prg_container);
	for (size_t i = 0; i < global_lim; i++){
		assert(symtbl[i] != NULL);
		cur->locations[i] = env->get_uniform_loc(cur->prg_container, symtbl[i]);
#ifdef SHADER_DEBUG
		if(cur->locations[i] != -1)
			arcan_warning("agp_shader_build(%s)(%d), "
				"resolving uniform: %s to %i\n", tag, i, symtbl[i], cur->locations[i]);
#endif
	}

/* same treatment for attributes */
	for (size_t i = 0; i < sizeof(attrsymtbl) / sizeof(attrsymtbl[0]); i++){
		cur->attributes[i] = env->get_attr_loc(cur->prg_container, attrsymtbl[i]);
#ifdef SHADER_DEBUG
	if (cur->attributes[i] != -1)
		arcan_warning("agp_shader_build(%s)(%d), "
			"resolving attribute: %s to %i\n", tag,
			i, attrsymtbl[i], cur->attributes[i]
		);
#endif
	}

/* revert to last used program! */
	if (shdr_global.active_prg != BROKEN_SHADER){
		env->use_program(shdr_global.slots[
			SHADER_INDEX(shdr_global.active_prg)].prg_container);
	}

	agp_shader_addgroup(dstind);
	return (uint32_t)dstind;
}

int agp_shader_envv(enum agp_shader_envts slot, void* value, size_t size)
{
	memcpy((char*) (&shdr_global.context) + ofstbl[slot], value, size);
	int rv = counttbl[slot];
	counttbl[slot] = 0;

	if (BROKEN_SHADER == shdr_global.active_prg)
		return rv;

	int glloc = shdr_global.slots[
		SHADER_INDEX(shdr_global.active_prg)].locations[slot];

/*
 * reflect change in current active shader, the others will be changed on
 * activation
 */
	if (glloc != -1){
		assert(size == sizetbl[ typetbl[slot] ]);
		setv(glloc, typetbl[slot], value, symtbl[slot],
			shdr_global.slots[SHADER_INDEX(shdr_global.active_prg)].label );
		counttbl[slot]++;

		return rv;
	}

	return rv;
}

static int find_hole(struct shader_cont* shdr)
{
	for (size_t i = 0; i < shdr->ugroups.limit; i++)
		if (!shdr->ugroups.cdata[i])
			return i;
	return -1;
}

agp_shader_id agp_shader_addgroup(agp_shader_id shid)
{
	if (!agp_shader_valid(shid))
		return BROKEN_SHADER;

/* note: _build should've been invoked AT LEAST once before this point,
 * (considering it's part of _video_init, that isn't much of a stretch) */
	struct shader_cont* cur = &shdr_global.slots[SHADER_INDEX(shid)];

	if (cur->ugroups.count >= 65535)
		return BROKEN_SHADER;

	if (cur->ugroups.limit - cur->ugroups.count == 0)
		arcan_mem_growarr(&cur->ugroups);

/* note: normal allocation pattern is typically build_shader, allocate
 * a group of uniforms and then very rarely delete or grow without a
 * full reset. So we do a costly linear search if only the 'guessed'
 * slot has left us with holes */
	int dsti = -1;
	if (!cur->ugroups.cdata[cur->ugroups.count])
		dsti = cur->ugroups.count;
	else
		dsti = find_hole(cur);

/* shouldn't happen, count will hit 65535 and stay there */
	if (-1 == dsti){
		return BROKEN_SHADER;
	}

	cur->ugroups.count++;

	struct shaderv** chain = (struct shaderv**) &cur->ugroups.cdata[dsti];
	struct shaderv* mgroup = cur->ugroups.cdata[GROUP_INDEX(shid)];

	while(mgroup){
		*chain = arcan_alloc_mem(sizeof(struct shaderv),
			ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
		memcpy(*chain, mgroup, sizeof(struct shaderv));
		(*chain)->label = strdup(mgroup->label);
		(*chain)->next = NULL;
		chain = &((*chain)->next);
		mgroup = mgroup->next;
	}

	return SHADER_ID(SHADER_INDEX(shid), dsti);
}

int agp_shader_vattribute_loc(enum shader_vertex_attributes attr)
{
	return shdr_global.slots[
		SHADER_INDEX(shdr_global.active_prg)].attributes[ attr ];
}

void agp_shader_forceunif(const char* label, enum shdrutype type, void* value)
{
	GLint loc;
	assert(shdr_global.active_prg != BROKEN_SHADER);
	struct shader_cont* slot = &shdr_global.slots[
		SHADER_INDEX(shdr_global.active_prg)];

/* linear search */
	struct shaderv** current = (struct shaderv**) &(
		slot->ugroups.cdata[GROUP_INDEX(shdr_global.active_prg)]);
	for (; *current; current = &(*current)->next)
		if (strcmp((*current)->label, label) == 0)
			break;

/* found? then continue, else allocate new and return that loc */
	if (*current){
		loc = (*current)->loc;
		if ((*current)->type != type)
			arcan_warning("agp_shader_forceunif(), type mismatch for "
				"persistant shader uniform (%s:%i=>%i), ignored.\n", label, loc, type);
	}
	else {
		loc = agp_env()->get_uniform_loc(slot->prg_container, label);
		*current = arcan_alloc_mem(sizeof(struct shaderv),
			ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
		(*current)->label = strdup(label);
		(*current)->loc   = loc;
		(*current)->type  = type;
		(*current)->next  = NULL;
	}
	memcpy((*current)->data, value, sizetbl[type]);

	if (loc >= 0){
		setv(loc, type, value, label, slot->label);
	}
#ifdef DEBUG
	else
		arcan_warning("agp_shader_forceunif(): no matching location"
			" found for %s in shader: %s\n", label,
			shdr_global.slots[SHADER_INDEX(shdr_global.active_prg)].label
		);
#endif
}

static void kill_shader(GLuint* dprg, GLuint* vprg, GLuint* fprg){
	struct agp_fenv* env = agp_env();
	if (*dprg)
		env->delete_program(*dprg);

	if (*vprg)
		env->delete_shader(*vprg);

	if (*fprg)
		env->delete_shader(*fprg);

	*dprg = *vprg = *fprg = 0;
}

static bool build_shunit(GLint stage, const char* prg, GLuint* dprg)
{
	struct agp_fenv* env = agp_env();

	TRACE_MARK_ENTER("agp", "shader-compiler", TRACE_SYS_DEFAULT, 0, 0, prg);
		*dprg = env->create_shader(stage);
		env->shader_source(*dprg, 1, &prg, NULL);
		env->compile_shader(*dprg);
		GLint status = 0;
		env->get_shader_iv(*dprg, GL_COMPILE_STATUS, &status);
	TRACE_MARK_EXIT("agp", "shader-compiler", TRACE_SYS_DEFAULT, 0, 0, prg);

	return status != GL_FALSE;
}

/*
 * this does not mesh well with crash dumps or system snapshots,
 *
 * perhaps a better way is to actually create a 'dumb' shader in the slot
 * and provide a way to on-demand retrieve message and source then do so
 * in the normal system_snapshot call
 */
static void dump_shaderlog(const char* label,
	const char* stage, const char* src, GLuint prg)
{
	char buf[1024];
	char* msgbuf;

	int rlen = -1;
	agp_env()->shader_log(prg, 1024, &rlen, buf);

/* combine source and reason as the source might be preprocessed etc. from the
 * offline store, making it difficult to match line-number and offset -
 *
 * while there is no standard for the contents of the compilation error,
 * looking at mesa + nvidia and a misc fallback would probably be enough to be
 * able to highlight the specific line and offset, but leave it to some
 * external tool */
	if (rlen > 0 && (msgbuf = malloc(64 * 1024))){
		snprintf(msgbuf, 64*1024, "Stage:%s\nError:%s\n:Source:%s\n", stage, buf, src);
		TRACE_MARK_ONESHOT("agp", "shader-compiler", TRACE_SYS_ERROR, 0, 0, buf);
		arcan_warning(msgbuf);
		free(msgbuf);
		return;
	}

	TRACE_MARK_ONESHOT("agp", "shader-compiler", TRACE_SYS_ERROR, 0, 0, label);
	arcan_warning("%s shader failed on %s stage:\n", label, stage);
}

static bool build_shader(const char* label, GLuint* dprg,
	GLuint* vprg, GLuint* fprg, const char* vprogram, const char* fprogram)
{
	struct agp_fenv* env = agp_env();
	bool failed = false;

#ifdef DEBUG
	bool force = true;
#else
	bool force = false;
#endif

	if (( failed = !build_shunit(GL_VERTEX_SHADER, vprogram, vprg)) || force)
		dump_shaderlog(label, "vertex", vprogram, *vprg);

	if (( failed |= !build_shunit(GL_FRAGMENT_SHADER, fprogram, fprg)) || force)
		dump_shaderlog(label, "fragment", fprogram, *fprg);

/*
 * driver issues make this validation step rather uncertain, another option
 * would be to use a reference shader that should compile, resolve attributes
 * and uniforms and if they map to the same location, we know something is
 * broken and that it's not our fault.
 */
	*dprg = env->create_program();
	env->attach_shader(*dprg, *fprg);
	env->attach_shader(*dprg, *vprg);
	env->link_program(*dprg);

	int lstat = 0;
	env->get_program_iv(*dprg, GL_LINK_STATUS, &lstat);

	if (GL_FALSE == lstat){
		failed = true;
		dump_shaderlog(label, "link-vertex", vprogram, *dprg);
		dump_shaderlog(label, "link-fragment", fprogram, *dprg);
	}
	else {
		env->use_program(*dprg);
		int loc = env->get_uniform_loc(*dprg, "map_tu0");
		GLint val = 0;

		if (loc >= 0)
			env->unif_1i(loc, val);

		loc = env->get_uniform_loc(*dprg, "map_diffuse");
		if (loc >= 0)
			env->unif_1i(loc, val);
	}

	return !failed;
}

const char* agp_shader_symtype(enum agp_shader_envts env)
{
	return symtbl[env];
}

void agp_shader_flush()
{
	for (size_t i = 0; i < sizeof(shdr_global.slots)
		/ sizeof(shdr_global.slots[0]); i++){
		destroy_shader(&shdr_global.slots[i]);
	}

	shdr_global.ofs = 0;
	shdr_global.active_prg = BROKEN_SHADER;
}

void agp_shader_rebuild_all()
{
	for (size_t i = 0; i < sizeof(shdr_global.slots) /
			sizeof(shdr_global.slots[0]); i++){
		struct shader_cont* cur = shdr_global.slots + i;
		if (cur->label == NULL)
			continue;

		build_shader(cur->label,
			&cur->prg_container,
			&cur->obj_vertex,
			&cur->obj_fragment,
			cur->vertex,
			cur->fragment
		);
	}
}
