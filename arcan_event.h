/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
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
#define ARCAN_MOUSEIDBASE 0

/* this is relevant if the event queue is authoritative,
 * i.e. the main process side with a frameserver associated. A failure to get
 * a lock within the set time, will forcibly free the frameserver */
#define DEFAULT_EVENT_TIMEOUT 500

#define ARCAN_IO_AXIS_LIM = 6

enum ARCAN_EVENT_CATEGORY {
	EVENT_SYSTEM = 1,
	EVENT_IO     = 2,
	EVENT_TIMER  = 4,
	EVENT_VIDEO  = 8,
	EVENT_AUDIO  = 16,
	EVENT_TARGET = 32,
	EVENT_FRAMESERVER = 64
};

enum ARCAN_EVENT_SYSTEM {
	EVENT_SYSTEM_EXIT = 0,
	EVENT_SYSTEM_VIDEO_FAIL,
	EVENT_SYSTEM_AUDIO_FAIL,
	EVENT_SYSTEM_IO_FAIL,
	EVENT_SYSTEM_MEMORY_FAIL,
	EVENT_SYSTEM_INACTIVATE,
	EVENT_SYSTEM_ACTIVATE,
	EVENT_SYSTEM_LAUNCH_EXTERNAL,
	EVENT_SYSTEM_CLEANUP_EXTERNAL
};

enum ARCAN_TARGET_COMMAND {
	TARGET_COMMAND_FDTRANSFER,
	TARGET_COMMAND_FRAMESKIP,
	TARGET_COMMAND_STORE,
	TARGET_COMMAND_RESTORE,
	TARGET_COMMAND_RESET,
	TARGET_COMMAND_PAUSE,
	TARGET_COMMAND_SETIODEV,
	TARGET_COMMAND_UNPAUSE,
	TARGET_COMMAND_STEPFRAME,
	TARGET_COMMAND_VECTOR_LINEWIDTH,
	TARGET_COMMAND_VECTOR_POINTSIZE,
	TARGET_COMMAND_NTSCFILTER,
	TARGET_COMMAND_NTSCFILTER_ARGS
};

enum ARCAN_EVENT_IO {
	EVENT_IO_BUTTON_PRESS, /*  joystick buttons, mouse buttons, ...    */
	EVENT_IO_BUTTON_RELEASE,
	EVENT_IO_KEYB_PRESS,
	EVENT_IO_KEYB_RELEASE,
	EVENT_IO_AXIS_MOVE
};

enum ARCAN_EVENT_IDEVKIND {
	EVENT_IDEVKIND_KEYBOARD,
	EVENT_IDEVKIND_MOUSE,
	EVENT_IDEVKIND_GAMEDEV
};

enum ARCAN_EVENT_IDATATYPE {
	EVENT_IDATATYPE_ANALOG,
	EVENT_IDATATYPE_DIGITAL,
	EVENT_IDATATYPE_TRANSLATED
};

enum ARCAN_EVENT_FRAMESERVER {
	EVENT_FRAMESERVER_RESIZED,
	EVENT_FRAMESERVER_TERMINATED,
#ifdef _DEBUG
	EVENT_FRAMESERVER_BUFFERSTATUS,
#endif
	EVENT_FRAMESERVER_LOOPED
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

enum ARCAN_EVENT_EXTERNAL {
	EVENT_EXTERNAL_CONNECTED,
	EVENT_EXTERNAL_DISCONNECTED,
	EVENT_EXTERNAL_CUSTOMMSG,
	EVENT_EXTERNAL_INPUTEVENT
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
	TARGET_SKIP_AUTO = 0,
	TARGET_SKIP_NONE = -1,
	TARGET_SKIP_STEP = 1
};

enum event_priority {
	PRIORITY_SYSTEM = 2,
	PRIORITY_NORMAL = 1,
	PRIORITY_SAMPLE = 0
};

typedef union arcan_ioevent_data {
	struct {
		uint8_t devid;
		uint8_t subid;
		bool active;
	} digital;

	struct {
		bool gotrel; /* axis- values are first relative then absolute if set */
		uint8_t devid;
		uint8_t subid;
		uint8_t nvalues;
		int16_t axisval[4];
	} analog;
	
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
	long long hitag, lotag;	
} arcan_sevent;

typedef struct arcan_tevent {
	long long int pulse_count;
} arcan_tevent;

typedef struct arcan_tgtevent {
	enum ARCAN_TARGET_COMMAND command;
	union {
		int iv;
		float fv;
	} ioevs[4];
#ifdef _WIN32
	HANDLE fh;
#endif
} arcan_tgtevent;

typedef union event_data {
	arcan_ioevent io;
	arcan_vevent video;
	arcan_aevent audio;
	arcan_sevent system;
	arcan_tevent timer;
	arcan_tgtevent target;
	arcan_fsrvevent frameserver;
	void* other;
} event_data;

typedef struct arcan_event {
	unsigned kind;
	unsigned tickstamp;
	enum event_priority prio;

	char label[16];
	char category;
	char used;
	
	event_data data;
} arcan_event;

struct arcan_evctx {
	unsigned c_ticks;
	unsigned c_leaks;
	unsigned mask_cat_inp;
	unsigned mask_cat_out;

	unsigned kbdrepeat;

/* limit analog sampling rate as to not saturate the event buffer,
 * with rate == 0, all axis events will be emitted 
 * with rate >  0, the upper limit is n samples per second. 
 * with rate <  0, emitt a sample per axis every n milliseconds. */
	struct {
		int rate;
		
/* with smooth samples > 0, use a ring-buffer of smooth_samples values per axis,
 * and whenever an sample is to be emitted, the actual value will be based on an average
 * of the smooth buffer. */
		char smooth_samples;
	};
	
	unsigned n_eventbuf;
	arcan_event* eventbuf;
	
	unsigned* front;
	unsigned* back;
	unsigned cell_aofs;

	bool local;
	union {
		void* local;
		
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
arcan_event* arcan_event_poll(arcan_evctx*);

/* similar to event poll, but will only
 * return events matching masked event */
arcan_event* arcan_event_poll_masked(arcan_evctx*, unsigned mask_cat, unsigned mask_ev);

/* force a keyboard repeat- rate */
void arcan_event_keyrepeat(arcan_evctx*, unsigned rate);

arcan_evctx* arcan_event_defaultctx();

/* add an event to the queue,
 * currently thread-unsafe as there's
 * no active context-management */
void arcan_event_enqueue(arcan_evctx*, const arcan_event*);

/* ignore-all on enqueue */
void arcan_event_maskall(arcan_evctx*);

/* drop any mask, including maskall */
void arcan_event_clearmask(arcan_evctx*);

/* set a specific mask, somewhat limited */
void arcan_event_setmask(arcan_evctx*, unsigned mask);

int64_t arcan_frametime();

/* call to initialise/deinitialize the current context
 * may occur several times due to external target launch */
void arcan_event_init(arcan_evctx*);
void arcan_event_deinit(arcan_evctx*);

/* call to dump the contents of the queue */
void arcan_event_dumpqueue(arcan_evctx*);
#endif
