/*
 * Copyright: Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include "arcan_hmeta.h"
#include "arcan_ttf.h"

#define CLAMP(x, l, h) (((x) > (h)) ? (h) : (((x) < (l)) ? (l) : (x)))

#ifndef ASYNCH_CONCURRENT_THREADS
#define ASYNCH_CONCURRENT_THREADS 12
#endif

#ifndef offsetof
#define offsetof(type, member) ((size_t)((char*)&(*(type*)0).member\
 - (char*)&(*(type*)0)))
#endif

#ifndef ARCAN_VIDEO_DEFAULT_MIPMAP_STATE
#define ARCAN_VIDEO_DEFAULT_MIPMAP_STATE false
#endif

static surface_properties empty_surface();
static sem_handle asynchsynch;

/* these match arcan_vinterpolant enum */
static arcan_interp_3d_function lut_interp_3d[] = {
	interp_3d_linear,
	interp_3d_sine,
	interp_3d_expin,
	interp_3d_expout,
	interp_3d_expinout,
	interp_3d_smoothstep,
};

static arcan_interp_1d_function lut_interp_1d[] = {
	interp_1d_linear,
	interp_1d_sine,
	interp_1d_expin,
	interp_1d_expout,
	interp_1d_expinout,
	interp_1d_smoothstep
};

struct arcan_video_display arcan_video_display = {
	.conservative = false,
	.deftxs = ARCAN_VTEX_CLAMP, ARCAN_VTEX_CLAMP,
	.scalemode = ARCAN_VIMAGE_NOPOW2,
	.filtermode = ARCAN_VFILTER_BILINEAR,
	.blendmode = BLEND_FORCE,
	.order3d = ORDER3D_FIRST,
	.suspended = false,
	.msasamples = 4,
	.c_ticks = 1,
	.default_vitemlim = 1024,
	.imageproc = IMAGEPROC_NORMAL,
	.mipmap = ARCAN_VIDEO_DEFAULT_MIPMAP_STATE,
	.dirty = 0,
	.cursor.w = 24,
	.cursor.h = 16
};

struct arcan_video_context vcontext_stack[CONTEXT_STACK_LIMIT] = {
	{
		.n_rtargets = 0,
		.vitem_ofs = 1,
		.nalive    = 0,
		.world = {
			.tracetag = "(world)",
			.current  = {
				.opa = 1.0,
				.rotation.quaternion.w = 1.0
			}
		}
	}
};

unsigned vcontext_ind = 0;

/*
 * additional internal forwards that do not really belong to videoint.h
 */
static bool detach_fromtarget(struct rendertarget* dst, arcan_vobject* src);
static void attach_object(struct rendertarget* dst, arcan_vobject* src);
static arcan_errc update_zv(arcan_vobject* vobj, int newzv);
static void rebase_transform(struct surface_transform*, int64_t);
static size_t process_rendertarget(struct rendertarget*, float, bool nest);
static arcan_vobject* new_vobject(arcan_vobj_id* id,
struct arcan_video_context* dctx);
static inline void build_modelview(float* dmatr,
	float* imatr, surface_properties* prop, arcan_vobject* src);
static inline void process_readback(struct rendertarget* tgt, float fract);

static inline void trace(const char* msg, ...)
{
#ifdef TRACE_ENABLE
	va_list args;
	va_start( args, msg );
		vfprintf(stderr,  msg, args );
	va_end( args);
#endif
}

static const char* video_tracetag(arcan_vobject* src)
{
	return src == NULL || src->tracetag == NULL ? "(unknown)" : src->tracetag;
}

/* a default more-or-less empty context */
static struct arcan_video_context* current_context = vcontext_stack;

void arcan_vint_drop_vstore(struct agp_vstore* s)
{
	assert(s->refcount);
	s->refcount--;

	if (s->refcount == 0){
		if (s->txmapped != TXSTATE_OFF && s->vinf.text.glid){
			if (s->vinf.text.raw){
				arcan_mem_free(s->vinf.text.raw);
				s->vinf.text.raw = NULL;
			}

/* vstore doesn't track font group so do that manually */
			if (s->vinf.text.tpack.group){
				arcan_renderfun_release_fontgroup(s->vinf.text.tpack.group);
			}

			agp_drop_vstore(s);

			if (s->vinf.text.source)
				arcan_mem_free(s->vinf.text.source);

			memset(s, '\0', sizeof(struct agp_vstore));
		}

		arcan_mem_free(s);
	}
}

void arcan_video_default_texfilter(enum arcan_vfilter_mode mode)
{
	arcan_video_display.filtermode = mode;
}

void arcan_video_default_imageprocmode(enum arcan_imageproc_mode mode)
{
	arcan_video_display.imageproc = mode;
}

struct rendertarget* arcan_vint_findrt_vstore(struct agp_vstore* st)
{
	if (!st)
		return NULL;

	for (size_t i = 0; i < current_context->n_rtargets && st; i++)
		if (current_context->rtargets[i].color->vstore == st)
			return &current_context->rtargets[i];

	if (current_context->stdoutp.color &&
		st == current_context->stdoutp.color->vstore)
		return &current_context->stdoutp;
	return NULL;
}

struct rendertarget* arcan_vint_findrt(arcan_vobject* vobj)
{
	for (size_t i = 0; i < current_context->n_rtargets && vobj; i++)
		if (current_context->rtargets[i].color == vobj)
			return &current_context->rtargets[i];

	if (vobj == &current_context->world)
		return &current_context->stdoutp;

	return NULL;
}

static void addchild(arcan_vobject* parent, arcan_vobject* child)
{
	arcan_vobject** slot = NULL;
	for (size_t i = 0; i < parent->childslots; i++){
		if (parent->children[i] == NULL){
			slot = &parent->children[i];
			break;
		}
	}

/* grow and set element */
	if (!slot){
		arcan_vobject** news = arcan_alloc_mem(
			(parent->childslots + 8) * sizeof(void*),
			ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_NATURAL
		);

		if (parent->children){
			memcpy(news, parent->children, parent->childslots * sizeof(void*));
			arcan_mem_free(parent->children);
		}

		parent->children = news;
		for (size_t i = 0; i < 8; i++)
			parent->children[parent->childslots + i] = NULL;

		slot = &parent->children[parent->childslots];
		parent->childslots += 8;
	}

	parent->extrefc.links++;

	child->parent = parent;
	*slot = child;
}

/*
 * recursively sweep children and
 * flag their caches for updates as well
 */
static void invalidate_cache(arcan_vobject* vobj)
{
	FLAG_DIRTY(vobj);

	if (!vobj->valid_cache)
		return;

	vobj->valid_cache = false;

	for (size_t i = 0; i < vobj->childslots; i++)
		if (vobj->children[i])
			invalidate_cache(vobj->children[i]);
}

static void dropchild(arcan_vobject* parent, arcan_vobject* child)
{
	for (size_t i = 0; i < parent->childslots; i++){
		if (parent->children[i] == child){
			parent->children[i] = NULL;
			parent->extrefc.links--;
			child->parent = &current_context->world;
			break;
		}
	}
}

/* scan through each cell in use, and either deallocate / wrap with deleteobject
 * or pause frameserver connections and (conservative) delete resources that can
 * be recreated later on. */
static void deallocate_gl_context(
	struct arcan_video_context* context, bool del, struct agp_vstore* safe_store)
{
/* index (0) is always worldid */
	for (size_t i = 1; i < context->vitem_limit; i++){
		if (FL_TEST(&(context->vitems_pool[i]), FL_INUSE)){
			arcan_vobject* current = &(context->vitems_pool[i]);

/* before doing any modification, wait for any async load calls to finish(!),
 * question is IF this should invalidate or not */
			if (current->feed.state.tag == ARCAN_TAG_ASYNCIMGLD ||
				current->feed.state.tag == ARCAN_TAG_ASYNCIMGRD)
				arcan_video_pushasynch(i);

/* for persistant objects, deleteobject will only be "effective" if we're at
 * the stack layer where the object was created */
			if (del)
				arcan_video_deleteobject(i);

/* only non-persistant objects will have their GL objects removed immediately
 * but not for the cases where we share store with the world */
			else if (
				!FL_TEST(current, FL_PRSIST) && !FL_TEST(current, FL_RTGT) &&
				current->vstore != safe_store)
				agp_null_vstore(current->vstore);
		}
	}

/* pool is dynamically sized and size is set on layer push */
	if (del){
		arcan_mem_free(context->vitems_pool);
		context->vitems_pool = NULL;
	}
}

static inline void step_active_frame(arcan_vobject* vobj)
{
	if (!vobj->frameset)
		return;

	size_t sz = vobj->frameset->n_frames;

	vobj->frameset->index = (vobj->frameset->index + 1) % sz;
	if (vobj->owner)
		vobj->owner->transfc++;

	FLAG_DIRTY(vobj);
}

/*
 * Iterate a saved context, and reallocate all resources associated with it.
 * Note that this doesn't really consider other forms of gl storage at the
 * moment, particularly rendertargets(!)
 *
 */
static void reallocate_gl_context(struct arcan_video_context* context)
{
	arcan_tickv cticks = arcan_video_display.c_ticks;

/* If there's nothing saved, we reallocate */
	if (!context->vitems_pool){
		context->vitem_limit = arcan_video_display.default_vitemlim;
		context->vitem_ofs   = 1;
		context->vitems_pool = arcan_alloc_mem(
			sizeof(struct arcan_vobject) * context->vitem_limit,
				ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
	}
	else for (size_t i = 1; i < context->vitem_limit; i++)
		if (FL_TEST(&(context->vitems_pool[i]), FL_INUSE)){
			arcan_vobject* current = &context->vitems_pool[i];
			surface_transform* ctrans = current->transform;

			if (FL_TEST(current, FL_PRSIST))
				continue;

/* since there may be queued transforms in an already pushed context,
 * we maintain the timing and reset them to match the changes that
 * has already occurred */
			if (ctrans && cticks > context->last_tickstamp){
				rebase_transform(ctrans, cticks - context->last_tickstamp);
			}

/* for conservative memory management mode we need to reallocate
 * static resources. getimage will strdup the source so to avoid leaking,
 * copy and free */
			if (arcan_video_display.conservative &&
				(char)current->feed.state.tag == ARCAN_TAG_IMAGE){
					char* fname = strdup( current->vstore->vinf.text.source );
					arcan_mem_free(current->vstore->vinf.text.source);
				arcan_vint_getimage(fname,
					current, (img_cons){.w = current->origw, .h = current->origh}, false);
				arcan_mem_free(fname);
			}
			else
				if (current->vstore->txmapped != TXSTATE_OFF)
					agp_update_vstore(current->vstore, true);

			arcan_frameserver* fsrv = current->feed.state.ptr;
			if (current->feed.state.tag == ARCAN_TAG_FRAMESERV && fsrv){
				arcan_frameserver_flush(fsrv);
				arcan_frameserver_resume(fsrv);
				arcan_audio_play(fsrv->aid, false, 0.0, -2); /* -2 == LUA_NOREF */
			}
		}
}

unsigned arcan_video_nfreecontexts()
{
		return CONTEXT_STACK_LIMIT - 1 - vcontext_ind;
}

static void rebase_transform(struct surface_transform* current, int64_t ofs)
{
	if (current->move.startt){
		current->move.startt += ofs;
		current->move.endt   += ofs;
	}

	if (current->rotate.startt){
		current->rotate.startt += ofs;
		current->rotate.endt   += ofs;
	}

	if (current->scale.startt){
		current->scale.startt += ofs;
		current->scale.endt   += ofs;
	}

	if (current->next)
		rebase_transform(current->next, ofs);
}

static void push_transfer_persists(
	struct arcan_video_context* src,
	struct arcan_video_context* dst)
{
	for (size_t i = 1; i < src->vitem_limit - 1; i++){
		arcan_vobject* srcobj = &src->vitems_pool[i];
		arcan_vobject* dstobj = &dst->vitems_pool[i];

		if (!FL_TEST(srcobj, FL_INUSE) || !FL_TEST(srcobj, FL_PRSIST))
			continue;

		detach_fromtarget(srcobj->owner, srcobj);
		memcpy(dstobj, srcobj, sizeof(arcan_vobject));
		dst->nalive++; /* fake allocate */
		dstobj->parent = &dst->world; /* don't cross- reference worlds */
		attach_object(&dst->stdoutp, dstobj);
		trace("vcontext_stack_push() : transfer-attach: %s\n", srcobj->tracetag);
	}
}

/*
 * if an object exists in src, is flagged persist,
 * and a similar (shadow) object is flagged persist in dst,
 * update the state in dst with src and detach/remove from src.
 */
static void pop_transfer_persists(
	struct arcan_video_context* src,
	struct arcan_video_context* dst)
{
	for (size_t i = 1; i < src->vitem_limit - 1; i++){
		arcan_vobject* srcobj = &src->vitems_pool[i];
		arcan_vobject* dstobj = &dst->vitems_pool[i];

		if (!FL_TEST(srcobj, FL_INUSE) || !FL_TEST(srcobj, FL_PRSIST))
			continue;

		arcan_vobject* parent = dstobj->parent;

		detach_fromtarget(srcobj->owner, srcobj);
		src->nalive--;

		memcpy(dstobj, srcobj, sizeof(arcan_vobject));
		attach_object(&dst->stdoutp, dstobj);
		dstobj->parent = parent;
		memset(srcobj, '\0', sizeof(arcan_vobject));
	}
}

void arcan_vint_drawrt(struct agp_vstore* vs, int x, int y, int w, int h)
{
	_Alignas(16) float imatr[16];
	identity_matrix(imatr);
	agp_shader_activate(agp_default_shader(BASIC_2D));
	if (!vs)
		return;

	agp_activate_vstore(vs);
	agp_shader_envv(MODELVIEW_MATR, imatr, sizeof(float)*16);
	agp_shader_envv(PROJECTION_MATR,
		arcan_video_display.window_projection, sizeof(float)*16);

	agp_blendstate(BLEND_NONE);
	agp_draw_vobj(0, 0, x + w, y + h,
		arcan_video_display.mirror_txcos, NULL);

	agp_deactivate_vstore();
}

void arcan_vint_applyhint(arcan_vobject* src, enum blitting_hint hint,
	float* txin, float* txout,
	size_t* outx, size_t* outy,
	size_t* outw, size_t* outh, size_t* blackframes)
{
	memcpy(txout, txin, sizeof(float) * 8);

	if (hint & HINT_ROTATE_CW_90){
		txout[0] = txin[2];
		txout[1] = txin[3];
		txout[2] = txin[4];
		txout[3] = txin[5];
		txout[4] = txin[6];
		txout[5] = txin[7];
		txout[6] = txin[0];
		txout[7] = txin[1];
	}
	else if (hint & HINT_ROTATE_CCW_90){
		txout[0] = txin[6];
		txout[1] = txin[7];
		txout[2] = txin[0];
		txout[3] = txin[1];
		txout[4] = txin[2];
		txout[5] = txin[3];
		txout[6] = txin[4];
		txout[7] = txin[5];
	}
	else if (hint & HINT_ROTATE_180){
		txout[0] = txin[4];
		txout[1] = txin[5];
		txout[2] = txin[6];
		txout[3] = txin[7];
		txout[4] = txin[0];
		txout[5] = txin[1];
		txout[6] = txin[2];
		txout[7] = txin[3];
	}

	if (hint & HINT_YFLIP){
		float flipb[8];
		memcpy(flipb, txout, sizeof(float) * 8);
		txout[0] = flipb[6];
		txout[1] = flipb[7];
		txout[2] = flipb[4];
		txout[3] = flipb[5];
		txout[4] = flipb[2];
		txout[5] = flipb[3];
		txout[6] = flipb[0];
		txout[7] = flipb[1];
	}

	if (hint & HINT_CROP){
		ssize_t diffw = *outw - src->vstore->w;
		ssize_t diffh = *outh - src->vstore->h;
		if (diffw < 0){
			*outx = -1 * diffw;
		}
		else{
			*outw = src->vstore->w;
			*outx = diffw >> 1;
		}

		if (diffh < 0){
			*outy = -1 * diffh;
		}
		else{
			*outh = src->vstore->h;
			*outy = diffh >> 1;
		}
	}
	else {
		*outx = *outy = 0;
	}

	*blackframes = 3;
}

void arcan_vint_drawcursor(bool erase)
{
	if (!arcan_video_display.cursor.vstore)
		return;

	float txmatr[8];
	float* txcos = arcan_video_display.cursor_txcos;

/*
 * flip internal cursor position to last drawn cursor position
 */
	if (!erase){
		arcan_video_display.cursor.ox = arcan_video_display.cursor.x;
		arcan_video_display.cursor.oy = arcan_video_display.cursor.y;
	}

	int x1 = arcan_video_display.cursor.ox;
	int y1 = arcan_video_display.cursor.oy;
	int x2 = x1 + arcan_video_display.cursor.w;
	int y2 = y1 + arcan_video_display.cursor.h;
	struct monitor_mode mode = platform_video_dimensions();

	if (erase){
		float s1 = (float)x1 / mode.width;
		float s2 = (float)x2 / mode.width;
		float t1 = 1.0 - ((float)y1 / mode.height);
		float t2 = 1.0 - ((float)y2 / mode.height);

		txmatr[0] = s1;
		txmatr[1] = t1;
		txmatr[2] = s2;
		txmatr[3] = t1;
		txmatr[4] = s2;
		txmatr[5] = t2;
		txmatr[6] = s1;
		txmatr[7] = t2;

		txcos = txmatr;

		agp_blendstate(BLEND_NONE);
		agp_activate_vstore(current_context->world.vstore);
	}
	else{
		agp_blendstate(BLEND_FORCE);
		agp_activate_vstore(arcan_video_display.cursor.vstore);
	}

	float opa = 1.0;
	agp_shader_activate(agp_default_shader(BASIC_2D));
	agp_shader_envv(OBJ_OPACITY, &opa, sizeof(float));
	agp_draw_vobj(x1, y1, x2, y2, txcos, NULL);

	agp_deactivate_vstore();
}

signed arcan_video_pushcontext()
{
	arcan_vobject empty_vobj = {
		.current = {
			.position = {0},
			.opa = 1.0,
			.scale = {.x = 1.0, .y = 1.0, .z = 1.0},
			.rotation.quaternion = default_quat
		},
/* we transfer the vstore over as that will be used as a
 * container for the main display FBO */
		.vstore = current_context->world.vstore
	};

	if (vcontext_ind + 1 == CONTEXT_STACK_LIMIT)
		return -1;

	current_context->last_tickstamp = arcan_video_display.c_ticks;

/* copy everything then manually reset some fields to defaults */
	memcpy(&vcontext_stack[ ++vcontext_ind ], current_context,
		sizeof(struct arcan_video_context));
	deallocate_gl_context(current_context, false, empty_vobj.vstore);
	if (current_context->world.vstore){
		empty_vobj.origw = empty_vobj.vstore->w;
		empty_vobj.origh = empty_vobj.vstore->h;
	}

	current_context = &vcontext_stack[ vcontext_ind ];
	current_context->stdoutp.first = NULL;
	current_context->vitem_ofs = 1;
	current_context->nalive = 0;

	current_context->world = empty_vobj;
	current_context->stdoutp.refreshcnt = 1;
	current_context->stdoutp.refresh = 1;
	current_context->stdoutp.vppcm = current_context->stdoutp.hppcm = 28;
	current_context->stdoutp.color = &current_context->world;
	current_context->stdoutp.max_order = 65536;
	current_context->vitem_limit = arcan_video_display.default_vitemlim;
	current_context->vitems_pool = arcan_alloc_mem(
		sizeof(struct arcan_vobject) * current_context->vitem_limit,
		ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL
	);

	current_context->rtargets[0].first = NULL;

/* propagate persistent flagged objects upwards */
	push_transfer_persists(
		&vcontext_stack[ vcontext_ind - 1], current_context);
	FLAG_DIRTY(NULL);

	return arcan_video_nfreecontexts();
}

void arcan_video_recoverexternal(bool pop, int* saved,
	int* truncated, recovery_adoptfun adopt, void* tag)
{
	unsigned lastctxa, lastctxc;
	size_t n_ext = 0;

	*saved = 0;
	*truncated = 0;

/* pass, count contexts and disable rendertarget proxies */
	for (size_t i = 0; i <= vcontext_ind; i++){
		struct arcan_video_context* ctx = &vcontext_stack[i];

		for (size_t j = 1; j < ctx->vitem_limit; j++){
			if (FL_TEST(&(ctx->vitems_pool[j]), FL_INUSE)){
				if (ctx->vitems_pool[j].feed.state.tag == ARCAN_TAG_FRAMESERV)
					n_ext++;
			}
		}

		for (size_t j = 0; j < ctx->n_rtargets; j++){
			agp_rendertarget_proxy(ctx->rtargets[j].art, NULL, 0);
		}
	}

	struct {
		struct agp_vstore* gl_store;
		char* tracetag;
		ffunc_ind ffunc;
		vfunc_state state;
		int origw, origh;
		int zv;
	} alim[n_ext+1];

	arcan_aobj_id audbuf[n_ext+1];

	if (n_ext == 0)
		goto clense;

/* clamp number of salvaged objects, save space for WORLDID
 * and if necessary, increase the size for new contexts */
	if (n_ext >= VITEM_CONTEXT_LIMIT - 1)
		n_ext = VITEM_CONTEXT_LIMIT - 1;

	if (n_ext > arcan_video_display.default_vitemlim)
		arcan_video_display.default_vitemlim = n_ext + 1;

/* pass 2, salvage remains */
	int s_ofs = 0;

	for (size_t i = 0; i <= vcontext_ind; i++){
		struct arcan_video_context* ctx = &vcontext_stack[i];

/* only care about frameservers */
		for (size_t j = 1; j < ctx->vitem_limit; j++){
			if (!FL_TEST(&ctx->vitems_pool[j], FL_INUSE) ||
				ctx->vitems_pool[j].feed.state.tag != ARCAN_TAG_FRAMESERV)
				continue;

			arcan_vobject* cobj = &ctx->vitems_pool[j];

/* some feedfunctions are dangerous to try and save */
			if (cobj->feed.ffunc == FFUNC_SOCKVER ||
				cobj->feed.ffunc == FFUNC_SOCKPOLL)
				continue;

			arcan_frameserver* fsrv = cobj->feed.state.ptr;

/* and some might want to opt-out of the whole thing */
			if (fsrv->flags.no_adopt)
				continue;

/* only liberate if we have enough space left */
			if (s_ofs < n_ext){
				alim[s_ofs].state = cobj->feed.state;
				alim[s_ofs].ffunc = cobj->feed.ffunc;
				alim[s_ofs].gl_store = cobj->vstore;
				alim[s_ofs].origw = cobj->origw;
				alim[s_ofs].origh = cobj->origh;
				alim[s_ofs].zv = i + 1;
				alim[s_ofs].tracetag = cobj->tracetag ? strdup(cobj->tracetag) : NULL;

				audbuf[s_ofs] = fsrv->aid;

/* disassociate with cobj (when killed in pop, free wont be called),
 * and increase refcount on storage (won't be killed in pop) */
				cobj->vstore->refcount++;
				cobj->feed.state.tag = ARCAN_TAG_NONE;
				cobj->feed.ffunc = FFUNC_FATAL;
				cobj->feed.state.ptr = NULL;

				s_ofs++;
			}
			else
				(*truncated)++;
		}
	}

/* pop them all, will also create a new fresh
 * context with at least enough space */
clense:
	if (pop){
		lastctxc = arcan_video_popcontext();

		while ( lastctxc != (lastctxa = arcan_video_popcontext()))
			lastctxc = lastctxa;
	}

	if (n_ext == 0)
		return;

/* pass 3, setup new world. a big note here: since we adopt and get a new
 * cellid, internally tracked relations (subsegments tracking parents for
 * instance) will point to an old and broken ID or, even worse, frameservers in
 * different context levels being merged down and subsegments now referring to
 * the wrong parent. This need to be fixed by the FFUNC_ADOPT */
	for (size_t i = 0; i < s_ofs; i++){
		arcan_vobj_id did;
		arcan_vobject* vobj = new_vobject(&did, current_context);
		vobj->vstore = alim[i].gl_store;
		vobj->feed.state = alim[i].state;
		vobj->feed.ffunc = alim[i].ffunc;
		vobj->origw = alim[i].origw;
		vobj->origh = alim[i].origh;
/*		vobj->order = alim[i].zv;
		vobj->blendmode = BLEND_NORMAL; */
		vobj->tracetag = alim[i].tracetag;

/* since the feed function may keep a track of its parent (some do)
 * we also need to support the adopt call */
		arcan_vint_attachobject(did);
		arcan_ffunc_lookup(vobj->feed.ffunc)(FFUNC_ADOPT,
			0, 0, 0, 0, 0, vobj->feed.state, vobj->cellid);

		(*saved)++;
		if (adopt)
			adopt(did, tag);
	}

	arcan_audio_purge(audbuf, s_ofs);
	arcan_event_purge();
}

arcan_vobj_id arcan_video_findstate(enum arcan_vobj_tags tag, void* ptr)
{
	for (size_t i = 1; i < current_context->vitem_limit; i++){
	if (FL_TEST(&current_context->vitems_pool[i], FL_INUSE)){
		arcan_vobject* vobj = &current_context->vitems_pool[i];
		if (vobj->feed.state.tag == tag && vobj->feed.state.ptr == ptr)
			return i;
	}
	}

	return ARCAN_EID;
}

/*
 * the first approach to the _extpop etc. was to create a separate FBO, a vid
 * in the current context and a view in the next context then run a separate
 * rendertarget and readback the FBO into a texture.  Now we reuse the
 * screenshot function into a buffer, use that buffer to create a raw image and
 * voilà.
 */
unsigned arcan_video_extpopcontext(arcan_vobj_id* dst)
{
	av_pixel* dstbuf;
	size_t dsz;

	FLAG_DIRTY(NULL);

	arcan_vint_refresh(0.0, &dsz);

	bool ss = arcan_video_screenshot((void*)&dstbuf, &dsz) == ARCAN_OK;
	int rv = arcan_video_popcontext();

	if (ss){
		struct monitor_mode mode = platform_video_dimensions();
		int w = mode.width;
		int h = mode.height;

		img_cons cons = {.w = w, .h = h, .bpp = sizeof(av_pixel)};
		*dst = arcan_video_rawobject(dstbuf, cons, w, h, 1);

		if (*dst == ARCAN_EID){
			arcan_mem_free(dstbuf);
		}
		else{
/* flip y by using texture coordinates */
			arcan_vobject* vobj = arcan_video_getobject(*dst);
			vobj->txcos = arcan_alloc_mem(sizeof(float) * 8,
				ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_SIMD);

			arcan_vint_mirrormapping(vobj->txcos, 1.0, 1.0);
		}
	}

	return rv;
}

signed arcan_video_extpushcontext(arcan_vobj_id* dst)
{
	av_pixel* dstbuf;
	size_t dsz;

	FLAG_DIRTY(NULL);
	arcan_vint_refresh(0.0, &dsz);
	bool ss = arcan_video_screenshot(&dstbuf, &dsz) == ARCAN_OK;
	int rv = arcan_video_pushcontext();

	if (ss){
		struct monitor_mode mode = platform_video_dimensions();
		int w = mode.width;
		int h = mode.height;

		img_cons cons = {.w = w, .h = h, .bpp = sizeof(av_pixel)};
		*dst = arcan_video_rawobject(dstbuf, cons, w, h, 1);

		if (*dst == ARCAN_EID)
			arcan_mem_free(dstbuf);
		else
		{
			arcan_vobject* vobj = arcan_video_getobject(*dst);
			vobj->txcos = arcan_alloc_mem(sizeof(float) * 8,
				ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_SIMD);

			arcan_vint_mirrormapping(vobj->txcos, 1.0, 1.0);
		}
	}

	return rv;
}

unsigned arcan_video_popcontext()
{
/* propagate persistent flagged objects downwards */
	if (vcontext_ind > 0)
		pop_transfer_persists(
			current_context, &vcontext_stack[vcontext_ind-1]);

	deallocate_gl_context(current_context, true, current_context->world.vstore);

	if (vcontext_ind > 0){
		vcontext_ind--;
		current_context = &vcontext_stack[ vcontext_ind ];
	}

	reallocate_gl_context(current_context);
	FLAG_DIRTY(NULL);

	return (CONTEXT_STACK_LIMIT - 1) - vcontext_ind;
}

static inline surface_properties empty_surface()
{
	surface_properties res  = {
		.rotation.quaternion = default_quat
	};
	return res;
}

static arcan_vobj_id video_allocid(
	bool* status, struct arcan_video_context* ctx, bool write)
{
	unsigned i = ctx->vitem_ofs, c = ctx->vitem_limit;
	*status = false;

	while (c--){
		if (i == 0) /* 0 is protected */
			i = 1;

		if (!FL_TEST(&ctx->vitems_pool[i], FL_INUSE)){
			*status = true;
			if (!write)
				return i;

			ctx->nalive++;
			FL_SET(&ctx->vitems_pool[i], FL_INUSE);
			ctx->vitem_ofs = (ctx->vitem_ofs + 1) >= ctx->vitem_limit ? 1 : i + 1;
			return i;
		}

		i = (i + 1) % (ctx->vitem_limit - 1);
	}

	return ARCAN_EID;
}

arcan_errc arcan_video_resampleobject(arcan_vobj_id vid,
	arcan_vobj_id did, size_t neww, size_t newh, agp_shader_id shid,
	bool nocopy)
{
	arcan_vobject* vobj = arcan_video_getobject(vid);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (neww <= 0 || newh <= 0)
		return ARCAN_ERRC_OUT_OF_SPACE;

	if (vobj->vstore->txmapped != TXSTATE_TEX2D)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	arcan_vobj_id xfer = arcan_video_nullobject(neww, newh, 0);
	if (xfer == ARCAN_EID)
		return ARCAN_ERRC_OUT_OF_SPACE;

/* dstbuf is now managed by the glstore in xfer */
	arcan_video_shareglstore(vid, xfer);
	arcan_video_setprogram(xfer, shid);
	arcan_video_forceblend(xfer, BLEND_FORCE);

	img_cons cons = {.w = neww, .h = newh, .bpp = sizeof(av_pixel)};
	arcan_vobj_id dst;
	arcan_vobject* dobj;

/* if we want to sample into another dstore, some more safeguard checks
 * are needed so that we don't break other state (textured backend, not
 * a rendertarget) */
	if (did != ARCAN_EID){
		arcan_vobject* dvobj = arcan_video_getobject(did);
		if (!dvobj){
			arcan_video_deleteobject(xfer);
			return ARCAN_ERRC_OUT_OF_SPACE;
		}

		bool is_rtgt = arcan_vint_findrt(dvobj) != NULL;
		if (vobj->vstore->txmapped != TXSTATE_TEX2D){
			arcan_video_deleteobject(xfer);
			return ARCAN_ERRC_UNACCEPTED_STATE;
		}

/* create another intermediate object to act as our rendertarget as
 * that is an irreversible state transform which we can't do to did */
		arcan_vobj_id rtgt = arcan_video_nullobject(neww, newh, 0);
		if (rtgt == ARCAN_EID){
			arcan_video_deleteobject(xfer);
			return ARCAN_ERRC_OUT_OF_SPACE;
		}

/* and now swap and the rest of the function should behave as normal */
		if (dvobj->vstore->w != neww || dvobj->vstore->h != newh){
			agp_resize_vstore(dvobj->vstore, neww, newh);
		}
		arcan_video_shareglstore(did, rtgt);
		dst = rtgt;
	}
	else{
/* new intermediate storage that the FBO will draw into */
		size_t new_sz = neww * newh * sizeof(av_pixel);
		av_pixel* dstbuf = arcan_alloc_mem(new_sz,
			ARCAN_MEM_VBUFFER, ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE);

		if (!dstbuf){
			arcan_video_deleteobject(xfer);
			return ARCAN_ERRC_OUT_OF_SPACE;
		}

/* bind that to the destination object */
		dst = arcan_video_rawobject(dstbuf, cons, neww, newh, 1);
		if (dst == ARCAN_EID){
			arcan_mem_free(dstbuf);
			arcan_video_deleteobject(xfer);
			return ARCAN_ERRC_OUT_OF_SPACE;
		}
	}

/* set up a rendertarget and a proxy transfer object */
	arcan_errc rts = arcan_video_setuprendertarget(
		dst, 0, -1, false, RENDERTARGET_COLOR | RENDERTARGET_RETAIN_ALPHA);

	if (rts != ARCAN_OK){
		arcan_video_deleteobject(dst);
		arcan_video_deleteobject(xfer);
		return rts;
	}

/* draw, transfer storages and cleanup, xfer will
 * be deleted implicitly when dst cascades */
	arcan_video_attachtorendertarget(dst, xfer, true);
	agp_rendertarget_clearcolor(
		arcan_vint_findrt(arcan_video_getobject(dst))->art, 0.0, 0.0, 0.0, 0.0);
	arcan_video_objectopacity(xfer, 1.0, 0);
	arcan_video_forceupdate(dst, true);

/* in the call mode where caller specifies destination storage, we don't
 * share / override (or update the dimensions of the storage) */
	if (did == ARCAN_EID){
		vobj->origw = neww;
		vobj->origh = newh;
		arcan_video_shareglstore(dst, vid);
		arcan_video_objectscale(vid, 1.0, 1.0, 1.0, 0);
	}
	arcan_video_deleteobject(dst);

/* readback so we can survive push/pop and restore external */
	if (!nocopy){
		struct agp_vstore* dstore = vobj->vstore;
		agp_readback_synchronous(dstore);
	}

	return ARCAN_OK;
}

arcan_errc arcan_video_mipmapset(arcan_vobj_id vid, bool enable)
{
	arcan_vobject* vobj = arcan_video_getobject(vid);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj->vstore->txmapped != TXSTATE_TEX2D ||
		!vobj->vstore->vinf.text.raw)
		return ARCAN_ERRC_UNACCEPTED_STATE;

/*
 * For both disable and enable, we need to recreate the
 * gl_store and possibly remove the old one.
 */
	void* newbuf = arcan_alloc_fillmem(vobj->vstore->vinf.text.raw,
		vobj->vstore->vinf.text.s_raw,
		ARCAN_MEM_VBUFFER, ARCAN_MEM_NONFATAL,
		ARCAN_MEMALIGN_PAGE
	);

	if (!newbuf)
		return ARCAN_ERRC_OUT_OF_SPACE;

	arcan_vint_drop_vstore(vobj->vstore);
	if (enable)
		vobj->vstore->filtermode |= ARCAN_VFILTER_MIPMAP;
	else
		vobj->vstore->filtermode &= ~ARCAN_VFILTER_MIPMAP;

	vobj->vstore->vinf.text.raw = newbuf;
	agp_update_vstore(vobj->vstore, true);

	return ARCAN_OK;
}

