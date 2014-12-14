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
 * Primarily hinting to the running appl, but can also dictate
 * scheduling groups, priority in terms of resource exhaustion,
 * sandboxing scheme and similar limitations (e.g. TITLEBAR /
 * CURSOR should not update 1080p60Hz)
 */
enum ARCAN_SEGID {
	SEGID_LWA = 0, /* LIGHTWEIGHT ARCAN (arcan-in-arcan) */
	SEGID_NETWORK_SERVER, /* external connection, 1:many */
	SEGID_NETWORK_CLIENT, /* external connection, 1:1 */
	SEGID_MEDIA, /* multimedia, non-interactive data source */
	SEGID_TERMINAL, /* terminal, privilege level vary, low-speed interactivity */
	SEGID_REMOTING, /* network client but A/V/latency sensitive */
	SEGID_ENCODER, /* high-CPU, low-latency, wants access to engine data */
	SEGID_SENSOR, /* sampled continuous update */
	SEGID_TITLEBAR, /* some clients may want to try and draw decoration */
	SEGID_CURSOR, /* active cursor, competes with cursorhint event */
	SEGID_INPUTDEVICE, /* event/user-interaction driven */
	SEGID_GAME, /* high-interactivity, high A/V cost, low latency requirements */
	SEGID_APPLICATION, /* video updates typically reactive to input */
	SEGID_BROWSER, /* network client, high-risk for malicious data */
	SEGID_VM, /* virtual-machine, high resource consumption, high risk */
	SEGID_HMD_SBS, /* head-mounter display, even split left/ right */
	SEGID_HMD_L, /* head-mounted display, left eye view (otherwise _GAME) */
  SEGID_HMD_R, /* head-mounted display, right eye view (otherwise _GAME) */
	SEGID_ICON, /* minimized- status indicator */
	SEGID_DEBUG, /* can always be terminated, may hold extraneous information */
	SEGID_UNKNOWN
};

/*
 * These are commands that map from parent to child.
 */
enum ARCAN_TARGET_COMMAND {
/* shutdown sequence:
 * 0. dms is released,
 * 1. _EXIT enqueued,
 * 2. semaphores explicitly unlocked
 * 3. parent spawns a monitor thread, kills unless exited after
 *    a set amount of time (for authoritative connections).
 */
	TARGET_COMMAND_EXIT,

/*
 * Hints regarding how the underlying client should treat
 * rendering and video synchronization.
 */
	TARGET_COMMAND_FRAMESKIP,
	TARGET_COMMAND_STEPFRAME,

/*
 * Set a specific key-value pair. These have been registered
 * in beforehand through EVENT_EXTERNAL_COREOPT.
 */
	TARGET_COMMAND_COREOPT,

/*
 * This event is a setup for other ones, it merely indicates
 * that the active input descriptor slot for this segment
 * should be retrieved from the OOB data-channel (typically
 * a socket) and stored for later.
 *
 * Used as a prelude to:
 * 	STORE, RESTORE, NEWSEGMENT, BCHUNK_IN, BCHUNK_OUT
 */
	TARGET_COMMAND_FDTRANSFER,

/*
 * Use the last received descriptor and (de-)serialize internal
 * application state to it. It should be in such a format
 * that state can be restored and possibly transfered between
 * instances of the same program.
 */
	TARGET_COMMAND_STORE,
	TARGET_COMMAND_RESTORE,

/*
 * Similar to store/store, but used to indicate that the data
 * source and binary protocol carried within is implementation-
 * defined.
 */
	TARGET_COMMAND_BCHUNK_IN,
	TARGET_COMMAND_BCHUNK_OUT,

/*
 * Revert to a safe / known / default state.
 */
	TARGET_COMMAND_RESET,

/*
 * Suspend operations, only _EXIT and _UNPAUSE should be valid
 * events in this state. Indicates that the server does not
 * want the client to consume any system- resources.
 */
	TARGET_COMMAND_PAUSE,
	TARGET_COMMAND_UNPAUSE,

/*
 * for all connections that have a perception of time that
 * can be manipulated, this is used to request rollback or
 * fast-forward between states
 */
	TARGET_COMMAND_SEEKTIME,

/*
 * A hint in regards to the currently displayed dimensions.
 * It is up to the program running on the server to decide
 * how much internal resolution that it is recommended for
 * the client to use. When the visible image resolution
 * deviates a lot from the internal resolution of the client,
 * this event can appear as a friendly suggestion to resize.
 */
	TARGET_COMMAND_DISPLAYHINT,

/*
 * Hint input/device mapping (device-type, input-port),
 * primarily used for gaming / legacy applications and
 * will be reconsidered.
 */
	TARGET_COMMAND_SETIODEV,

/*
 * Used when audio playback is controlled by the frameserver,
 * e.g. clients that do not use the shmif to playback audio
 */
	TARGET_COMMAND_ATTENUATE,

/*
 * This indicates that A/V synch is not quite right and
 * the client, if possible, should try to adjust internal
 * buffering.
 */
	TARGET_COMMAND_AUDDELAY,

/*
 * Comes either as a positive response to a EXTERNAL_SEQREQ,
 * and then ioev[0].iv carries the client- provided request
 * cookie -- or as an explicit request from the parent that
 * a new window of a certain type should be created (used
 * for image- transfers, debug windows, ...)
 */
	TARGET_COMMAND_NEWSEGMENT,

/*
 * The running application in the server explicitly prohibited
 * the client from getting access to new segments due to UX
 * restrictions or resource limitations.
 */
	TARGET_COMMAND_REQFAIL,

/*
 * There is a whole slew of reasons why a buffer handled provided
 * could not be used. This event is returned when such a case has
 * been detected in order to try and provide a graceful fallback
 * to regular shm- copying.
 */
	TARGET_COMMAND_BUFFER_FAIL,

/*
 * Specialized output hinting, considered deprecated
 */
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

/*
 * These events map from a connected client to an arcan server.
 */
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
 * (for FDTRANSFER related operations).
 */
	EVENT_EXTERNAL_FAILURE,

/*
 * Similar to FDTRANSFER in that the server is expected to take
 * responsibility for a descriptor on the pipe that should be
 * used for rendering instead of the .vidp buffer. This is for
 * accelerated transfers when using an AGP platform and GPU
 * setup that supports such sharing.
 *
 * This is managed by arcan_shmif_control.
 */
	EVENT_EXTERNAL_BUFFERSTREAM,

/*
 * Debugging hints for video/timing information
 */
	EVENT_EXTERNAL_FRAMESTATUS,

/*
 * Decode playback discovered additional substreams that can be
 * selected or switched between
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
 * Hint how the cursor is to be rendered; i.e. if it's locally defined
 * or a user-readable string suggesting what kind of cursor image
 * that could be used.
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

/*
 * These are actually not connected to the shmif at all,
 * and will be moved to the engine where they belong when
 * the event- management is refactored into an actual
 * protocol. [ Then we can keep the above enums shared,
 * and move everything below this point into the _event.h ]
 */
enum ARCAN_EVENT_VIDEO {
	EVENT_VIDEO_EXPIRE,
	EVENT_VIDEO_CHAIN_OVER,
	EVENT_VIDEO_DISPLAY_ADDED,
	EVENT_VIDEO_DISPLAY_REMOVED,
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

	union {
		struct {
			int16_t width;
			int16_t height;
		};
		int slot;
	};

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

		struct{
/* platform specific content needed for some platforms to map a buffer */
			size_t pitch;
			int format;
		} bstream;

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
			uint64_t pts;
			uint64_t acquired;
			float fhint;
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
