/*
 Arcan Shared Memory Interface, Event Namespace
 Copyright (c) 2014, Bjorn Stahl
 All rights reserved.

 Redistribution and use in source and binary forms,
 with or without modification, are permitted provided that the
 following conditions are met:

 1. Redistributions of source code must retain the above copyright notice,
 this list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.

 3. Neither the name of the copyright holder nor the names of its contributors
 may be used to endorse or promote products derived from this software without
 specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 THE POSSIBILITY OF SUCH DAMAGE.
*/

#ifndef _HAVE_ARCAN_SHMIF_EVENT
#define _HAVE_ARCAN_SHMIF_EVENT

/*
 * The types and structures used herein are "transitional" in the sense
 * that during the later hardening / cleanup phases, we'll move over to
 * a protobuf based serialization format and only retain the fields that
 * are actually used in parent<->child communication.
 *
 * The only actual categories to rely on / use now for shmif purposes
 * are TARGET (parent -> child), EXTERNAL (child -> parent), NET
 * (parent <-> child) and INPUT (parent <-> child).
 *
 * Then the contents of this header will split into a version that
 * corresponds to what the engine uses internally and what is accessible
 * in the shmif interface. Until then, frameservers built against the
 * shared memory API are expected to recompile with the arcan version.
 */

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

/*
 * Some meta- descriptors to propagate ONCE for non-authoritative
 * connections, used as hinting to window manager script
 */
enum ARCAN_SEGID {
	SEGID_LWA = 0, /* LIGHTWEIGHT ARCAN (arcan-in-arcan) */
	SEGID_MEDIA, /* multimedia, non-interactive data source */
	SEGID_NETWORK_SERVER, /* external connection, 1:many */
	SEGID_NETWORK_CLIENT, /* external connection, 1:1 */
	SEGID_SHELL, /* terminal, privilege level vary, low-speed interactivity */
	SEGID_REMOTING, /* network client but A/V/latency sensitive */
	SEGID_ENCODER, /* high-CPU, low-latency, wants access to engine data */
	SEGID_GAME, /* high-interactivity, high A/V cost, low latency */
	SEGID_APPLICATION, /* video updates typically reactive */
	SEGID_BROWSER, /* network client, high-risk for malicious data */
	SEGID_UNKNOWN
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

/* libretro: set new value for previously notified key,
 * for on-load options, use commandline arguments */
	TARGET_COMMAND_COREOPT,

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

/*
 * hint for visible surface dimensions, careful
 * to avoid feedback loops here where (user resizes) ->
 * (resize_hint sent) -> (frameserver responds by resizing)
 * -> (prompting a new resize hint etc.)
 */
	TARGET_COMMAND_DISPLAYHINT,

/*
 * used for sending/receiving larger data-blocks,
 * used primarily in NET and in TERM
 */
	TARGET_COMMAND_BCHUNK_IN,
	TARGET_COMMAND_BCHUNK_OUT,

/* plug in device of a specific kind in a set port,
 * switch audio / video stream etc. */
	TARGET_COMMAND_SETIODEV,

/* used when audio playback is in the frameserver
 * (so hijacked targets) */
	TARGET_COMMAND_ATTENUATE,

/* used for libretro to seek back in state (if that feature
 * is activated) and for decode frameserver to seek relative
 * or absolute in the current streams */
	TARGET_COMMAND_SEEKTIME,

/* for audio / video synchronization in video decode/encode
 * (ioevs[0] -> samples per channel) */
	TARGET_COMMAND_AUDDELAY,

/*
 * to indicate that there's a new segment to be allocated
 * ioev[0].iv carries request ID (if one has been provided)
 */
	TARGET_COMMAND_NEWSEGMENT,

/*
 * request for a state transfer or new segment failed,
 * ioev[0].iv carries request ID (if one has been provided)
 */
	TARGET_COMMAND_REQFAIL,

/* specialized output hinting, deprecated */
	TARGET_COMMAND_GRAPHMODE,
	TARGET_COMMAND_VECTOR_LINEWIDTH,
	TARGET_COMMAND_VECTOR_POINTSIZE,
	TARGET_COMMAND_NTSCFILTER,
	TARGET_COMMAND_NTSCFILTER_ARGS
};

enum ARCAN_TARGET_SKIPMODE {
	TARGET_SKIP_AUTO     =  0, /* drop to keep sync */
	TARGET_SKIP_NONE     = -1, /* never discard data */
	TARGET_SKIP_REVERSE  = -2, /* play backward */
	TARGET_SKIP_ROLLBACK = -3, /* apply input events to prev. state */
	TARGET_SKIP_STEP     =  1, /* single stepping, advance with events */
	TARGET_SKIP_FASTFWD  = 10  /* 10+, only return every nth frame */
};