void arcan_vint_defaultmapping(float* dst, float st, float tt)
{
	dst[0] = 0.0;
	dst[1] = 0.0;
	dst[2] = st;
	dst[3] = 0.0;
	dst[4] = st;
	dst[5] = tt;
	dst[6] = 0.0;
	dst[7] = tt;
}

void arcan_vint_mirrormapping(float* dst, float st, float tt)
{
	dst[6] = 0.0;
	dst[7] = 0.0;
	dst[4] = st;
	dst[5] = 0.0;
	dst[2] = st;
	dst[3] = tt;
	dst[0] = 0.0;
	dst[1] = tt;
}

static void populate_vstore(struct agp_vstore** vs)
{
	*vs = arcan_alloc_mem(
		sizeof(struct agp_vstore),
		ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO,
		ARCAN_MEMALIGN_NATURAL
	);

	(*vs)->txmapped   = TXSTATE_TEX2D;
	(*vs)->txu        = arcan_video_display.deftxs;
	(*vs)->txv        = arcan_video_display.deftxt;
	(*vs)->scale      = arcan_video_display.scalemode;
	(*vs)->imageproc  = arcan_video_display.imageproc;
	(*vs)->filtermode = arcan_video_display.filtermode;

	if (arcan_video_display.mipmap)
		(*vs)->filtermode |= ARCAN_VFILTER_MIPMAP;

	(*vs)->refcount   = 1;
}

arcan_vobj_id arcan_vint_nextfree()
{
	bool status;
	arcan_vobj_id id = video_allocid(&status, current_context, false);
	if (!status)
		return ARCAN_EID;
	else
		return id;
}

/*
 * arcan_video_newvobject is used in other parts (3d, renderfun, ...)
 * as well, but they wrap to this one as to not expose more of the
 * context stack
 */
static arcan_vobject* new_vobject(
	arcan_vobj_id* id, struct arcan_video_context* dctx)
{
	arcan_vobject* rv = NULL;

	bool status;
	arcan_vobj_id fid = video_allocid(&status, dctx, true);

	if (!status)
		return NULL;

	rv = dctx->vitems_pool + fid;
	rv->order = 0;
	populate_vstore(&rv->vstore);

	rv->feed.ffunc = FFUNC_FATAL;
	rv->childslots = 0;
	rv->children = NULL;

	rv->valid_cache = false;

	rv->blendmode = arcan_video_display.blendmode;
	rv->clip = ARCAN_CLIP_OFF;

	rv->current.scale.x = 1.0;
	rv->current.scale.y = 1.0;
	rv->current.scale.z = 1.0;

	rv->current.position.x = 0;
	rv->current.position.y = 0;
	rv->current.position.z = 0;

	rv->current.rotation.quaternion = default_quat;

	rv->current.opa = 0.0;

	rv->cellid = fid;
	assert(rv->cellid > 0);

	rv->parent = &current_context->world;
	rv->mask = MASK_ORIENTATION | MASK_OPACITY | MASK_POSITION
		| MASK_FRAMESET | MASK_LIVING;

	if (id != NULL)
		*id = fid;

	return rv;
}

arcan_vobject* arcan_video_newvobject(arcan_vobj_id* id )
{
	return new_vobject(id, current_context);
}

arcan_vobject* arcan_video_getobject(arcan_vobj_id id)
{
	arcan_vobject* rc = NULL;

	if (id > 0 && id < current_context->vitem_limit &&
		FL_TEST(&current_context->vitems_pool[id], FL_INUSE))
		rc = current_context->vitems_pool + id;
	else
		if (id == ARCAN_VIDEO_WORLDID){
			rc = &current_context->world;
		}

	return rc;
}

static bool detach_fromtarget(struct rendertarget* dst, arcan_vobject* src)
{
	arcan_vobject_litem* torem;
	assert(src);

/* already detached? */
	if (!dst){
		return false;
	}

	if (dst->camtag == src->cellid)
		dst->camtag = ARCAN_EID;

/* or empty set */
 	if (!dst->first)
		return false;

	if (dst->camtag == src->cellid)
		dst->camtag = ARCAN_EID;

/* find it */
	torem = dst->first;
	while(torem){
		if (torem->elem == src)
			break;

		torem = torem->next;
	}
	if (!torem)
		return false;

/* (1.) remove first */
	if (dst->first == torem){
		dst->first = torem->next;

/* only one element? */
		if (dst->first){
			dst->first->previous = NULL;
		}
	}
/* (2.) remove last */
	else if (torem->next == NULL){
		assert(torem->previous);
		torem->previous->next = NULL;
	}
/* (3.) remove arbitrary */
	else {
		torem->next->previous = torem->previous;
		torem->previous->next = torem->next;
	}

/* (4.) mark as something easy to find in dumps */
	torem->elem = (arcan_vobject*) 0xfeedface;

/* cleanup torem */
	arcan_mem_free(torem);

	if (src->owner == dst)
		src->owner = NULL;

	if (dst->color && dst != &current_context->stdoutp){
		dst->color->extrefc.attachments--;
		src->extrefc.attachments--;

		trace("(detach) (%ld:%s) removed from rendertarget:(%ld:%s),"
			"left: %d, attached to: %d\n", src->cellid, video_tracetag(src),
			dst->color ? dst->color->cellid : -1, video_tracetag(dst->color),
			dst->color->extrefc.attachments, src->extrefc.attachments);

		if (dst->color->extrefc.attachments < 0){
			arcan_warning(
				"[bug] attach-count (%d) < 0", dst->color->extrefc.attachments);
		}
	} else {
		src->extrefc.attachments--;
		trace("(detach) (%ld:%s) removed from stdout, attached to: %d\n",
		src->cellid, video_tracetag(src), src->extrefc.attachments);
	}

	FLAG_DIRTY(NULL);
	return true;
}

void arcan_vint_dirty_all()
{
	for (size_t ind = 0; ind < current_context->n_rtargets; ind++){
		struct rendertarget* tgt = &current_context->rtargets[ind];
		tgt->dirtyc++;
	}

	arcan_video_display.dirty++;
}

void arcan_vint_reraster(arcan_vobject* src, struct rendertarget* rtgt)
{
	struct agp_vstore* vs = src->vstore;

/* unless the storage is eligible and the density is sufficiently different */
	if (!
		((vs->txmapped && (vs->vinf.text.kind ==
		STORAGE_TEXT || vs->vinf.text.kind == STORAGE_TEXTARRAY)) &&
		((fabs(vs->vinf.text.vppcm - rtgt->vppcm) > EPSILON ||
		 fabs(vs->vinf.text.hppcm - rtgt->hppcm) > EPSILON)))
	)
		return;

/*  in update sourcedescr we guarantee that any vinf that come here with
 *  the TEXT | TEXTARRAY storage type will have a copy of the format string
 *  that led to its creation. This allows us to just reraster into that */
	size_t dw, dh, maxw, maxh;
	uint32_t dsz;
	if (vs->vinf.text.kind == STORAGE_TEXT)
		arcan_renderfun_renderfmtstr(
			vs->vinf.text.source, src->cellid,
			false, NULL, NULL, &dw, &dh, &dsz, &maxw, &maxh, false
		);
	else {
		arcan_renderfun_renderfmtstr_extended(
			(const char**) vs->vinf.text.source_arr, src->cellid,
			false, NULL, NULL, &dw, &dh, &dsz, &maxw, &maxh, false
		);
	}
}

static void attach_object(struct rendertarget* dst, arcan_vobject* src)
{
	arcan_vobject_litem* new_litem =
		arcan_alloc_mem(sizeof *new_litem,
			ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_NATURAL);

	new_litem->next = new_litem->previous = NULL;
	new_litem->elem = src;

/* (pre) if orphaned, assign */
	if (src->owner == NULL){
		src->owner = dst;
	}

/* 2. insert first into empty? */
	if (!dst->first)
		dst->first = new_litem;
	else
/* 3. insert first with n >= 1 */
	if (dst->first->elem->order > src->order){
		new_litem->next = dst->first;
		dst->first = new_litem;
		new_litem->next->previous = new_litem;
	}
/* 4. insert last or arbitrary */
	else {
		bool last;
		arcan_vobject_litem* ipoint = dst->first;

/* 5. scan for insertion point */
		do
			last = (ipoint->elem->order <= src->order);
		while (last && ipoint->next && (ipoint = ipoint->next));

/* 6. insert last? */
		if (last){
			new_litem->previous = ipoint;
			ipoint->next = new_litem;
		}

		else {
/* 7. insert arbitrary */
			ipoint->previous->next = new_litem;
			new_litem->previous = ipoint->previous;
			ipoint->previous = new_litem;
			new_litem->next = ipoint;
		}
	}

	FLAG_DIRTY(src);
	if (dst->color){
		src->extrefc.attachments++;
		dst->color->extrefc.attachments++;
		trace("(attach) (%d:%s) attached to rendertarget:(%ld:%s), "
			"src-count: %d, dst-count: %d\n", src->cellid, video_tracetag(src),
			dst->color ? dst->color->cellid : -1,
			dst->color ? video_tracetag(dst->color) : "(stdout)",
			src->extrefc.attachments, dst->color->extrefc.attachments);
	} else {
		src->extrefc.attachments++;
		trace("(attach) (%d:%s) attached to stdout, count: %d\n", src->cellid,
		video_tracetag(src), src->extrefc.attachments);
	}

	struct agp_vstore* vs = src->vstore;

/* IF the new attachment point has a different density than the previous,
 * AND the source is of a vector source, RERASTER to match the new target. */
	struct rendertarget* rtgt = current_context->attachment ?
		current_context->attachment : &current_context->stdoutp;

	arcan_vint_reraster(src, rtgt);
}

arcan_errc arcan_vint_attachobject(arcan_vobj_id id)
{
	arcan_vobject* src = arcan_video_getobject(id);

	if (!src)
		return ARCAN_ERRC_BAD_RESOURCE;

	struct rendertarget* rtgt = current_context->attachment ?
		current_context->attachment : &current_context->stdoutp;

	if (rtgt == src->owner)
		return ARCAN_OK;

/* make sure that there isn't already one attached */
	trace("(attach-eval-detach)\n");
	if (src->extrefc.attachments)
		detach_fromtarget(src->owner, src);

	trace("(attach-eval-attach)\n");
	attach_object(rtgt, src);
	trace("(attach-eval-done)\n");
	FLAG_DIRTY(src);

	return ARCAN_OK;
}

arcan_errc arcan_vint_dropshape(arcan_vobject* vobj)
{
	if (!vobj->shape)
		return ARCAN_OK;

	agp_drop_mesh(vobj->shape);
	return ARCAN_OK;
}

/* run through the chain and delete all occurences at ofs */
static void swipe_chain(surface_transform* base, unsigned ofs, unsigned size)
{
	while (base){
		memset((char*)base + ofs, 0, size);
		base = base->next;
	}
}

/* copy a transform and at the same time, compact it into
 * a better sized buffer */
static surface_transform* dup_chain(surface_transform* base)
{
	if (!base)
		return NULL;

	surface_transform* res = arcan_alloc_mem( sizeof(surface_transform),
		ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_NATURAL);

	surface_transform* current = res;

	while (base)
	{
		memcpy(current, base, sizeof(surface_transform));

		if (base->next)
			current->next = arcan_alloc_mem( sizeof(surface_transform),
			ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_NATURAL);
		else
			current->next = NULL;

		current = current->next;
		base = base->next;
	}

	return res;
}

arcan_errc arcan_video_inheritorder(arcan_vobj_id id, bool val)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id != ARCAN_VIDEO_WORLDID && vobj->order >= 0){
		rv = ARCAN_OK;
		if (val)
			FL_SET(vobj, FL_ORDOFS);
		else
			FL_CLEAR(vobj, FL_ORDOFS);
		update_zv(vobj, vobj->parent->order);
	}

	return rv;
}

enum arcan_transform_mask arcan_video_getmask(arcan_vobj_id id)
{
	enum arcan_transform_mask mask = 0;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id > 0)
		mask = vobj->mask;

	return mask;
}


arcan_errc arcan_video_readtag(arcan_vobj_id id, const char** tag, const char** alt)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	if (!vobj){
		if (tag)
			*tag = NULL;
		if (alt)
			*alt = NULL;
	}
	else {
		if (tag)
			*tag = vobj->tracetag;
		if (alt)
			*alt = vobj->alttext;
	}

	return ARCAN_OK;
}

