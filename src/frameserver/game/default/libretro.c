/*
 * Copyright 2012-2016, Björn Ståhl
 * License: GPLv2, see COPYING file in arcan source repository.
 * Reference: http://www.libretro.com
 */

#define AGP_ENABLE_UNPURE 1

#include <math.h>
#include <stdlib.h>
#include <assert.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <string.h>
#include <strings.h>
#include <pthread.h>
#include <errno.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <inttypes.h>

#ifdef FRAMESERVER_LIBRETRO_3D
#ifdef ENABLE_RETEXTURE
#include "retexture.h"
#endif
#include "video_platform.h"
#include "platform.h"
#define WANT_ARCAN_SHMIF_HELPER
#endif
#include <arcan_shmif.h>

#include <sys/stat.h>
#include <sys/types.h>

#include "frameserver.h"
#include "ntsc/snes_ntsc.h"
#include "sync_plot.h"
#include "libretro.h"

#include "font_8x8.h"

#ifndef MAX_PORTS
#define MAX_PORTS 4
#endif

#ifndef MAX_AXES
#define MAX_AXES 32
#endif

#ifndef MAX_BUTTONS
#define MAX_BUTTONS 16
#endif

#undef BADID

#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))

/* note on synchronization:
 * the async and esync mechanisms will buffer locally and have that buffer
 * flushed by the main application whenever appropriate. For audio, this is
 * likely limited by the buffering capacity of the sound device / pipeline
 * whileas the event queue might be a bit more bursty.
 *
 * however, we will lock to video, meaning that it is the framerate of the
 * frameserver that will decide the actual framerate, that may be locked
 * to VREFRESH (or lower, higher / variable). Thus we also need frameskipping
 * heuristics here.
 */
struct input_port {
	bool buttons[MAX_BUTTONS];
	int16_t axes[MAX_AXES];

/* special offsets into buttons / axes based on device */
	unsigned cursor_x, cursor_y, cursor_btns[5];
};

struct core_variable {
	const char* key;
	const char* value;
	bool updated;
};

typedef void(*pixconv_fun)(const void* data, shmif_pixel* outp,
	unsigned width, unsigned height, size_t pitch, bool postfilter);

static struct {
	struct synch_graphing* sync_data; /* overlaying statistics */

/* flag for rendering callbacks, should the frame be processed or not */
	bool skipframe_a, skipframe_v, empty_v;
	bool in_3d;

/* miliseconds per frame, 1/fps */
	double mspf;

/* when did we last seed gameplay timing */
	long long int basetime;

/* for debugging / testing, added extra jitter to
 * the cost for the different stages */
	int jitterstep, jitterxfer;

/* add 'n' frames pseudoskipping to populate audiobuffers */
	int preaudiogen;
/* user changeable variable, how synching should be treated */
	int skipmode;
/* for frameskip auto to compensate for jitter in transfer etc. */
	int prewake;

/* statistics / timing */
	unsigned long long aframecount, vframecount;
	struct retro_system_av_info avinfo; /* timing according to libretro */

	int rebasecount, frameskips, transfercost, framecost;
	const char* colorspace;

/* colour conversion / filtering */
	pixconv_fun converter;
	uint16_t* ntsc_imb;
	bool ntscconv;
	snes_ntsc_t* ntscctx;
	int ntscvals[4];
	snes_ntsc_setup_t ntsc_opts;

/* SHM- API input /output */
	struct arcan_shmif_cont shmcont;
	int graphmode;

/* libretro states / function pointers */
	struct retro_system_info sysinfo;
	struct retro_game_info gameinfo;

/* for core options support:
 * 1. on SET_VARIABLES, expose each as an event to parent.
 *    populate a separate table that acts as a cache.
 *
 * 2. on GET_VARIABLE, lookup against the args and fallback
 *    on the cache. Dynamic switching isn't supported currently. */
	struct arg_arr* inargs;
	struct core_variable* varset;
	struct arcan_event ident;
	bool optdirty;

/* for skipmode = TARGET_SKIP_ROLLBACK,
 * then we maintain a statebuffer (requires savestate support)
 * and when input is "dirty" roll back one frame ignoring output,
 * apply, then fast forward one frame */
 	bool dirty_input;
	float aframesz;
	int rollback_window;
	unsigned rollback_front;
	char* rollback_state;
	size_t state_sz;
	char* syspath;
	bool res_empty;

/*
 * performance trim-values for video/audio buffer synchronization
 */
	uint16_t def_abuf_sz;
	uint8_t abuf_cnt, vbuf_cnt;

#ifdef FRAMESERVER_LIBRETRO_3D
	struct retro_hw_render_callback hwctx;
	bool got_3dframe;
#endif

/* parent uses an event->push model for input, libretro uses a poll one, so
 * prepare a lookup table that events gets pushed into and libretro can poll */
	struct input_port input_ports[MAX_PORTS];
	char kbdtbl[RETROK_LAST];

	void (*run)();
	void (*reset)();
	bool (*load_game)(const struct retro_game_info* game);
	size_t (*serialize_size)();
	bool (*serialize)(void*, size_t);
	bool (*deserialize)(const void*, size_t);
	void (*set_ioport)(unsigned, unsigned);
} retro = {
	.abuf_cnt = 12,
	.def_abuf_sz = 1,
	.vbuf_cnt = 3,
	.prewake = 10,
	.preaudiogen = 1,
	.skipmode = TARGET_SKIP_AUTO
};

/* render statistics unto *vidp, at the very end of this .c file */
static void update_ntsc();
static void push_stats();

#ifdef FRAMESERVER_LIBRETRO_3D
static void setup_3dcore(struct retro_hw_render_callback*);
#endif

static void* lastlib, (* globallib);
retro_proc_address_t libretro_requirefun(const char* sym)
{
/* not very relevant here, but proper form is dlerror() */
	if (!sym)
		return NULL;

/*
  if (module){
		if (lastlib)
			return dlsym(lastlib, sym);
		else
			return NULL;
	}
 */

	return dlsym(lastlib, sym);
}

static bool write_handle(const void* const data,
	size_t sz_data, file_handle dst, bool finalize)
{
	bool rv = false;

	if (dst != BADFD)
	{
		off_t ofs = 0;
		ssize_t nw;

		while ( ofs != sz_data){
			nw = write(dst, ((char*) data) + ofs, sz_data - ofs);
			if (-1 == nw)
				switch (errno){
				case EAGAIN: continue;
				case EINTR: continue;
				default:
					LOG("write_handle(dumprawfile) -- write failed (%d),"
					"	reason: %s\n", errno, strerror(errno));
					goto out;
			}

			ofs += nw;
		}
		rv = true;

		out:
		if (finalize)
			close(dst);
	}
	 else
		 LOG("write_handle(dumprawfile) -- request to dump to invalid "
			"file handle ignored, no output set by parent.\n");

	return rv;
}

static void resize_shmpage(int neww, int newh, bool first)
{
	if (retro.shmcont.abufpos){
		LOG("resize(), force flush %zu samples\n", (size_t)retro.shmcont.abufpos);
		arcan_shmif_signal(&retro.shmcont, SHMIF_SIGAUD | SHMIF_SIGBLK_NONE);
	}

#ifdef FRAMESERVER_LIBRETRO_3D
	if (retro.in_3d)
		retro.shmcont.hints = SHMIF_RHINT_ORIGO_LL;
#endif

	if (!arcan_shmif_resize_ext(&retro.shmcont, neww, newh,
		(struct shmif_resize_ext){
			.abuf_sz = 1024,
			.samplerate = retro.avinfo.timing.sample_rate,
			.abuf_cnt = retro.abuf_cnt,
			.vbuf_cnt = retro.vbuf_cnt})){
		LOG("resizing shared memory page failed\n");
		exit(1);
	}
	else {
		LOG("requested resize to (%d * %d), %d 1k audio buffers, "
				"%d video buffers\n", neww, newh, retro.abuf_cnt, retro.vbuf_cnt);
	}

#ifdef FRAMESERVER_LIBRETRO_3D
	if (retro.in_3d)
		arcan_shmifext_make_current(&retro.shmcont);

	if (!getenv("GAME_NORESET") && retro.hwctx.context_reset)
		retro.hwctx.context_reset();
#endif

	if (retro.sync_data)
		retro.sync_data->cont_switch(retro.sync_data, &retro.shmcont);

/* will be reallocated if needed and not set so just free and unset */
	if (retro.ntsc_imb){
		free(retro.ntsc_imb);
		retro.ntsc_imb = NULL;
	}
}