enum ARCAN_EVENT_IO {
	EVENT_IO_BUTTON,
	EVENT_IO_KEYB,
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

enum ARCAN_EVENT_EXTERNAL {
/*
 * custom string message, used as some user- directed hint
 */
	EVENT_EXTERNAL_MESSAGE = 0,

/*
 * specify that there is a possible key=value argument
 * that could be set.
 */
	EVENT_EXTERNAL_COREOPT,

/*
 * Dynamic data source identification string, similar to message
 */
	EVENT_EXTERNAL_IDENT,

/*
 * Hint that the previous I/O operation failed
 */
	EVENT_EXTERNAL_FAILURE,

/*
 * Debugging hints for video/timing information
 */
	EVENT_EXTERNAL_FRAMESTATUS,

/*
 * Decode playback discovered additional substreams that can be
 * selected or switched to
 */
	EVENT_EXTERNAL_STREAMINFO,

/*
 * playback information regarding completion, current time,
 * estimated length etc.
 */
	EVENT_EXTERNAL_STREAMSTATUS,

/*
 * hint that serialization operations (STORE / RESTORE)
 * are possible and how much buffer data / which transfer limits
 * that apply.
 */
	EVENT_EXTERNAL_STATESIZE,
	EVENT_EXTERNAL_RESOURCE,

/*
 * hint that any pending buffers on the audio device should
 * be discarded. used primarily for A/V synchronization.
 */
	EVENT_EXTERNAL_FLUSHAUD,

/*
 * Request an additional shm-if connection to be allocated,
 * only one segment is guaranteed per process. Tag with an
 * ID for the parent to be able to accept- or reject properly.
 */
	EVENT_EXTERNAL_SEGREQ,

/*
 * used to indicated that some external entity tries to provide
 * input data (e.g. a vnc client connected to an encode frameserver)
 */
	EVENT_EXTERNAL_KEYINPUT,
	EVENT_EXTERNAL_CURSORINPUT,

/*
 * Hint how the cursor is to be rendered,
 * if it's locally defined (client renders own),
 * or a user-readable string suggesting which icon should be used.
 */
	EVENT_EXTERNAL_CURSORHINT,

/*
 * Hint to the running script what user-readable identifier this
 * segment should be known as, and what archetype the window
 * behaves like (multiple messages will only update identifier,
 * switching archetype is not permitted.)
 */
	EVENT_EXTERNAL_REGISTER
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
	EVENT_NET_STATEREQ
};

enum ARCAN_EVENT_VIDEO {
	EVENT_VIDEO_EXPIRE,
	EVENT_VIDEO_ASYNCHIMAGE_LOADED,
	EVENT_VIDEO_ASYNCHIMAGE_FAILED
};

enum ARCAN_EVENT_SYSTEM {
	EVENT_SYSTEM_EXIT = 0,
	EVENT_SYSTEM_SWITCHAPPL
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

enum ARCAN_EVENT_FRAMESERVER {
	EVENT_FRAMESERVER_RESIZED,
	EVENT_FRAMESERVER_TERMINATED,
	EVENT_FRAMESERVER_DROPPEDFRAME,
	EVENT_FRAMESERVER_DELIVEREDFRAME,
	EVENT_FRAMESERVER_VIDEOSOURCE_FOUND,
	EVENT_FRAMESERVER_VIDEOSOURCE_LOST,
	EVENT_FRAMESERVER_AUDIOSOURCE_FOUND,
	EVENT_FRAMESERVER_AUDIOSOURCE_LOST
};

enum ARCAN_ANALOGFILTER_KIND {
	ARCAN_ANALOGFILTER_NONE = 0,
	ARCAN_ANALOGFILTER_PASS = 1,
	ARCAN_ANALOGFILTER_AVG  = 2,
 	ARCAN_ANALOGFILTER_ALAST = 3
};

typedef union arcan_ioevent_data {
	struct {
		uint8_t active;
		uint8_t devid;
		uint8_t subid;
	} digital;

	struct {
/* axis- values are first relative then absolute if set */
		int8_t gotrel;
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
		uint8_t active;
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

	uint32_t pts;
	arcan_ioevent_data input;
} arcan_ioevent;

typedef struct {
	int64_t source;
	int16_t width;
	int16_t height;
	intptr_t data;
} arcan_vevent;

typedef struct {
	int64_t video;
	int32_t audio;

	int width, height;

	unsigned c_abuffer, c_vbuffer;
	unsigned l_abuffer, l_vbuffer;

	int8_t glsource;
	uint64_t pts;
	uint64_t counter;

	intptr_t otag;
} arcan_fsrvevent;

typedef struct {
	int32_t source;
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
	int64_t source;
	unsigned connid;

	union {
		struct {
			char key[32];
			char ident[15];
/* max ipv6 textual representation, 39 + strsep + port */
			char addr[46];
		} host;

		char message[93];
	};
} arcan_netevent;

typedef struct arcan_tgtevent {
	union {
		int32_t iv;
		float fv;
	} ioevs[6];

	int code;
	char message[78];
#ifdef _WIN32
	HANDLE fh;
#endif
} arcan_tgtevent;

typedef struct arcan_extevent {
	int64_t source;

	union {
		uint8_t message[78];
		int32_t state_sz;

		struct {
			uint8_t id;
			uint32_t x, y;
			uint8_t buttons[5];
		} cursor;

		struct{
			uint8_t id;
			int keysym;
			uint8_t active;
		} key;

		struct {
			uint8_t message[3]; /* 3 character country code */
			uint8_t streamid;   /* key used to tell the decoder to switch */
			uint8_t datakind;   /* 0: audio, 1: video, 2: text, 3: overlay */
		} streaminf;

		struct {
			uint8_t state;
			uint8_t message[8];
		} cursorstat;

		struct {
			uint32_t id;
			uint8_t type;
			uint16_t width;
			uint16_t height;
		} noticereq;

		struct {
			char title[64];
			enum ARCAN_SEGID kind;
		} registr;

		struct {
			uint8_t timestr[9]; /* HH:MM:SS\0 */
			uint8_t timelim[9]; /* HH:MM:SS\0 */
			float completion;   /* float 0..1 -> 8-bit */
			uint8_t streaming;  /* makes lim/completion unknown */
			uint32_t frameno;  /* simple counter */
		} streamstat;

/*
 * emitted as a verification / debugging /
 * synchronization primitive,
 * EVENT_EXTERNAL_NOTICE_FRAMESTATUS, emitted once for each
 * port actually sampled
 */
		struct {
			uint32_t framenumber;
			uint8_t port;
			uint8_t input_bitf[4];
			int32_t axes_samples[8];
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

/* matches those that libraries such as SDL uses */
typedef enum {
	ARKMOD_NONE  = 0x0000,
	ARKMOD_LSHIFT= 0x0001,
	ARKMOD_RSHIFT= 0x0002,
	ARKMOD_LCTRL = 0x0040,
	ARKMOD_RCTRL = 0x0080,
	ARKMOD_LALT  = 0x0100,
	ARKMOD_RALT  = 0x0200,
	ARKMOD_LMETA = 0x0400,
	ARKMOD_RMETA = 0x0800,
	ARKMOD_NUM   = 0x1000,
	ARKMOD_CAPS  = 0x2000,
	ARKMOD_MODE  = 0x4000,
	ARKMOD_RESERVED = 0x8000
} key_modifiers;

struct arcan_evctx {
/* time and mask- tracking, only used parent-side */
	unsigned c_ticks;
	unsigned c_leaks;
	unsigned mask_cat_inp;
	unsigned mask_cat_out;

/* only used for local queues,  */
	size_t eventbuf_sz;

	arcan_event* eventbuf;

/* offsets into the eventbuf queue, parent will always
 * % ARCAN_SHMPAGE_QUEUE_SZ to prevent nasty surprises */
	volatile unsigned* front;
	volatile unsigned* back;

	int8_t local;

/*
 * When the child (!local flag) wants the parent to wake it up,
 * the sem_handle (by default, 1) is set to 0 and calls sem_wait.
 *
 * When the parent pushes data on the event-queue it checks the
 * state if this sem_handle. If it's 0, and some internal
 * dynamic heuristic (if the parent knows multiple- connected
 * events are enqueued, it can wait a bit before waking the child)
 * and if that heuristic is triggered, the semaphore is posted.
 *
 * This is also used by the guardthread (that periodically checks
 * if the parent is still alive, and if not, unlocks a batch
 * of semaphores).
 */
	struct {
		volatile uintptr_t* killswitch;
		sem_handle handle;

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
		bool init;
		pthread_mutex_t lock;
#endif
	} synch;

};

typedef struct arcan_evctx arcan_evctx;

#endif