arcan_errc arcan_video_transformmask(arcan_vobj_id id,
	enum arcan_transform_mask mask)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id > 0){
		vobj->mask = mask;
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_video_linkobjs(arcan_vobj_id srcid,
	arcan_vobj_id parentid, enum arcan_transform_mask mask,
	enum parent_anchor anchorp, enum parent_scale scalem)
{
	arcan_vobject* src = arcan_video_getobject(srcid);
	arcan_vobject* dst = arcan_video_getobject(parentid);

/* link to self always means link to world */
	if (srcid == parentid || parentid == 0)
		dst = &current_context->world;

	if (!src || !dst)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	arcan_vobject* current = dst;

/* traverse destination and make sure we don't create cycles */
	while (current){
		if (current->parent == src)
			return ARCAN_ERRC_CLONE_NOT_PERMITTED;
		else
			current = current->parent;
	}

/* update anchor, mask and scale */
	src->p_anchor = anchorp;
	src->mask = mask;
	src->p_scale = scalem;
	src->valid_cache = false;

/* already linked to dst? do nothing */
		if (src->parent == dst)
			return ARCAN_OK;

/* otherwise, first decrement parent counter */
		else if (src->parent != &current_context->world)
			dropchild(src->parent, src);

/* create link connection, and update counter */
	if (dst != &current_context->world){
		addchild(dst, src);
		trace("(link) (%d:%s) linked to (%d:%s), count: %d\n",
			src->cellid, src->tracetag == NULL ? "(unknown)" : src->tracetag,
			dst->cellid, dst->tracetag ? "(unknown)" : dst->tracetag,
			src->parent->extrefc.links);
	}

	if (FL_TEST(src, FL_ORDOFS))
		update_zv(src, src->parent->order);

/* reset all transformations except blend as they don't make sense until
 * redefined relative to their new parent. Blend is a special case in that
 * [fade + switch ownership] is often a desired operation */
	swipe_chain(src->transform, offsetof(surface_transform, move),
		sizeof(struct transf_move  ));
	swipe_chain(src->transform, offsetof(surface_transform, scale),
		sizeof(struct transf_scale ));
	swipe_chain(src->transform, offsetof(surface_transform, rotate),
		sizeof(struct transf_rotate));

	FLAG_DIRTY(NULL);

	return ARCAN_OK;
}

arcan_errc arcan_video_init(uint16_t width, uint16_t height, uint8_t bpp,
	bool fs, bool frames, bool conservative, const char* caption)
{
	static bool firstinit = true;

/* might be called multiple times due to longjmp recover etc. */
	if (firstinit){
		if (-1 == arcan_sem_init(&asynchsynch, ASYNCH_CONCURRENT_THREADS)){
			arcan_warning("video_init couldn't create synchronization handle\n");
		}

		arcan_vint_defaultmapping(arcan_video_display.default_txcos, 1.0, 1.0);
		arcan_vint_defaultmapping(arcan_video_display.cursor_txcos, 1.0, 1.0);
		arcan_vint_mirrormapping(arcan_video_display.mirror_txcos, 1.0, 1.0);
		arcan_video_reset_fontcache();
		firstinit = false;

/* though it should not be the default, the option to turn of the
 * 'block rendertarget drawing if not dirty' optimization may be
 * useful for some cases and for troubleshooting */
		uintptr_t tag;
		cfg_lookup_fun get_config = platform_config_lookup(&tag);
		if (get_config("video_ignore_dirty", 0, NULL, tag)){
			arcan_video_display.ignore_dirty = SIZE_MAX >> 1;
		}
	}

	if (!platform_video_init(width, height, bpp, fs, frames, caption)){
		arcan_warning("platform_video_init() failed.\n");
		return ARCAN_ERRC_BADVMODE;
	}

	agp_init();

	arcan_video_display.in_video = true;
	arcan_video_display.conservative = conservative;

	current_context->world.current.scale.x = 1.0;
	current_context->world.current.scale.y = 1.0;
	current_context->vitem_limit = arcan_video_display.default_vitemlim;
	current_context->vitems_pool = arcan_alloc_mem(
		sizeof(struct arcan_vobject) * current_context->vitem_limit,
		ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

	struct monitor_mode mode = platform_video_dimensions();
	if (mode.width == 0 || mode.height == 0){
		arcan_fatal("(video) platform error, invalid default mode\n");
	}
	arcan_video_resize_canvas(mode.width, mode.height);

	identity_matrix(current_context->stdoutp.base);
	current_context->stdoutp.order3d = arcan_video_display.order3d;
	current_context->stdoutp.refreshcnt = 1;
	current_context->stdoutp.refresh = -1;
	current_context->stdoutp.max_order = 65536;
	current_context->stdoutp.shid = agp_default_shader(BASIC_2D);
	current_context->stdoutp.vppcm = current_context->stdoutp.hppcm;

	arcan_renderfun_outputdensity(
		current_context->stdoutp.hppcm, current_context->stdoutp.vppcm);

/*
 * By default, expected video output display matches canvas 1:1,
 * canvas can be explicitly resized and these two matrices will still
 * make the output correct. For multiple- dynamic monitor configurations,
 * things get hairy; the video platform will be expected to
 * map rendertargets / videoobjects to output displays.
 */
	FLAG_DIRTY(NULL);
	return ARCAN_OK;
}

arcan_errc arcan_video_resize_canvas(size_t neww, size_t newh)
{
	struct monitor_mode mode = platform_video_dimensions();

	if (!arcan_video_display.no_stdout){
		if (!current_context->world.vstore || !current_context->stdoutp.art){
			populate_vstore(&current_context->world.vstore);
			current_context->world.vstore->filtermode &= ~ARCAN_VFILTER_MIPMAP;
			agp_empty_vstore(current_context->world.vstore, neww, newh);
			current_context->stdoutp.color = &current_context->world;
			current_context->stdoutp.mode = RENDERTARGET_COLOR_DEPTH_STENCIL;
			current_context->stdoutp.art = agp_setup_rendertarget(
				current_context->world.vstore,
				current_context->stdoutp.mode
			);
		}
		else
			agp_resize_rendertarget(current_context->stdoutp.art, neww, newh);
	}

	build_orthographic_matrix(
		arcan_video_display.window_projection, 0, mode.width, mode.height, 0,0,1);

	build_orthographic_matrix(
		arcan_video_display.default_projection, 0, mode.width, mode.height, 0,0,1);

	memcpy(current_context->stdoutp.projection,
		arcan_video_display.default_projection, sizeof(float) * 16);

	current_context->world.origw = neww;
	current_context->world.origh = newh;

	FLAG_DIRTY(NULL);
	arcan_video_forceupdate(ARCAN_VIDEO_WORLDID, true);

	return ARCAN_OK;
}

static uint16_t nexthigher(uint16_t k)
{
	k--;
	for (size_t i=1; i < sizeof(uint16_t) * 8; i = i * 2)
		k = k | k >> i;
	return k+1;
}

arcan_errc arcan_vint_getimage(const char* fname, arcan_vobject* dst,
	img_cons forced, bool asynchsrc)
{
/*
 * with asynchsynch, it's likely that we get a storm of requests and we'd
 * likely suffer thrashing, so limit this.  also, look into using
 * pthread_setschedparam and switch to pthreads exclusively
 */
	arcan_sem_wait(asynchsynch);

	size_t inw, inh;

/* try- open */
	data_source inres = arcan_open_resource(fname);
	if (inres.fd == BADFD){
		arcan_sem_post(asynchsynch);
		return ARCAN_ERRC_BAD_RESOURCE;
	}

/* mmap (preferred) or buffer (mmap not working / useful due to alignment) */
	map_region inmem = arcan_map_resource(&inres, false);
	if (inmem.ptr == NULL){
		arcan_sem_post(asynchsynch);
		arcan_release_resource(&inres);
		return ARCAN_ERRC_BAD_RESOURCE;
	}

	struct arcan_img_meta meta = {0};
	uint32_t* ch_imgbuf = NULL;

	arcan_errc rv = arcan_img_decode(fname, inmem.ptr, inmem.sz,
		&ch_imgbuf, &inw, &inh, &meta, dst->vstore->imageproc == IMAGEPROC_FLIPH);

	arcan_release_map(inmem);
	arcan_release_resource(&inres);

	if (ARCAN_OK != rv)
		goto done;

	av_pixel* imgbuf = arcan_img_repack(ch_imgbuf, inw, inh);
	if (!imgbuf){
		rv = ARCAN_ERRC_OUT_OF_SPACE;
		goto done;
	}

	uint16_t neww, newh;

/* store this so we can maintain aspect ratios etc. while still
 * possibly aligning to next power of two */
	dst->origw = inw;
	dst->origh = inh;

	neww = inw;
	newh = inh;

/* the thread_loader will take care of converting the asynchsrc
 * to an image once its completely done */
	if (!asynchsrc)
		dst->feed.state.tag = ARCAN_TAG_IMAGE;

/* need to keep the identification string in order to rebuild
 * on a forced push/pop */
	struct agp_vstore* dstframe = dst->vstore;
	dstframe->vinf.text.source = strdup(fname);

	enum arcan_vimage_mode desm = dst->vstore->scale;

	if (meta.compressed)
		goto push_comp;

/* the user requested specific dimensions, or we are in a mode where
 * we should manually enfore a stretch to the nearest power of two */
	if (desm == ARCAN_VIMAGE_SCALEPOW2){
		forced.w = nexthigher(neww) == neww ? 0 : nexthigher(neww);
		forced.h = nexthigher(newh) == newh ? 0 : nexthigher(newh);
	}

	if (forced.h > 0 && forced.w > 0){
		neww = desm == ARCAN_VIMAGE_SCALEPOW2 ? nexthigher(forced.w) : forced.w;
		newh = desm == ARCAN_VIMAGE_SCALEPOW2 ? nexthigher(forced.h) : forced.h;
		dst->origw = forced.w;
		dst->origh = forced.h;

		dstframe->vinf.text.s_raw = neww * newh * sizeof(av_pixel);
		dstframe->vinf.text.raw = arcan_alloc_mem(dstframe->vinf.text.s_raw,
			ARCAN_MEM_VBUFFER, 0, ARCAN_MEMALIGN_PAGE);

		arcan_renderfun_stretchblit((char*)imgbuf, inw, inh,
			(uint32_t*) dstframe->vinf.text.raw,
			neww, newh, dst->vstore->imageproc == IMAGEPROC_FLIPH);
		arcan_mem_free(imgbuf);
	}
	else {
		neww = inw;
		newh = inh;
		dstframe->vinf.text.raw = imgbuf;
		dstframe->vinf.text.s_raw = inw * inh * sizeof(av_pixel);
	}

	dst->vstore->w = neww;
	dst->vstore->h = newh;

/*
 * for the asynch case, we need to do this separately as we're in a different
 * thread and forcibly assigning the glcontext to another thread is expensive */

push_comp:
	if (!asynchsrc && dst->vstore->txmapped != TXSTATE_OFF)
		agp_update_vstore(dst->vstore, true);

done:
	arcan_sem_post(asynchsynch);
	return rv;
}

arcan_errc arcan_video_3dorder(enum arcan_order3d order, arcan_vobj_id rt)
{
	if (rt != ARCAN_EID){
		arcan_vobject* vobj = arcan_video_getobject(rt);
		if (!vobj)
			return ARCAN_ERRC_NO_SUCH_OBJECT;

		struct rendertarget* rtgt = arcan_vint_findrt(vobj);
		if (!rtgt)
			return ARCAN_ERRC_NO_SUCH_OBJECT;

		rtgt->order3d = order;
	}
	else
		arcan_video_display.order3d = order;
	return ARCAN_OK;
}

static void rescale_origwh(arcan_vobject* dst, float fx, float fy)
{
	vector svect = build_vect(fx, fy, 1.0);
	surface_transform* current = dst->transform;

	while (current){
		current->scale.startd = mul_vector(current->scale.startd, svect);
		current->scale.endd   = mul_vector(current->scale.endd, svect);
		current = current->next;
	}
}

arcan_errc arcan_video_framecyclemode(arcan_vobj_id id, int mode)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (!vobj->frameset)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	vobj->frameset->ctr = vobj->frameset->mctr = abs(mode);

	return ARCAN_OK;
}

void arcan_video_cursorpos(int newx, int newy, bool absolute)
{
	if (absolute){
		arcan_video_display.cursor.x = newx;
		arcan_video_display.cursor.y = newy;
	}
	else {
		arcan_video_display.cursor.x += newx;
		arcan_video_display.cursor.y += newy;
	}
}

void arcan_video_cursorsize(size_t w, size_t h)
{
	arcan_video_display.cursor.w = w;
	arcan_video_display.cursor.h = h;
}

void arcan_video_cursorstore(arcan_vobj_id src)
{
	if (arcan_video_display.cursor.vstore){
		arcan_vint_drop_vstore(arcan_video_display.cursor.vstore);
		arcan_video_display.cursor.vstore = NULL;
	}

	arcan_vobject* vobj = arcan_video_getobject(src);
	if (src == ARCAN_VIDEO_WORLDID || !vobj ||
		vobj->vstore->txmapped != TXSTATE_TEX2D)
		return;

/* texture coordinates are managed separately through _display.cursor_txcos */
	arcan_video_display.cursor.vstore = vobj->vstore;
	vobj->vstore->refcount++;
}

arcan_errc arcan_video_shareglstore(arcan_vobj_id sid, arcan_vobj_id did)
{
	arcan_vobject* src = arcan_video_getobject(sid);
	arcan_vobject* dst = arcan_video_getobject(did);

	if (!src || !dst || src == dst)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

/* remove the original target store, substitute in our own */
	arcan_vint_drop_vstore(dst->vstore);

	struct rendertarget* rtgt = arcan_vint_findrt(dst);

/* if the source is broken, convert dst to null store (color with bad prg) */
	if (src->vstore->txmapped == TXSTATE_OFF ||
		FL_TEST(src, FL_PRSIST) ||
		FL_TEST(dst, FL_PRSIST)
	){

/* but leave rendertarget vstore alone */
		if (rtgt){
			return ARCAN_OK;
		}

/* transfer the vstore data, this will have no effect for real txstate off
 * but for the color_surface we copy the colors and the shader used */
		populate_vstore(&dst->vstore);
		struct agp_vstore* store = dst->vstore;
		store->txmapped = TXSTATE_OFF;
		store->vinf.col = src->vstore->vinf.col;
		dst->program = src->program;

		FLAG_DIRTY(dst);
		return ARCAN_OK;
	}

	dst->vstore = src->vstore;
	dst->vstore->refcount++;

/* customized texture coordinates unless we should use defaults ... */
	if (src->txcos){
		if (!dst->txcos)
			dst->txcos = arcan_alloc_mem(8 * sizeof(float),
				ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_SIMD);
		memcpy(dst->txcos, src->txcos, sizeof(float) * 8);
	}
	else if (dst->txcos){
		arcan_mem_free(dst->txcos);
		dst->txcos = NULL;
	}

/* for rendertarget, we also need to rebuild attachments and so on, the easiest
 * approach for this is to drop the FBO entirely and rebuild with the new store
 * as the store affects format. */
	if (rtgt){
		agp_drop_rendertarget(rtgt->art);
		agp_setup_rendertarget(rtgt->color->vstore, rtgt->mode);
		arcan_video_forceupdate(did, true);
	}

	FLAG_DIRTY(dst);
	return ARCAN_OK;
}

arcan_vobj_id arcan_video_solidcolor(float origw, float origh,
	uint8_t r, uint8_t g, uint8_t b, unsigned short zv)
{
	arcan_vobj_id rv = ARCAN_EID;
	arcan_vobject* newvobj = arcan_video_newvobject(&rv);
	if (!newvobj)
		return rv;

	newvobj->vstore->txmapped = TXSTATE_OFF;
	newvobj->vstore->vinf.col.r = (float)r / 255.0f;
	newvobj->vstore->vinf.col.g = (float)g / 255.0f;
	newvobj->vstore->vinf.col.b = (float)b / 255.0f;

	newvobj->program = agp_default_shader(COLOR_2D);

	newvobj->origw = origw;
	newvobj->origh = origh;
	newvobj->order = zv;

	arcan_vint_attachobject(rv);

	return rv;
}

/* solid and null are essentially treated the same, the difference being
 * there's no program associated in the vstore for the nullobject */
arcan_vobj_id arcan_video_nullobject(float origw,
	float origh, unsigned short zv)
{
	arcan_vobj_id rv =  arcan_video_solidcolor(origw, origh, 0, 0, 0, zv);
	arcan_vobject* vobj = arcan_video_getobject(rv);
	if (vobj)
		vobj->program = 0;

	return rv;
}

arcan_vobj_id arcan_video_rawobject(av_pixel* buf,
	img_cons cons, float origw, float origh, unsigned short zv)
{
	arcan_vobj_id rv = ARCAN_EID;
	size_t bufs = cons.w * cons.h * cons.bpp;

	if (cons.bpp != sizeof(av_pixel))
		return ARCAN_EID;

	arcan_vobject* newvobj = arcan_video_newvobject(&rv);

	if (!newvobj)
		return ARCAN_EID;

	struct agp_vstore* ds = newvobj->vstore;

	if (!buf){
		ds->vinf.text.s_raw = cons.w * cons.h * sizeof(av_pixel);
		ds->vinf.text.raw = arcan_alloc_mem(
			ds->vinf.text.s_raw,
			ARCAN_MEM_VBUFFER, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_PAGE);
	}
	else {
		ds->vinf.text.s_raw = bufs;
		ds->vinf.text.raw = buf;
	}

	ds->w = cons.w;
	ds->h = cons.h;
	ds->bpp = cons.bpp;
	ds->txmapped = TXSTATE_TEX2D;

	newvobj->origw = origw;
	newvobj->origh = origh;
	newvobj->order = zv;

	agp_update_vstore(newvobj->vstore, true);
	arcan_vint_attachobject(rv);

	return rv;
}

arcan_errc arcan_video_rendertargetdensity(
	arcan_vobj_id src, float vppcm, float hppcm, bool reraster, bool rescale)
{
/* sanity checks */
	arcan_vobject* srcobj = arcan_video_getobject(src);
	if (!srcobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	struct rendertarget* rtgt = arcan_vint_findrt(srcobj);
	if (!rtgt)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	if (vppcm < EPSILON)
		vppcm = rtgt->vppcm;

	if (hppcm < EPSILON)
		hppcm = rtgt->hppcm;

	if (rtgt->vppcm == vppcm && rtgt->hppcm == hppcm)
		return ARCAN_OK;

/* reflect the new changes */
	float sfx = hppcm / rtgt->hppcm;
	float sfy = vppcm / rtgt->vppcm;
	arcan_renderfun_outputdensity(rtgt->hppcm, rtgt->vppcm);

	rtgt->vppcm = vppcm;
	rtgt->hppcm = hppcm;

	struct arcan_vobject_litem* cent = rtgt->first;
	while(cent){
		struct arcan_vobject* vobj = cent->elem;
		if (vobj->owner != rtgt){
			cent = cent->next;
			continue;
		}

/* for all vobj- that are attached to this rendertarget AND has it as
 * primary, check if it is possible to rebuild a raster representation
 * with more accurate density */
		if (reraster)
			arcan_vint_reraster(vobj, rtgt);

		if (rescale){
			float ox = (float)vobj->origw*vobj->current.scale.x;
			float oy = (float)vobj->origh*vobj->current.scale.y;
			rescale_origwh(vobj,
					sfx / vobj->current.scale.x, sfy / vobj->current.scale.y);
			invalidate_cache(vobj);
		}
		cent = cent->next;
	}

	FLAG_DIRTY(srcobj);
	return ARCAN_OK;
}

arcan_errc arcan_video_detachfromrendertarget(arcan_vobj_id did,
	arcan_vobj_id src)
{
	arcan_vobject* srcobj = arcan_video_getobject(src);
	arcan_vobject* dstobj = arcan_video_getobject(did);
	if (!srcobj || !dstobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (&current_context->stdoutp == srcobj->owner){
		detach_fromtarget(&current_context->stdoutp, srcobj);
		return ARCAN_OK;
	}

	for (size_t ind = 0; ind < current_context->n_rtargets; ind++){
		if (current_context->rtargets[ind].color == dstobj &&
			srcobj->owner != &current_context->rtargets[ind])
				detach_fromtarget(&current_context->rtargets[ind], srcobj);
	}

	return ARCAN_OK;
}

arcan_errc arcan_video_attachtorendertarget(
	arcan_vobj_id did, arcan_vobj_id src, bool detach)
{
	if (src == ARCAN_VIDEO_WORLDID){
		arcan_warning("arcan_video_attachtorendertarget(), WORLDID attach"
			" not directly supported, use a null-surface with "
			"shared storage instead.");

		return ARCAN_ERRC_UNACCEPTED_STATE;
	}

/* don't allow to attach to self, that FBO behavior would be undefined
 * and don't allow persist attachments as the other object can go out of
 * scope */
	arcan_vobject* dstobj = arcan_video_getobject(did);
	arcan_vobject* srcobj = arcan_video_getobject(src);
	if (!dstobj || !srcobj || dstobj == srcobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (FL_TEST(dstobj, FL_PRSIST) || FL_TEST(srcobj, FL_PRSIST))
		return ARCAN_ERRC_UNACCEPTED_STATE;

	if (current_context->stdoutp.color == dstobj){
		if (srcobj->owner && detach)
			detach_fromtarget(srcobj->owner, srcobj);

/* try and detach (most likely fail) to make sure that we don't get duplicates*/
		detach_fromtarget(&current_context->stdoutp, srcobj);
		attach_object(&current_context->stdoutp, srcobj);

		return ARCAN_OK;
	}

/* linear search for rendertarget matching the destination id */
	for (size_t ind = 0; ind < current_context->n_rtargets; ind++){
		if (current_context->rtargets[ind].color == dstobj){
/* find whatever rendertarget we're already attached to, and detach */
			if (srcobj->owner && detach)
				detach_fromtarget(srcobj->owner, srcobj);

/* try and detach (most likely fail) to make sure that we don't get duplicates*/
			detach_fromtarget(&current_context->rtargets[ind], srcobj);
			attach_object(&current_context->rtargets[ind], srcobj);

			return ARCAN_OK;
		}
	}

	return ARCAN_ERRC_BAD_ARGUMENT;
}

arcan_errc arcan_video_defaultattachment(arcan_vobj_id src)
{
	if (src == ARCAN_EID)
		return ARCAN_ERRC_BAD_ARGUMENT;

	arcan_vobject* vobj = arcan_video_getobject(src);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	struct rendertarget* rtgt = arcan_vint_findrt(vobj);
	if (!rtgt)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	current_context->attachment = rtgt;
	return ARCAN_OK;
}

arcan_vobj_id arcan_video_currentattachment()
{
	struct rendertarget* rtgt = current_context->attachment;
	if (!rtgt || !rtgt->color)
		return ARCAN_VIDEO_WORLDID;

	return rtgt->color->cellid;
}

arcan_errc arcan_video_alterreadback(arcan_vobj_id did, int readback)
{
	if (did == ARCAN_VIDEO_WORLDID){
		current_context->stdoutp.readback = readback;
		return ARCAN_OK;
	}

	arcan_vobject* vobj = arcan_video_getobject(did);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	struct rendertarget* rtgt = arcan_vint_findrt(vobj);
	if (!rtgt)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	rtgt->readback = readback;
	rtgt->readcnt = abs(readback);
	return ARCAN_OK;
}

arcan_errc arcan_video_rendertarget_range(
	arcan_vobj_id did, ssize_t min, ssize_t max)
{
	struct rendertarget* rtgt;

	if (did == ARCAN_VIDEO_WORLDID)
		rtgt = &current_context->stdoutp;
	else {
		arcan_vobject* vobj = arcan_video_getobject(did);
		if (!vobj)
			return ARCAN_ERRC_NO_SUCH_OBJECT;

		rtgt = arcan_vint_findrt(vobj);
	}

	if (!rtgt)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (min < 0 || max < min){
		min = 0;
		max = 65536;
	}

	rtgt->min_order = min;
	rtgt->max_order = max;

	return ARCAN_OK;
}

arcan_errc arcan_video_rendertarget_setnoclear(arcan_vobj_id did, bool value)
{
	struct rendertarget* rtgt;

	if (did == ARCAN_VIDEO_WORLDID)
		rtgt = &current_context->stdoutp;
	else {
		arcan_vobject* vobj = arcan_video_getobject(did);
		if (!vobj)
			return ARCAN_ERRC_NO_SUCH_OBJECT;

		rtgt = arcan_vint_findrt(vobj);
	}

	if (!rtgt)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (value)
		FL_SET(rtgt, TGTFL_NOCLEAR);
	else
		FL_CLEAR(rtgt, TGTFL_NOCLEAR);

	return ARCAN_OK;
}

arcan_errc arcan_video_linkrendertarget(arcan_vobj_id did,
	arcan_vobj_id tgt_id, int refresh, bool scale, enum rendertarget_mode format)
{
	arcan_vobject* vobj = arcan_video_getobject(tgt_id);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	struct rendertarget* tgt = arcan_vint_findrt(vobj);
	if (!tgt)
		return ARCAN_ERRC_BAD_ARGUMENT;

/* this can be used to update the link state of an existing rendertarget
 * or to define a new one based on the pipeline of an existing one */
	vobj = arcan_video_getobject(did);
	struct rendertarget* newtgt = arcan_vint_findrt(vobj);
	if (!newtgt){
		arcan_errc rv =
			arcan_video_setuprendertarget(did, 0, refresh, scale, format);
		if (rv != ARCAN_OK)
			return rv;

		newtgt = arcan_vint_findrt(vobj);
	}

	if (!newtgt || newtgt == tgt)
		return ARCAN_ERRC_BAD_ARGUMENT;

	newtgt->link = tgt;
	return ARCAN_OK;
}

arcan_errc arcan_video_setuprendertarget(arcan_vobj_id did,
	int readback, int refresh, bool scale, enum rendertarget_mode format)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(did);
	if (!vobj)
		return rv;

	bool is_rtgt = arcan_vint_findrt(vobj) != NULL;
	if (is_rtgt){
		arcan_warning("arcan_video_setuprendertarget() source vid"
			"already is a rendertarget\n");
		rv = ARCAN_ERRC_BAD_ARGUMENT;
		return rv;
	}

/* hard-coded number of render-targets allowed */
	if (current_context->n_rtargets >= RENDERTARGET_LIMIT)
		return ARCAN_ERRC_OUT_OF_SPACE;

	int ind = current_context->n_rtargets++;
	struct rendertarget* dst = &current_context->rtargets[ ind ];
	*dst = (struct rendertarget){};

	FL_SET(vobj, FL_RTGT);
	FL_SET(dst, TGTFL_ALIVE);
	dst->color = vobj;
	dst->camtag = ARCAN_EID;
	dst->readback = readback;
	dst->readcnt = abs(readback);
	dst->refresh = refresh;
	dst->refreshcnt = abs(refresh);
	dst->art = agp_setup_rendertarget(vobj->vstore, format);
	dst->shid = agp_default_shader(BASIC_2D);
	dst->mode = format;
	dst->order3d = arcan_video_display.order3d;
	dst->vppcm = dst->hppcm = 28.346456692913385;
	dst->min_order = 0;
	dst->max_order = 65536;

	static int rendertarget_id;
	rendertarget_id = (rendertarget_id + 1) % (INT_MAX-1);
	dst->id = rendertarget_id;

	vobj->extrefc.attachments++;
	trace("(setuprendertarget), (%d:%s) defined as rendertarget."
		"attachments: %d\n", vobj->cellid, video_tracetag(vobj),
		vobj->extrefc.attachments);

/* alter projection so the GL texture gets stored in the way
 * the images are rendered in normal mode, with 0,0 being upper left */
	build_orthographic_matrix(
		dst->projection, 0, vobj->origw, 0, vobj->origh, 0, 1);
	identity_matrix(dst->base);

	struct monitor_mode mode = platform_video_dimensions();
	if (scale){
		float xs = (float)vobj->vstore->w / (float)mode.width;
		float ys = (float)vobj->vstore->h / (float)mode.height;

/* since we may likely have a differently sized FBO, scale it */
		scale_matrix(dst->base, xs, ys, 1.0);
	}

	return ARCAN_OK;
}

arcan_errc arcan_video_setactiveframe(arcan_vobj_id dst, unsigned fid)
{
	arcan_vobject* dstvobj = arcan_video_getobject(dst);

	if (!dstvobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (!dstvobj->frameset)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	dstvobj->frameset->index = fid < dstvobj->frameset->n_frames ? fid : 0;

	FLAG_DIRTY(dstvobj);
	return ARCAN_OK;
}

arcan_errc arcan_video_setasframe(arcan_vobj_id dst,
	arcan_vobj_id src, size_t fid)
{
	arcan_vobject* dstvobj = arcan_video_getobject(dst);
	arcan_vobject* srcvobj = arcan_video_getobject(src);

	if (!dstvobj || !srcvobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (dstvobj->frameset == NULL || srcvobj->vstore->txmapped != TXSTATE_TEX2D)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	if (fid >= dstvobj->frameset->n_frames)
		return ARCAN_ERRC_BAD_ARGUMENT;

	struct frameset_store* store = &dstvobj->frameset->frames[fid];
	if (store->frame != srcvobj->vstore){
		arcan_vint_drop_vstore(store->frame);
		store->frame = srcvobj->vstore;
	}

/* we need texture coordinates to come with in order to support
 * animations using 'sprite-sheet' like features */
	if (srcvobj->txcos)
		memcpy(store->txcos, srcvobj->txcos, sizeof(float)*8);
	else
		arcan_vint_defaultmapping(store->txcos, 1.0, 1.0);

	store->frame->refcount++;

	return ARCAN_OK;
}

struct thread_loader_args {
	arcan_vobject* dst;
	pthread_t self;
	arcan_vobj_id dstid;
	char* fname;
	intptr_t tag;
	img_cons constraints;
	arcan_errc rc;
};

static void* thread_loader(void* in)
{
	struct thread_loader_args* largs = (struct thread_loader_args*) in;
	arcan_vobject* dst = largs->dst;
	largs->rc = arcan_vint_getimage(largs->fname, dst, largs->constraints, true);
	dst->feed.state.tag = ARCAN_TAG_ASYNCIMGRD;
	return 0;
}

void arcan_vint_joinasynch(arcan_vobject* img, bool emit, bool force)
{
	if (!force && img->feed.state.tag != ARCAN_TAG_ASYNCIMGRD){
		return;
	}

	struct thread_loader_args* args =
		(struct thread_loader_args*) img->feed.state.ptr;

	pthread_join(args->self, NULL);

	arcan_event loadev = {
		.category = EVENT_VIDEO,
		.vid.data = args->tag,
		.vid.source = args->dstid
	};

	if (args->rc == ARCAN_OK){
		loadev.vid.kind = EVENT_VIDEO_ASYNCHIMAGE_LOADED;
		loadev.vid.width = img->origw;
		loadev.vid.height = img->origh;
	}
/* copy broken placeholder instead */
	else {
		img->origw = 32;
		img->origh = 32;
		img->vstore->vinf.text.s_raw = 32 * 32 * sizeof(av_pixel);
		img->vstore->vinf.text.raw = arcan_alloc_mem(img->vstore->vinf.text.s_raw,
			ARCAN_MEM_VBUFFER, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_PAGE);

		img->vstore->w = 32;
		img->vstore->h = 32;
		img->vstore->vinf.text.source = strdup(args->fname);
		img->vstore->filtermode = ARCAN_VFILTER_NONE;

		loadev.vid.width = 32;
		loadev.vid.height = 32;
		loadev.vid.kind = EVENT_VIDEO_ASYNCHIMAGE_FAILED;
	}

	agp_update_vstore(img->vstore, true);

	if (emit)
		arcan_event_enqueue(arcan_event_defaultctx(), &loadev);

	arcan_mem_free(args->fname);
	arcan_mem_free(args);
	img->feed.state.ptr = NULL;
	img->feed.state.tag = ARCAN_TAG_IMAGE;
}

static arcan_vobj_id loadimage_asynch(const char* fname,
	img_cons constraints, intptr_t tag)
{
	arcan_vobj_id rv = ARCAN_EID;
	arcan_vobject* dstobj = arcan_video_newvobject(&rv);
	if (!dstobj)
		return rv;

	struct thread_loader_args* args = arcan_alloc_mem(
		sizeof(struct thread_loader_args),
		ARCAN_MEM_THREADCTX, 0, ARCAN_MEMALIGN_NATURAL);

	args->dstid = rv;
	args->dst = dstobj;
	args->fname = strdup(fname);
	args->tag = tag;
	args->constraints = constraints;

	dstobj->feed.state.tag = ARCAN_TAG_ASYNCIMGLD;
	dstobj->feed.state.ptr = args;

	pthread_create(&args->self, NULL, thread_loader, (void*) args);

	return rv;
}

arcan_errc arcan_video_pushasynch(arcan_vobj_id source)
{
	arcan_vobject* vobj = arcan_video_getobject(source);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj->feed.state.tag == ARCAN_TAG_ASYNCIMGLD ||
		vobj->feed.state.tag == ARCAN_TAG_ASYNCIMGRD){
		/* protect us against premature invocation */
		arcan_vint_joinasynch(vobj, false, true);
	}
	else
		return ARCAN_ERRC_UNACCEPTED_STATE;

	return ARCAN_OK;
}

static arcan_vobj_id loadimage(const char* fname, img_cons constraints,
	arcan_errc* errcode)
{
	arcan_vobj_id rv = 0;

	arcan_vobject* newvobj = arcan_video_newvobject(&rv);
	if (newvobj == NULL)
		return ARCAN_EID;

	arcan_errc rc = arcan_vint_getimage(fname, newvobj, constraints, false);

	if (rc != ARCAN_OK)
		arcan_video_deleteobject(rv);

	if (errcode != NULL)
		*errcode = rc;

	return rv;
}

vfunc_state* arcan_video_feedstate(arcan_vobj_id id)
{
	void* rv = NULL;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id > 0){
		rv = &vobj->feed.state;
	}

	return rv;
}

arcan_errc arcan_video_alterfeed(arcan_vobj_id id,
	ffunc_ind cb, vfunc_state state)
{
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	vobj->feed.state = state;
	vobj->feed.ffunc = cb;

	return ARCAN_OK;
}

static arcan_vobj_id arcan_video_setupfeed(
	ffunc_ind ffunc, img_cons cons, uint8_t ntus, uint8_t ncpt)
{
	if (!ffunc)
		return 0;

	arcan_vobj_id rv = 0;
	arcan_vobject* newvobj = arcan_video_newvobject(&rv);

	if (!newvobj || !ffunc)
		return ARCAN_EID;

	struct agp_vstore* vstor = newvobj->vstore;
/* preset */
	newvobj->origw = cons.w;
	newvobj->origh = cons.h;
	newvobj->vstore->bpp = ncpt == 0 ? sizeof(av_pixel) : ncpt;
	newvobj->vstore->filtermode &= ~ARCAN_VFILTER_MIPMAP;

	if (newvobj->vstore->scale == ARCAN_VIMAGE_NOPOW2){
		newvobj->vstore->w = cons.w;
		newvobj->vstore->h = cons.h;
	}
	else {
/* For feeds, we don't do the forced- rescale on
 * every frame, way too expensive, this behavior only
 * occurs if there's a custom set of texture coordinates already */
		newvobj->vstore->w = nexthigher(cons.w);
		newvobj->vstore->h = nexthigher(cons.h);
		float hx = (float)cons.w / (float)newvobj->vstore->w;
		float hy = (float)cons.h / (float)newvobj->vstore->h;
		if (newvobj->txcos)
			arcan_vint_defaultmapping(newvobj->txcos, hx, hy);
	}

/* allocate */
	vstor->vinf.text.s_raw = newvobj->vstore->w *
		newvobj->vstore->h * newvobj->vstore->bpp;
	vstor->vinf.text.raw = arcan_alloc_mem(vstor->vinf.text.s_raw,
		ARCAN_MEM_VBUFFER, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_PAGE);

	newvobj->feed.ffunc = ffunc;
	agp_update_vstore(newvobj->vstore, true);

	return rv;
}

/* some targets like to change size dynamically (thanks for that),
 * thus, drop the allocated buffers, generate new one and tweak txcos */
arcan_errc arcan_video_resizefeed(arcan_vobj_id id, size_t w, size_t h)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj->feed.state.tag == ARCAN_TAG_ASYNCIMGLD ||
		vobj->feed.state.tag == ARCAN_TAG_ASYNCIMGRD)
		arcan_video_pushasynch(id);

/* rescale transformation chain */
	float ox = (float)vobj->origw*vobj->current.scale.x;
	float oy = (float)vobj->origh*vobj->current.scale.y;
	float sfx = ox / (float)w;
	float sfy = oy / (float)h;
	if (vobj->current.scale.x > 0 && vobj->current.scale.y > 0){
		rescale_origwh(vobj,
			sfx / vobj->current.scale.x, sfy / vobj->current.scale.y);
	}

/* "initial" base dimensions, important when dimensions change for objects that
 * have a shared storage elsewhere but where scale differs. */
	vobj->origw = w;
	vobj->origh = h;

	vobj->current.scale.x = sfx;
	vobj->current.scale.y = sfy;
	invalidate_cache(vobj);
	agp_resize_vstore(vobj->vstore, w, h);

	FLAG_DIRTY(vobj);
	return ARCAN_OK;
}

arcan_vobj_id arcan_video_loadimageasynch(const char* rloc,
	img_cons constraints, intptr_t tag)
{
	arcan_vobj_id rv = loadimage_asynch(rloc, constraints, tag);

	if (rv > 0){
		arcan_vobject* vobj = arcan_video_getobject(rv);

		if (vobj){
			vobj->current.rotation.quaternion = default_quat;
			arcan_vint_attachobject(rv);
		}
	}

	return rv;
}

arcan_vobj_id arcan_video_loadimage(const char* rloc,
	img_cons constraints, unsigned short zv)
{
	arcan_vobj_id rv = loadimage((char*) rloc, constraints, NULL);

/* the asynch version could've been deleted in between,
 * so we need to double check */
		if (rv > 0){
		arcan_vobject* vobj = arcan_video_getobject(rv);
		if (vobj){
			vobj->order = zv;
			vobj->current.rotation.quaternion = default_quat;
			arcan_vint_attachobject(rv);
		}
	}

	return rv;
}

arcan_vobj_id arcan_video_addfobject(
	ffunc_ind feed, vfunc_state state, img_cons cons, unsigned short zv)
{
	arcan_vobj_id rv;
	const int feed_ntus = 1;

	if ((rv = arcan_video_setupfeed(feed, cons, feed_ntus, cons.bpp)) > 0){
		arcan_vobject* vobj = arcan_video_getobject(rv);
		vobj->order = zv;
		vobj->feed.state = state;

		if (state.tag == ARCAN_TAG_3DOBJ){
			FL_SET(vobj, FL_FULL3D);
			vobj->order *= -1;
		}

		arcan_vint_attachobject(rv);
	}

	return rv;
}

arcan_errc arcan_video_scaletxcos(arcan_vobj_id id, float sfs, float sft)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (!vobj->txcos){
		vobj->txcos = arcan_alloc_mem(8 * sizeof(float),
			ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_SIMD);
		if (!vobj->txcos)
			return ARCAN_ERRC_OUT_OF_SPACE;

		arcan_vint_defaultmapping(vobj->txcos, 1.0, 1.0);
	}

	vobj->txcos[0] *= sfs;
	vobj->txcos[1] *= sft;
	vobj->txcos[2] *= sfs;
	vobj->txcos[3] *= sft;
	vobj->txcos[4] *= sfs;
	vobj->txcos[5] *= sft;
	vobj->txcos[6] *= sfs;
	vobj->txcos[7] *= sft;

	FLAG_DIRTY(vobj);
	return ARCAN_OK;
}