/* overrv / overra are needed for handling rollbacks etc.
 * while still making sure the other frameskipping options are working */
static void process_frames(int nframes, bool overrv, bool overra)
{
	bool cv = retro.skipframe_v;
	bool ca = retro.skipframe_a;

	if (overrv)
		retro.skipframe_v = true;

	if (overra)
		retro.skipframe_a = true;

	while(nframes--)
		retro.run();

	if (retro.skipmode <= TARGET_SKIP_ROLLBACK){
		retro.serialize(retro.rollback_state +
			(retro.rollback_front * retro.state_sz), retro.state_sz);
		retro.rollback_front = (retro.rollback_front + 1)
			% retro.rollback_window;
	}

	retro.skipframe_v = cv;
	retro.skipframe_a = ca;
}

#define RGB565(b, g, r) ((uint16_t)(((uint8_t)(r) >> 3) << 11) | \
								(((uint8_t)(g) >> 2) << 5) | ((uint8_t)(b) >> 3))

static void push_ntsc(unsigned width, unsigned height,
	const uint16_t* ntsc_imb, shmif_pixel* outp)
{
	size_t linew = SNES_NTSC_OUT_WIDTH(width) * 4;

/* only draw on every other line, so we can easily mix or
 * blend interleaved (or just duplicate) */
	snes_ntsc_blit(retro.ntscctx, ntsc_imb, width, 0,
		width, height, outp, linew * 2);

/* this might be a possible test-case for running two shmif
 * connections and let the compositor do interlacing management */
	assert(ARCAN_SHMPAGE_VCHANNELS == 4);
	for (int row = 1; row < height * 2; row += 2)
		memcpy(& ((char*) retro.shmcont.vidp)[row * linew],
			&((char*) retro.shmcont.vidp)[(row-1) * linew], linew);
}

/* better distribution for conversion (white is white ..) */
static const uint8_t rgb565_lut5[] = {
  0,   8,  16,  25,  33,  41,  49,  58,  66,   74,  82,  90,  99, 107, 115,123,
132, 140, 148, 156, 165, 173, 181, 189,  197, 206, 214, 222, 230, 239, 247,255
};

static const uint8_t rgb565_lut6[] = {
  0,   4,   8,  12,  16,  20,  24,  28,  32,  36,  40,  45,  49,  53,  57, 61,
 65,  69,  73,  77,  81,  85,  89,  93,  97, 101, 105, 109, 113, 117, 121, 125,
130, 134, 138, 142, 146, 150, 154, 158, 162, 166, 170, 174, 178, 182, 186, 190,
194, 198, 202, 206, 210, 215, 219, 223, 227, 231, 235, 239, 243, 247, 251, 255
};

static void libretro_rgb565_rgba(const uint16_t* data, shmif_pixel* outp,
	unsigned width, unsigned height, size_t pitch)
{
	uint16_t* interm = retro.ntsc_imb;
	retro.colorspace = "RGB565->RGBA";

/* with NTSC on, the input format is already correct */
	for (int y = 0; y < height; y++){
		for (int x = 0; x < width; x++){
			uint16_t val = data[x];
			uint8_t r = rgb565_lut5[ (val & 0xf800) >> 11 ];
			uint8_t g = rgb565_lut6[ (val & 0x07e0) >> 5  ];
			uint8_t b = rgb565_lut5[ (val & 0x001f)       ];

			if (retro.ntscconv)
				*interm++ = RGB565(r, g, b);
			else
				*outp++ = RGBA(r, g, b, 0xff);
		}
		data += pitch >> 1;
	}

	if (retro.ntscconv)
		push_ntsc(width, height, retro.ntsc_imb, outp);

	return;
}

static void libretro_xrgb888_rgba(const uint32_t* data, uint32_t* outp,
	unsigned width, unsigned height, size_t pitch)
{
	assert( (uintptr_t)data % 4 == 0 );
	retro.colorspace = "XRGB888->RGBA";

	uint16_t* interm = retro.ntsc_imb;

	for (int y = 0; y < height; y++){
		for (int x = 0; x < width; x++){
			uint8_t* quad = (uint8_t*) (data + x);
			if (retro.ntscconv)
				*interm++ = RGB565(quad[2], quad[1], quad[0]);
			else
				*outp++ = RGBA(quad[2], quad[1], quad[0], 0xff);
		}

		data += pitch >> 2;
	}

	if (retro.ntscconv)
		push_ntsc(width, height, retro.ntsc_imb, outp);
}

static void libretro_rgb1555_rgba(const uint16_t* data, uint32_t* outp,
	unsigned width, unsigned height, size_t pitch, bool postfilter)
{
	uint16_t* interm = retro.ntsc_imb;
	retro.colorspace = "RGB1555->RGBA";

	unsigned dh = height >= ARCAN_SHMPAGE_MAXH ? ARCAN_SHMPAGE_MAXH : height;
	unsigned dw =  width >= ARCAN_SHMPAGE_MAXW ? ARCAN_SHMPAGE_MAXW : width;

	for (int y = 0; y < dh; y++){
		for (int x = 0; x < dw; x++){
			uint16_t val = data[x];
			uint8_t r = ((val & 0x7c00) >> 10) << 3;
			uint8_t g = ((val & 0x03e0) >>  5) << 3;
			uint8_t b = ( val & 0x001f) <<  3;

			if (postfilter)
				*interm++ = RGB565(r, g, b);
			else
				*outp++ = RGBA(r, g, b, 0xff);
		}

		data += pitch >> 1;
	}

	if (postfilter)
		push_ntsc(width, height, retro.ntsc_imb, outp);
}


static int testcounter;
static void libretro_vidcb(const void* data, unsigned width,
	unsigned height, size_t pitch)
{
	testcounter++;

	if (retro.in_3d && !data)
		;
	else if (!data || retro.skipframe_v){
		retro.empty_v = true;
		return;
	}
	else
		retro.empty_v = false;

/* width / height can be changed without notice, so we have to be ready for the
 * fact that the cost of conversion can suddenly move outside the allowed
 * boundaries, then NTSC is ignored (or if we have 3d/hw source) */
	unsigned outw = width;
	unsigned outh = height;
	bool ntscconv = retro.ntscconv && data != RETRO_HW_FRAME_BUFFER_VALID;

	if (ntscconv && SNES_NTSC_OUT_WIDTH(width)<= ARCAN_SHMPAGE_MAXW
		&& height * 2 <= ARCAN_SHMPAGE_MAXH){
		outh = outh << 1;
		outw = SNES_NTSC_OUT_WIDTH( width );
	}
	else {
		outw = width;
		outh = height;
		ntscconv = false;
	}

/* the shmpage size will be larger than the possible values for width / height,
 * so if we have a mismatch, just change the shared dimensions and toggle
 * resize flag */
	if (outw != retro.shmcont.addr->w || outh != retro.shmcont.addr->h){
		resize_shmpage(outw, outh, false);
	}

	if (ntscconv && !retro.ntsc_imb){
		retro.ntsc_imb = malloc(sizeof(uint16_t) * outw * outh);
	}

#ifdef FRAMESERVER_LIBRETRO_3D
/* method one, just read color attachment */
	if (retro.in_3d){
/* it seems like tons of cores doesn't actually set this correctly */
		retro.got_3dframe = 1 || data == RETRO_HW_FRAME_BUFFER_VALID;
		return;
	}
	else
#endif

/* lastly, convert / blit, this will possibly clip */
	if (retro.converter)
		retro.converter(data, retro.shmcont.vidp, width,
			height, pitch, ntscconv);
}

