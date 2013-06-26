/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 */

#ifndef _HAVE_ARCAN_EVENT
#define _HAVE_ARCAN_EVENT

#define ARCAN_JOYIDBASE 64
#define ARCAN_HATBTNBASE 128
#define ARCAN_MOUSEIDBASE 0

/* this is relevant if the event queue is authoritative,
 * i.e. the main process side with a frameserver associated. A failure to get
 * a lock within the set time, will forcibly free the frameserver */
#define DEFAULT_EVENT_TIMEOUT 500

enum ARCAN_EVENT_CATEGORY {
	EVENT_SYSTEM      = 1,
	EVENT_IO          = 2,
	EVENT_TIMER       = 4,
	EVENT_VIDEO       = 8,
	EVENT_AUDIO       = 16,
	EVENT_TARGET      = 32,
	EVENT_FRAMESERVER = 64,
	EVENT_EXTERNAL    = 128,
	EVENT_NET         = 256
};

enum ARCAN_EVENT_SYSTEM {
	EVENT_SYSTEM_EXIT = 0,
	EVENT_SYSTEM_SWITCHTHEME,
	EVENT_SYSTEM_VIDEO_FAIL,
	EVENT_SYSTEM_AUDIO_FAIL,
	EVENT_SYSTEM_IO_FAIL,
	EVENT_SYSTEM_MEMORY_FAIL,
	EVENT_SYSTEM_INACTIVATE,
	EVENT_SYSTEM_ACTIVATE,
	EVENT_SYSTEM_LAUNCH_EXTERNAL,
	EVENT_SYSTEM_CLEANUP_EXTERNAL,
	EVENT_SYSTEM_EVALCMD
};

enum ARCAN_TARGET_COMMAND {
/* notify that the child will be shut down / killed,
 * this happens in three steps (1) dms is released, 
 * (2) exit is enqueued, (3) sigterm is sent. */
	TARGET_COMMAND_EXIT,

/* notify that there is a file descriptor to be retrieved and 
 * set as the input/output fd for other command events, additional 
 * ievs define destionation slot (net-srv), mode (state, res, ...) 
 * and size */
	TARGET_COMMAND_FDTRANSFER,
	
/* libretro/hijack: hinting event for frameskip modes 
 * (auto, process every n frames, singlestep) */
	TARGET_COMMAND_FRAMESKIP,
	TARGET_COMMAND_STEPFRAME,

/* libretro: store to last FDTRANSFER FD 
 * net-cl: read from FD, package and send to srv */
	TARGET_COMMAND_STORE,

/* libretro: restore from last FD */
	TARGET_COMMAND_RESTORE,

/* libretro/hijack: hinting event for reseting state 
 * to the first known initial steady one */
	TARGET_COMMAND_RESET,

/* hinting event for attempting to block the entire 
 * process until unpause is triggered */
	TARGET_COMMAND_PAUSE,
	TARGET_COMMAND_UNPAUSE,

/* plug in device of a specific kind in a set port */
	TARGET_COMMAND_SETIODEV,

/* used when audio playback is in the frameserver
 * (so hijacked targets) */
	TARGET_COMMAND_ATTENUATE,

/* for audio / video synchronization in video decode/encode 
 * (ioevs[0] -> samples per channel) */
	TARGET_COMMAND_AUDDELAY,
	
/* specialized output hinting */
	TARGET_COMMAND_GRAPHMODE,
	TARGET_COMMAND_VECTOR_LINEWIDTH,
	TARGET_COMMAND_VECTOR_POINTSIZE,
	TARGET_COMMAND_NTSCFILTER,
	TARGET_COMMAND_NTSCFILTER_ARGS
};

enum ARCAN_EVENT_IO {
	EVENT_IO_BUTTON_PRESS, 
	EVENT_IO_BUTTON_RELEASE,
	EVENT_IO_KEYB_PRESS,
	EVENT_IO_KEYB_RELEASE,
	EVENT_IO_AXIS_MOVE,
	EVENT_IO_TOUCH
};