arcan_errc arcan_video_forceblend(arcan_vobj_id id, enum arcan_blendfunc mode)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id > 0){
		vobj->blendmode = mode;
		FLAG_DIRTY(vobj);
		rv = ARCAN_OK;
	}

	return rv;
}

unsigned short arcan_video_getzv(arcan_vobj_id id)
{
	unsigned short rv = 0;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj){
		rv = vobj->order;
	}

	return rv;
}

/* no parent resolve performed */
static arcan_errc update_zv(arcan_vobject* vobj, int newzv)
{
	struct rendertarget* owner = vobj->owner;

	if (!owner)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	newzv = newzv < 0 ? 0 : newzv;
	newzv = newzv > 65535 ? 65535 : newzv;

/*
 * attach also works like an insertion sort where
 * the insertion criterion is <= order, to aid dynamic
 * corruption checks, this could be further optimized
 * by using the fact that we're simply "sliding" in the
 * same chain.
 */
	int oldv = vobj->order;
	detach_fromtarget(owner, vobj);
	vobj->order = newzv;

	if (vobj->feed.state.tag == ARCAN_TAG_3DOBJ)
		vobj->order *= -1;

	attach_object(owner, vobj);

/*
 * unfortunately, we need to do this recursively AND
 * take account for the fact that we may relatively speaking shrink
 * the distance between our orderv vs. parent
 */
	for (size_t i = 0; i < vobj->childslots; i++)
		if (vobj->children[i] && FL_TEST(vobj->children[i], FL_ORDOFS)){
			int distance = vobj->children[i]->order - oldv;
			update_zv(vobj->children[i], newzv + distance);
		}

	return ARCAN_OK;
}

/* change zval (see arcan_video_addobject) for a particular object.
 * return value is an error code */
arcan_errc arcan_video_setzv(arcan_vobj_id id, int newzv)
{
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

/* calculate order relative to parent if that's toggled
 * clip to 16bit US and ignore if the parent is a 3dobj */
	if (FL_TEST(vobj, FL_ORDOFS))
		newzv = newzv + vobj->parent->order;

/*
 * Then propagate to any child that might've inherited
 */
	update_zv(vobj, newzv);

	return ARCAN_OK;
}

/* forcibly kill videoobject after n cycles,
 * which will reset a counter that upon expiration invocates
 * arcan_video_deleteobject(arcan_vobj_id id)
 */
arcan_errc arcan_video_setlife(arcan_vobj_id id, unsigned lifetime)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id > 0){
		if (lifetime == 0){
			vobj->lifetime = -1;
		}
		else
/* make sure the object is flagged as alive */
			vobj->mask |= MASK_LIVING;

		vobj->lifetime = lifetime;
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_video_zaptransform(
	arcan_vobj_id id, int mask, unsigned left[4])
{
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	surface_transform* current = vobj->transform;
	surface_transform** last = &vobj->transform;

	unsigned ct = arcan_video_display.c_ticks;

/* only set if the data is actually needed */
	if (left){
		if (current){
			left[0] = ct > current->blend.endt ? 0 : current->blend.endt - ct;
			left[1] = ct > current->move.endt ? 0 : current->move.endt - ct;
			left[2] = ct > current->rotate.endt ? 0 : current->rotate.endt - ct;
			left[3] = ct > current->scale.endt ? 0 : current->scale.endt - ct;
		}
		else{
			left[0] = left[1] = left[2] = left[3] = 4;
		}
	}

/* if we don't set a mask, zap the entire chain - otherwise walk the chain,
 * remove the slots that match the mask, and then drop ones that has become empty */
	if (!mask)
		mask = ~mask;

	while (current){
		current->blend.endt  *= !!!(mask & MASK_OPACITY); /* int to 0|1, then invert result */
		current->move.endt   *= !!!(mask & MASK_POSITION);
		current->rotate.endt *= !!!(mask & MASK_ORIENTATION);
		current->scale.endt  *= !!!(mask & MASK_SCALE);

		current->blend.startt  *= !!!(mask & MASK_OPACITY); /* int to 0|1, then invert result */
		current->move.startt   *= !!!(mask & MASK_POSITION);
		current->rotate.startt *= !!!(mask & MASK_ORIENTATION);
		current->scale.startt  *= !!!(mask & MASK_SCALE);

/* any transform alive? then don't free the transform */
		bool used =
			!!(current->blend.endt | current->move.endt |
			current->rotate.endt | current->scale.endt);

		if (!used){

/* relink previous valid and point to next, this might be null but since wain
 * from &vobj->transform that will reset the head as well so no weird aliasing */
			if (*last == current)
				*last = current->next;

			surface_transform* next = current->next;
			arcan_mem_free(current);
			current = next;
		}
		else {
			last = &current->next;
			current = current->next;
		}
	}

	invalidate_cache(vobj);
	return ARCAN_OK;
}

arcan_errc arcan_video_tagtransform(arcan_vobj_id id,
	intptr_t tag, enum arcan_transform_mask mask)
{
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (!vobj->transform)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	if ((mask & ~MASK_TRANSFORMS) > 0)
		return ARCAN_ERRC_BAD_ARGUMENT;

	surface_transform* current = vobj->transform;

	while(current && mask > 0){
		if ((mask & MASK_POSITION) > 0){
			if (current->move.startt &&
			(!current->next || !current->next->move.startt)){
				mask &= ~MASK_POSITION;
				current->move.tag = tag;
			}
		}

		if ((mask & MASK_SCALE) > 0){
			if (current->scale.startt &&
			(!current->next || !current->next->scale.startt)){
				mask &= ~MASK_SCALE;
				current->scale.tag = tag;
			}
		}

		if ((mask & MASK_ORIENTATION) > 0){
			if (current->rotate.startt &&
			(!current->next || !current->next->rotate.startt)){
				mask &= ~MASK_ORIENTATION;
				current->rotate.tag = tag;
			}
		}

		if ((mask & MASK_OPACITY) > 0){
			if (current->blend.startt &&
			(!current->next || !current->next->blend.startt)){
				mask &= ~MASK_OPACITY;
				current->blend.tag = tag;
			}
		}

		current = current->next;
	}

	return ARCAN_OK;
}

static void emit_transform_event(arcan_vobj_id src,
	enum arcan_transform_mask slot, intptr_t tag)
{
	arcan_event_enqueue(arcan_event_defaultctx(),
		&(struct arcan_event){
			.category = EVENT_VIDEO,
			.vid.kind = EVENT_VIDEO_CHAIN_OVER,
			.vid.data = tag,
			.vid.source = src,
			.vid.slot = slot
		}
	);
}

arcan_errc arcan_video_instanttransform(
	arcan_vobj_id id, int mask, enum tag_transform_methods method)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (!vobj->transform)
		return ARCAN_OK;

/* step through the list of transforms */
	surface_transform* current = vobj->transform;

/* determine if any tag events should be produced or not, and if so, if we want
 * all of them, or only the last. The last case is more complicated as there
 * might be a ->next allocated for another transform so also need to check the
 * time */
	if (!mask)
		mask = ~mask;

	bool at_last;
	struct surface_transform** last = &vobj->transform;

	while (current){
		if (current->move.startt && (mask & MASK_POSITION)){
			vobj->current.position = current->move.endp;
				current->move.startt = 0;

			at_last = (method == TAG_TRANSFORM_LAST) &&
				!( current->next && current->next->move.startt );

			if (current->move.tag && (method == TAG_TRANSFORM_ALL || at_last))
				emit_transform_event(vobj->cellid, MASK_POSITION, current->move.tag);
		}

		if (current->blend.startt && (mask & MASK_OPACITY)){
			vobj->current.opa = current->blend.endopa;
			current->blend.startt = 0;

			at_last = (method == TAG_TRANSFORM_LAST) &&
				!( current->next && current->next->blend.startt );

			if (current->blend.tag && (method == TAG_TRANSFORM_ALL || at_last))
				emit_transform_event(vobj->cellid, MASK_OPACITY, current->blend.tag);
		}

		if (current->rotate.startt && (mask & MASK_ORIENTATION)){
			vobj->current.rotation = current->rotate.endo;
			current->rotate.startt = 0;

			at_last = (method == TAG_TRANSFORM_LAST) &&
				!( current->next && current->next->rotate.startt );

			if (current->rotate.tag && (method == TAG_TRANSFORM_LAST || at_last))
				emit_transform_event(
					vobj->cellid, MASK_ORIENTATION, current->rotate.tag);
		}

		if (current->scale.startt && (mask & MASK_SCALE)){
			vobj->current.scale = current->scale.endd;
			current->scale.startt = 0;

			at_last = (method == TAG_TRANSFORM_LAST) &&
				!( current->next && current->next->scale.startt );

			if (current->scale.tag && (method == TAG_TRANSFORM_LAST || at_last))
				emit_transform_event(vobj->cellid, MASK_SCALE, current->scale.tag);
		}

/* see also: zaptransform */
		bool used =
			!!(current->blend.startt | current->move.startt |
			current->rotate.startt | current->scale.startt);

		if (!used){
			if (*last == current){
				*last = current->next;
			}

			if (vobj->transform == current)
				vobj->transform = current->next;

			surface_transform* tokill = current;
			current = current->next;
			arcan_mem_free(tokill);
		}
		else {
			last = &current->next;
			current = current->next;
		}
	}

	invalidate_cache(vobj);
	return ARCAN_OK;
}

arcan_errc arcan_video_objecttexmode(arcan_vobj_id id,
	enum arcan_vtex_mode modes, enum arcan_vtex_mode modet)
{
	arcan_vobject* src = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (src){
		src->vstore->txu = modes;
		src->vstore->txv = modet;
		agp_update_vstore(src->vstore, false);
		FLAG_DIRTY(src);
	}

	return rv;
}

arcan_errc arcan_video_objectfilter(arcan_vobj_id id,
	enum arcan_vfilter_mode mode)
{
	arcan_vobject* src = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

/* fake an upload with disabled filteroptions */
	if (src){
		src->vstore->filtermode = mode;
		agp_update_vstore(src->vstore, false);
	}

	return rv;
}

arcan_errc arcan_video_transformcycle(arcan_vobj_id sid, bool flag)
{
	arcan_vobject* src = arcan_video_getobject(sid);
	if (!src)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (flag)
		FL_SET(src, FL_TCYCLE);
	else
		FL_CLEAR(src, FL_TCYCLE);

	return ARCAN_OK;
}

arcan_errc arcan_video_copyprops ( arcan_vobj_id sid, arcan_vobj_id did )
{
	if (sid == did)
		return ARCAN_OK;

	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	arcan_vobject* src = arcan_video_getobject(sid);
	arcan_vobject* dst = arcan_video_getobject(did);

	if (src && dst){
		surface_properties newprop;
		arcan_resolve_vidprop(src, 0.0, &newprop);

		dst->current = newprop;
/* we need to translate scale */
		if (newprop.scale.x > 0 && newprop.scale.y > 0){
			int dstw = newprop.scale.x * src->origw;
			int dsth = newprop.scale.y * src->origh;

			dst->current.scale.x = (float) dstw / (float) dst->origw;
			dst->current.scale.y = (float) dsth / (float) dst->origh;
		}

		rv = ARCAN_OK;
	}

	return rv;
}

arcan_errc arcan_video_copytransform(arcan_vobj_id sid, arcan_vobj_id did)
{
	arcan_vobject* src, (* dst);

	src = arcan_video_getobject(sid);
	dst = arcan_video_getobject(did);

	if (!src || !dst || src == dst)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

/* remove what's happening in destination, move
 * pointers from source to dest and done. */
	memcpy(&dst->current, &src->current, sizeof(surface_properties));

	arcan_video_zaptransform(did, 0, NULL);
	dst->transform = dup_chain(src->transform);
	update_zv(dst, src->order);

	invalidate_cache(dst);

/* in order to NOT break resizefeed etc. this copy actually
 * requires a modification of the transformation
 * chain, as scale is relative origw? */
	dst->origw = src->origw;
	dst->origh = src->origh;

	return ARCAN_OK;
}

/*
 * quick set and run from gdb or update_object
 */
#ifdef DUMP_TRANSFORM
static void dump_chain(surface_transform* base)
{
	for (int i = 0; base; i++, base = base->next){
		printf("[transform (%"PRIxPTR") @%d]\n", (uintptr_t)base, i);
		printf("\trotate (%zu / %zu)\n\t\t x: %.2f->%.2f y: %.2f->%.2f z: %.2f->%.2f\n",
			(size_t) base->rotate.startt, (size_t) base->rotate.endt,
			base->rotate.starto.roll, base->rotate.endo.roll,
			base->rotate.starto.pitch, base->rotate.endo.pitch,
			base->rotate.starto.yaw, base->rotate.endo.yaw
		);
		printf("\tscale (%zu / %zu)\n\t\t x: %2.f->%.2f y: %.2f->%.2f z: %.2f->%.2f\n",
			(size_t) base->scale.startt, (size_t) base->scale.endt,
			base->scale.startd.x, base->scale.endd.x,
			base->scale.startd.y, base->scale.endd.y,
			base->scale.startd.z, base->scale.endd.z
		);
		printf("\tblend (%zu / %zu)\n\t\t opacity: %2.f->%.2f\n",
			(size_t) base->blend.startt, (size_t) base->blend.endt,
			base->blend.startopa, base->blend.endopa
		);
		printf("\tmove (%zu / %zu)\n\t\t x: %2.f->%.2f y: %.2f->%.2f z: %.2f->%.2f\n",
			(size_t) base->move.startt, (size_t) base->move.endt,
			base->move.startp.x, base->move.endp.x,
			base->move.startp.y, base->move.endp.y,
			base->move.startp.z, base->move.endp.z
		);
	}
}
#endif