static void do_preaudio()
{
	if (retro.preaudiogen == 0)
		return;

	retro.skipframe_v = true;
	retro.skipframe_a = false;

	int afc = retro.aframecount;
	int vfc = retro.vframecount;

	for (int i = 0; i < retro.preaudiogen; i++)
		retro.run();

	retro.skipframe_v = false;
	retro.aframecount = afc;
	retro.vframecount = vfc;
}

static void libretro_skipnframes(unsigned count, bool fastfwd)
{
	retro.skipframe_v = true;
	retro.skipframe_a = fastfwd;

	long long afc = retro.aframecount;

	for (int i = 0; i < count; i++)
		retro.run();

	if (fastfwd){
		retro.aframecount = afc;
		retro.frameskips += count;
	}
	else
		retro.vframecount += count;

	retro.skipframe_a = false;
	retro.skipframe_v = false;
}

static void reset_timing(bool newstate)
{
	arcan_shmif_enqueue(&retro.shmcont, &(arcan_event){
		.ext.kind = ARCAN_EVENT(FLUSHAUD)
	});
	retro.basetime = arcan_timemillis();
	do_preaudio();
	retro.vframecount = 1;
	retro.aframecount = 1;
	retro.frameskips  = 0;
	if (!newstate){
		retro.rebasecount++;
	}

/* since we can't be certain about our current vantage point...*/
	if (newstate && retro.skipmode <= TARGET_SKIP_ROLLBACK &&
		retro.state_sz > 0){
		retro.rollback_window = (TARGET_SKIP_ROLLBACK - retro.skipmode) + 1;
		if (retro.rollback_window > 10)
			retro.rollback_window = 10;

		free(retro.rollback_state);
		retro.rollback_state = malloc(retro.state_sz * retro.rollback_window);
		retro.rollback_front = 0;

		retro.serialize(retro.rollback_state, retro.state_sz);
		for (int i=1; i < retro.rollback_window - 1; i++)
			memcpy(retro.rollback_state + (i*retro.state_sz),
				retro.rollback_state, retro.state_sz);

		LOG("setting input rollback (%d)\n", retro.rollback_window);
	}
}

static void libretro_audscb(int16_t left, int16_t right)
{
	if (retro.skipframe_a)
		return;

	retro.aframecount++;
	retro.shmcont.audp[retro.shmcont.abufpos++] = SHMIF_AINT16(left);
	retro.shmcont.audp[retro.shmcont.abufpos++] = SHMIF_AINT16(right);

	if (retro.shmcont.abufpos >= retro.shmcont.abufcount){
		long long elapsed = arcan_shmif_signal(&retro.shmcont, SHMIF_SIGAUD | SHMIF_SIGBLK_NONE);
		LOG("audio buffer synch cost (%lld) ms\n", elapsed);
	}
}

static size_t libretro_audcb(const int16_t* data, size_t nframes)
{
	if (retro.skipframe_a)
		return nframes;

/* from FRAMES to SAMPLES */
	size_t left = nframes * 2;

	while (left){
		size_t bfree = retro.shmcont.abufcount - retro.shmcont.abufpos;
		bool flush = false;
		size_t ntw;

		if (left > bfree){
			ntw = bfree;
			flush = true;
		}
		else {
			ntw = left;
			flush = false;
		}

/* this is in BYTES not SAMPLES or FRAMES */
		memcpy(&retro.shmcont.audp[retro.shmcont.abufpos], data, ntw * 2);
		left -= ntw;
		data += ntw;
		retro.shmcont.abufpos += ntw;
		if (flush){
			long long elapsed = arcan_shmif_signal(&retro.shmcont, SHMIF_SIGAUD | SHMIF_SIGBLK_NONE);
			LOG("audio buffer synch cost (%lld) ms\n", elapsed);
		}
	}

	retro.aframecount += nframes;
	return nframes;
}

/* we ignore these since before pushing for a frame,
 * we've already processed the queue */
static void libretro_pollcb(){}

static const char* lookup_varset( const char* key )
{
	struct core_variable* var = retro.varset;
	char buf[ strlen(key) + sizeof("core_") + 1];
	snprintf(buf, sizeof(buf), "core_%s", key);
	const char* val = NULL;

/* we have an initial preset, only update if dirty,
 * note: this might not be necessary anymore, test and drop */
	if (arg_lookup(retro.inargs, buf, 0, &val)){
		if (var)
			while(var->key){
				if (var->updated && strcmp(var->key, key) == 0){
					return var->value;
				}

				var++;
			}

	}
/* no preset, just return the first match */
	else if (var) {
		while (var->key){
			if (strcmp(var->key, key) == 0)
				return var->value;

			var++;
		}
	}

	return val;
}

/* from parent, not all cores support dynamic arguments
 * so this is just a complement to launch arguments */
static void update_corearg(int code, const char* value)
{
	struct core_variable* var = retro.varset;
	while (var && var->key && code--)
		var++;

	if (code <= 0){
		free((char*)var->value);
		var->value = strdup(value);
		var->updated = true;
	}
}

static void update_varset( struct retro_variable* data )
{
	int count = 0;
	arcan_event outev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(COREOPT)
	};

	size_t msgsz = COUNT_OF(outev.ext.coreopt.data);

/* reset current varset */
	if (retro.varset){
		while (retro.varset[count].key){
			free((char*)retro.varset[count].key);
			free((char*)retro.varset[count].value);
			count++;
		}

		free(retro.varset);
		retro.varset = NULL;
		count = 0;
	}

/* allocate a new set */
	while ( data[count].key )
		count++;

	if (count == 0)
		return;

	count++;
	retro.varset = malloc( sizeof(struct core_variable) * count);
	memset(retro.varset, '\0', sizeof(struct core_variable) * count);

	count = 0;
	while ( data[count].key ){
		retro.varset[count].key = strdup(data[count].key);
		outev.ext.coreopt.index = count;

/* parse, grab the first argument and keep in table,
 * queue the argument as a series of event to the parent */
		if (data[count].value){
			bool gotval = false;
			char* msg = strdup(data[count].value);
			char* workbeg = msg;
			char* workend = msg;

/* message */
			while (*workend && *workend != ';') workend++;

			if (*workend != ';'){
				LOG("malformed core argument (%s:%s)\n", data[count].key,
					data[count].value);
				goto step;
			}
			*workend++ = '\0';

			if (msgsz < strlen(workbeg)){
				LOG("suspiciously long description (%s:%s), %d\n", data[count].key,
					workbeg, (int)msgsz);
				goto step;
			}

/* skip leading whitespace */
		while(*workend && *workend == ' ') workend++;

/* key */
			outev.ext.coreopt.type = 0;
			snprintf((char*)outev.ext.coreopt.data, msgsz, "%s", data[count].key);
			arcan_shmif_enqueue(&retro.shmcont, &outev);
/* description */
			outev.ext.coreopt.type = 1;
			snprintf((char*)outev.ext.coreopt.data, msgsz, "%s", workbeg);
			arcan_shmif_enqueue(&retro.shmcont, &outev);

/* each option */
startarg:
			workbeg = workend;
			while (*workend && *workend != '|') workend++;

/* treats || as erroneous */
			if (strlen(workbeg) > 0){
				if (*workend == '|')
					*workend++ = '\0';

				if (!gotval && (gotval = true))
					retro.varset[count].value = strdup(workbeg);

				outev.ext.coreopt.type = 2;
				snprintf((char*)outev.ext.coreopt.data, msgsz, "%s", workbeg);
				arcan_shmif_enqueue(&retro.shmcont, &outev);

				goto startarg;
			}

			const char* curv = lookup_varset(data[count].key);
			if (curv){
				outev.ext.coreopt.type = 3;
				snprintf((char*)outev.ext.coreopt.data, msgsz, "%s", curv);
				arcan_shmif_enqueue(&retro.shmcont, &outev);
			}

step:
			free(msg);
		}

		count++;
	}
}