enum ARCAN_EVENT_IDEVKIND {
	EVENT_IDEVKIND_KEYBOARD,
	EVENT_IDEVKIND_MOUSE,
	EVENT_IDEVKIND_GAMEDEV,
	EVENT_IDEVKIND_TOUCHDISP
};

enum ARCAN_EVENT_IDATATYPE {
	EVENT_IDATATYPE_ANALOG,
	EVENT_IDATATYPE_DIGITAL,
	EVENT_IDATATYPE_TRANSLATED,
	EVENT_IDATATYPE_TOUCH
};

enum ARCAN_EVENT_FRAMESERVER {
	EVENT_FRAMESERVER_RESIZED,
	EVENT_FRAMESERVER_TERMINATED,
	EVENT_FRAMESERVER_LOOPED,
	EVENT_FRAMESERVER_DROPPEDFRAME,
	EVENT_FRAMESERVER_VIDEOSOURCE_FOUND,
	EVENT_FRAMESERVER_VIDEOSOURCE_LOST,
	EVENT_FRAMESERVER_AUDIOSOURCE_FOUND,
	EVENT_FRAMESERVER_AUDIOSOURCE_LOST
};

enum ARCAN_EVENT_EXTERNAL {
	EVENT_EXTERNAL_NOTICE_MESSAGE = 0,
	EVENT_EXTERNAL_NOTICE_IDENT, 
	EVENT_EXTERNAL_NOTICE_FAILURE,
	EVENT_EXTERNAL_NOTICE_FRAMESTATUS,
	EVENT_EXTERNAL_NOTICE_STATESIZE,
	EVENT_EXTERNAL_NOTICE_RESOURCE
};

enum ARCAN_EVENT_VIDEO {
	EVENT_VIDEO_EXPIRE = 0,
	EVENT_VIDEO_SCALED,
	EVENT_VIDEO_MOVED,
	EVENT_VIDEO_BLENDED,
	EVENT_VIDEO_ROTATED,
	EVENT_VIDEO_ASYNCHIMAGE_LOADED,
	EVENT_VIDEO_ASYNCHIMAGE_LOAD_FAILED
};

enum ARCAN_EVENT_NET {
/* server -> parent */
	EVENT_NET_BROKEN,
	EVENT_NET_CONNECTED,
	EVENT_NET_DISCONNECTED,
	EVENT_NET_NORESPONSE,
	EVENT_NET_DISCOVERED,
/* parent -> server */
	EVENT_NET_GRAPHREFRESH,
	EVENT_NET_CONNECT,
	EVENT_NET_DISCONNECT,
	EVENT_NET_AUTHENTICATE,
/* bidirectional */
	EVENT_NET_CUSTOMMSG,
	EVENT_NET_INPUTEVENT,
};

enum ARCAN_EVENT_AUDIO {
	EVENT_AUDIO_PLAYBACK_FINISHED = 0,
	EVENT_AUDIO_PLAYBACK_ABORTED,
	EVENT_AUDIO_BUFFER_UNDERRUN,
	EVENT_AUDIO_PITCH_TRANSFORMATION_FINISHED,
	EVENT_AUDIO_GAIN_TRANSFORMATION_FINISHED,
	EVENT_AUDIO_OBJECT_GONE,
	EVENT_AUDIO_INVALID_OBJECT_REFERENCED
};

enum ARCAN_EVENTFILTER_ANALOG {
	EVENT_FILTER_ANALOG_NONE,
	EVENT_FILTER_ANALOG_ALL,
	EVENT_FILTER_ANALOG_SPECIFIC
};

enum ARCAN_TARGET_SKIPMODE {
	TARGET_SKIP_AUTO = 0,
	TARGET_SKIP_NONE = -1,
	TARGET_SKIP_STEP = 1,
	TARGET_SKIP_FASTFWD = 10
};

typedef union arcan_ioevent_data {
	struct {
		uint8_t devid;
		uint8_t subid;
		bool active;
	} digital;

	struct {
/* axis- values are first relative then absolute if set */
		bool gotrel; 
		uint8_t devid;
		uint8_t subid;
		uint8_t idcount;
		uint8_t nvalues;
		int16_t axisval[4];
	} analog;

	struct {
		uint8_t devid;
		uint8_t subid;
		int16_t x, y;
		float pressure, size;
	} touch;

	struct {
		bool active;
		uint8_t devid;
		uint16_t subid;

		uint16_t keysym;
		uint16_t modifiers;
		uint8_t scancode;
	} translated;

} arcan_ioevent_data;