arcan_errc arcan_video_transfertransform(arcan_vobj_id sid, arcan_vobj_id did)
{
	arcan_errc rv = arcan_video_copytransform(sid, did);

	if (rv == ARCAN_OK){
		arcan_vobject* src = arcan_video_getobject(sid);
		arcan_video_zaptransform(sid, 0, NULL);
		src->transform = NULL;
	}

	return rv;
}

/* remove a video object that is also a rendertarget (FBO) output */
static void drop_rtarget(arcan_vobject* vobj)
{
/* check if vobj is indeed a rendertarget */
	struct rendertarget* dst = NULL;
	int cascade_c = 0;
	arcan_vobject** pool;

	unsigned dstind;

/* linear search for the vobj among rendertargets */
	for (dstind = 0; dstind < current_context->n_rtargets; dstind++){
		if (current_context->rtargets[dstind].color == vobj){
			dst = &current_context->rtargets[dstind];
			break;
		}
	}

	if (!dst)
		return;

/* make sure to drop references from any linktarget */
	for (size_t i = 0; i < current_context->n_rtargets; i++){
		if (i == dstind)
			continue;

		if (current_context->rtargets[dstind].link == dst)
			current_context->rtargets[dstind].link = NULL;
	}

	if (current_context->attachment == dst)
		current_context->attachment = NULL;

/* found one, disassociate with the context */
	current_context->n_rtargets--;
	if (current_context->n_rtargets < 0){
		arcan_warning(
			"[bug] rtgt count (%d) < 0\n", current_context->n_rtargets);
	}

	if (vobj->tracetag)
		arcan_warning("(arcan_video_deleteobject(reference-pass) -- "
			"remove rendertarget (%s)\n", vobj->tracetag);

/* kill GPU resources */
	if (dst->art)
		agp_drop_rendertarget(dst->art);
	dst->art = NULL;

/* create a temporary copy of all the elements in the rendertarget,
 * this will be a noop for a linked rendertarget */
	arcan_vobject_litem* current = dst->first;
	size_t pool_sz = (dst->color->extrefc.attachments) * sizeof(arcan_vobject*);
	pool = arcan_alloc_mem(pool_sz, ARCAN_MEM_VSTRUCT, ARCAN_MEM_TEMPORARY,
		ARCAN_MEMALIGN_NATURAL);

/* note the contents of the rendertarget as "detached" from the source vobj */
	while (current){
		arcan_vobject* base = current->elem;
		pool[cascade_c++] = base;

/* rtarget has one less attachment, and base is attached to one less */
		vobj->extrefc.attachments--;
		base->extrefc.attachments--;

		trace("(deleteobject::drop_rtarget) remove attached (%d:%s) from"
			"	rendertarget (%d:%s), left: %d:%d\n",
			current->elem->cellid, video_tracetag(current->elem), vobj->cellid,
			video_tracetag(vobj),vobj->extrefc.attachments,base->extrefc.attachments);

		if (base->extrefc.attachments < 0){
			arcan_warning(
				"[bug] obj-attach-refc (%d) < 0\n", base->extrefc.attachments);
		}

		if (vobj->extrefc.attachments < 0){
			arcan_warning(
				"[bug] rtgt-ext-refc (%d) < 0\n", vobj->extrefc.attachments);
		}

/* cleanup and unlink before moving on */
		arcan_vobject_litem* last = current;
		current->elem = (arcan_vobject*) 0xfacefeed;
		current = current->next;
		last->next = (struct arcan_vobject_litem*) 0xdeadbeef;
		arcan_mem_free(last);
	}

/* compact the context array of rendertargets */
	if (dstind+1 < RENDERTARGET_LIMIT)
		memmove(&current_context->rtargets[dstind],
			&current_context->rtargets[dstind+1],
			sizeof(struct rendertarget) * (RENDERTARGET_LIMIT - 1 - dstind));

/* always kill the last element */
	memset(&current_context->rtargets[RENDERTARGET_LIMIT- 1], 0,
		sizeof(struct rendertarget));

/* self-reference gone */
	vobj->extrefc.attachments--;
	trace("(deleteobject::drop_rtarget) remove self reference from "
		"rendertarget (%d:%s)\n", vobj->cellid, video_tracetag(vobj));
	if (vobj->extrefc.attachments != 0){
		arcan_warning("[bug] vobj refc (%d) != 0\n", vobj->extrefc.attachments);
	}

/* sweep the list of rendertarget children, and see if we have the
 * responsibility of cleaning it up */
	for (size_t i = 0; i < cascade_c; i++)
		if (pool[i] && FL_TEST(pool[i], FL_INUSE) &&
		(pool[i]->owner == dst || !FL_TEST(pool[i]->owner, TGTFL_ALIVE))){
			pool[i]->owner = NULL;

/* cascade or push to stdout as new owner */
			if ((pool[i]->mask & MASK_LIVING) > 0)
				arcan_video_deleteobject(pool[i]->cellid);
			else
				attach_object(&current_context->stdoutp, pool[i]);
		}

/* lastly, remove any dangling references/links, converting those rendertargets
 * to normal/empty ones */
	cascade_c = 0;
	for (dstind = 0; dstind < current_context->n_rtargets; dstind++){
		if (current_context->rtargets[dstind].link == dst){
			current_context->rtargets[dstind].link = NULL;
		}
	}

	arcan_mem_free(pool);
}

static void drop_frameset(arcan_vobject* vobj)
{
	if (vobj->frameset){
		for (size_t i = 0; i < vobj->frameset->n_frames; i++)
			arcan_vint_drop_vstore(vobj->frameset->frames[i].frame);

		arcan_mem_free(vobj->frameset->frames);
		vobj->frameset->frames = NULL;

		arcan_mem_free(vobj->frameset);
		vobj->frameset = NULL;
	}
}

/* by far, the most involved and dangerous function in this .o,
 * hence the many safe-guards checks and tracing output,
 * the simplest of objects (just an image or whatnot) should have
 * a minimal cost, with everything going up from there.
 * Things to consider:
 * persistence (existing in multiple stack layers, only allowed to be deleted
 * IF it doesn't exist at a lower layer
 * rendertargets (objects that gets rendered to)
 * links (objects linked to others to be deleted in a cascading fashion)
 *
 * an object can belong to either a parent object (ultimately, WORLD),
 * one or more rendertargets, at the same time,
 * and these deletions should also sustain a full context wipe
 */
arcan_errc arcan_video_deleteobject(arcan_vobj_id id)
{
	arcan_vobject* vobj = arcan_video_getobject(id);

	int cascade_c = 0;

/* some objects can't be deleted */
	if (!vobj || id == ARCAN_VIDEO_WORLDID || id == ARCAN_EID)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

/* when a persist is defined in a lower layer, we know that the lowest layer
 * is the last on to have the persistflag) */
	if (FL_TEST(vobj, FL_PRSIST) &&
		(vcontext_ind > 0 && FL_TEST(
			&vcontext_stack[vcontext_ind - 1].vitems_pool[
			vobj->cellid], FL_PRSIST))
	)
		return ARCAN_ERRC_UNACCEPTED_STATE;

/* step one, disassociate from ALL rendertargets,  */
	detach_fromtarget(&current_context->stdoutp, vobj);
	for (unsigned int i = 0; i < current_context->n_rtargets &&
		vobj->extrefc.attachments; i++)
		detach_fromtarget(&current_context->rtargets[i], vobj);

/* step two, disconnect from parent, WORLD references doesn't count */
	if (vobj->parent && vobj->parent != &current_context->world)
		dropchild(vobj->parent, vobj);

/* vobj might be a rendertarget itself, so detach all its
 * possible members, free FBO/PBO resources etc. */
	drop_rtarget(vobj);
	drop_frameset(vobj);

/* populate a pool of cascade deletions */
	unsigned sum = vobj->extrefc.links;

	arcan_vobject* pool[ (sum + 1) ];

	if (sum)
		memset(pool, 0, sizeof(pool));

/* drop all children, add those that should be deleted to the pool */
	for (size_t i = 0; i < vobj->childslots; i++){
		arcan_vobject* cur = vobj->children[i];
		if (!cur)
			continue;

/* the last constraint should be guaranteed, but safety first */
		if ((cur->mask & MASK_LIVING) > 0 && cascade_c < sum+1)
			pool[cascade_c++] = cur;

		dropchild(vobj, cur);
	}

	arcan_mem_free(vobj->children);
	vobj->childslots = 0;

	current_context->nalive--;

/* time to drop all associated resources */
	arcan_video_zaptransform(id, 0, NULL);
	arcan_mem_free(vobj->txcos);

/* full- object specific clean-up */
	if (vobj->feed.ffunc){
		arcan_ffunc_lookup(vobj->feed.ffunc)(FFUNC_DESTROY,
			0, 0, 0, 0, 0, vobj->feed.state, vobj->cellid);
		vobj->feed.state.ptr = NULL;
		vobj->feed.ffunc = FFUNC_FATAL;
		vobj->feed.state.tag = ARCAN_TAG_NONE;
	}

	if (vobj->feed.state.tag == ARCAN_TAG_ASYNCIMGLD)
		arcan_video_pushasynch(id);

/* video storage, will take care of refcounting in case of shared storage */
	arcan_vint_drop_vstore(vobj->vstore);
	vobj->vstore = NULL;

	if (vobj->extrefc.attachments|vobj->extrefc.links){
		arcan_warning("[BUG] Broken reference counters for expiring objects, "
			"%d, %d, tracetag? (%s)\n", vobj->extrefc.attachments,
			vobj->extrefc.links, vobj->tracetag ? vobj->tracetag : "(NO TAG)"
		);
#ifdef _DEBUG
		abort();
#endif
	}

	arcan_mem_free(vobj->tracetag);
	arcan_mem_free(vobj->alttext);
	arcan_vint_dropshape(vobj);

/* lots of default values are assumed to be 0, so reset the
 * entire object to be sure. will help leak detectors as well */
	memset(vobj, 0, sizeof(arcan_vobject));

	for (size_t i = 0; i < cascade_c; i++){
		if (!pool[i])
			continue;

		trace("(deleteobject) cascade pool entry (%d), %d:%s\n", i, pool[i]->cellid,
			pool[i]->tracetag ? pool[i]->tracetag : "(NO TAG)");

		if (FL_TEST(pool[i], FL_INUSE))
			arcan_video_deleteobject(pool[i]->cellid);
	}

	return ARCAN_OK;
}

arcan_errc arcan_video_override_mapping(arcan_vobj_id id, float* newmapping)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj && id > 0){
		if (vobj->txcos)
			arcan_mem_free(vobj->txcos);

		vobj->txcos = arcan_alloc_fillmem(newmapping,
			sizeof(float) * 8, ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_SIMD);

		rv = ARCAN_OK;
		FLAG_DIRTY(vobj);
	}

	return rv;
}

arcan_errc arcan_video_retrieve_mapping(arcan_vobj_id id, float* dst)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj && dst && id > 0){
		float* sptr = vobj->txcos ?
			vobj->txcos : arcan_video_display.default_txcos;
		memcpy(dst, sptr, sizeof(float) * 8);
		rv = ARCAN_OK;
	}

	return rv;
}

arcan_vobj_id arcan_video_findparent(arcan_vobj_id id, arcan_vobj_id ref)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	if (!vobj)
		return ARCAN_EID;

	if (!vobj->parent || !vobj->parent->owner)
		return ARCAN_EID;

	if (ref != ARCAN_EID){
		while (vobj && vobj->parent){
			vobj = vobj->parent;
			if (ref == vobj->cellid){
				return vobj->cellid;
			}
		}
		return ARCAN_EID;
	}

	return vobj->parent->cellid;
}

arcan_vobj_id arcan_video_findchild(arcan_vobj_id parentid, unsigned ofs)
{
	arcan_vobj_id rv = ARCAN_EID;
	arcan_vobject* vobj = arcan_video_getobject(parentid);

	if (!vobj)
		return rv;

	for (size_t i = 0; i < vobj->childslots; i++){
		if (vobj->children[i]){
			if (ofs > 0)
				ofs--;
			else
				return vobj->children[i]->cellid;
		}
	}

	return rv;
}

static bool recsweep(arcan_vobject* base, arcan_vobject* match, int limit)
{
	if (base == NULL || (limit != -1 && limit-- <= 0))
		return false;

	if (base == match)
		return true;

	for (size_t i = 0; i < base->childslots; i++)
		if (recsweep(base->children[i], match, limit))
			return true;

	return false;
}

bool arcan_video_isdescendant(arcan_vobj_id vid,
	arcan_vobj_id parent, int limit)
{
	arcan_vobject* base = arcan_video_getobject(parent);
	arcan_vobject* match = arcan_video_getobject(vid);

	if (base== NULL || match == NULL)
		return false;

	return recsweep(base, match, limit);
}

arcan_errc arcan_video_objectrotate(arcan_vobj_id id,
	float ang, arcan_tickv time)
{
	return arcan_video_objectrotate3d(id, ang, 0.0, 0.0, time);
}

arcan_errc arcan_video_objectrotate3d(arcan_vobj_id id,
	float roll, float pitch, float yaw, arcan_tickv tv)
{
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	invalidate_cache(vobj);

/* clear chains for rotate attribute previous rotate objects */
	if (tv == 0){
		swipe_chain(vobj->transform, offsetof(surface_transform, rotate),
			sizeof(struct transf_rotate));
		vobj->current.rotation.roll  = roll;
		vobj->current.rotation.pitch = pitch;
		vobj->current.rotation.yaw   = yaw;
		vobj->current.rotation.quaternion = build_quat_taitbryan(roll,pitch,yaw);

		return ARCAN_OK;
	}

	surface_orientation bv  = vobj->current.rotation;
	surface_transform* base = vobj->transform;
	surface_transform* last = base;

/* figure out the starting angle */
	while (base && base->rotate.startt){
		bv = base->rotate.endo;

		last = base;
		base = base->next;
	}

	if (!base){
		if (last)
			base = last->next = arcan_alloc_mem(sizeof(surface_transform),
							ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
		else
			base = last = arcan_alloc_mem(sizeof(surface_transform),
				ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
	}

	if (!vobj->transform)
		vobj->transform = base;

	base->rotate.startt = last->rotate.endt < arcan_video_display.c_ticks ?
		arcan_video_display.c_ticks : last->rotate.endt;
	base->rotate.endt   = base->rotate.startt + tv;
	base->rotate.starto = bv;

	base->rotate.endo.roll  = roll;
	base->rotate.endo.pitch = pitch;
	base->rotate.endo.yaw   = yaw;
	base->rotate.endo.quaternion = build_quat_taitbryan(roll, pitch, yaw);
	if (vobj->owner)
		vobj->owner->transfc++;

	base->rotate.interp = (fabsf(bv.roll - roll) > 180.0 ||
		fabsf(bv.pitch - pitch) > 180.0 || fabsf(bv.yaw - yaw) > 180.0) ?
		nlerp_quat180 : nlerp_quat360;

	return ARCAN_OK;
}

arcan_errc arcan_video_allocframes(arcan_vobj_id id,
	unsigned char capacity, enum arcan_framemode mode)
{
	arcan_vobject* target = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (!target)
		return rv;

/* similar restrictions as with sharestore */
	if (target->vstore->txmapped != TXSTATE_TEX2D)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	if (FL_TEST(target, FL_PRSIST))
		return ARCAN_ERRC_CLONE_NOT_PERMITTED;

/* special case, de-allocate */
	if (capacity <= 1){
		drop_frameset(target);
		return ARCAN_OK;
	}

/* only permit framesets to grow */
	if (target->frameset){
		if (target->frameset->n_frames > capacity)
			return ARCAN_ERRC_UNACCEPTED_STATE;
	}
	else
		target->frameset = arcan_alloc_mem(sizeof(struct vobject_frameset),
			ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

	target->frameset->n_frames = capacity;
	target->frameset->frames = arcan_alloc_mem(
			sizeof(struct frameset_store) * capacity,
			ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL
	);

	for (size_t i = 0; i < capacity; i++){
		target->frameset->frames[i].frame = target->vstore;
		arcan_vint_defaultmapping(target->frameset->frames[i].txcos, 1.0, 1.0);

		target->vstore->refcount++;
	}

	target->frameset->mode = mode;

	return ARCAN_OK;
}

arcan_errc arcan_video_origoshift(arcan_vobj_id id,
	float sx, float sy, float sz)
{
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	invalidate_cache(vobj);
	FL_SET(vobj, FL_ORDOFS);
	vobj->origo_ofs.x = sx;
	vobj->origo_ofs.y = sy;
	vobj->origo_ofs.z = sz;

	return ARCAN_OK;
}

/* alter object opacity, range 0..1 */
arcan_errc arcan_video_objectopacity(arcan_vobj_id id,
	float opa, unsigned int tv)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);
	opa = CLAMP(opa, 0.0, 1.0);

	if (vobj){
		rv = ARCAN_OK;
		invalidate_cache(vobj);

		/* clear chains for rotate attribute
		 * if time is set to ovverride and be immediate */
		if (tv == 0){
			swipe_chain(vobj->transform, offsetof(surface_transform, blend),
				sizeof(struct transf_blend));
			vobj->current.opa = opa;
		}
		else { /* find endpoint to attach at */
			float bv = vobj->current.opa;

			surface_transform* base = vobj->transform;
			surface_transform* last = base;

			while (base && base->blend.startt){
				bv = base->blend.endopa;
				last = base;
				base = base->next;
			}

			if (!base){
				if (last)
					base = last->next =
						arcan_alloc_mem(sizeof(surface_transform), ARCAN_MEM_VSTRUCT,
							ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
				else
					base = last =
						arcan_alloc_mem(sizeof(surface_transform), ARCAN_MEM_VSTRUCT,
							ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
			}

			if (!vobj->transform)
				vobj->transform = base;

			if (vobj->owner)
				vobj->owner->transfc++;

			base->blend.startt = last->blend.endt < arcan_video_display.c_ticks ?
				arcan_video_display.c_ticks : last->blend.endt;
			base->blend.endt = base->blend.startt + tv;
			base->blend.startopa = bv;
			base->blend.endopa = opa + EPSILON;
			base->blend.interp = ARCAN_VINTER_LINEAR;
		}
	}

	return rv;
}

arcan_errc arcan_video_blendinterp(arcan_vobj_id id, enum arcan_vinterp inter)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (!vobj->transform)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	surface_transform* base = vobj->transform;

	while (base && base->blend.startt &&
		base->next && base->next->blend.startt)
			base = base->next;

	assert(base);
	base->blend.interp = inter;

	return ARCAN_OK;
}

arcan_errc arcan_video_scaleinterp(arcan_vobj_id id, enum arcan_vinterp inter)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (!vobj->transform)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	surface_transform* base = vobj->transform;

	while (base && base->scale.startt &&
		base->next && base->next->scale.startt)
			base = base->next;

	assert(base);
	base->scale.interp = inter;

	return ARCAN_OK;
}

arcan_errc arcan_video_moveinterp(arcan_vobj_id id, enum arcan_vinterp inter)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (!vobj->transform)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	surface_transform* base = vobj->transform;

	while (base && base->move.startt &&
		base->next && base->next->move.startt)
			base = base->next;

	assert(base);
	base->move.interp = inter;

	return ARCAN_OK;
}

/* linear transition from current position to a new desired position,
 * if time is 0 the move will be instantaneous (and not generate an event)
 * otherwise time denotes how many ticks it should take to move the object
 * from its start position to it's final.
 * An event will in this case be generated */
arcan_errc arcan_video_objectmove(arcan_vobj_id id, float newx,
	float newy, float newz, unsigned int tv)
{
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	invalidate_cache(vobj);

/* clear chains for rotate attribute
 * if time is set to ovverride and be immediate */
	if (tv == 0){
		swipe_chain(vobj->transform, offsetof(surface_transform, move),
			sizeof(struct transf_move));
		vobj->current.position.x = newx;
		vobj->current.position.y = newy;
		vobj->current.position.z = newz;
		return ARCAN_OK;
	}

/* find endpoint to attach at */
	surface_transform* base = vobj->transform;
	surface_transform* last = base;

/* figure out the coordinates which the transformation is chained to */
	point bwp = vobj->current.position;

	while (base && base->move.startt){
		bwp = base->move.endp;

		last = base;
		base = base->next;
	}

	if (!base){
		if (last)
			base = last->next =
				arcan_alloc_mem(sizeof(surface_transform), ARCAN_MEM_VSTRUCT,
					ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
		else
			base = last =
				arcan_alloc_mem(sizeof(surface_transform), ARCAN_MEM_VSTRUCT,
					ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
	}

	point newp = {newx, newy, newz};

	if (!vobj->transform)
		vobj->transform = base;

	base->move.startt = last->move.endt < arcan_video_display.c_ticks ?
		arcan_video_display.c_ticks : last->move.endt;
	base->move.endt   = base->move.startt + tv;
	base->move.interp = ARCAN_VINTER_LINEAR;
	base->move.startp = bwp;
	base->move.endp   = newp;
	if (vobj->owner)
		vobj->owner->transfc++;

	return ARCAN_OK;
}

/* scale the video object to match neww and newh, with stepx or
 * stepy at 0 it will be instantaneous,
 * otherwise it will move at stepx % of delta-size each tick
 * return value is an errorcode, run through char* arcan_verror(int8_t) */
arcan_errc arcan_video_objectscale(arcan_vobj_id id, float wf,
	float hf, float df, unsigned tv)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj){
		const int immediately = 0;
		rv = ARCAN_OK;
		invalidate_cache(vobj);

		if (tv == immediately){
			swipe_chain(vobj->transform, offsetof(surface_transform, scale),
				sizeof(struct transf_scale));

			vobj->current.scale.x = wf;
			vobj->current.scale.y = hf;
			vobj->current.scale.z = df;
		}
		else {
			surface_transform* base = vobj->transform;
			surface_transform* last = base;

/* figure out the coordinates which the transformation is chained to */
			scalefactor bs = vobj->current.scale;

			while (base && base->scale.startt){
				bs = base->scale.endd;

				last = base;
				base = base->next;
			}

			if (!base){
				if (last)
					base = last->next = arcan_alloc_mem(sizeof(surface_transform),
						ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
				else
					base = last = arcan_alloc_mem(sizeof(surface_transform),
						ARCAN_MEM_VSTRUCT, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
			}

			if (!vobj->transform)
				vobj->transform = base;

			base->scale.startt = last->scale.endt < arcan_video_display.c_ticks ?
				arcan_video_display.c_ticks : last->scale.endt;
			base->scale.endt = base->scale.startt + tv;
			base->scale.interp = ARCAN_VINTER_LINEAR;
			base->scale.startd = bs;
			base->scale.endd.x = wf;
			base->scale.endd.y = hf;
			base->scale.endd.z = df;

			if (vobj->owner)
				vobj->owner->transfc++;
		}
	}

	return rv;
}

/*
 * fill out vertices / txcos, return number of elements to draw
 */
static struct agp_mesh_store tesselate_2d(size_t n_s, size_t n_t)
{
	struct agp_mesh_store res = {
		.depth_func = AGP_DEPTH_LESS
	};

	float step_s = 2.0 / (n_s-1);
	float step_t = 2.0 / (n_t-1);

/* use same buffer for both vertices and txcos, can't reuse the same values
 * though initially similar, the user might want to modify */
	res.shared_buffer_sz = sizeof(float) * n_s * n_t * 4;
	void* sbuf = arcan_alloc_mem(res.shared_buffer_sz,
		ARCAN_MEM_MODELDATA, ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE);
	res.shared_buffer = (uint8_t*) sbuf;
	float* vertices = sbuf;
	float* txcos = &vertices[n_s*n_t*2];

	if (!vertices)
		return res;

	unsigned* indices = arcan_alloc_mem(sizeof(unsigned)*(n_s-1)*(n_t-1)*6,
		ARCAN_MEM_MODELDATA, ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE);

	if (!indices){
		arcan_mem_free(vertices);
		return res;
	}

/* populate txco/vertices */
	for (size_t y = 0; y < n_t; y++){
		for (size_t x = 0; x < n_s; x++){
			size_t ofs = (y * n_s + x) * 2;
			vertices[ofs + 0] = (float)x * step_s - 1.0;
			vertices[ofs + 1] = (float)y * step_t - 1.0;
			txcos[ofs + 0] = (float)x / (float)n_s;
			txcos[ofs + 1] = (float)y / (float)n_t;
		}
	}

/* get the indices */
	size_t ofs = 0;
	#define GETVERT(X,Y)( ( (X) * n_s) + Y)
	for (size_t y = 0; y < n_t-1; y++)
		for (size_t x = 0; x < n_s-1; x++){
		indices[ofs++] = GETVERT(x, y);
		indices[ofs++] = GETVERT(x, y+1);
		indices[ofs++] = GETVERT(x+1, y+1);
		indices[ofs++] = GETVERT(x, y);
		indices[ofs++] = GETVERT(x+1, y+1);
		indices[ofs++] = GETVERT(x+1, y);
	}

	res.verts = vertices;
	res.txcos = txcos;
	res.indices = indices;
	res.n_vertices = n_s * n_t;
	res.vertex_size = 2;
	res.n_indices = (n_s-1) * (n_t-1) * 6;
	res.type = AGP_MESH_TRISOUP;

	return res;
}

arcan_errc arcan_video_defineshape(arcan_vobj_id dst,
	size_t n_s, size_t n_t, struct agp_mesh_store** store, bool depth)
{
	arcan_vobject* vobj = arcan_video_getobject(dst);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	if (!vobj){
		if (store)
			*store = NULL;
		return ARCAN_ERRC_NO_SUCH_OBJECT;
	}

	if (n_s == 0 || n_t == 0){
		if (store)
			*store = vobj->shape;
		return ARCAN_OK;
	}

	if (vobj->shape || n_s == 1 || n_t == 1){
		agp_drop_mesh(vobj->shape);
		if (n_s == 1 || n_t == 1){
			vobj->shape = NULL;
			if (store)
				*store = vobj->shape;
			return ARCAN_OK;
		}
	}
	else
		vobj->shape = arcan_alloc_mem(sizeof(struct agp_mesh_store),
			ARCAN_MEM_MODELDATA, ARCAN_MEM_BZERO |
			ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_NATURAL
		);

	if (!vobj->shape){
		if (store)
			*store = NULL;
		return ARCAN_ERRC_OUT_OF_SPACE;
	}

/* we now KNOW that s > 1 and t > 1, that shape is valid -
 * time to build the mesh */
	struct agp_mesh_store ns = tesselate_2d(n_s, n_t);
	if (!ns.verts){
		if (vobj->shape){
			arcan_vint_dropshape(vobj);
		}
		if (store)
			*store = NULL;
		return ARCAN_ERRC_OUT_OF_SPACE;
	}

	*(vobj->shape) = ns;
	vobj->shape->nodepth = depth;

/* dirty- flag here if we support meshing into VBO */
	if (store)
		*store = vobj->shape;
	return ARCAN_OK;
}

/* called whenever a cell in update has a time that reaches 0 */
static void compact_transformation(arcan_vobject* base,
	unsigned int ofs, unsigned int count)
{
	if (!base || !base->transform) return;

	surface_transform* last = NULL;
	surface_transform* work = base->transform;
/* copy the next transformation */

	while (work && work->next){
		assert(work != work->next);
		memcpy((char*)(work) + ofs, (char*)(work->next) + ofs, count);
		last = work;
		work = work->next;
	}

/* reset the last one */
	memset((char*) work + ofs, 0, count);

/* if it is now empty, free and delink */
	if (!(work->blend.startt | work->scale.startt |
		work->move.startt | work->rotate.startt )){

		arcan_mem_free(work);
		if (last)
			last->next = NULL;
		else
			base->transform = NULL;
	}
}

arcan_errc arcan_video_setprogram(arcan_vobj_id id, agp_shader_id shid)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj && agp_shader_valid(shid)){
		FLAG_DIRTY(vobj);
		vobj->program = shid;
		rv = ARCAN_OK;
	}

	return rv;
}