static void libretro_log(enum retro_log_level level, const char* fmt, ...)
{
}

static struct retro_log_callback log_cb = {
	.log = libretro_log
};

static bool libretro_setenv(unsigned cmd, void* data){
	bool rv = true;

	if (!retro.shmcont.addr)
		return false;

	switch (cmd){
	case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:

		switch ( *(enum retro_pixel_format*) data ){
		case RETRO_PIXEL_FORMAT_0RGB1555:
			LOG("pixel format set to RGB1555\n");
			retro.converter = (pixconv_fun) libretro_rgb1555_rgba;
		break;

		case RETRO_PIXEL_FORMAT_RGB565:
			LOG("pixel format set to RGB565\n");
			retro.converter = (pixconv_fun) libretro_rgb565_rgba;
		break;

		case RETRO_PIXEL_FORMAT_XRGB8888:
			LOG("pixel format set to XRGB8888\n");
			retro.converter = (pixconv_fun) libretro_xrgb888_rgba;
		break;

		default:
			LOG("unknown pixelformat encountered (%d).\n", *(unsigned*)data);
			retro.converter = NULL;
		}
	break;

	case RETRO_ENVIRONMENT_GET_CAN_DUPE:
		*((bool*) data) = true;
	break;

	case RETRO_ENVIRONMENT_SHUTDOWN:
		arcan_shmif_drop(&retro.shmcont);
		exit(EXIT_SUCCESS);
	break;

	case RETRO_ENVIRONMENT_SET_VARIABLES:
		update_varset( (struct retro_variable*) data );
	break;

	case RETRO_ENVIRONMENT_GET_VARIABLE:
		{
			struct retro_variable* arg = (struct retro_variable*) data;
			const char* val = lookup_varset(arg->key);
			if (val){
				arg->value = val;
				LOG("core requested (%s), got (%s)\n", arg->key, arg->value);
				rv = true;
			}
		}
	break;

	case RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL:
/* don't care */
	break;

	case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
		rv = retro.optdirty;
		if (data)
			*(bool*)data = rv;
		retro.optdirty = false;
	break;

	case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
		*((const char**) data) = retro.syspath;
		rv = retro.syspath != NULL;
		LOG("system directory set to (%s).\n",
			retro.syspath ? retro.syspath : "MISSING");
	break;

	case RETRO_ENVIRONMENT_SET_FRAME_TIME_CALLBACK:
		LOG("frame-time callback unsupported.\n");
		rv = false;
	break;

	case RETRO_ENVIRONMENT_GET_RUMBLE_INTERFACE:
		LOG("rumble- interfaces unsupported.\n");
		rv = false;
	break;

	case RETRO_ENVIRONMENT_GET_PERF_INTERFACE:
		LOG("performance- interfaces unsupported.\n");
		rv = false;
	break;

	case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
		retro.res_empty = true;
	break;

	case RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK:
		LOG("retro- keyboard callback unsupported.\n");
		rv = false;
	break;

	case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
		*((struct retro_log_callback*) data) = log_cb;
	break;

	case RETRO_ENVIRONMENT_GET_USERNAME:
		*((const char**) data) = strdup("defusr");
	break;

	case RETRO_ENVIRONMENT_GET_LANGUAGE:
		*((unsigned*) data) = RETRO_LANGUAGE_ENGLISH;
	break;

#ifdef FRAMESERVER_LIBRETRO_3D
	case RETRO_ENVIRONMENT_SET_HW_RENDER | RETRO_ENVIRONMENT_EXPERIMENTAL:
	case RETRO_ENVIRONMENT_SET_HW_RENDER:
	{
/* this should be matched with AGP model rather than statically
 * set that we only care about GL, doesn't look like any core rely
 * on this behavior though */
		struct retro_hw_render_callback* hwrend = data;
		if (hwrend->context_type == RETRO_HW_CONTEXT_OPENGL ||
			hwrend->context_type == RETRO_HW_CONTEXT_OPENGL_CORE){
			setup_3dcore( hwrend );
		}
		else
			LOG("unsupported hw context requested.\n");
	}
	break;
#else
	case RETRO_ENVIRONMENT_SET_HW_RENDER | RETRO_ENVIRONMENT_EXPERIMENTAL:
	case RETRO_ENVIRONMENT_SET_HW_RENDER:
		LOG("trying to load a GL/3D enabled core, but "
			"frameserver was built without 3D support.\n");
		rv = false;
	break;
#endif

	default:
		rv = false;
#ifdef _DEBUG
		LOG("unhandled retro request (%d)\n", cmd);
#endif
	}

	return rv;
}

/*
 * this is quite sensitive to changes in libretro.h
 */
static inline int16_t map_analog_axis(unsigned port, unsigned ind, unsigned id)
{
	ind *= 2;
	ind += id;
	assert(ind < MAX_AXES);

	return (int16_t) retro.input_ports[port].axes[ind];
}

/* use the context-tables from retro in combination with dev / ind / ... to
 * figure out what to return, this table is populated in flush_eventq(). */
static inline int16_t libretro_inputmain(unsigned port, unsigned dev,
	unsigned ind, unsigned id){
	static bool butn_warning = false;
	static bool port_warning = false;

	if (id > MAX_BUTTONS){
		if (butn_warning == false)
			LOG("unexpectedly high button index (dev:%u)(%u:%%) "
				"requested, ignoring.\n", ind, id);

		butn_warning = true;
		return 0;
	}

	if (port >= MAX_PORTS){
		if (port_warning == false)
			LOG("core requested unknown port (%u:%u:%u), ignored.\n", dev, ind, id);

		port_warning = true;
		return 0;
	}

	int16_t rv = 0;
	struct input_port* inp;

	switch (dev){
		case RETRO_DEVICE_JOYPAD:
			return (int16_t) retro.input_ports[port].buttons[id];
		break;

		case RETRO_DEVICE_KEYBOARD:
			if (id < RETROK_LAST)
				rv |= retro.kbdtbl[id];
		break;

		case RETRO_DEVICE_MOUSE:
			if (port == 1) port = 0;
			inp = &retro.input_ports[port];
			switch (id){
				case RETRO_DEVICE_ID_MOUSE_LEFT:
					return inp->buttons[ inp->cursor_btns[0] ];

				case RETRO_DEVICE_ID_MOUSE_RIGHT:
					return inp->buttons[ inp->cursor_btns[2] ];

				case RETRO_DEVICE_ID_MOUSE_X:
					rv = inp->axes[ inp->cursor_x ];
					inp->axes[ inp->cursor_x ] = 0;
					return rv;

				case RETRO_DEVICE_ID_MOUSE_Y:
					rv = inp->axes[ inp->cursor_y ];
					inp->axes[ inp->cursor_y ] = 0;
					return rv;
			}
		break;

		case RETRO_DEVICE_LIGHTGUN:
			switch (id){
				case RETRO_DEVICE_ID_LIGHTGUN_X:
					return (int16_t) retro.input_ports[port].axes[
						retro.input_ports[port].cursor_x
					];

				case RETRO_DEVICE_ID_LIGHTGUN_Y:
					return (int16_t) retro.input_ports[port].axes[
						retro.input_ports[port].cursor_y
					];

				case RETRO_DEVICE_ID_LIGHTGUN_TRIGGER:
					return (int16_t) retro.input_ports[port].buttons[
						retro.input_ports[port].cursor_btns[0]
					];

				case RETRO_DEVICE_ID_LIGHTGUN_CURSOR:
					return (int16_t) retro.input_ports[port].buttons[
						retro.input_ports[port].cursor_btns[1]
					];

				case RETRO_DEVICE_ID_LIGHTGUN_START:
					return (int16_t) retro.input_ports[port].buttons[
					retro.input_ports[port].cursor_btns[2]
				];

					case RETRO_DEVICE_ID_LIGHTGUN_TURBO:
					return (int16_t) retro.input_ports[port].buttons[
					retro.input_ports[port].cursor_btns[3]
				];

				case RETRO_DEVICE_ID_LIGHTGUN_PAUSE:
					return (int16_t) retro.input_ports[port].buttons[
					retro.input_ports[port].cursor_btns[4]
				];
		}
		break;

		case RETRO_DEVICE_ANALOG:
			return map_analog_axis(port, ind, id);

		break;

		default:
			LOG("Unknown device ID specified (%d), video will be disabled.\n", dev);
	}

	return 0;
}