typedef struct {
	enum ARCAN_EVENT_IDEVKIND devkind;
	enum ARCAN_EVENT_IDATATYPE datatype;

	arcan_ioevent_data input;
} arcan_ioevent;

typedef struct {
	arcan_vobj_id source;
	img_cons constraints;
	surface_properties props;
	intptr_t data;
} arcan_vevent;

typedef struct {
	arcan_vobj_id video;
	arcan_aobj_id audio;

	int width, height;

	unsigned c_abuffer, c_vbuffer;
	unsigned l_abuffer, l_vbuffer;

	bool glsource;

	intptr_t otag;
} arcan_fsrvevent;

typedef struct {
	arcan_aobj_id source;
	void* data;
} arcan_aevent;

typedef struct arcan_sevent {
	int errcode; /* copy of errno if possible */
	union {
		struct {
			long long hitag, lotag;
		} tagv;
		struct {
/* only for dev/dbg purposes, expected scripting 
 * frontend to free and not-mask */
			char* dyneval_msg;
		} mesg;
		char message[64];
	} data;
} arcan_sevent;

typedef struct arcan_tevent {
	long long int pulse_count;
} arcan_tevent;

typedef struct arcan_netevent{
	arcan_vobj_id source;
	unsigned connid;

	union {
		struct {
			char key[32];
			char addr[46]; 
/* max ipv6 textual representation, 39 */
		} host;

		char message[78];
	};
} arcan_netevent;

typedef struct arcan_tgtevent {
	union {
		int iv;
		float fv;
	} ioevs[6];
#ifdef _WIN32
	HANDLE fh;
#endif
} arcan_tgtevent;

typedef struct arcan_extevent {
	arcan_vobj_id source;

	union {
		char message[24];
		int32_t state_sz;
		uint32_t code;

/*
 * emitted as a verification / debugging / 
 * synchronization primitive,
 * EVENT_EXTERNAL_NOTICE_FRAMESTATUS, emitted once for each
 * port actually sampled
 */
		struct {
			uint32_t framenumber;
			char port;
			char input_bitf[4];
			signed axes_samples[8];
		} framestatus;
	};
} arcan_extevent;

typedef union event_data {
	arcan_ioevent   io;
	arcan_vevent    video;
	arcan_aevent    audio;
	arcan_sevent    system;
	arcan_tevent    timer;
	arcan_tgtevent  target;
	arcan_fsrvevent frameserver;
	arcan_extevent  external;
	arcan_netevent  network;

	void* other;
} event_data;

typedef struct arcan_event {
	unsigned kind;
	unsigned tickstamp;

	char label[16];
	unsigned short category;

	event_data data;
} arcan_event;

#ifndef _SDL_keysym_h
/* matches those that libraries such as SDL uses */
typedef enum {
	KMOD_NONE  = 0x0000,
	KMOD_LSHIFT= 0x0001,
	KMOD_RSHIFT= 0x0002,
	KMOD_LCTRL = 0x0040,
	KMOD_RCTRL = 0x0080,
	KMOD_LALT  = 0x0100,
	KMOD_RALT  = 0x0200,
	KMOD_LMETA = 0x0400,
	KMOD_RMETA = 0x0800,
	KMOD_NUM   = 0x1000,
	KMOD_CAPS  = 0x2000,
	KMOD_MODE  = 0x4000,
	KMOD_RESERVED = 0x8000
} key_modifiers;
#endif

struct arcan_evctx {
	bool interactive; /* should STDIN be processed for command events? */

	unsigned c_ticks;
	unsigned c_leaks;
	unsigned mask_cat_inp;
	unsigned mask_cat_out;