static inline float lerp_fract(float startt, float endt, float ts)
{
	float rv = (EPSILON + (ts - startt)) / (endt - startt);
	rv = rv > 1.0 ? 1.0 : rv;
	return rv;
}

/* This is run for each active rendertarget and once for each object by
 * generating a cookie (stamp) so that objects that exist in multiple
 * rendertargets do not get updated several times.
 *
 * It returns the number of transforms applied to the object. */
static int update_object(arcan_vobject* ci, unsigned long long stamp)
{
	int upd = 0;

/* update parent if this has not already been updated this cycle */
	if (ci->last_updated < stamp &&
		ci->parent && ci->parent != &current_context->world &&
		ci->parent->last_updated != stamp){
		upd += update_object(ci->parent, stamp);
	}

	ci->last_updated = stamp;

	if (!ci->transform)
		return upd;

	if (ci->transform->blend.startt){
		upd++;
		float fract = lerp_fract(ci->transform->blend.startt,
			ci->transform->blend.endt, stamp);

		ci->current.opa = lut_interp_1d[ci->transform->blend.interp](
			ci->transform->blend.startopa,
			ci->transform->blend.endopa, fract
		);

		if (fract > 1.0-EPSILON){
			ci->current.opa = ci->transform->blend.endopa;

			if (FL_TEST(ci, FL_TCYCLE)){
				arcan_video_objectopacity(ci->cellid, ci->transform->blend.endopa,
					ci->transform->blend.endt - ci->transform->blend.startt);
				if (ci->transform->blend.interp > 0)
					arcan_video_blendinterp(ci->cellid, ci->transform->blend.interp);
			}

			if (ci->transform->blend.tag)
				emit_transform_event(ci->cellid,
					MASK_OPACITY, ci->transform->blend.tag);

			compact_transformation(ci,
				offsetof(surface_transform, blend),
				sizeof(struct transf_blend));
		}
	}

	if (ci->transform && ci->transform->move.startt){
		upd++;
		float fract = lerp_fract(ci->transform->move.startt,
			ci->transform->move.endt, stamp);

		ci->current.position = lut_interp_3d[ci->transform->move.interp](
				ci->transform->move.startp,
				ci->transform->move.endp, fract
			);

		if (fract > 1.0-EPSILON){
			ci->current.position = ci->transform->move.endp;

			if (FL_TEST(ci, FL_TCYCLE)){
				arcan_video_objectmove(ci->cellid,
					ci->transform->move.endp.x,
					ci->transform->move.endp.y,
					ci->transform->move.endp.z,
					ci->transform->move.endt - ci->transform->move.startt
				);

				if (ci->transform->move.interp > 0)
					arcan_video_moveinterp(ci->cellid, ci->transform->move.interp);
			}

			if (ci->transform->move.tag)
				emit_transform_event(ci->cellid,
					MASK_POSITION, ci->transform->move.tag);

			compact_transformation(ci,
				offsetof(surface_transform, move),
				sizeof(struct transf_move));
		}
	}

	if (ci->transform && ci->transform->scale.startt){
		upd++;
		float fract = lerp_fract(ci->transform->scale.startt,
			ci->transform->scale.endt, stamp);
		ci->current.scale = lut_interp_3d[ci->transform->scale.interp](
			ci->transform->scale.startd,
			ci->transform->scale.endd, fract
		);

		if (fract > 1.0-EPSILON){
			ci->current.scale = ci->transform->scale.endd;

			if (FL_TEST(ci, FL_TCYCLE)){
				arcan_video_objectscale(ci->cellid, ci->transform->scale.endd.x,
					ci->transform->scale.endd.y,
					ci->transform->scale.endd.z,
					ci->transform->scale.endt - ci->transform->scale.startt);

				if (ci->transform->scale.interp > 0)
					arcan_video_scaleinterp(ci->cellid, ci->transform->scale.interp);
			}

			if (ci->transform->scale.tag)
				emit_transform_event(ci->cellid, MASK_SCALE, ci->transform->scale.tag);

			compact_transformation(ci,
				offsetof(surface_transform, scale),
				sizeof(struct transf_scale));
		}
	}

	if (ci->transform && ci->transform->rotate.startt){
		upd++;
		float fract = lerp_fract(ci->transform->rotate.startt,
			ci->transform->rotate.endt, stamp);

/* close enough */
		if (fract > 1.0-EPSILON){
			ci->current.rotation = ci->transform->rotate.endo;
			if (FL_TEST(ci, FL_TCYCLE))
				arcan_video_objectrotate3d(ci->cellid,
					ci->transform->rotate.endo.roll,
					ci->transform->rotate.endo.pitch,
					ci->transform->rotate.endo.yaw,
					ci->transform->rotate.endt - ci->transform->rotate.startt
				);

			if (ci->transform->rotate.tag)
				emit_transform_event(ci->cellid,
					MASK_ORIENTATION, ci->transform->rotate.tag);

			compact_transformation(ci,
				offsetof(surface_transform, rotate),
				sizeof(struct transf_rotate));
		}
		else {
			ci->current.rotation.quaternion =
				ci->transform->rotate.interp(
					ci->transform->rotate.starto.quaternion,
					ci->transform->rotate.endo.quaternion, fract
				);
		}
	}

	return upd;
}

static void expire_object(arcan_vobject* obj){
	if (obj->lifetime && --obj->lifetime == 0)
	{
		arcan_event dobjev = {
		.category = EVENT_VIDEO,
		.vid.kind = EVENT_VIDEO_EXPIRE
		};

		dobjev.vid.source = obj->cellid;

#ifdef _DEBUG
		if (obj->tracetag){
			arcan_warning("arcan_event(EXPIRE) -- "
				"traced object expired (%s)\n", obj->tracetag);
		}
#endif

		arcan_event_enqueue(arcan_event_defaultctx(), &dobjev);
	}
}

static inline bool process_counter(
	struct rendertarget* tgt, int* field, int base, float fract)
{
/* manually clocked, do nothing */
	if (0 == base)
		return false;

/* simply decrement the counter and reset it, two dimensions to
 * the clock (tick vs frame), then abs() to convert to counter */
	(*field)--;
	if (*field <= 0){
		*field = abs(base);
		return true;
	}

	return false;
}

static inline void process_readback(struct rendertarget* tgt, float fract)
{
	if (!FL_TEST(tgt, TGTFL_READING) &&
		process_counter(tgt, &tgt->readcnt, tgt->readback, fract)){

/* for handle passing we can go immediately, even though the asynch job
 * might not be done, that's up to the fences tied to the export */
		if (tgt->hwreadback){
			arcan_vobject* vobj = tgt->color;

/* don't check the readback unless the client is ready, should possibly have a
 * timeout for this as well so we don't hold GL resources with an unwilling /
 * broken client, it's a hard tradeoff as streaming video encode might deal
 * well with the dropped frame at this stage, while a variable rate interactive
 * source may lose data */
			arcan_vfunc_cb ffunc = NULL;
			if (vobj->feed.ffunc){
				ffunc = arcan_ffunc_lookup(vobj->feed.ffunc);
				if (FRV_GOTFRAME == ffunc(FFUNC_READBACK_HANDLE,
					NULL, 0, 0, 0, 0, vobj->feed.state, vobj->cellid))
					return;
			}
		}

/* check again as the ffunc might av unset the hwreadback flag */
		if (!tgt->hwreadback){
			agp_request_readback(tgt->color->vstore);
			FL_SET(tgt, TGTFL_READING);
		}
	}
}

/*
 * return number of actual objects that were updated / dirty,
 * move/process/etc. and possibly dispatch draw commands if needed
 */
static int tick_rendertarget(struct rendertarget* tgt)
{
	tgt->transfc = 0;
	arcan_vobject_litem* current = tgt->first;

	while (current){
		arcan_vobject* elem = current->elem;

		arcan_vint_joinasynch(elem, true, false);

		if (elem->last_updated != arcan_video_display.c_ticks)
			tgt->transfc += update_object(elem, arcan_video_display.c_ticks);

		if (elem->feed.ffunc)
			arcan_ffunc_lookup(elem->feed.ffunc)
				(FFUNC_TICK, 0, 0, 0, 0, 0, elem->feed.state, elem->cellid);

/* mode > 0, cycle activate frame every 'n' ticks */
		if (elem->frameset && elem->frameset->mctr != 0){
			elem->frameset->ctr--;
			if (elem->frameset->ctr == 0){
				step_active_frame(elem);
				elem->frameset->ctr = abs( elem->frameset->mctr );
			}
		}

		if ((elem->mask & MASK_LIVING) > 0)
			expire_object(elem);

		current = current->next;
	}

	if (tgt->refresh > 0 && process_counter(tgt,
		&tgt->refreshcnt, tgt->refresh, 0.0)){
		tgt->transfc += process_rendertarget(tgt, 0.0, false);
		tgt->dirtyc = 0;
	}

	if (tgt->readback < 0)
		process_readback(tgt, 0.0);

	return tgt->transfc;
}

unsigned arcan_video_tick(unsigned steps, unsigned* njobs)
{
	if (steps == 0)
		return 0;

	unsigned now = arcan_frametime();
	uint32_t tsd = arcan_video_display.c_ticks;
	arcan_random((void*)&arcan_video_display.cookie, 8);

#ifdef SHADER_TIME_PERIOD
	tsd = tsd % SHADER_TIME_PERIOD;
#endif

	do {
		arcan_video_display.dirty +=
			update_object(&current_context->world, arcan_video_display.c_ticks);

		arcan_video_display.dirty +=
			agp_shader_envv(TIMESTAMP_D, &tsd, sizeof(uint32_t));

		for (size_t i = 0; i < current_context->n_rtargets; i++)
			arcan_video_display.dirty +=
				tick_rendertarget(&current_context->rtargets[i]);

		arcan_video_display.dirty +=
			tick_rendertarget(&current_context->stdoutp);

/*
 * we don't want c_ticks running too high (the tick is monotonic, but not
 * continous) as lots of float operations are relying on this as well, this
 * will cause transformations that are scheduled across the boundary to behave
 * oddly until reset. A fix would be to rebase if that is a problem.
 */
		arcan_video_display.c_ticks =
			(arcan_video_display.c_ticks + 1) % (INT32_MAX / 3);

		steps = steps - 1;
	} while (steps);

	if (njobs)
		*njobs = arcan_video_display.dirty;

	return arcan_frametime() - now;
}

arcan_errc arcan_video_clipto(arcan_vobj_id id, arcan_vobj_id clip_tgt)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	vobj->clip_src = clip_tgt;

	return ARCAN_OK;
}

arcan_errc arcan_video_setclip(arcan_vobj_id id, enum arcan_clipmode mode)
{
	arcan_vobject* vobj = arcan_video_getobject(id);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	vobj->clip = mode;

	return ARCAN_OK;
}

arcan_errc arcan_video_persistobject(arcan_vobj_id id)
{
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (!vobj->frameset &&
		vobj->vstore->refcount == 1 &&
		vobj->parent == &current_context->world){
		FL_SET(vobj, FL_PRSIST);

		return ARCAN_OK;
	}
	else
		return ARCAN_ERRC_UNACCEPTED_STATE;
}

bool arcan_video_visible(arcan_vobj_id id)
{
	bool rv = false;
	arcan_vobject* vobj= arcan_video_getobject(id);

	if (vobj && id > 0)
		return vobj->current.opa > EPSILON;

	return rv;
}

/* take sprops, apply them to the coordinates in vobj with proper
 * masking (or force to ignore mask), store the results in dprops */
static void apply(arcan_vobject* vobj, surface_properties* dprops,
	surface_properties* sprops, float lerp, bool force)
{
	*dprops = vobj->current;

	if (vobj->transform){
		surface_transform* tf = vobj->transform;
		unsigned ct = arcan_video_display.c_ticks;

		if (tf->move.startt)
			dprops->position = lut_interp_3d[tf->move.interp](
				tf->move.startp,
				tf->move.endp,
				lerp_fract(tf->move.startt, tf->move.endt, (float)ct + lerp)
			);

		if (tf->scale.startt)
			dprops->scale = lut_interp_3d[tf->scale.interp](
				tf->scale.startd,
				tf->scale.endd,
				lerp_fract(tf->scale.startt, tf->scale.endt, (float)ct + lerp)
			);

		if (tf->blend.startt)
			dprops->opa = lut_interp_1d[tf->blend.interp](
				tf->blend.startopa,
				tf->blend.endopa,
				lerp_fract(tf->blend.startt, tf->blend.endt, (float)ct + lerp)
			);

		if (tf->rotate.startt){
			dprops->rotation.quaternion = tf->rotate.interp(
				tf->rotate.starto.quaternion, tf->rotate.endo.quaternion,
				lerp_fract(tf->rotate.startt, tf->rotate.endt,
					(float)ct + lerp)
			);

			vector ang = angle_quat(dprops->rotation.quaternion);
			dprops->rotation.roll  = ang.x;
			dprops->rotation.pitch = ang.y;
			dprops->rotation.yaw   = ang.z;
		}

		if (!sprops)
			return;
	}

/* translate to sprops */
	if (force || (vobj->mask & MASK_POSITION) > 0)
		dprops->position = add_vector(dprops->position, sprops->position);

	if (force || (vobj->mask & MASK_ORIENTATION) > 0){
		dprops->rotation.yaw   += sprops->rotation.yaw;
		dprops->rotation.pitch += sprops->rotation.pitch;
		dprops->rotation.roll  += sprops->rotation.roll;
		if (FL_TEST(vobj, FL_FULL3D)){
			dprops->rotation.quaternion = mul_quat(
				sprops->rotation.quaternion, dprops->rotation.quaternion );
		}
	}

	if (force || (vobj->mask & MASK_OPACITY) > 0){
		dprops->opa *= sprops->opa;
	}
}

/*
 * Caching works as follows;
 * Any object that has a parent with an ongoing transformation
 * has its valid_cache property set to false
 * upon changing it to true a copy is made and stored in prop_cache
 * and a resolve- pass is performed with its results stored in prop_matr
 * which is then re-used every rendercall.
 * Queueing a transformation immediately invalidates the cache.
 */
void arcan_resolve_vidprop(
	arcan_vobject* vobj, float lerp, surface_properties* props)
{
	if (vobj->valid_cache)
		*props = vobj->prop_cache;

/* walk the chain up to the parent, resolve recursively - there might be an
 * early out detection here if all transforms are masked though the value of
 * that is questionable without more real-world data */
	else if (vobj->parent && vobj->parent != &current_context->world){
		surface_properties dprop = empty_surface();
		arcan_resolve_vidprop(vobj->parent, lerp, &dprop);

/* now apply the parent chain to ourselves */
		apply(vobj, props, &dprop, lerp, false);

		if (vobj->p_scale){
/* resolve parent scaled size, then our own delta, apply that and then back
 * to object-local scale factor */
			if (vobj->p_scale & SCALEM_WIDTH){
				float pw = vobj->parent->origw * dprop.scale.x;
				float mw_d = vobj->origw + ((vobj->origw * props->scale.x) - vobj->origw);
				pw += mw_d - 1;
				props->scale.x = pw / (float)vobj->origw;
			}
			if (vobj->p_scale & SCALEM_HEIGHT){
				float ph = vobj->parent->origh * dprop.scale.y;
				float mh_d = vobj->origh + ((vobj->origh * props->scale.y) - vobj->origh);
				ph += mh_d - 1;
				props->scale.y = ph / (float)vobj->origh;
			}
		}

/* anchor ignores normal position mask */
		switch(vobj->p_anchor){
		case ANCHORP_UR:
			props->position.x += (float)vobj->parent->origw * dprop.scale.x;
		break;
		case ANCHORP_LR:
			props->position.y += (float)vobj->parent->origh * dprop.scale.y;
			props->position.x += (float)vobj->parent->origw * dprop.scale.x;
		break;
		case ANCHORP_LL:
			props->position.y += (float)vobj->parent->origh * dprop.scale.y;
		break;
		case ANCHORP_CR:
			props->position.y += (float)vobj->parent->origh * dprop.scale.y * 0.5;
			props->position.x += (float)vobj->parent->origw * dprop.scale.x;
		break;
		case ANCHORP_C:
		case ANCHORP_UC:
		case ANCHORP_CL:
		case ANCHORP_LC:{
			float mid_y = (vobj->parent->origh * dprop.scale.y) * 0.5;
			float mid_x = (vobj->parent->origw * dprop.scale.x) * 0.5;
			if (vobj->p_anchor == ANCHORP_UC ||
				vobj->p_anchor == ANCHORP_LC || vobj->p_anchor == ANCHORP_C)
				props->position.x += mid_x;

			if (vobj->p_anchor == ANCHORP_CL || vobj->p_anchor == ANCHORP_C)
				props->position.y += mid_y;

			if (vobj->p_anchor == ANCHORP_LC)
				props->position.y += vobj->parent->origh * dprop.scale.y;
		}
		case ANCHORP_UL:
		default:
		break;
		}
	}
	else
		apply(vobj, props, &current_context->world.current, lerp, true);

/* the cache evaluation here is a bit shallow - there are differences between
 * in-frame caching (multiple resolves of related objects within the same
 * frame) and time-stable (no ongoing transformations queued) - likely that big
 * gains can be have with in-frame caching as well */
	arcan_vobject* current = vobj;
	bool can_cache = true;
	while (current && can_cache){
		if (current->transform){
			can_cache = false;
			break;
		}
		current = current->parent;
	}

	if (can_cache && vobj->owner && !vobj->valid_cache){
		surface_properties dprop = *props;
		vobj->prop_cache  = *props;
		vobj->valid_cache = true;
		build_modelview(vobj->prop_matr, vobj->owner->base, &dprop, vobj);
	}
	else
		;
}

static void calc_cp_area(arcan_vobject* vobj, point* ul, point* lr)
{
	surface_properties cur;
	arcan_resolve_vidprop(vobj, 0.0, &cur);

	ul->x = cur.position.x < ul->x ? cur.position.x : ul->x;
	ul->y = cur.position.y < ul->y ? cur.position.y : ul->y;

	float t1 = (cur.position.x + cur.scale.x * vobj->origw);
	float t2 = (cur.position.y + cur.scale.y * vobj->origh);
	lr->x = cur.position.x > t1 ? cur.position.x : t1;
	lr->y = cur.position.y > t2 ? cur.position.y : t2;

	if (vobj->parent && vobj->parent != &current_context->world)
		calc_cp_area(vobj->parent, ul, lr);
}

static inline void build_modelview(float* dmatr,
	float* imatr, surface_properties* prop, arcan_vobject* src)
{
	float _Alignas(16) omatr[16];
	float _Alignas(16) tmatr[16];

/* now position represents centerpoint in screen coordinates */
	prop->scale.x *= (float)src->origw * 0.5f;
	prop->scale.y *= (float)src->origh * 0.5f;

	prop->position.x += prop->scale.x;
	prop->position.y += prop->scale.y;

	src->rotate_state =
		fabsf(prop->rotation.roll)  > EPSILON ||
		fabsf(prop->rotation.pitch) > EPSILON ||
		fabsf(prop->rotation.yaw)   > EPSILON;

	memcpy(tmatr, imatr, sizeof(float) * 16);

	if (src->rotate_state){
		if (FL_TEST(src, FL_FULL3D))
			matr_quatf(norm_quat (prop->rotation.quaternion), omatr);
		else
			matr_rotatef(DEG2RAD(prop->rotation.roll), omatr);
	}

	point oofs = src->origo_ofs;

/* rotate around user-defined point rather than own center */
	if (oofs.x > EPSILON || oofs.y > EPSILON){
		translate_matrix(tmatr,
			prop->position.x + src->origo_ofs.x,
			prop->position.y + src->origo_ofs.y, 0.0);

		multiply_matrix(dmatr, tmatr, omatr);
		translate_matrix(dmatr, -src->origo_ofs.x, -src->origo_ofs.y, 0.0);
	}
	else
		translate_matrix(tmatr, prop->position.x, prop->position.y, 0.0);

	if (src->rotate_state)
		multiply_matrix(dmatr, tmatr, omatr);
	else
		memcpy(dmatr, tmatr, sizeof(float) * 16);
}

static inline float time_ratio(arcan_tickv start, arcan_tickv stop)
{
	return start > 0 ? (float)(arcan_video_display.c_ticks - start) /
		(float)(stop - start) : 1.0;
}

static void update_shenv(arcan_vobject* src, surface_properties* prop)
{
	agp_shader_envv(OBJ_OPACITY, &prop->opa, sizeof(float));

	float sz_i[2] = {src->origw, src->origh};
	agp_shader_envv(SIZE_INPUT, sz_i, sizeof(float)*2);

	float sz_o[2] = {prop->scale.x * 2.0, prop->scale.y * 2.0};
	agp_shader_envv(SIZE_OUTPUT, sz_o, sizeof(float)*2);

	float sz_s[2] = {src->vstore->w, src->vstore->h};
	agp_shader_envv(SIZE_STORAGE, sz_s, sizeof(float)*2);

	if (src->transform){
		struct surface_transform* trans = src->transform;
		float ev = time_ratio(trans->move.startt, trans->move.endt);
		agp_shader_envv(TRANS_MOVE, &ev, sizeof(float));

		ev = time_ratio(trans->rotate.startt, trans->rotate.endt);
		agp_shader_envv(TRANS_ROTATE, &ev, sizeof(float));

		ev = time_ratio(trans->scale.startt, trans->scale.endt);
		agp_shader_envv(TRANS_SCALE, &ev, sizeof(float));

		ev = time_ratio(trans->blend.startt, trans->blend.endt);
		agp_shader_envv(TRANS_BLEND, &ev, sizeof(float));
	}
	else {
		float ev = 1.0;
		agp_shader_envv(TRANS_MOVE, &ev, sizeof(float));
		agp_shader_envv(TRANS_ROTATE, &ev, sizeof(float));
		agp_shader_envv(TRANS_SCALE, &ev, sizeof(float));
		agp_shader_envv(TRANS_BLEND, &ev, sizeof(float));
	}
}

