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

#define ARCAN_JOYIDBASE 64
#define ARCAN_HATBTNBASE 128
#define ARCAN_MOUSEIDBASE 0

/*
 * This part of the interface is still rather crude and messy,
 * being a blob that has grown organically through the course 
 * of the project (and initially just being a part of the engine
 * internals, not of the shmif), and will be refactored in 
 * incremental steps.
 *
 * 1. Document the EXTERNAL NOTICES, NET_, TARGET_COMMANDS
 *    (as they are used to communicate betewen parent - frameservers)
 *
 * 2. Separate out all the "arcan internal" categories / states
 *
 * 3. Make this into a proper protocol / IPC part 
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

enum ARCAN_EVENT_SYSTEM {
	EVENT_SYSTEM_EXIT = 0,
	EVENT_SYSTEM_SWITCHTHEME
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
 * ioev[0].iv carries 
 */
	TARGET_COMMAND_NEWSEGMENT,

/*
 * request for a state transfer or new segment failed,
 * ioev[0].iv carries request ID
 */
	TARGET_COMMAND_REQFAIL,

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
	EVENT_FRAMESERVER_DROPPEDFRAME,
	EVENT_FRAMESERVER_DELIVEREDFRAME,
	EVENT_FRAMESERVER_VIDEOSOURCE_FOUND,
	EVENT_FRAMESERVER_VIDEOSOURCE_LOST,
	EVENT_FRAMESERVER_AUDIOSOURCE_FOUND,
	EVENT_FRAMESERVER_AUDIOSOURCE_LOST
};

enum ARCAN_EVENT_EXTERNAL {
	EVENT_EXTERNAL_MESSAGE = 0,
	EVENT_EXTERNAL_COREOPT,
	EVENT_EXTERNAL_IDENT, 
	EVENT_EXTERNAL_FAILURE,
	EVENT_EXTERNAL_FRAMESTATUS,
	EVENT_EXTERNAL_STREAMINFO,
	EVENT_EXTERNAL_STREAMSTATUS,
	EVENT_EXTERNAL_PLAYBACKSTATUS,
	EVENT_EXTERNAL_STATESIZE,
	EVENT_EXTERNAL_RESOURCE,
	EVENT_EXTERNAL_FLUSHAUD,
	EVENT_EXTERNAL_SEGREQ,
	EVENT_EXTERNAL_DATASEQ,
	EVENT_EXTERNAL_KEYINPUT,
	EVENT_EXTERNAL_CURSORINPUT
};

enum ARCAN_EVENT_VIDEO {
	EVENT_VIDEO_EXPIRE,
	EVENT_VIDEO_ASYNCHIMAGE_LOADED,
	EVENT_VIDEO_ASYNCHIMAGE_FAILED
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

enum ARCAN_EVENT_AUDIO {
	EVENT_AUDIO_PLAYBACK_FINISHED = 0,
	EVENT_AUDIO_PLAYBACK_ABORTED,
	EVENT_AUDIO_BUFFER_UNDERRUN,
	EVENT_AUDIO_PITCH_TRANSFORMATION_FINISHED,
	EVENT_AUDIO_GAIN_TRANSFORMATION_FINISHED,
	EVENT_AUDIO_OBJECT_GONE,
	EVENT_AUDIO_INVALID_OBJECT_REFERENCED
};

enum ARCAN_TARGET_SKIPMODE {
	TARGET_SKIP_AUTO     =  0, /* drop to keep sync */
	TARGET_SKIP_NONE     = -1, /* never discard data */
	TARGET_SKIP_REVERSE  = -2, /* play backward */
	TARGET_SKIP_ROLLBACK = -3, /* apply input events to prev. state */
	TARGET_SKIP_STEP     =  1, /* single stepping, advance with events */
	TARGET_SKIP_FASTFWD  = 10  /* 10+, only return every nth frame */
};

enum ARCAN_ANALOGFILTER_KIND {
	ARCAN_ANALOGFILTER_NONE = 0,
	ARCAN_ANALOGFILTER_PASS = 1, 
	ARCAN_ANALOGFILTER_AVG  = 2,
 	ARCAN_ANALOGFILTER_ALAST = 3
};

typedef union arcan_ioevent_data {
	struct {
		uint8_t devid;
		uint8_t subid;
		uint8_t active;
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
			uint32_t id;
			uint8_t type;
			uint16_t width;
			uint16_t height;
		} noticereq;

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
	} synch;

};

typedef struct arcan_evctx arcan_evctx;

#endif