	unsigned kbdrepeat;

/* limit analog sampling rate as to not saturate the event buffer,
 * with rate == 0, all axis events will be emitted
 * with rate >  0, the upper limit is n samples per second.
 * with rate <  0, emit a sample per axis every n milliseconds. */
	struct {
		int rate;

/* with smooth samples > 0, use a ring-buffer of smooth_sample
 * values per axis,and whenever an sample is to be emitted,
 * the actual value will be based on an averag eof the smooth buffer. */
		char smooth_samples;
	} analog_filter;

	unsigned n_eventbuf;
	arcan_event* eventbuf;

	unsigned* front;
	unsigned* back;

	bool local;
	union {
		pthread_mutex_t local;

		struct {
			void* killswitch; /* assumed to be NULL or frameserver */
			sem_handle shared;
		} external;

	} synch;
};

typedef struct arcan_evctx arcan_evctx;

/* check timers, poll IO events and timing calculations
 * out : (NOT NULL) storage- container for number of ticks that has passed
 *                   since the last call to arcan_process
 * ret : range [0 > n < 1] how much time has passed towards the next tick */
float arcan_event_process(arcan_evctx*, unsigned* nticks);

/* check the queue for events,
 * don't attempt to run this one-
 * on more than one thread */
arcan_event* arcan_event_poll(arcan_evctx*, arcan_errc* status);

/* similar to event poll, but will only
 * return events matching masked event */
arcan_event* arcan_event_poll_masked(arcan_evctx*, unsigned mask_cat, 
	unsigned mask_ev, arcan_errc* status);

/* force a keyboard repeat- rate */
void arcan_event_keyrepeat(arcan_evctx*, unsigned rate);

arcan_evctx* arcan_event_defaultctx();

/* 
 * Pushes as many events from srcqueue to dstqueue as possible 
 * without over-saturating. allowed defines which kind of category
 * that will be transferred, other events will be ignored.
 * The saturation cap is defined in 0..1 range as % of full capacity
 * specifying a source ID (can be ARCAN_EID) will be used for rewrites
 * if the category has a source identifier
 */
void arcan_event_queuetransfer(arcan_evctx* dstqueue, arcan_evctx* srcqueue,
	enum ARCAN_EVENT_CATEGORY allowed, float saturation, arcan_vobj_id source);

/* enqueue an event into the specified event-context,
 * for non-frameserver part of the application, this can be 
 * substituted with arcan_event_defaultctx thread-safe */
void arcan_event_enqueue(arcan_evctx*, const arcan_event*);

/* ignore-all on enqueue */
void arcan_event_maskall(arcan_evctx*);

/* drop any mask, including maskall */
void arcan_event_clearmask(arcan_evctx*);

/* set a specific mask, somewhat limited */
void arcan_event_setmask(arcan_evctx*, unsigned mask);

int64_t arcan_frametime();

/*
 * special case, due to the event driven approach of LUA invocation,
 * we can get situations where we have a queue of events related to
 * a certain vid/aid, after the user has explicitly asked for it to be deleted.
 *
 * This means the user either has to check for this condition by tracking 
 * the object (possibly dangling references etc.)
 * or that we sweep the queue and erase the tracks of the object in question.
 *
 * the default behaviour is to not erase unprocessed events that are made 
 * irrelevant due to a deleted object.
 */
void arcan_event_erase_vobj(arcan_evctx* ctx, 
	enum ARCAN_EVENT_CATEGORY category, arcan_vobj_id source);

void arcan_event_init(arcan_evctx* dstcontext);
void arcan_event_deinit(arcan_evctx*);

/* call to dump the contents of the queue */
void arcan_event_dumpqueue(arcan_evctx*);

/*
 * Supply a buffer sizeof(arcan_event) or larger and it'll be packed down to
 * an internal format (XDR) for serialization,
 * which can be transmitted over the wire and later deserialized again with 
 * unpack. dbuf is dynamically allocated, and the payload is padded by 'pad' 
 * byte, final size is stored in sz. returns false on out of memory or 
 * unusable event contents  
 */
bool arcan_event_pack(arcan_event*, int pad, char** dbuf, size_t* sz);

/* takes an input character buffer, unpacks it and stores the result in dst.
 * returns false if any of the arguments are missing or the buffer contents is invalid */
arcan_event arcan_event_unpack(arcan_event* dst, char* buf, size_t* bufsz);
#endif