static void enable_graphseg()
{
	struct arcan_shmif_cont cont =
		arcan_shmif_acquire(&retro.shmcont,
			NULL, SEGID_DEBUG, SHMIF_DISABLE_GUARD);

	if (!cont.addr){
		LOG("segment transfer failed, investigate.\n");
		return;
	}

	if (!arcan_shmif_resize(&cont, 640, 180)){
		LOG("resize failed on debug graph context\n");
		return;
	}

	struct arcan_shmif_cont* pcont = malloc(sizeof(struct arcan_shmif_cont));

	if (retro.sync_data)
		retro.sync_data->free(&retro.sync_data);

	*pcont = cont;
	retro.sync_data = setup_synch_graph(pcont, false);
}

static int16_t libretro_inputstate(unsigned port, unsigned dev,
	unsigned ind, unsigned id)
{
	int16_t rv = libretro_inputmain(port, dev, ind, id);
/* indirection to be used for debug graphing what inputs
 * the core actually requested */
	return rv;
}

static int remaptbl[] = {
	RETRO_DEVICE_ID_JOYPAD_A,
	RETRO_DEVICE_ID_JOYPAD_B,
	RETRO_DEVICE_ID_JOYPAD_X,
	RETRO_DEVICE_ID_JOYPAD_Y,
	RETRO_DEVICE_ID_JOYPAD_L,
	RETRO_DEVICE_ID_JOYPAD_R,
	RETRO_DEVICE_ID_JOYPAD_L2,
	RETRO_DEVICE_ID_JOYPAD_R2,
	RETRO_DEVICE_ID_JOYPAD_L3,
	RETRO_DEVICE_ID_JOYPAD_R3
};

/*
 * A static default input layout for apps that provide no
 * higher-level semantic translation on its own.
 */
static void default_map(arcan_ioevent* ioev)
{
	if (ioev->datatype == EVENT_IDATATYPE_TRANSLATED){
		int button = -1;
		int port = -1;

/* happy coincidence, keysyms here match retro_key (as they both
 * originate from SDL) */
		switch(ioev->input.translated.keysym){
		case RETROK_x:
			port = 0;
			button = RETRO_DEVICE_ID_JOYPAD_A;
		break;
		case RETROK_z:
			port = 0;
			button = RETRO_DEVICE_ID_JOYPAD_B;
		break;
		case RETROK_a:
			port = 0;
			button = RETRO_DEVICE_ID_JOYPAD_Y;
		break;
		case RETROK_s:
			port = 0;
			button = RETRO_DEVICE_ID_JOYPAD_X;
		break;
		case RETROK_RETURN:
			port = 0;
			button = RETRO_DEVICE_ID_JOYPAD_START;
		break;
		case RETROK_RSHIFT:
			port = 0;
			button = RETRO_DEVICE_ID_JOYPAD_SELECT;
		break;
		case RETROK_LEFT:
			port = 0;
			button = RETRO_DEVICE_ID_JOYPAD_LEFT;
		break;
		case RETROK_RIGHT:
			port = 0;
			button = RETRO_DEVICE_ID_JOYPAD_RIGHT;
		break;
		case RETROK_UP:
			port = 0;
			button = RETRO_DEVICE_ID_JOYPAD_UP;
		break;
		case RETROK_DOWN:
			port = 0;
			button = RETRO_DEVICE_ID_JOYPAD_DOWN;
		break;
		}

		if (-1 != button && -1 != port){
			retro.input_ports[
				port].buttons[button] = ioev->input.translated.active;
		}
	}
	else if (ioev->devkind == EVENT_IDEVKIND_GAMEDEV){
		int port_number = ioev->devid % MAX_PORTS;
		int button_number = ioev->subid % MAX_BUTTONS;
		int button = remaptbl[button_number];
		retro.input_ports[
			port_number].buttons[button] = ioev->input.digital.active;
	}
}

static void ioev_ctxtbl(arcan_ioevent* ioev, const char* label)
{
	size_t remaptbl_sz = sizeof(remaptbl) / sizeof(remaptbl[0]) - 1;
	int ind, button = -1, axis;
	char* subtype;

/*
 * if the calling script does no translation of its own
 */
	if (label[0] == '\0'){
		return default_map(ioev);
	}

	if (!retro.dirty_input && retro.sync_data)
		retro.sync_data->mark_input(retro.sync_data, arcan_timemillis());

	retro.dirty_input = true;

	signed value = ioev->datatype == EVENT_IDATATYPE_TRANSLATED ?
		ioev->input.translated.active : ioev->input.digital.active;

	if (1 == sscanf(label, "PLAYER%d_", &ind) && ind > 0 &&
		ind <= MAX_PORTS && (subtype = strchr(label, '_')) ){
		subtype++;

		if (1 == sscanf(subtype, "BUTTON%d", &button) && button > 0 &&
			button <= MAX_BUTTONS - remaptbl_sz){
			button--;
			button = remaptbl[button];
		}
		else if (1 == sscanf(subtype, "AXIS%d", &axis) && axis > 0
			&& axis <= MAX_AXES){
			retro.input_ports[ind-1].axes[ axis - 1 ] =
				ioev->input.analog.gotrel ?
				ioev->input.analog.axisval[0] :
				ioev->input.analog.axisval[1];
		}
		else if ( strcmp(subtype, "UP") == 0 )
			button = RETRO_DEVICE_ID_JOYPAD_UP;
		else if ( strcmp(subtype, "DOWN") == 0 )
			button = RETRO_DEVICE_ID_JOYPAD_DOWN;
		else if ( strcmp(subtype, "LEFT") == 0 )
			button = RETRO_DEVICE_ID_JOYPAD_LEFT;
		else if ( strcmp(subtype, "RIGHT") == 0 )
			button = RETRO_DEVICE_ID_JOYPAD_RIGHT;
		else if ( strcmp(subtype, "SELECT") == 0 )
			button = RETRO_DEVICE_ID_JOYPAD_SELECT;
		else if ( strcmp(subtype, "START") == 0 )
			button = RETRO_DEVICE_ID_JOYPAD_START;
		else;
		if (button >= 0)
			retro.input_ports[ind-1].buttons[button] = value;
	}
	else if (ioev->datatype == EVENT_IDATATYPE_TRANSLATED){
		if (ioev->input.translated.keysym < RETROK_LAST)
			retro.kbdtbl[ioev->input.translated.keysym] = value;
	}
}

static void toggle_ntscfilter(int toggle)
{
	if (retro.ntscconv && toggle == 0){
		free(retro.ntsc_imb);
		retro.ntsc_imb = NULL;
		retro.ntscconv = false;
	}
	else if (!retro.ntscconv && toggle == 1) {
/* malloc etc. happens in resize */
		retro.ntscconv = true;
	}
}

