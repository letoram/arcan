 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdbool.h>
#include <assert.h>

#include "../platform_types.h"
#include "../video_platform.h"
#include "../platform.h"

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_video.h"
#include "arcan_videoint.h"

agp_shader_id agp_default_shader(enum SHADER_TYPES type)
{
	return 1;
}

const char* agp_ident()
{
	return "STUB";
}

const char* agp_shader_language()
{
	return "STUB";
}

int agp_shader_envv(enum agp_shader_envts slot, void* value, size_t size)
{
	return 1;
}

agp_shader_id arcan_shader_lookup(const char* tag)
{
	return 1;
}

void agp_shader_source(enum SHADER_TYPES type,
	const char** vert, const char** frag)
{
	*vert = "";
	*frag = "";
}

const char** agp_envopts()
{
	static const char* env[] = {NULL};
	return env;
}

void agp_readback_synchronous(struct agp_vstore* dst)
{
}

void agp_drop_vstore(struct agp_vstore* s)
{
}

struct stream_meta agp_stream_prepare(struct agp_vstore* s,
	struct stream_meta meta, enum stream_type type)
{
	struct stream_meta mout = {0};
	return mout;
}

void agp_stream_release(struct agp_vstore* s, struct stream_meta meta)
{
}

void agp_stream_commit(struct agp_vstore* s, struct stream_meta meta)
{
}

void agp_resize_vstore(struct agp_vstore* s, size_t w, size_t h)
{
}

void agp_request_readback(struct agp_vstore* s)
{
}

struct asynch_readback_meta agp_poll_readback(struct agp_vstore* t)
{
	struct asynch_readback_meta res = {0};
	return res;
}

void agp_empty_vstore(struct agp_vstore* vs, size_t w, size_t h)
{
}

struct agp_rendertarget* agp_setup_rendertarget(
	struct agp_vstore* vstore, enum rendertarget_mode m)
{
	return NULL;
}

void agp_init()
{
}

void agp_drop_rendertarget(struct agp_rendertarget* tgt)
{
}

void agp_activate_rendertarget(struct agp_rendertarget* tgt)
{
}

void agp_rendertarget_viewport(struct agp_rendertarget* tgt,
	ssize_t x1, ssize_t y1, ssize_t x2, ssize_t y2)
{
}

void agp_rendertarget_clear()
{
}

void agp_pipeline_hint(enum pipeline_mode mode)
{
}

void agp_null_vstore(struct agp_vstore* store)
{
}

void agp_resize_rendertarget(
	struct agp_rendertarget* tgt, size_t neww, size_t newh)
{
}

void agp_activate_vstore_multi(struct agp_vstore** backing, size_t n)
{
}

void agp_update_vstore(struct agp_vstore* s, bool copy)
{
	FLAG_DIRTY();
}

void agp_prepare_stencil()
{
}

void agp_activate_stencil()
{
}

void agp_disable_stencil()
{
}

void agp_blendstate(enum arcan_blendfunc mdoe)
{
}

void agp_draw_vobj(
	float x1, float y1, float x2, float y2, const float* txcos, const float* m)
{
}

void agp_submit_mesh(struct agp_mesh_store* base, enum agp_mesh_flags fl)
{
}

void agp_invalidate_mesh(struct agp_mesh_store* base)
{
}

void agp_activate_vstore(struct agp_vstore* s)
{
}

void agp_deactivate_vstore()
{
}

void agp_save_output(size_t w, size_t h, av_pixel* dst, size_t dsz)
{
}

int agp_shader_activate(agp_shader_id shid)
{
	return shid == 1;
}

const char* agp_shader_lookuptag(agp_shader_id id)
{
	if (id != 1)
		return NULL;

	return "tag";
}

bool agp_shader_lookupprgs(agp_shader_id id,
	const char** vert, const char** frag)
{
	if (id != 1)
		return false;

	*vert = "";
	*frag = "";

	return true;
}

bool agp_shader_valid(agp_shader_id id)
{
	return 1 == id;
}

agp_shader_id arcan_shader_build(const char* tag, const char* geom,
	const char* vert, const char* frag)
{
	return (vert && frag && tag && geom) ? 1 : 0;
}

void agp_shader_forceunif(const char* label, enum shdrutype type, void* val)
{
}

agp_shader_id agp_shader_lookup(const char* tag)
{
	return BROKEN_SHADER;
}

agp_shader_id agp_shader_build(const char* tag,
	const char* geom, const char* vert, const char* frag)
{
	return BROKEN_SHADER;
}

bool agp_shader_destroy(agp_shader_id shid)
{
	return false;
}

agp_shader_id agp_shader_addgroup(agp_shader_id shid)
{
	return BROKEN_SHADER;
}

void agp_empty_vstoreext(struct agp_vstore* vs,
	size_t w, size_t h, enum vstore_hint hint)
{
}

void agp_rendertarget_proxy(struct agp_rendertarget* tgt,
	bool (*proxy_state)(struct agp_rendertarget*, uintptr_t tag), uintptr_t tag)
{
}

void agp_drop_mesh(struct agp_mesh_store* s)
{
}

bool agp_slice_vstore(struct agp_vstore* backing,
	size_t n_slices, size_t base, enum txstate txstate)
{
	return false;
}

bool agp_slice_synch(
	struct agp_vstore* backing, size_t n_slices, struct agp_vstore** slices)
{
	return false;
}

void agp_glinit_fenv(struct agp_fenv* dst,
	void*(*lookup)(void* tag, const char* sym, bool req), void* tag)
{

}

void agp_setenv(struct agp_fenv* dst)
{
}

#define TBLSIZE (1 + TIMESTAMP_D - MODELVIEW_MATR)
static char* symtbl[TBLSIZE] = {
	"modelview",
	"projection",
	"texturem",
	"obj_opacity",
	"trans_move",
	"trans_scale",
	"trans_rotate",
	"obj_input_sz",
	"obj_output_sz",
	"obj_storage_sz",
	"fract_timestamp",
	"timestamp"
};

const char* agp_shader_symtype(enum agp_shader_envts env)
{
	return symtbl[env];
}

void agp_shader_flush()
{
}

void agp_shader_rebuild_all()
{
}

void agp_rendertarget_clearcolor(
	struct agp_rendertarget* tgt, float r, float g, float b, float a)
{
}

bool agp_status_ok(const char** msg)
{
	return true;
}

void agp_render_options(struct agp_render_options opts)
{
}

bool agp_accelerated()
{
	return false;
}

