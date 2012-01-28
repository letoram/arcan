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

#define ARCAN_IO_AXIS_LIM = 6

enum ARCAN_EVENT_CATEGORY {
	EVENT_SYSTEM = 1,
	EVENT_IO     = 2,
	EVENT_TIMER  = 4,
	EVENT_VIDEO  = 8,
	EVENT_AUDIO  = 16
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
	EVENT_SYSTEM_CLEANUP_EXTERNAL,
	EVENT_SYSTEM_FRAMESERVER_TERMINATED
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

enum ARCAN_EVENT_VIDEO {
	EVENT_VIDEO_EXPIRE = 0,
	EVENT_VIDEO_SCALED,
	EVENT_VIDEO_MOVED,
	EVENT_VIDEO_BLENDED,
	EVENT_VIDEO_RESIZED,
	EVENT_VIDEO_ROTATED,
	EVENT_VIDEO_FRAMESERVER_TERMINATED,
	EVENT_VIDEO_ASYNCHIMAGE_LOADED,
	EVENT_VIDEO_ASYNCHIMAGE_LOAD_FAILED
};

enum ARCAN_EVENT_AUDIO {
	EVENT_AUDIO_PLAYBACK_FINISHED = 0,
	EVENT_AUDIO_PLAYBACK_ABORTED,
	EVENT_AUDIO_BUFFER_UNDERRUN,
	EVENT_AUDIO_PITCH_TRANSFORMATION_FINISHED,
	EVENT_AUDIO_GAIN_TRANSFORMATION_FINISHED,
	EVENT_AUDIO_OBJECT_GONE,
	EVENT_AUDIO_INVALID_OBJECT_REFERENCED,
	EVENT_AUDIO_FRAMESERVER_TERMINATED
};

enum ARCAN_EVENT_TARGET {
	EVENT_TARGET_EXTERNAL_LAUNCHED,
	EVENT_TARGET_EXTERNAL_TERMINATED,
	EVENT_TARGET_INTERNAL_LAUNCHED,
	EVENT_TARGET_INTERNAL_TERMINATED
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
	void* data;
} arcan_vevent;

typedef struct {
	arcan_aobj_id source;
	void* data;
} arcan_aevent;

typedef struct arcan_sevent {
	int errcode; /* copy of errno if possible */
	int64_t hitag, lotag;	
} arcan_sevent;

typedef struct arcan_tevent {
	uint8_t pulse_count;
} arcan_tevent;

typedef union event_data {
	arcan_ioevent io;
	arcan_vevent video;
	arcan_aevent audio;
	arcan_sevent system;
	arcan_tevent timer;
	void* other;
} event_data;

typedef struct arcan_event {
	uint32_t kind;
	uint32_t tickstamp;
	uint32_t seqn;

	char label[16];
	uint8_t category;
	event_data data;
} arcan_event;

/* check timers, poll IO events and timing calculations
 * out : (NOT NULL) storage- container for number of ticks that has passed
 *                   since the last call to arcan_process 
 * ret : range [0 > n < 1] how much time has passed towards the next tick */ 
float arcan_process(unsigned* nticks);

/* check the queue for events,
 * don't attempt to run this one
 * on more than one thread */
arcan_event* arcan_event_poll();

/* similar to event poll, but will only
 * return events matching masked event */
arcan_event* arcan_event_poll_masked(uint32_t mask_cat, uint32_t mask_ev);

/* serialize src into dst, 
 * returns number of bytes used OR -1 (invalid size) */
ssize_t arcan_event_tobytebuf(char* dst, size_t dstsize, arcan_event* src);

/* deserialize src into dst, return false of *dst could not be filled in or set */
bool arcan_event_frombytebuf(arcan_event* dst, char* src, size_t dstsize);

/* force a keyboard repeat- rate */
void arcan_event_keyrepeat(unsigned rate);

/* add an event to the queue,
 * currently thread-unsafe as there's
 * no active context-management */
void arcan_event_enqueue(arcan_event*);

/* ignore-all on enqueue */
void arcan_event_maskall();

/* drop any mask, including maskall */
void arcan_event_clearmask();

/* set a specific mask, somewhat limited */
void arcan_event_setmask(uint32_t mask);

/* call to initialise/deinitialize the current context
 * may occur several times due to external target launch */
void arcan_event_init();
void arcan_event_deinit();

/* call to dump the contents of the queue */
void arcan_event_dumpqueue();
#endif