static inline void targetev(arcan_event* ev)
{
	arcan_tgtevent* tgt = &ev->tgt;
	switch (tgt->kind){
		case TARGET_COMMAND_RESET:
		switch(tgt->ioevs[0].iv){
		case 0:
		case 1:
			retro.reset();
		break;
		case 2:
		case 3:
/* send coreargs too */
			if (retro.sync_data){
				retro.sync_data->free(&retro.sync_data);
				retro.sync_data = NULL;
			}
			arcan_shmif_enqueue(&retro.shmcont, &retro.ident);
			reset_timing(true);
		break;
		}
		break;

		case TARGET_COMMAND_GRAPHMODE:
			if (tgt->ioevs[0].iv == 1 || tgt->ioevs[1].iv == 2){
				toggle_ntscfilter(tgt->ioevs[1].iv - 1);
			}
			else if (tgt->ioevs[0].iv == 3){
				retro.ntscvals[0] = tgt->ioevs[1].fv;
				retro.ntscvals[1] = tgt->ioevs[2].fv;
				retro.ntscvals[2] = tgt->ioevs[3].fv;
				retro.ntscvals[3] = tgt->ioevs[4].fv;
				update_ntsc();
			}
		break;

/* 0 : auto, -1 : single-step, > 0 render every n frames.
 * with 0, the second ioev defines pre-wake. -1 (last frame cost),
 * 0 (whatever), 1..mspf-1
 * ioev[2] audio preemu- frames, whenever the counter is reset,
 * perform n extra run()
 * passes to populate audiobuffer -- increases latency but reduces pops..
 * ioev[3] debugging
 * options -- added emulation cost ms (0 default, +n constant n ms,
 * -n 1..abs(n) random)
 */
		case TARGET_COMMAND_FRAMESKIP:
			retro.skipmode    = tgt->ioevs[0].iv;
			retro.prewake     = tgt->ioevs[1].iv;
			retro.preaudiogen = tgt->ioevs[2].iv;
			retro.jitterstep  = tgt->ioevs[3].iv;
			retro.jitterxfer  = tgt->ioevs[4].iv;
			reset_timing(true);
		break;

/*
 * multiple possible receivers, e.g.
 * retexture transfer page, debugwindow or secondary etc. screens
 */
		case TARGET_COMMAND_NEWSEGMENT:
			if (tgt->ioevs[2].iv == SEGID_DEBUG)
				enable_graphseg();
		break;

/* can safely assume there are no other events in the queue after this one,
 * more important for encode etc. that need to flush codecs */
		case TARGET_COMMAND_EXIT:
			arcan_shmif_drop(&retro.shmcont);
			exit(EXIT_SUCCESS);
		break;

		case TARGET_COMMAND_DISPLAYHINT:
/* don't do anything about these, scaling is implemented arcan - side */
		break;

		case TARGET_COMMAND_COREOPT:
			retro.optdirty = true;
			update_corearg(tgt->code, tgt->message);
		break;

		case TARGET_COMMAND_SETIODEV:
			retro.set_ioport(tgt->ioevs[0].iv, tgt->ioevs[1].iv);
		break;

/* should also emit a corresponding event back with the current framenumber */
		case TARGET_COMMAND_STEPFRAME:
			if (tgt->ioevs[0].iv < 0);
				else
					while(tgt->ioevs[0].iv--)
						retro.run();
		break;

/* store / rewind operate on the last FD set through FDtransfer */
		case TARGET_COMMAND_STORE:
		{
			size_t dstsize = retro.serialize_size();
			void* buf;
			if (dstsize && ( buf = malloc( dstsize ) )){

				if ( retro.serialize(buf, dstsize) ){
					write_handle( buf, dstsize, ev->tgt.ioevs[0].iv, true );
				} else
					LOG("serialization failed.\n");

				free(buf);
			}
			else
				LOG("snapshot store requested without	any viable target.\n");
		}
		break;

		case TARGET_COMMAND_RESTORE:
		{
			ssize_t dstsize = retro.serialize_size();
			size_t ntc = dstsize;
			void* buf;

		if (dstsize && (buf = malloc(dstsize))){
			char* dst = buf;
			while (ntc){
				ssize_t nr = read(ev->tgt.ioevs[0].iv, dst, ntc);
				if (nr == -1){
					if (errno != EINTR && errno != EAGAIN)
						break;
					else
						continue;
				}

				dst += nr;
				ntc -= nr;
			}

			if (ntc == 0){
				retro.deserialize( buf, dstsize );
				reset_timing(true);
			}
			else
				LOG("failed restoring from snapshot (%s)\n", strerror(errno));

			free(buf);
		}
		else
			LOG("restore requested but core does not support savestates\n");
		}
		break;

		default:
			LOG("unknown target event (%s), ignored.\n",
				arcan_shmif_eventstr(ev, NULL, 0));
	}
}

/* use labels etc. for trying to populate the context table we also process
 * requests to save state, shutdown, reset, plug/unplug input, here */
static inline int flush_eventq(){
	arcan_event ev;
	int ps;

	while ((ps = arcan_shmif_poll(&retro.shmcont, &ev)) > 0){
		switch (ev.category){
			case EVENT_IO:
				ioev_ctxtbl(&(ev.io), ev.io.label);
			break;

			case EVENT_TARGET:
				targetev(&ev);

			default:
			break;
		}
	}

	return ps;
}

void update_ntsc()
{
	static bool init;
	if (!init){
		retro.ntsc_opts = snes_ntsc_rgb;
		retro.ntscctx = malloc(sizeof(snes_ntsc_t));
		snes_ntsc_init(retro.ntscctx, &retro.ntsc_opts);
		init = true;
	}

	snes_ntsc_update_setup(
		retro.ntscctx, &retro.ntsc_opts,
		retro.ntscvals[0], retro.ntscvals[1],
		retro.ntscvals[2], retro.ntscvals[3]);
}

/* return true if we're in synch (may sleep),
 * return false if we're lagging behind */
static inline bool retro_sync()
{
	long long int timestamp = arcan_timemillis();
	retro.vframecount++;

/* only skip (at most) 1 frame */
	if (retro.skipframe_v || retro.empty_v)
		return true;

	long long int now  = timestamp - retro.basetime;
	long long int next = floor( (double)retro.vframecount * retro.mspf );
	int left = next - now;

/* ntpd, settimeofday, wonky OS etc. or some massive stall, disqualify
 * DEBUGSTALL for the normal timing thing, or even switching 3d settings */
	static int checked;

/*
 * a jump this large (+- 10 frames) indicate some kind of problem with timing
 * or insanely slow emulation/rendering - nothing we can do about that except
 * try and resynch
 */
	if (retro.skipmode == TARGET_SKIP_AUTO){
		if (left < -200 || left > 200){
			if (checked == 0){
				checked = getenv("ARCAN_FRAMESERVER_DEBUGSTALL") ? -1 : 1;
			}
			else if (checked == 1){
				LOG("frameskip stall (%d ms deviation) - detected, resetting timers.\n", left);
				reset_timing(false);
			}
			return true;
		}

		if (left < -0.5 * retro.mspf){
			if (retro.sync_data)
				retro.sync_data->mark_drop(retro.sync_data, timestamp);
			LOG("frameskip: at(%lld), next: (%lld), "
				"deviation: (%d)\n", now, next, left);
			retro.frameskips++;
			return false;
		}
	}

/* since we have to align the transfer with the parent, and it's better to
 * under- than overshoot- a deadline in that respect, prewake tries to
 * compensate lightly for scheduling jitter etc. */
	if (left > retro.prewake){
		LOG("sleep %d ms\n", left - retro.prewake);
		arcan_timesleep( left - retro.prewake );
	}

	return true;
}

/*
 * used for debugging / testing synchronization during various levels of harsh
 * synchronization costs
 */
static inline long long add_jitter(int num)
{
	long long start = arcan_timemillis();
	if (num < 0)
		arcan_timesleep( rand() % abs(num) );
	else if (num > 0)
		arcan_timesleep( num );
	long long stop = arcan_timemillis();
	return stop - start;
}

#ifdef FRAMESERVER_LIBRETRO_3D
/*
 * legacy from agp_* functions, mostly just to make symbols resolve
 */
void* platform_video_gfxsym(const char* sym)
{
	return arcan_shmifext_lookup(&retro.shmcont, sym);
}

static uintptr_t get_framebuffer()
{
	uintptr_t tgt = 0;
	arcan_shmifext_gl_handles(&retro.shmcont, &tgt, NULL, NULL);
	return tgt;
}