static inline void setup_surf(struct rendertarget* dst,
	surface_properties* prop, arcan_vobject* src, float** mv)
{
/* just temporary storage/scratch */
	static float _Alignas(16) dmatr[16];

	if (src->feed.state.tag == ARCAN_TAG_ASYNCIMGLD)
		return;

/* currently, we only cache the primary rendertarget, and the better option is
 * to actually remove secondary attachments etc. now that we have order-peeling
 * and sharestorage there should really just be 1:1 between src and dst */
	if (src->valid_cache && dst == src->owner){
		prop->scale.x *= src->origw * 0.5f;
		prop->scale.y *= src->origh * 0.5f;
		prop->position.x += prop->scale.x;
		prop->position.y += prop->scale.y;
		*mv = src->prop_matr;
	}
	else {
		build_modelview(dmatr, dst->base, prop, src);
		*mv = dmatr;
	}
	update_shenv(src, prop);
}

static inline void setup_shape_surf(struct rendertarget* dst,
	surface_properties* prop, arcan_vobject* src, float** mv)
{
	static float _Alignas(16) dmatr[16];
	surface_properties oldprop = *prop;
	if (src->feed.state.tag == ARCAN_TAG_ASYNCIMGLD)
		return;

	build_modelview(dmatr, dst->base, prop, src);
	*mv = dmatr;
	scale_matrix(*mv, prop->scale.x, prop->scale.y, 1.0);
	update_shenv(src, prop);
}

static inline void draw_colorsurf(struct rendertarget* dst,
	surface_properties prop, arcan_vobject* src,
	float r, float g, float b, float* txcos)
{
	float cval[3] = {r, g, b};
	float* mvm = NULL;

	setup_surf(dst, &prop, src, &mvm);
	agp_shader_forceunif("obj_col", shdrvec3, (void*) &cval);

	agp_draw_vobj(-prop.scale.x, -prop.scale.y,
		prop.scale.x, prop.scale.y, txcos, mvm);
}

/*
 * When we deal with multiple AGP implementations, it probably makes sense
 * to move some of these steps to that layer, as there might be more backend
 * specific ways that are faster (particularly for software that can have
 * many fastpaths)
 */
static inline void draw_texsurf(struct rendertarget* dst,
	surface_properties prop, arcan_vobject* src, float* txcos)
{
	float* mvm = NULL;
/*
 * Shape is treated mostly as a simplified 3D model but with an ortographic
 * projection and no hierarchy of meshes etc. we still need to switch to 3D
 * mode so we get a depth buffer to work with as there might be vertex- stage Z
 * displacement. This switch is slightly expensive (depth-buffer clear) though
 * used for such fringe cases that it's only a problem when measured as such.
 */
	if (src->shape){
		if (!src->shape->nodepth)
			agp_pipeline_hint(PIPELINE_3D);

		setup_shape_surf(dst, &prop, src, &mvm);
		agp_shader_envv(MODELVIEW_MATR, mvm, sizeof(float) * 16);
		agp_submit_mesh(src->shape, MESH_FACING_BOTH);

		if (!src->shape->nodepth)
			agp_pipeline_hint(PIPELINE_2D);
	}
	else {
		setup_surf(dst, &prop, src, &mvm);
		agp_draw_vobj(
				(-prop.scale.x),
				(-prop.scale.y),
				( prop.scale.x),
				( prop.scale.y), txcos, mvm);
	}
}

/*
 * Perform an explicit poll pass of the object in question.
 * Assumes [dst] is valid.
 *
 * [step] will commit- the buffer, rotate frame-store and have the object
 * cookie tagged with the current update
 */
static void ffunc_process(arcan_vobject* dst, bool step)
{
	if (!dst->feed.ffunc)
		return;

	TRACE_MARK_ONESHOT("video", "feed-poll", TRACE_SYS_DEFAULT, dst->cellid, 0, dst->tracetag);
	int frame_status = arcan_ffunc_lookup(dst->feed.ffunc)(
		FFUNC_POLL, 0, 0, 0, 0, 0, dst->feed.state, dst->cellid);

	if (frame_status == FRV_GOTFRAME){
/* there is an edge condition from the conductor where it wants to 'pump' the
 * feeds but not induce any video buffer transfers (audio is ok) as we still
 * have buffers in flight and can't buffer more */
		if (!step)
			return;

/* this feed has already been updated during the current round so we can't
 * continue without risking graphics-layer undefined behavior (mutating stores
 * while pending asynch tasks), mark the rendertarget as dirty and move on */
		FLAG_DIRTY(dst);
		if (dst->feed.pcookie == arcan_video_display.cookie){
			dst->owner->transfc++;
			return;
		}
		dst->feed.pcookie = arcan_video_display.cookie;

/* cycle active frame store (depending on how often we want to
 * track history frames, might not be every time) */
		if (dst->frameset && dst->frameset->mctr != 0){
			dst->frameset->ctr--;

			if (dst->frameset->ctr == 0){
				dst->frameset->ctr = abs( dst->frameset->mctr );
				step_active_frame(dst);
			}
		}

/* this will queue the new frame upload, unlocking any external provider
 * and so on, see frameserver.c and the different vfunc handlers there */
		TRACE_MARK_ENTER("video", "feed-render", TRACE_SYS_DEFAULT, dst->cellid, 0, dst->tracetag);
		arcan_ffunc_lookup(dst->feed.ffunc)(FFUNC_RENDER,
			dst->vstore->vinf.text.raw, dst->vstore->vinf.text.s_raw,
			dst->vstore->w, dst->vstore->h,
			dst->vstore->vinf.text.glid,
			dst->feed.state, dst->cellid
		);
		TRACE_MARK_EXIT("video", "feed-render", TRACE_SYS_DEFAULT, dst->cellid, 0, dst->tracetag);

/* for statistics, mark an upload */
		arcan_video_display.dirty++;
		dst->owner->uploadc++;
		dst->owner->transfc++;
	}

	return;
}

arcan_errc arcan_vint_pollfeed(arcan_vobj_id vid, bool step)
{
	arcan_vobject* vobj = arcan_video_getobject(vid);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

/* this will always invalidate, so calling this multiple times per
 * frame is implementation defined behavior */
	ffunc_process(vobj, step);

	return ARCAN_OK;
}

/*
 * For large Ns this approach 'should' be rather dumb in the sense
 * that we could arguably well just have a set of descriptors and
 * check the ones that have been signalled. On the other hand, they
 * will be read almost immediately after this, and with that in mind,
 * we would possibly gain more by just having a big-array(TM){for
 * all cases where n*obj_size < data_cache_size} as that hit/miss is
 * really all that matters now.
 */
static void poll_list(arcan_vobject_litem* current)
{
	while(current && current->elem){
		arcan_vobject* celem = current->elem;

		if (celem->feed.ffunc)
			ffunc_process(celem, true);

		current = current->next;
	}
}

void arcan_video_pollfeed()
{
 for (off_t ind = 0; ind < current_context->n_rtargets; ind++)
		arcan_vint_pollreadback(&current_context->rtargets[ind]);
	arcan_vint_pollreadback(&current_context->stdoutp);

	for (size_t i = 0; i < current_context->n_rtargets; i++)
		poll_list(current_context->rtargets[i].first);

	poll_list(current_context->stdoutp.first);
}

static arcan_vobject* get_clip_source(arcan_vobject* vobj)
{
	arcan_vobject* res = vobj->parent;
	if (vobj->clip_src && vobj->clip_src != ARCAN_VIDEO_WORLDID){
		arcan_vobject* clipref = arcan_video_getobject(vobj->clip_src);
		if (clipref)
			return clipref;
	}

	if (vobj->parent == &current_context->world)
		res = NULL;

	return res;
}

static inline void populate_stencil(
	struct rendertarget* tgt, arcan_vobject* celem, float fract)
{
	agp_prepare_stencil();

/* note that the stencil buffer setup currently forces the default shader, this
 * might not be desired if some vertex transform is desired in the clipping */
	agp_shader_activate(tgt->shid);

	if (celem->clip == ARCAN_CLIP_SHALLOW){
		celem = get_clip_source(celem);
		if (celem){
			surface_properties pprops = empty_surface();
			arcan_resolve_vidprop(celem, fract, &pprops);
			draw_colorsurf(tgt, pprops, celem, 1.0, 1.0, 1.0, NULL);
		}
	}
	else
/* deep -> draw all objects that aren't clipping to parent,
 * terminate when a shallow clip- object is found */
		while (celem->parent != &current_context->world){
			surface_properties pprops = empty_surface();
			arcan_resolve_vidprop(celem->parent, fract, &pprops);

			if (celem->parent->clip == ARCAN_CLIP_OFF)
				draw_colorsurf(tgt, pprops, celem->parent, 1.0, 1.0, 1.0, NULL);

			else if (celem->parent->clip == ARCAN_CLIP_SHALLOW){
				draw_colorsurf(tgt, pprops, celem->parent, 1.0, 1.0, 1.0, NULL);
				break;
			}

			celem = celem->parent;
		}

	agp_activate_stencil();
}

arcan_errc arcan_video_rendertargetid(arcan_vobj_id did, int* inid, int* outid)
{
	arcan_vobject* vobj = arcan_video_getobject(did);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	struct rendertarget* tgt = arcan_vint_findrt(vobj);
	if (!tgt)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	if (inid){
		tgt->id = *inid;
		FLAG_DIRTY(vobj);
	}

	if (outid)
		*outid = tgt->id;

	return ARCAN_OK;
}

void arcan_vint_bindmulti(arcan_vobject* elem, size_t ind)
{
	struct vobject_frameset* set = elem->frameset;
	size_t sz = set->n_frames;

/* Build a temporary array of storage- info references for multi-
 * build. Note that this does not respect texture coordinates */
	struct agp_vstore* elems[sz];

	for (size_t i = 0; i < sz; i++, ind = (ind > 0 ? ind - 1 : sz - 1))
		elems[i] = set->frames[ind].frame;

	agp_activate_vstore_multi(elems, sz);
}

static int draw_vobj(struct rendertarget* tgt,
	arcan_vobject* vobj, surface_properties* dprops, float* txcos)
{
	if (vobj->blendmode == BLEND_NORMAL && dprops->opa > 1.0 - EPSILON)
		agp_blendstate(BLEND_NONE);
	else
		agp_blendstate(vobj->blendmode);

/* pick the right vstore drawing type (textured, colored) */
	struct agp_vstore* vstore = vobj->vstore;
	if (vstore->txmapped == TXSTATE_OFF && vobj->program != 0){
		draw_colorsurf(tgt, *dprops, vobj, vstore->vinf.col.r,
			vstore->vinf.col.g, vstore->vinf.col.b, txcos);
		return 1;
	}

	if (vstore->txmapped == TXSTATE_TEX2D){
		draw_texsurf(tgt, *dprops, vobj, txcos);
		return 1;
	}

	return 0;
}

/*
 * Apply clipping without using the stencil buffer, cheaper but with some
 * caveats of its own. Will work particularly bad for partial clipping with
 * customized texture coordinates.
 */
static inline bool setup_shallow_texclip(
	arcan_vobject* elem,
	arcan_vobject* clip_src,
	float** txcos, surface_properties* dprops, float fract)
{
	static float cliptxbuf[8];

	surface_properties pprops = empty_surface();
	arcan_resolve_vidprop(clip_src, fract, &pprops);

	float p_x = pprops.position.x;
	float p_y = pprops.position.y;
	float p_w = pprops.scale.x * clip_src->origw;
	float p_h = pprops.scale.y * clip_src->origh;
	float p_xw = p_x + p_w;
	float p_yh = p_y + p_h;

	float cp_x = dprops->position.x;
	float cp_y = dprops->position.y;
	float cp_w = dprops->scale.x * elem->origw;
	float cp_h = dprops->scale.y * elem->origh;
	float cp_xw = cp_x + cp_w;
	float cp_yh = cp_y + cp_h;

/* fully outside? skip drawing */
	if (cp_xw < p_x || cp_yh < p_y ||	cp_x > p_xw || cp_y > p_yh){
		return false;
	}

/* fully contained? don't do anything */
	else if (	cp_x >= p_x && cp_xw <= p_xw && cp_y >= p_y && cp_yh <= p_yh ){
		return true;
	}

	memcpy(cliptxbuf, *txcos, sizeof(float) * 8);
	float xrange = cliptxbuf[2] - cliptxbuf[0];
	float yrange = cliptxbuf[7] - cliptxbuf[1];

	if (cp_x < p_x){
		float sl = ((p_x - cp_x) / elem->origw) * xrange;
		cp_w -= p_x - cp_x;
		cliptxbuf[0] += sl;
		cliptxbuf[6] += sl;
		cp_x = p_x;
	}

	if (cp_y < p_y){
		float su = ((p_y - cp_y) / elem->origh) * yrange;
		cp_h -= p_y - cp_y;
		cliptxbuf[1] += su;
		cliptxbuf[3] += su;
		cp_y = p_y;
	}

	if (cp_x + cp_w > p_xw){
		float sr = ((cp_x + cp_w) - p_xw) / elem->origw * xrange;
		cp_w -= (cp_x + cp_w) - p_xw;
		cliptxbuf[2] -= sr;
		cliptxbuf[4] -= sr;
	}

	if (cp_y + cp_h > p_yh){
		float sd = ((cp_y + cp_h) - p_yh) / elem->origh * yrange;
		cp_h -= (cp_y + cp_h) - p_yh;
		cliptxbuf[5] -= sd;
		cliptxbuf[7] -= sd;
	}

/* dprops modifications should be moved to a scaled draw */
	dprops->position.x = cp_x;
	dprops->position.y = cp_y;
	dprops->scale.x = cp_w / elem->origw;
	dprops->scale.y = cp_h / elem->origh;

/* this is expensive, we should instead temporarily offset */
	elem->valid_cache = false;
	*txcos = cliptxbuf;
	return true;
}

_Thread_local static struct rendertarget* current_rendertarget;
struct rendertarget* arcan_vint_current_rt()
{
	return current_rendertarget;
}

static size_t process_rendertarget(
	struct rendertarget* tgt, float fract, bool nest)
{
	arcan_vobject_litem* current;
	size_t pc = arcan_video_display.ignore_dirty ? 1 : 0;

/* If a link- target is defined, we implement that by first running the linked
 * chain as if it was part of ourselves - then we run our own chain on top of
 * that. This could be used to create cycles (a link to b link to a) but that
 * would get thwarted with the tgt->link = NULL write. */
	if (tgt->link){
		struct rendertarget* tmp_tgt = tgt->link;
		arcan_vobject_litem* tmp_cur = tgt->first;
		tgt->first = tgt->link->first;
		tgt->link = NULL;
		size_t old_msc = tgt->msc;

		pc += process_rendertarget(tgt, fract, false);
		nest = pc > 0;

		tgt->first = tmp_cur;
		tgt->link = tmp_tgt;

		tgt->dirtyc += tgt->link->dirtyc;
		tgt->transfc += tgt->link->transfc;
		tgt->msc = old_msc;
	}

	current = tgt->first;

/* If there are no ongoing transformations, or the platform has flagged that we
 * need to redraw everything, and there are no actual changes to the rtgt pipe
 * (FLAG_DIRTY) then early out. This does not cover content update from
 * external sources directly as those are set during ffunc_process/pollfeed */
	if (
		!arcan_video_display.dirty &&
		!arcan_video_display.ignore_dirty &&
		!tgt->dirtyc && !tgt->transfc)
		return 0;

	tgt->uploadc = 0;
	tgt->msc++;

/* this does not really swap the stores unless they are actually different, it
 * is cheaper to do it here than shareglstore as the search for vobj to rtgt is
 * expensive */
	if (tgt->color && !nest)
		agp_rendertarget_swapstore(tgt->art, tgt->color->vstore);

	current_rendertarget = tgt;
	agp_activate_rendertarget(tgt->art);
	agp_shader_envv(RTGT_ID, &tgt->id, sizeof(int));
	agp_shader_envv(OBJ_OPACITY, &(float){1.0}, sizeof(float));

	if (!FL_TEST(tgt, TGTFL_NOCLEAR) && !nest)
		agp_rendertarget_clear();

/* first, handle all 3d work (which may require multiple passes etc.) */
	if (tgt->order3d == ORDER3D_FIRST && current && current->elem->order < 0){
		current = arcan_3d_refresh(tgt->camtag, current, fract);
		pc++;
	}

/* skip a possible 3d pipeline */
	while (current && current->elem->order < 0)
		current = current->next;

	if (!current)
		goto end3d;

/* make sure we're in a decent state for 2D */
	agp_pipeline_hint(PIPELINE_2D);

	agp_shader_activate(agp_default_shader(BASIC_2D));
	agp_shader_envv(PROJECTION_MATR, tgt->projection, sizeof(float)*16);

	while (current && current->elem->order >= 0){
		arcan_vobject* elem = current->elem;

		if (current->elem->order < tgt->min_order){
			current = current->next;
			continue;
		}

		if (current->elem->order > tgt->max_order)
			break;

/* calculate coordinate system translations, world cannot be masked */
		surface_properties dprops = empty_surface();
		arcan_resolve_vidprop(elem, fract, &dprops);

/* don't waste time on objects that aren't supposed to be visible */
		if ( dprops.opa <= EPSILON || elem == tgt->color){
			current = current->next;
			continue;
		}

/* enable clipping using stencil buffer, we need to reset the state of the
 * stencil buffer between draw calls so track if it's enabled or not */
		bool clipped = false;

/*
 * texture coordinates that will be passed to the draw call, clipping and other
 * effects may maintain a local copy and manipulate these
 */
		float* txcos = elem->txcos;
		float** dstcos = &txcos;

		if ( (elem->mask & MASK_MAPPING) > 0)
			txcos = elem->parent != &current_context->world ?
				elem->parent->txcos : elem->txcos;

		if (!txcos)
			txcos = arcan_video_display.default_txcos;

/* depending on frameset- mode, we may need to split the frameset up into
 * multitexturing, or switch the txcos with the ones that may be used for
 * clipping, but mapping TU indices to current shader must be done before.
 * To not skip on the early-out-on-clipping and not incur additional state
 * change costs, only do it in this edge case. */
		agp_shader_id shid = tgt->shid;
		if (!tgt->force_shid && elem->program)
			shid = elem->program;
		agp_shader_activate(shid);

		if (elem->frameset){
			if (elem->frameset->mode == ARCAN_FRAMESET_MULTITEXTURE){
				arcan_vint_bindmulti(elem, elem->frameset->index);
			}
			else{
				struct frameset_store* ds =
					&elem->frameset->frames[elem->frameset->index];
				txcos = ds->txcos;
				agp_activate_vstore(ds->frame);
			}
		}
		else
			agp_activate_vstore(elem->vstore);

/* fast-path out if no clipping */
		arcan_vobject* clip_src;
		current = current->next;

		if (elem->clip == ARCAN_CLIP_OFF || !(clip_src = get_clip_source(elem))){
			pc += draw_vobj(tgt, elem, &dprops, *dstcos);
			continue;
		}

/* fast-path, shallow non-rotated clipping */
		if (elem->clip == ARCAN_CLIP_SHALLOW &&
			!elem->rotate_state && !clip_src->rotate_state){

/* this will tweak the output object size and texture coordinates */
			if (!setup_shallow_texclip(elem, clip_src, dstcos, &dprops, fract)){
				continue;
			}

			pc += draw_vobj(tgt, elem, &dprops, *dstcos);
			continue;
		}

		populate_stencil(tgt, elem, fract);
		pc += draw_vobj(tgt, elem, &dprops, *dstcos);
		agp_disable_stencil();
	}

/* reset and try the 3d part again if requested */
end3d:
	current = tgt->first;
	if (current && current->elem->order < 0 && tgt->order3d == ORDER3D_LAST){
		agp_shader_activate(agp_default_shader(BASIC_2D));
		current = arcan_3d_refresh(tgt->camtag, current, fract);
		if (current != tgt->first)
			pc++;
	}

	if (pc){
		tgt->frame_cookie = arcan_video_display.cookie;
	}
	return pc;
}

arcan_errc arcan_video_forceread(
	arcan_vobj_id sid, bool local, av_pixel** dptr, size_t* dsize)
{
/*
 * more involved than one may think, the store doesn't have to be representative
 * in case of rendertargets, and for streaming readbacks of those we already
 * have readback toggles etc. Thus this function is only for "one-off" reads
 * where a blocking behavior may be accepted, especially outside a main
 * renderloop as this will possibly stall the pipeline
 */

	arcan_vobject* vobj = arcan_video_getobject(sid);
	struct agp_vstore* dstore = vobj->vstore;

	if (!vobj || !dstore)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (dstore->txmapped != TXSTATE_TEX2D)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	*dsize = sizeof(av_pixel) * dstore->w * dstore->h;
	*dptr  = arcan_alloc_mem(*dsize, ARCAN_MEM_VBUFFER,
		ARCAN_MEM_TEMPORARY | ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE);

	if (local && dstore->vinf.text.raw && dstore->vinf.text.s_raw > 0){
		memcpy(dptr, dstore->vinf.text.raw, *dsize);
	}
	else {
		av_pixel* temp = dstore->vinf.text.raw;
		dstore->vinf.text.raw = *dptr;
		agp_readback_synchronous(dstore);
		dstore->vinf.text.raw = temp;
	}

	return ARCAN_OK;
}

void arcan_video_disable_worldid()
{
	if (current_context->stdoutp.art){
		agp_drop_rendertarget(current_context->stdoutp.art);
		current_context->stdoutp.art = NULL;
	}
	arcan_video_display.no_stdout = true;
}

struct agp_rendertarget* arcan_vint_worldrt()
{
	return current_context->stdoutp.art;
}

struct agp_vstore* arcan_vint_world()
{
	return current_context->stdoutp.color->vstore;
}

arcan_errc arcan_video_forceupdate(arcan_vobj_id vid, bool forcedirty)
{
	arcan_vobject* vobj = arcan_video_getobject(vid);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	struct rendertarget* tgt = arcan_vint_findrt(vobj);
	if (!tgt)
		return ARCAN_ERRC_UNACCEPTED_STATE;

/* remember / retain platform decay */
	size_t id = arcan_video_display.ignore_dirty;
	if (forcedirty){
		FLAG_DIRTY(vobj);
/* full pass regardless of there being any updates or not */
		arcan_video_display.ignore_dirty = 1;
	}
	else {
		arcan_video_display.ignore_dirty = 0;
	}

	process_rendertarget(tgt, arcan_video_display.c_lerp, false);
	tgt->dirtyc = 0;

	arcan_video_display.ignore_dirty = id;
	current_rendertarget = NULL;
	agp_activate_rendertarget(NULL);

	if (tgt->readback != 0){
		process_readback(tgt, arcan_video_display.c_lerp);
		arcan_vint_pollreadback(tgt);
	}

	return ARCAN_OK;
}

arcan_errc arcan_video_screenshot(av_pixel** dptr, size_t* dsize)
{
	struct monitor_mode mode = platform_video_dimensions();
	*dsize = sizeof(char) * mode.width * mode.height * sizeof(av_pixel);

	*dptr = arcan_alloc_mem(*dsize, ARCAN_MEM_VBUFFER,
		ARCAN_MEM_TEMPORARY | ARCAN_MEM_NONFATAL, ARCAN_MEMALIGN_PAGE);

	if (!(*dptr)){
		*dsize = 0;
		return ARCAN_ERRC_OUT_OF_SPACE;
	}

	agp_save_output(mode.width, mode.height, *dptr, *dsize);

	return ARCAN_OK;
}

/* Check outstanding readbacks, map and feed onwards, ideally we should synch
 * this with a fence - but the platform GL etc. versioning restricts things for
 * the time being. Threaded- dispatch from the conductor is the right way
 * forward */
void arcan_vint_pollreadback(struct rendertarget* tgt)
{
	if (!FL_TEST(tgt, TGTFL_READING))
		return;

	arcan_vobject* vobj = tgt->color;

/* don't check the readback unless the client is ready, should possibly have a
 * timeout for this as well so we don't hold GL resources with an unwilling /
 * broken client, it's a hard tradeoff as streaming video encode might deal
 * well with the dropped frame at this stage, while a variable rate interactive
 * source may lose data */
	arcan_vfunc_cb ffunc = NULL;
	if (vobj->feed.ffunc){
		ffunc = arcan_ffunc_lookup(vobj->feed.ffunc);
		if (FRV_GOTFRAME == ffunc(
			FFUNC_POLL, NULL, 0, 0, 0, 0, vobj->feed.state, vobj->cellid))
			return;
	}

/* now we can check the readback, it is not safe to call poll, get results
 * and then call poll again, we have to release once retrieved */
	struct asynch_readback_meta rbb = agp_poll_readback(vobj->vstore);

	if (rbb.ptr == NULL)
		return;

/* the ffunc might've disappeared, so disable the readback state */
	if (!vobj->feed.ffunc)
		tgt->readback = 0;
	else{
		arcan_ffunc_lookup(vobj->feed.ffunc)(
			FFUNC_READBACK, rbb.ptr, rbb.w * rbb.h * sizeof(av_pixel),
			rbb.w, rbb.h, 0, vobj->feed.state, vobj->cellid
		);
	}

	rbb.release(rbb.tag);
	FL_CLEAR(tgt, TGTFL_READING);
}