static void setup_3dcore(struct retro_hw_render_callback* ctx)
{
/*
 * cheat with some envvars as the agp_ interface because it was not designed
 * to handle these sort of 'someone else decides which version to use'
 */
	struct arcan_shmifext_setup setup = arcan_shmifext_defaults(&retro.shmcont);
	if (ctx->context_type == RETRO_HW_CONTEXT_OPENGL_CORE){
		setup.major = ctx->version_major;
		setup.minor = ctx->version_minor;
	}
	enum shmifext_setup_status status;
	setup.depth = 1;
	if ((status = arcan_shmifext_setup(&retro.shmcont, setup)) != SHMIFEXT_OK){
		LOG("couldn't setup 3D context, code: %d, giving up.\n", status);
		arcan_shmif_drop(&retro.shmcont);
		exit(EXIT_FAILURE);
	}

	retro.in_3d = true;

	ctx->get_current_framebuffer = get_framebuffer;
	ctx->get_proc_address = (retro_hw_get_proc_address_t) platform_video_gfxsym;

	memcpy(&retro.hwctx, ctx,
		sizeof(struct retro_hw_render_callback));
}
#endif

static void map_lretrofun()
{
/* map normal functions that will be called repeatedly */
	retro.run = (void(*)()) libretro_requirefun("retro_run");
	retro.reset = (void(*)()) libretro_requirefun("retro_reset");
	retro.load_game = (bool(*)(const struct retro_game_info* game))
		libretro_requirefun("retro_load_game");
	retro.serialize = (bool(*)(void*, size_t))
		libretro_requirefun("retro_serialize");
	retro.set_ioport = (void(*)(unsigned,unsigned))
		libretro_requirefun("retro_set_controller_port_device");
	retro.deserialize = (bool(*)(const void*, size_t))
		libretro_requirefun("retro_unserialize");
	retro.serialize_size = (size_t(*)())
		libretro_requirefun("retro_serialize_size");

/* setup callbacks */
	( (void(*)(retro_video_refresh_t) )
		libretro_requirefun("retro_set_video_refresh"))(libretro_vidcb);
	( (size_t(*)(retro_audio_sample_batch_t))
		libretro_requirefun("retro_set_audio_sample_batch"))(libretro_audcb);
	( (void(*)(retro_audio_sample_t))
		libretro_requirefun("retro_set_audio_sample"))(libretro_audscb);
	( (void(*)(retro_input_poll_t))
		libretro_requirefun("retro_set_input_poll"))(libretro_pollcb);
	( (void(*)(retro_input_state_t))
		libretro_requirefun("retro_set_input_state") )(libretro_inputstate);
}

/* might need to add another subgrammar here to handle multiple file-
 * images (another ??, why not just populate an array with images and a
 * swap- function.. */
static bool load_resource(const char* resname)
{
/* rather ugly -- core actually requires file-path */
	if (retro.sysinfo.need_fullpath){
		LOG("core(%s), core requires fullpath, resolved to (%s).\n",
			retro.sysinfo.library_name, resname );

		retro.gameinfo.data = NULL;
		retro.gameinfo.path = strdup( resname );
		retro.gameinfo.size = 0;
	}
	else {
		retro.gameinfo.path = strdup( resname );
		data_source res = arcan_open_resource(resname);
		map_region map = arcan_map_resource(&res, true);
		if (!map.ptr){
			arcan_shmif_last_words(&retro.shmcont, "Couldn't open/map resource");
			LOG("couldn't map (%s)\n", resname ? resname : "");
//			return false;
		}
		retro.gameinfo.data = map.ptr;
		retro.gameinfo.size = map.sz;
	}

	bool res = retro.load_game(&retro.gameinfo);
	if (!res){
		arcan_shmif_last_words(&retro.shmcont, "Core couldn't load resource");
		LOG("libretro core rejected the resource\n");
		return false;
	}
	return true;
}

static void setup_av()
{
/* load the game, and if that fails, give up */
#ifdef FRAMESERVER_LIBRETRO_3D
	if (retro.hwctx.context_reset)
		retro.hwctx.context_reset();
#endif

	( (void(*)(struct retro_system_av_info*))
		libretro_requirefun("retro_get_system_av_info"))(&retro.avinfo);

/* setup frameserver, synchronization etc. */
	assert(retro.avinfo.timing.fps > 1);
	assert(retro.avinfo.timing.sample_rate > 1);
	retro.mspf = ( 1000.0 * (1.0 / retro.avinfo.timing.fps) );

	retro.ntscconv = false;

	LOG("video timing: %f fps (%f ms), audio samplerate: %f Hz\n",
		(float)retro.avinfo.timing.fps, (float)retro.mspf,
		(float)retro.avinfo.timing.sample_rate);
}

static void setup_input()
{
/* setup standard device remapping tables, these can be changed
 * by the calling process with a corresponding target event. */
	for (int i = 0; i < MAX_PORTS; i++){
		retro.input_ports[i].cursor_x = 0;
		retro.input_ports[i].cursor_y = 1;
		retro.input_ports[i].cursor_btns[0] = 0;
		retro.input_ports[i].cursor_btns[1] = 1;
		retro.input_ports[i].cursor_btns[2] = 2;
		retro.input_ports[i].cursor_btns[3] = 3;
		retro.input_ports[i].cursor_btns[4] = 4;
	}

	retro.state_sz = retro.serialize_size();
	arcan_shmif_enqueue(&retro.shmcont, &(struct arcan_event){
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(STATESIZE),
		.ext.stateinf.size = retro.state_sz
	});
}

static void dump_help()
{
	fprintf(stdout, "ARCAN_ARG (environment variable, "
		"key1=value:key2:key3=value), arguments:\n"
		"   key   \t   value   \t   description\n"
		"---------\t-----------\t-----------------\n"
		" core    \t filename  \t relative path to libretro core (req)\n"
		" info    \t           \t load core, print information and quit\n"
		" syspath \t path      \t set core system path\n"
		" resource\t filename  \t resource file to load with core\n"
		" vbufc   \t num       \t (1) 1..4 - number of video buffers\n"
		" abufc   \t num       \t (8) 1..16 - number of audio buffers\n"
		" abufsz  \t num       \t audio buffer size in bytes (default = probe)\n"
    " noreset \t           \t (3D) disable context reset calls\n"
    "---------\t-----------\t-----------------\n"
	);
}

/* map up a libretro compatible library resident at fullpath:game,
 * if resource is /info, no loading will occur but a dump of the capabilities
 * of the core will be sent to stdout. */
int	afsrv_game(struct arcan_shmif_cont* cont, struct arg_arr* args)
{
	if (!cont || !args){
		dump_help();
		return EXIT_FAILURE;
	}

	retro.converter = (pixconv_fun) libretro_rgb1555_rgba;
	retro.inargs = args;
	retro.shmcont = *cont;

	const char* libname = NULL;
	const char* resname = NULL;
	const char* val;

	if (arg_lookup(args, "core", 0, &val))
		libname = strdup(val);

	if (arg_lookup(args, "resource", 0, &val))
		resname = strdup(val);

	if (arg_lookup(args, "abufc", 0, &val)){
		uint8_t bufc = strtoul(val, NULL, 10);
		retro.abuf_cnt = bufc > 0 && bufc < 16 ? bufc : 8;
	}

	if (arg_lookup(args, "vbufc", 0, &val)){
		uint8_t bufc = strtoul(val, NULL, 10);
		retro.vbuf_cnt = bufc > 0 && bufc <= 4 ? bufc : 1;
	}

	if (arg_lookup(args, "abufsz", 0, &val)){
		retro.def_abuf_sz = strtoul(val, NULL, 10);
	}

/* system directory doesn't really match any of arcan namespaces,
 * provide some kind of global-  user overridable way */
	const char* spath = getenv("ARCAN_LIBRETRO_SYSPATH");
	if (!spath)
		spath = "./";

	if (arg_lookup(args, "syspath", 0, &val))
		spath = val;

/* some cores (mednafen-psx, ..) currently breaks on relative paths,
 * so resolve to absolute one for the time being */
	retro.syspath = realpath(spath, NULL);

/* set if we only want to dump status about the core, info etc.  (which
 * incidentally was then moved to yet another format to parse and manage as
 * a separate file, not an embedded string in core.. */
	bool info_only = arg_lookup(args, "info", 0, NULL) || cont->addr == NULL;

	if (!libname || *libname == 0){
		LOG("error > No core specified.\n");
		dump_help();

		return EXIT_FAILURE;
	}

	if (!info_only)
		LOG("Loading core (%s) with resource (%s)\n", libname ?
			libname : "missing arg.", resname ? resname : "missing resarg.");

/* map up functions and test version */
	lastlib = dlopen(libname, RTLD_LAZY);
	if (!globallib)
		globallib = dlopen(NULL, RTLD_LAZY);

	if (!lastlib){
		arcan_shmif_last_words(&retro.shmcont, "Couldn't load/open core");
		LOG("couldn't open library (%s), giving up.\n", libname);
		exit(EXIT_FAILURE);
	}

	void (*initf)() = libretro_requirefun("retro_init");
	unsigned (*apiver)() = (unsigned(*)())
		libretro_requirefun("retro_api_version");

	( (void(*)(retro_environment_t))
		libretro_requirefun("retro_set_environment"))(libretro_setenv);

/* get the lib up and running, ensure that the version matches
 * the one we got from the header */
	if (!( (initf(), true) && apiver() == RETRO_API_VERSION) )
		return EXIT_FAILURE;

	((void(*)(struct retro_system_info*))
	 libretro_requirefun("retro_get_system_info"))(&retro.sysinfo);

	if (info_only){
		fprintf(stdout, "arcan_frameserver(info)\nlibrary:%s\n"
			"version:%s\nextensions:%s\n/arcan_frameserver(info)",
			retro.sysinfo.library_name, retro.sysinfo.library_version,
			retro.sysinfo.valid_extensions);
		return EXIT_FAILURE;
	}

	LOG("libretro(%s), version %s loaded. Accepted extensions: %s\n",
		retro.sysinfo.library_name, retro.sysinfo.library_version,
		retro.sysinfo.valid_extensions);

	resize_shmpage(retro.avinfo.geometry.base_width,
		retro.avinfo.geometry.base_height, true);

/* map functions to context structure */
   unsigned base_height;   /* Nominal video height of game. */

/* send some information on what core is actually loaded etc. */
	retro.ident.ext.kind = ARCAN_EVENT(IDENT);
	size_t msgsz = COUNT_OF(retro.ident.ext.message.data);
	snprintf((char*)retro.ident.ext.message.data, msgsz, "%s %s",
		retro.sysinfo.library_name, retro.sysinfo.library_version);
	arcan_shmif_enqueue(&retro.shmcont, &retro.ident);

/* map the functions we need during runtime */
	map_lretrofun();

/* load / start */
	if (!resname && retro.res_empty)
		;
	else if (!load_resource(resname ? resname : ""))
		return EXIT_FAILURE;

/* remixing, conversion functions for color formats... */
	setup_av();

/* default input tables, state management */
	setup_input();

/* since we're 'guaranteed' to get at least one input callback each run(),
 * call, we multiplex parent event processing as well */
	arcan_event outev = {.ext.framestatus.framenumber = 0};

/* some cores die on this kind of reset, retro.reset() e.g. NXengine
 * retro_reset() */

	if (retro.state_sz > 0)
		retro.rollback_state = malloc(retro.state_sz);

/* basetime is used as epoch for all other timing calculations, run
 * an initial frame because sometimes first run can introduce a large stall */
	retro.skipframe_v = retro.skipframe_a = true;
	retro.run();
	retro.skipframe_v = retro.skipframe_a = false;
	retro.basetime = arcan_timemillis();

/* pre-audio is a last- resort to work around buffering size issues
 * in audio layers -- run one or more frames of emulation, ignoring
 * timing and input, and just keep the audioframes */
	do_preaudio();
	long long int start, stop;

/* don't want the UI to draw a mouse cursor in this window */
	arcan_shmif_enqueue(&retro.shmcont, &(struct arcan_event){
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(CURSORHINT),
		.ext.message = "hidden"
	});

	while (flush_eventq() >= 0){
		if (retro.skipmode >= TARGET_SKIP_FASTFWD)
			libretro_skipnframes(retro.skipmode -
				TARGET_SKIP_FASTFWD + 1, true);

		else if (retro.skipmode >= TARGET_SKIP_STEP)
			libretro_skipnframes(retro.skipmode -
				TARGET_SKIP_STEP + 1, false);

		else if (retro.skipmode <= TARGET_SKIP_ROLLBACK &&
			retro.dirty_input){
/* last entry will always be the current front */
			retro.deserialize(retro.rollback_state +
				retro.state_sz * retro.rollback_front, retro.state_sz);

/* rollback to desired "point", run frame (which will consume input)
 * then roll forward to next video frame */
			process_frames(retro.rollback_window - 1, true, true);
			retro.dirty_input = false;
		}

		testcounter = 0;

/* add jitter, jitterstep, framecost etc. are used for debugging /
 * testing by adding delays at various key synchronization points */
		start = arcan_timemillis();
			add_jitter(retro.jitterstep);
			process_frames(1, false, false);
		stop = arcan_timemillis();
		retro.framecost = stop - start;
		if (retro.sync_data){
			retro.sync_data->mark_start(retro.sync_data, start);
			retro.sync_data->mark_stop(retro.sync_data, stop);
		}

#ifdef _DEBUG
		if (testcounter != 1){
			static bool countwarn = 0;
			if (!countwarn && (countwarn = true))
				LOG("inconsistent core behavior, "
					"expected 1 video frame / run(), got %d\n", testcounter);
		}
#endif

/* begin with synching video, as it is the one with the biggest deadline
 * penalties and the cost for resampling can be enough if we are close */
		if (!retro.empty_v){
			long long elapsed = add_jitter(retro.jitterstep);
#ifdef FRAMESERVER_LIBRETRO_3D
			if (retro.got_3dframe){
				int handlestatus = arcan_shmifext_signal(&retro.shmcont,
					0, SHMIF_SIGVID, SHMIFEXT_BUILTIN);
				if (handlestatus >= 0)
					elapsed += handlestatus;
				retro.got_3dframe = false;
				LOG("3d-video transfer cost (%lld)\n", elapsed);
			}
/* note the dangling else */
			else
#endif
			elapsed += arcan_shmif_signal(&retro.shmcont, SHMIF_SIGVID | SHMIF_SIGBLK_NONE);

			retro.transfercost = elapsed;
			LOG("video transfer cost (%lld)\n", elapsed);
			if (retro.sync_data)
				retro.sync_data->mark_transfer(retro.sync_data,
					stop, retro.transfercost);
		}

/* sleep / synch / skipframes */
		retro.skipframe_a = false;
		retro.skipframe_v = !retro_sync();

		if (retro.sync_data)
				push_stats();
	}
	return EXIT_SUCCESS;
}

static void push_stats()
{
	char scratch[512];
	long long int timestamp = arcan_timemillis();

	snprintf(scratch, 512, "%s, %s\n"
		"%s, %f fps, %f Hz\n"
		"Mode: %d, Preaudio: %d\n Jitter: %d/%d\n"
		"(A,V - A/V) %lld, %lld - %lld\n"
		"Real (Hz): %f\n"
		"cost,wake,xfer: %d, %d, %d ms \n",
		(char*)retro.sysinfo.library_name,
		(char*)retro.sysinfo.library_version,
		(char*)retro.colorspace,
		(float)retro.avinfo.timing.fps,
		(float)retro.avinfo.timing.sample_rate,
		retro.skipmode, retro.preaudiogen,
		retro.jitterstep, retro.jitterxfer,
		retro.aframecount, retro.vframecount,
		retro.aframecount / retro.vframecount,
		1000.0f * (float)retro.aframecount /
			(float)(timestamp - retro.basetime),
		retro.framecost, retro.prewake, retro.transfercost
	);

	if (!retro.sync_data->update(
		retro.sync_data, retro.mspf, scratch)){
		retro.sync_data->free(&retro.sync_data);
	}
}