static size_t steptgt(float fract, struct rendertarget* tgt)
{
/* A special case here are rendertargets where the color output store
 * is explicitly bound only to a frameserver. This requires that:
 * 1. The frameserver is still waiting to synch
 * 2. The object (rendertarget color vobj) is invisible
 * 3. The backing store has a single consumer
 */
	struct arcan_vobject* dst = tgt->color;
	if (dst && dst->current.opa < EPSILON && dst->vstore->refcount == 1 &&
		dst->feed.state.tag == ARCAN_TAG_FRAMESERV &&
		arcan_ffunc_lookup(dst->feed.ffunc)
			(FFUNC_POLL, 0, 0, 0, 0, 0, dst->feed.state, dst->cellid) == FRV_GOTFRAME)
	{
		return 1;
	}

	size_t transfc = 0;
	if (tgt->refresh < 0 && process_counter(
		tgt, &tgt->refreshcnt, tgt->refresh, fract)){
		transfc += process_rendertarget(tgt, fract, false);
		tgt->dirtyc = 0;

/* may need to readback even if we havn't updated as it may
 * be used as clock (though optimization possibility of using buffer) */
		process_readback(tgt, fract);
	}

	return transfc;
}

unsigned arcan_vint_refresh(float fract, size_t* ndirty)
{
	long long int pre = arcan_timemillis();
	TRACE_MARK_ENTER("video", "refresh", TRACE_SYS_DEFAULT, 0, 0, "");

	size_t transfc = 0;

/* we track last interp. state in order to handle forcerefresh */
	arcan_video_display.c_lerp = fract;
	arcan_random((void*)&arcan_video_display.cookie, 8);

/* active shaders with counter counts towards dirty */
	transfc += agp_shader_envv(FRACT_TIMESTAMP_F, &fract, sizeof(float));

/* the user/developer or the platform can decide that all dirty tracking should
 * be enabled - we do that with a global counter and then 'fake' a transform */
	if (arcan_video_display.ignore_dirty > 0){
		transfc++;
		arcan_video_display.ignore_dirty--;
	}

/* Right now there is an explicit 'first come first update' kind of
 * order except for worldid as everything else might be composed there.
 *
 * The opption would be to build the dependency graph between rendertargets
 * and account for cycles, but has so far not shown worth it. */
	size_t tgt_dirty = 0;
	for (size_t ind = 0; ind < current_context->n_rtargets; ind++){
		struct rendertarget* tgt = &current_context->rtargets[ind];

		const char* tag = tgt->color ? tgt->color->tracetag : NULL;
		TRACE_MARK_ENTER("video", "process-rendertarget", TRACE_SYS_DEFAULT, ind, 0, tag);
			tgt_dirty = steptgt(fract, tgt);
			transfc += tgt_dirty;
		TRACE_MARK_EXIT("video", "process-rendertarget", TRACE_SYS_DEFAULT, ind, tgt_dirty, tag);
	}

/* reset the bound rendertarget, otherwise we may be in an undefined
 * state if world isn't dirty or with pending transfers */
	current_rendertarget = NULL;
	agp_activate_rendertarget(NULL);

	TRACE_MARK_ENTER("video", "process-world-rendertarget", TRACE_SYS_DEFAULT, 0, 0, "world");
		tgt_dirty = steptgt(fract, &current_context->stdoutp);
		transfc += tgt_dirty;
	TRACE_MARK_EXIT("video", "process-world-rendertarget", TRACE_SYS_DEFAULT, 0, tgt_dirty, "world");
	*ndirty = transfc + arcan_video_display.dirty;
	arcan_video_display.dirty = 0;

/* This is part of another dirty workaround when n buffers are needed by the
 * video platform for a flip to reach the display and we want the same contents
 * in every buffer stage at the cost of rendering */
	if (*ndirty && arcan_video_display.ignore_dirty == 0){
		arcan_video_display.ignore_dirty = platform_video_decay();
	}

	long long int post = arcan_timemillis();
	TRACE_MARK_EXIT("video", "refresh", TRACE_SYS_DEFAULT, 0, 0, "");
	return post - pre;
}

void arcan_video_default_scalemode(enum arcan_vimage_mode newmode)
{
	arcan_video_display.scalemode = newmode;
}

void arcan_video_default_blendmode(enum arcan_blendfunc newmode)
{
	arcan_video_display.blendmode = newmode;
}

void arcan_video_default_texmode(enum arcan_vtex_mode modes,
	enum arcan_vtex_mode modet)
{
	arcan_video_display.deftxs = modes;
	arcan_video_display.deftxt = modet;
}

arcan_errc arcan_video_screencoords(arcan_vobj_id id, vector res[static 4])
{
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	if (vobj->feed.state.tag == ARCAN_TAG_3DOBJ)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	surface_properties prop;

	if (vobj->valid_cache)
		prop = vobj->prop_cache;
	else {
		prop = empty_surface();
		arcan_resolve_vidprop(vobj, arcan_video_display.c_lerp, &prop);
	}

	float w = (float)vobj->origw * prop.scale.x;
	float h = (float)vobj->origh * prop.scale.y;

	res[0].x = prop.position.x;
	res[0].y = prop.position.y;
	res[1].x = res[0].x + w;
	res[1].y = res[0].y;
	res[2].x = res[1].x;
	res[2].y = res[1].y + h;
	res[3].x = res[0].x;
	res[3].y = res[2].y;

	if (fabsf(prop.rotation.roll) > EPSILON){
		float ang = DEG2RAD(prop.rotation.roll);
		float sinv = sinf(ang);
		float cosv = cosf(ang);

		float cpx = res[0].x + 0.5 * w;
		float cpy = res[0].y + 0.5 * h;

		for (size_t i = 0; i < 4; i++){
			float rx = cosv * (res[i].x - cpx) - sinv * (res[i].y-cpy) + cpx;
			float ry = sinv * (res[i].x - cpx) + cosv * (res[i].y-cpy) + cpy;
			res[i].x = rx;
			res[i].y = ry;
		}
	}

	return ARCAN_OK;
}

static inline int isign(int p1_x, int p1_y,
	int p2_x, int p2_y, int p3_x, int p3_y)
{
	return (p1_x - p3_x) * (p2_y - p3_y) - (p2_x - p3_x) * (p1_y - p3_y);
}

static inline bool itri(int x, int y, int t[6])
{
	bool b1, b2, b3;

	b1 = isign(x, y, t[0], t[1], t[2], t[3]) < 0;
	b2 = isign(x, y, t[2], t[3], t[4], t[5]) < 0;
	b3 = isign(x, y, t[4], t[5], t[0], t[1]) < 0;

	return (b1 == b2) && (b2 == b3);
}

bool arcan_video_hittest(arcan_vobj_id id, int x, int y)
{
	vector projv[4];
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (ARCAN_OK != arcan_video_screencoords(id, projv)){
		if (vobj && vobj->feed.state.tag == ARCAN_TAG_3DOBJ){
			return arcan_3d_obj_bb_intersect(
				current_context->stdoutp.camtag, id, x, y);
		}
		return false;
	}

	if (vobj->rotate_state){
		int t1[] = {
			projv[0].x, projv[0].y,
			projv[1].x, projv[1].y,
			projv[2].x, projv[2].y
		};

		int t2[] = {
			projv[2].x, projv[2].y,
			projv[3].x, projv[3].y,
			projv[0].x, projv[0].y
		};

		return itri(x, y, t1) || itri(x, y, t2);
	}
	else
		return (x >= projv[0].x && y >= projv[0].y) &&
			(x <= projv[2].x && y <= projv[2].y);
}

arcan_errc arcan_video_sliceobject(arcan_vobj_id sid,
	enum arcan_slicetype type, size_t base, size_t n_slices)
{
	arcan_vobject* src = arcan_video_getobject(sid);
	if (!src)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	return (agp_slice_vstore(src->vstore, n_slices, base,
		type == ARCAN_CUBEMAP ? TXSTATE_CUBE : TXSTATE_TEX3D))
		? ARCAN_OK : ARCAN_ERRC_UNACCEPTED_STATE;
}

arcan_errc arcan_video_updateslices(
	arcan_vobj_id sid, size_t n_slices, arcan_vobj_id* slices)
{
	arcan_vobject* src = arcan_video_getobject(sid);
	if (!src || n_slices > 4096)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	struct agp_vstore* vstores[n_slices];
	for (size_t i = 0; i < sid; i++){
		arcan_vobject* slot = arcan_video_getobject(slices[i]);
		if (!slot){
			vstores[i] = NULL;
			continue;
		}
		vstores[i] = slot->vstore;
	}

	return (agp_slice_synch(src->vstore, n_slices, vstores)) ?
			ARCAN_OK : ARCAN_ERRC_UNACCEPTED_STATE;
}

static inline bool obj_visible(arcan_vobject* vobj)
{
	bool visible = vobj->current.opa > EPSILON;

	while (visible && vobj->parent && (vobj->mask & MASK_OPACITY) > 0){
		visible = vobj->current.opa > EPSILON;
		vobj = vobj->parent;
	}

	return visible;
}

size_t arcan_video_rpick(arcan_vobj_id rt,
	arcan_vobj_id* dst, size_t lim, int x, int y)
{
	size_t count = 0;
	arcan_vobject* vobj = arcan_video_getobject(rt);
	struct rendertarget* tgt = arcan_vint_findrt(vobj);

	if (lim == 0 || !tgt || !tgt->first)
		return count;

	arcan_vobject_litem* current = tgt->first;

/* skip to last, then start stepping backwards */
	while (current->next)
		current = current->next;

	while (current && count < lim){
		arcan_vobject* vobj = current->elem;

		if ((vobj->mask & MASK_UNPICKABLE) == 0 && obj_visible(vobj) &&
			arcan_video_hittest(vobj->cellid, x, y))
				dst[count++] = vobj->cellid;

		current = current->previous;
	}

	return count;
}

size_t arcan_video_pick(arcan_vobj_id rt,
	arcan_vobj_id* dst, size_t lim, int x, int y)
{
	size_t count = 0;
	arcan_vobject* vobj = arcan_video_getobject(rt);
	struct rendertarget* tgt = arcan_vint_findrt(vobj);
	if (lim == 0 || !tgt || !tgt->first)
		return count;

	arcan_vobject_litem* current = tgt->first;

	while (current && count < lim){
		arcan_vobject* vobj = current->elem;

		if (vobj->cellid && !(vobj->mask & MASK_UNPICKABLE) &&
			obj_visible(vobj) && arcan_video_hittest(vobj->cellid, x, y))
				dst[count++] = vobj->cellid;

		current = current->next;
	}

	return count;
}

img_cons arcan_video_storage_properties(arcan_vobj_id id)
{
	img_cons res = {.w = 0, .h = 0, .bpp = 0};
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && vobj->vstore){
		res.w = vobj->vstore->w;
		res.h = vobj->vstore->h;
		res.bpp = vobj->vstore->bpp;
	}

	return res;
}

/* image dimensions at load time, without
 * any transformations being applied */
surface_properties arcan_video_initial_properties(arcan_vobj_id id)
{
	surface_properties res = empty_surface();
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id > 0){
		res.scale.x = vobj->origw;
		res.scale.y = vobj->origh;
	}

	return res;
}

surface_properties arcan_video_resolve_properties(arcan_vobj_id id)
{
	surface_properties res = empty_surface();
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj && id > 0){
		arcan_resolve_vidprop(vobj, 0.0, &res);
		res.scale.x *= vobj->origw;
		res.scale.y *= vobj->origh;
	}

	return res;
}

surface_properties arcan_video_current_properties(arcan_vobj_id id)
{
	surface_properties rv = empty_surface();
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj){
		rv = vobj->current;
		rv.scale.x *= vobj->origw;
		rv.scale.y *= vobj->origh;
	}

	return rv;
}

surface_properties arcan_video_properties_at(arcan_vobj_id id, unsigned ticks)
{
	if (ticks == 0)
		return arcan_video_current_properties(id);

	bool fullprocess = ticks == (unsigned int) -1;

	surface_properties rv = empty_surface();
	arcan_vobject* vobj = arcan_video_getobject(id);

	if (vobj){
		rv = vobj->current;
/* if there's no transform defined, then the ticks will be the same */
		if (vobj->transform){
/* translate ticks from relative to absolute */
			if (!fullprocess)
				ticks += arcan_video_display.c_ticks;

/* check if there is a transform for each individual attribute, and find
 * the one that defines a timeslot within the range of the desired value */
			surface_transform* current = vobj->transform;
			if (current->move.startt){
				while ( (current->move.endt < ticks || fullprocess) && current->next
					&& current->next->move.startt)
					current = current->next;

				if (current->move.endt <= ticks)
					rv.position = current->move.endp;
				else if (current->move.startt == ticks)
					rv.position = current->move.startp;
				else{ /* need to interpolate */
					float fract = lerp_fract(current->move.startt,
						current->move.endt, ticks);
					rv.position = lut_interp_3d[current->move.interp](
						current->move.startp,
						current->move.endp, fract
					);
				}
			}

			current = vobj->transform;
			if (current->scale.startt){
				while ( (current->scale.endt < ticks || fullprocess) &&
					current->next && current->next->scale.startt)
					current = current->next;

				if (current->scale.endt <= ticks)
					rv.scale = current->scale.endd;
				else if (current->scale.startt == ticks)
					rv.scale = current->scale.startd;
				else{
					float fract = lerp_fract(current->scale.startt,
						current->scale.endt, ticks);
					rv.scale = lut_interp_3d[current->scale.interp](
						current->scale.startd,
						current->scale.endd, fract
					);
				}
			}

			current = vobj->transform;
			if (current->blend.startt){
				while ( (current->blend.endt < ticks || fullprocess) &&
					current->next && current->next->blend.startt)
					current = current->next;

				if (current->blend.endt <= ticks)
					rv.opa = current->blend.endopa;
				else if (current->blend.startt == ticks)
					rv.opa = current->blend.startopa;
				else{
					float fract = lerp_fract(current->blend.startt,
						current->blend.endt, ticks);
					rv.opa = lut_interp_1d[current->blend.interp](
						current->blend.startopa,
						current->blend.endopa,
						fract
					);
				}
			}

			current = vobj->transform;
			if (current->rotate.startt){
				while ( (current->rotate.endt < ticks || fullprocess) &&
					current->next && current->next->rotate.startt)
					current = current->next;

				if (current->rotate.endt <= ticks)
					rv.rotation = current->rotate.endo;
				else if (current->rotate.startt == ticks)
					rv.rotation = current->rotate.starto;
				else{
					float fract = lerp_fract(current->rotate.startt,
						current->rotate.endt, ticks);

					rv.rotation.quaternion = current->rotate.interp(
						current->rotate.starto.quaternion,
						current->rotate.endo.quaternion, fract
					);
				}
			}
		}

		rv.scale.x *= vobj->origw;
		rv.scale.y *= vobj->origh;
	}

	return rv;
}

bool arcan_video_prepare_external(bool keep_events)
{
	if (-1 == arcan_video_pushcontext())
		return false;

/* this still leaves rendertargets alive, normally this is ok but if the
 * platform swaps gpus, contexts whatever in the meanwhile, it is not! */
	if (!keep_events)
		arcan_event_deinit(arcan_event_defaultctx(), false);

	platform_video_prepare_external();

	return true;
}

static void invalidate_rendertargets()
{
/* passs one, rebuild all the rendertargets */
	for (size_t i = 0; i < current_context->n_rtargets; i++){
		struct rendertarget* tgt = &current_context->rtargets[i];
		if (!tgt->art)
			continue;

		arcan_mem_free(current_context->rtargets[i].art);
		tgt->art = NULL;

		if (!tgt->color)
			continue;

		tgt->art = agp_setup_rendertarget(tgt->color->vstore, tgt->mode);
	}

/* pass two, force update - back to forth to cover dependencies */
	for (ssize_t i = current_context->n_rtargets - 1; i >= 0; i--){
		struct rendertarget* tgt = &current_context->rtargets[i];
		if (!tgt->color)
			continue;
		arcan_video_forceupdate(tgt->color->cellid, true);
	}
}

arcan_errc arcan_video_maxorder(arcan_vobj_id rt, uint16_t* ov)
{
	arcan_vobject* vobj = arcan_video_getobject(rt);
	if (!vobj)
		return ARCAN_ERRC_NO_SUCH_OBJECT;

	struct rendertarget* tgt = arcan_vint_findrt(vobj);
	if (!tgt)
		return ARCAN_ERRC_UNACCEPTED_STATE;

	arcan_vobject_litem* current = current_context->stdoutp.first;
	uint16_t order = 0;

	while (current){
		if (current->elem && current->elem->order > order &&
			current->elem->order < 65531)
			order = current->elem->order;

		current = current->next;
	}

	*ov = order;
	return ARCAN_OK;
}

unsigned arcan_video_contextusage(unsigned* used)
{
	if (used){
		*used = 0;
		for (unsigned i = 1; i < current_context->vitem_limit-1; i++)
			if (FL_TEST(&current_context->vitems_pool[i], FL_INUSE))
				(*used)++;
	}

	return current_context->vitem_limit-1;
}

bool arcan_video_contextsize(unsigned newlim)
{
	if (newlim <= 1 || newlim >= VITEM_CONTEXT_LIMIT)
		return false;

/* this change isn't allowed when the shrink/expand operation would
 * change persistent objects in the stack */
	if (newlim < arcan_video_display.default_vitemlim)
		for (unsigned i = 1; i < current_context->vitem_limit-1; i++)
			if (FL_TEST(&current_context->vitems_pool[i], FL_INUSE|FL_PRSIST))
				return false;

	arcan_video_display.default_vitemlim = newlim;
	return true;
}

void arcan_video_restore_external(bool keep_events)
{
	if (!keep_events)
		arcan_event_init( arcan_event_defaultctx() );

	arcan_event ev = {
		.category = EVENT_VIDEO,
		.vid.kind = EVENT_VIDEO_DISPLAY_RESET,
	};
	arcan_event_enqueue(arcan_event_defaultctx(), &ev);
	platform_video_restore_external();

	platform_video_query_displays();
	agp_shader_rebuild_all();
	arcan_video_popcontext();
	invalidate_rendertargets();
}

static void flag_ctxfsrv_dms(struct arcan_video_context* ctx)
{
	if (!ctx)
		return;

	for (size_t i = 1; i < ctx->vitem_limit; i++){
		if (!FL_TEST(&(ctx->vitems_pool[i]), FL_INUSE))
			continue;

		arcan_vobject* current = &ctx->vitems_pool[i];
		if (current->feed.state.tag ==
			ARCAN_TAG_FRAMESERV && current->feed.state.ptr){
			struct arcan_frameserver* fsrv = current->feed.state.ptr;
			fsrv->flags.no_dms_free = true;
		}
	}
}

extern void platform_video_shutdown();
void arcan_video_shutdown(bool release_fsrv)
{
/* subsystem active or not */
	if (arcan_video_display.in_video == false)
		return;

	arcan_video_display.in_video = false;

/* This will effectively make sure that all external launchers, frameservers
 * etc. gets killed off. If we should release frameservers, individually set
 * their dms flag. */
	if (!release_fsrv)
		flag_ctxfsrv_dms(current_context);

	unsigned lastctxa, lastctxc = arcan_video_popcontext();

/* A bit ugly, the upper context slot gets reallocated on pop as a cheap way
 * of letting the caller 'flush', but since we want to interleave with calls
 * to flag_ctxfsrv_dms, we need to be a bit careful. This approach costs an
 * extra full- iteration, but it's in the shutdown stage - the big time waste
 * here is resetting screen resolution etc. */
	if (!release_fsrv)
		flag_ctxfsrv_dms(current_context);

	while ( lastctxc != (lastctxa = arcan_video_popcontext()) ){
		lastctxc = lastctxa;
		if (lastctxc != lastctxa && !release_fsrv)
			flag_ctxfsrv_dms(current_context);
	}

	agp_shader_flush();
	deallocate_gl_context(current_context, true, NULL);
	arcan_video_reset_fontcache();
	TTF_Quit();
	platform_video_shutdown();
}

arcan_errc arcan_video_tracetag(
	arcan_vobj_id id, const char*const message, const char* const alt)
{
	arcan_errc rv = ARCAN_ERRC_NO_SUCH_OBJECT;
	arcan_vobject* vobj = arcan_video_getobject(id);
	if (!vobj)
		return rv;

	if (vobj->tracetag)
		arcan_mem_free(vobj->tracetag);

	if (vobj->alttext && alt){
		arcan_mem_free(vobj->alttext);
		vobj->alttext = strdup(alt);
	}

	vobj->tracetag = strdup(message);

	return ARCAN_OK;
}

static void update_sourcedescr(struct agp_vstore* ds,
	struct arcan_rstrarg* data)
{
	assert(ds->vinf.text.kind != STORAGE_IMAGE_URI);

	if (ds->vinf.text.kind == STORAGE_TEXT){
		arcan_mem_free(ds->vinf.text.source);
	}
	else if (ds->vinf.text.kind == STORAGE_TEXTARRAY){
		char** work = ds->vinf.text.source_arr;
		while(*work){
			arcan_mem_free(*work);
			work++;
		}
		arcan_mem_free(ds->vinf.text.source_arr);
	}

	if (data->multiple){
		ds->vinf.text.kind = STORAGE_TEXTARRAY;
		ds->vinf.text.source_arr = data->array;
	}
	else {
		ds->vinf.text.kind = STORAGE_TEXT;
		ds->vinf.text.source = data->message;
	}
}

arcan_vobj_id arcan_video_renderstring(arcan_vobj_id src,
	struct arcan_rstrarg data, unsigned int* n_lines,
	struct renderline_meta** lineheights,arcan_errc* errc)
{
#define FAIL(CODE){ if (errc) *errc = CODE; return ARCAN_EID; }
	arcan_vobject* vobj;
	arcan_vobj_id rv = src;

	if (src == ARCAN_VIDEO_WORLDID){
		return ARCAN_ERRC_UNACCEPTED_STATE;
	}

	size_t maxw, maxh, w, h;
	struct agp_vstore* ds;
	uint32_t dsz;

	struct rendertarget* dst = current_context->attachment ?
		current_context->attachment : &current_context->stdoutp;
	arcan_renderfun_outputdensity(dst->hppcm, dst->vppcm);

	if (src == ARCAN_EID){
		vobj = arcan_video_newvobject(&rv);
		if (!vobj)
			FAIL(ARCAN_ERRC_OUT_OF_SPACE);

#define ARGLST src, false, n_lines, \
lineheights, &w, &h, &dsz, &maxw, &maxh, false

		ds = vobj->vstore;
		av_pixel* rawdst = ds->vinf.text.raw;

		vobj->feed.state.tag = ARCAN_TAG_TEXT;
		vobj->blendmode = BLEND_FORCE;

		ds->vinf.text.raw = data.multiple ?
			arcan_renderfun_renderfmtstr_extended((const char**)data.array, ARGLST) :
			arcan_renderfun_renderfmtstr(data.message, ARGLST);

		if (ds->vinf.text.raw == NULL){
			arcan_video_deleteobject(rv);
			FAIL(ARCAN_ERRC_BAD_ARGUMENT);
		}

		ds->vinf.text.vppcm = dst->vppcm;
		ds->vinf.text.hppcm = dst->hppcm;
		ds->vinf.text.kind = STORAGE_TEXT;
		ds->vinf.text.s_raw = dsz;
		ds->w = w;
		ds->h = h;

/* transfer sync is done separately here */
		agp_update_vstore(ds, true);
		arcan_vint_attachobject(rv);
	}
	else {
		vobj = arcan_video_getobject(src);

		if (!vobj)
			FAIL(ARCAN_ERRC_NO_SUCH_OBJECT);
		if (vobj->feed.state.tag != ARCAN_TAG_TEXT)
			FAIL(ARCAN_ERRC_UNACCEPTED_STATE);

		ds = vobj->vstore;

		if (data.multiple)
			arcan_renderfun_renderfmtstr_extended((const char**)data.array, ARGLST);
		else
			arcan_renderfun_renderfmtstr(data.message, ARGLST);

		invalidate_cache(vobj);
		arcan_video_objectscale(vobj->cellid, 1.0, 1.0, 1.0, 0);
	}

	vobj->origw = maxw;
	vobj->origh = maxh;

	update_sourcedescr(ds, &data);

/*
 * POT but not all used,
	vobj->txcos = arcan_alloc_mem(8 * sizeof(float),
		ARCAN_MEM_VSTRUCT, 0, ARCAN_MEMALIGN_SIMD);
	float wv = (float)maxw / (float)vobj->vstore->w;
	float hv = (float)maxh / (float)vobj->vstore->h;
	arcan_vint_defaultmapping(vobj->txcos, wv, hv);
 */
#undef ARGLST
#undef FAIL
	return rv;
}
