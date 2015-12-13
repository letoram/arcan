/*
 Arcan Shared Memory Interface, Event Namespace
 Copyright (c) 2014-2015, Bjorn Stahl
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
 * The types and structures used herein are "transitional" in the sense that
 * during the later optimization / harderning, we'll likely refactor to use
 * more compat message sizes in order to consume fewer cache-lines, and split
 * larger messages over a protobuf+socket.
 *
 * The event structure is rather messy as it is the result of quite a number of
 * years of evolutionary "adding more and more fields" as the engine developed.
 * The size of some fields are rather arbitrary, and has been picked to cover
 * the largest (networking discovery messages) matching % 32 == 0 with padding.
 */

enum ARCAN_EVENT_CATEGORY {
	EVENT_SYSTEM   = 1,
	EVENT_IO       = 2,
	EVENT_VIDEO    = 4,
	EVENT_AUDIO    = 8,
	EVENT_TARGET   = 16,
	EVENT_FSRV     = 32,
	EVENT_EXTERNAL = 64,
	EVENT_NET      = 128,

/* This is found in every enum that is explicitly used as that enum
 * as member-of-struct (which debuggers etc. need) rather than the explicit
 * sized member. The effect is that the standard restricts size to a numeric
 * type that fits (but not exceeds) an int, but the compiler is allowed to
 * use a smaller one which is bad for IPC. */
	EVENT_LIM      = INT_MAX
};

/*
 * Primarily hinting to the running appl, but can also dictate scheduling
 * groups, priority in terms of resource exhaustion, sandboxing scheme and
 * similar limitations (e.g. TITLEBAR / CURSOR should not update 1080p60Hz)
 *
 * Special flags (not enforced yet, will be after hardening phase) :
 * [INPUT] data from server to client
 * [LOCKSTEP] signalling may block indefinitely, appl- controlled
 * [UNIQUE] only one per connection
 */
enum ARCAN_SEGID {
/*
 * New / unclassified segments have this type until the first
 * _EXTERNAL_REGISTER event has been received. aud/vid signalling is ignored
 * in this state.
 */
	SEGID_UNKNOWN = 0,

/* LIGHTWEIGHT ARCAN (nested execution) */
	SEGID_LWA,

/* Server->Client exclusive --
 * External Connection, 1:many */
	SEGID_NETWORK_SERVER,

/* Server->Client exclusive -- cannot be requested
 * External Connection, 1:1 */
	SEGID_NETWORK_CLIENT,

/* External Connection, non-interactive data source */
	SEGID_MEDIA,

/* Sensitive, varying privilege level, event- driven */
	SEGID_TERMINAL,

/* External client connection, A/V/latency sensitive */
	SEGID_REMOTING,

/* [INPUT] High-CPU, Low Latency, data exfiltration risk */
	SEGID_ENCODER,

/* High-frequency event input, little if any A/V use */
	SEGID_SENSOR,

/* High-interactivity, CPU load, A/V cost, latency requirements */
	SEGID_GAME,

/* Input reactive, user- sensitive data */
	SEGID_APPLICATION,

/* Networking, high-risk for malicious data, aggressive resource consumption */
	SEGID_BROWSER,

/* Virtual Machine, high-risk for malicious data,
 * CPU load etc. guarantees support for state- management */
	SEGID_VM,

/* Head-Mounted display, buffer is split evenly left / right but updated
 * synchronously */
	SEGID_HMD_SBS,

/* Head-Mounted display, should be mapped as LEFT view */
	SEGID_HMD_L,

/* Head-Mounted display, should be mapped as RIGHT view */
	SEGID_HMD_R,

/*
 * [LOCKSTEP, UNIQUE] Popup-window, use with viewport hints
 */
	SEGID_POPUP,

/*
 * [UNIQUE] Used for statusbar style visual alert / identifcation
 */
	SEGID_ICON,

/* [UNIQUE] Visual titlebar style, actual text content can be per segment */
	SEGID_TITLEBAR,

/* [UNIQUE] User- provided cursor, competes with CURSORHINT event. */
	SEGID_CURSOR,

/*
 * [UNIQUE]
 * Indicates that this segment is used to propagate accessibility related data;
 * High-contrast, simplified text, screen-reader friendly.
 *
 * A reject on such a segment request indicates that no accessibility options
 * have been enabled and can thus be used as an initial probe.
 */
	SEGID_ACCESSIBILITY,

/*
 * [UNIQUE] Clipboard style data transfors, for image, text or audio sharing.
 * Can also have streaming transfers using the bchunk mechanism.  Distinction
 * between Drag'n'Drop and Clipboard state uses the CURSORHINT mechanism.
 */
	SEGID_CLIPBOARD,

/*
 * [INPUT] Incoming clipboard data
 */
	SEGID_CLIPBOARD_PASTE,

/* Can always be terminated without risk, may be stored as part of debug format
 * in terms of unexpected termination etc. */
	SEGID_DEBUG,
	SEGID_LIM = INT_MAX
};

/*
 * These are commands that map from parent to child.
 * If any ioevs[0..n].iv/fv are used, it is specified in the comments
 */
enum ARCAN_TARGET_COMMAND {
/* shutdown sequence:
 * 0. dms is released,
 * 1. _EXIT enqueued,
 * 2. semaphores explicitly unlocked
 * 3. parent spawns a monitor thread, kills unless exited after
 *    a set amount of time (for authoritative connections).
 */
	TARGET_COMMAND_EXIT = 1,

/*
 * Hints regarding how the underlying client should treat
 * rendering and video synchronization.
 * ioevs[0].iv maps to TARGET_SKIP_*
 */
	TARGET_COMMAND_FRAMESKIP,

/*
 * in case of TARGET_SKIP_STEP, this can be used to specify
 * a relative amount of frames to process or rollback
 * ioevs[0].iv represents the number of frames.
 */
	TARGET_COMMAND_STEPFRAME,

/*
 * Set a specific key-value pair. These have been registered
 * in beforehand through EVENT_EXTERNAL_COREOPT.
 * Uses coreopt substructure.
 */
	TARGET_COMMAND_COREOPT,

/*
 * Comes with a single descriptor in ioevs[0].iv that should be dup()ed before
 * next shmif_ call or used immediately for (user-defined) binary
 * store/restore. The conversion between socket- transfered descriptor and
 * ioev[0] is handled internally in shmif_control.c
 */
	TARGET_COMMAND_STORE,
	TARGET_COMMAND_RESTORE,

/*
 * Similar to store/store, but used to indicate that the data source and binary
 * protocol carried within is implementation- defined. It is used for advanced
 * cut/paste or transfer operations, possibly with zero-copy mechanisms like
 * memfd.
 */
	TARGET_COMMAND_BCHUNK_IN,
	TARGET_COMMAND_BCHUNK_OUT,

/*
 * User requested that the frameserver should revert to a safe initial state.
 * This is also an indication that the current application state is undesired.
 * ioevs[0].iv == 0, normal / "soft" (impl. defined) reset
 * ioevs[0].iv == 1, hard reset (as close to initial state as possible)
 * ioevs[0].iv == 2, recovery- reset, parent has lost tracking states
 */
	TARGET_COMMAND_RESET,

/*
 * Suspend operations, only _EXIT, _PAUSE and _UNPAUSE should be valid events
 * in this state. Indicates that the server does not want the client to consume
 * any system- resources.  Will be sent at user request or as part of
 * power-save.
 */
	TARGET_COMMAND_PAUSE,
	TARGET_COMMAND_UNPAUSE,

/*
 * For connections that have a fine-grained perception of time, both absolute
 * and relative in terms of some internal timebase, request a seek to a
 * specific point in time (or as close as possible).
 * ioevs[0].iv != 1 indicates relative,
 * ioevs[1].fv = contains the actual timeslot.
 */
	TARGET_COMMAND_SEEKTIME,

/*
 * For segments that have indicated content-state, move content position
 * to specified "absolute" position:
 * ioevs[0].iv = x axis: 0[no change], 1 (left) <= n <= 65536 (right)
 * ioevs[1].iv = y axis: 0[no change], 1 (top) <= n <= 65536 (bottom)
 */
	TARGET_COMMAND_SEEKCONTENT,

/*
 * A hint in regards to the currently displayed dimensions.  It is up to the
 * program running on the server to decide how much internal resolution that it
 * is recommended for the client to use. When the visible image resolution
 * deviates a lot from the internal resolution of the client, this event can
 * appear as a friendly suggestion to resize.
 * The continued field may be set to !0 indicating that there will be more
 * resize events shortly.
 * The 3/4 slots, if set, indicates the physical properties of the display
 * currently in use.
 * ioevs[0].iv = width,
 * ioevs[1].iv = height,
 * ioevs[2].iv = continued
 * ioevs[3].iv = (uint16_t) xdpi << 16 | (uint16_t) ydpi in mm.
 * ioevs[4].iv = RGB layout (0 RGB, 1 BGR, 2 VRGB, 3 VBGR)
 */
	TARGET_COMMAND_DISPLAYHINT,

/*
 * Hint input/device mapping (device-type, input-port),
 * primarily used for gaming / legacy applications.
 * ioevs[0].iv = device_type,
 * ioevs[1].iv = input_port
 */
	TARGET_COMMAND_SETIODEV,

/*
 * Used when audio playback is controlled by the frameserver, e.g. clients that
 * do not use the shmif to playback audio for quality- or latency- reasons.
 * This is sent transparently when a script changes the gain for an audio
 * source.
 * ioevs[0].fv = gain_value
 */
	TARGET_COMMAND_ATTENUATE,

/*
 * This indicates that A/V synch is not quite right and the client, if
 * possible, should try to adjust internal buffering.
 * ioevs[0].iv = relative audio-skew (ms)
 * ioevs[1].iv = relative video-skew (ms)
 */
	TARGET_COMMAND_AUDDELAY,

/*
 * Comes either as a positive response to a EXTERNAL_SEQREQ, and then
 * ioev[0].iv carries the client- provided request cookie -- or as an explicit
 * request from the parent that a new window of a certain type should be
 * created (used for image- transfers, debug windows, ...)
 * ioev[1].iv is set to !0 if the segment is used to receive rather than send
 * data.
 * ioev[2].iv carries the current segment type, which should pair the request
 * (or if the request is unknown, hint what it should be used for).
 *
 * To access this segment, call arcan_shmif_acquire with a NULL key. This can
 * only be called once for each NEWSEGMENT event and the user accepts
 * responsibility for the segment. Future calls to _poll or _wait with a
 * pending NEWSEGMENT without accept will drop the segment negotiation.
 */
	TARGET_COMMAND_NEWSEGMENT,

/*
 * The running application in the server explicitly prohibited the client from
 * getting access to new segments due to UX restrictions or resource
 * limitations.
 * ioev[0].iv = cookie (submitted in request)
 */
	TARGET_COMMAND_REQFAIL,

/*
 * There is a whole slew of reasons why a buffer handled provided could not be
 * used. This event is returned when such a case has been detected in order to
 * try and provide a graceful fallback to regular shm- copying.
 */
	TARGET_COMMAND_BUFFER_FAIL,

/*
 * Reserved for future use, will provide a handle to a specific device node,
 * where the type of the node defines how it is supposed to be used.
 * ioev[0].iv = handle,
 * ioev[1].iv = type [e.g. render-node for switching GPUs]
 */
	TARGET_COMMAND_DEVICE_NODE,

/*
 * Graph- mode is a special case thing for switching between active
 * representation for a specific segment. It is implementation defined and
 * primarily used in custom LWA- targeted appls that need custom frameservers
 * as well (e.g. the Senseye project).
 * ioev[0].iv = mode,
 * ioev[1].fv .. ioev[4].fv = user defined, mode related values
 */
	TARGET_COMMAND_GRAPHMODE,

/*
 * Primarily used on clipboards ("pasteboards") that are sent as recordtargets,
 * and comes with a possibly multipart UTF-8 encoded message at a fixed limit
 * per message. Each individual message MUST be valid UTF-8 even in multipart.
 * ioev[0].iv = !0, multipart continued
 * ioev.message = utf-8 valid byte sequence
 */
	TARGET_COMMAND_MESSAGE,

/*
 * Specialized output hinting, considered deprecated. To be replaced with
 * graphmode.
 */
	TARGET_COMMAND_VECTOR_LINEWIDTH,
	TARGET_COMMAND_VECTOR_POINTSIZE,
	TARGET_COMMAND_NTSCFILTER,
	TARGET_COMMAND_NTSCFILTER_ARGS,
	TARGET_COMMAND_LIMIT = INT_MAX
};

/*
 * These events map from a connected client to an arcan server, the namespacing
 * is transitional and it is recommended that the indirection macro,
 * ARCAN_EVENT(X) is used. Those marked UNIQUE _may_ lead to the queue window
 * being scanned for newer events of the same time, discarding previous ones.
 */
#define _INT_SHMIF_TMERGE(X, Y) X ## Y
#define _INT_SHMIF_TEVAL(X, Y) _INT_SHMIF_TMERGE(X, Y)
#define ARCAN_EVENT(X)_INT_SHMIF_TEVAL(EVENT_EXTERNAL_, X)
enum ARCAN_EVENT_EXTERNAL {
/*
 * Custom string message, used as some user- directed hint, or in the case
 * of a clipboard segid, UTF-8 sequence to inject.
 * Uses the message field.
 */
	EVENT_EXTERNAL_MESSAGE = 0,

/*
 * Specify that there is a possible key=value argument that could be set.
 * uses the message field to encode key and value pair.
 */
	EVENT_EXTERNAL_COREOPT,

/*
 * [UNIQUE]
 * Dynamic data source identification string, similar to message but is
 * expected to come when something has changed radically, (streaming external
 * video sources redirecting to new url for instance).
 * uses the message field.
 */
	EVENT_EXTERNAL_IDENT,

/*
 * Hint that the previous I/O operation failed (for FDTRANSFER related
 * operations).
 */
	EVENT_EXTERNAL_FAILURE,

/*
 * Similar to FDTRANSFER in that the server is expected to take responsibility
 * for a descriptor on the pipe that should be used for rendering instead of
 * the .vidp buffer. This is for accelerated transfers when using an AGP
 * platform and GPU setup that supports such sharing. Note that this is a
 * rather young interface with possible security complications. Block this
 * operation in sensitive contexts.
 *
 * This is managed by arcan_shmif_control.
 */
	EVENT_EXTERNAL_BUFFERSTREAM,

/* [UNIQUE]
 * Contains additional timing information about a delivered videoframe.
 * Uses framestatus substructure.
 */
	EVENT_EXTERNAL_FRAMESTATUS,

/*
 * Decode playback discovered additional substreams that can be selected or
 * switched between.  Uses the streamstat substructure.
 */
	EVENT_EXTERNAL_STREAMINFO,

/*
 * [UNIQUE]
 * Playback information regarding completion, current time, estimated length
 * etc. Uses the streaminf substructure.
 */
	EVENT_EXTERNAL_STREAMSTATUS,

/*
 * [UNIQUE]
 * hint that serialization operations (STORE / RESTORE) are possible and how
 * much buffer data / which transfer limits that apply.
 */
	EVENT_EXTERNAL_STATESIZE,

/*
 * [UNIQUE]
 * hint that any pending buffers on the audio device should be discarded.
 * used primarily for A/V synchronization.
 */
	EVENT_EXTERNAL_FLUSHAUD,

/*
 * Request an additional shm-if connection to be allocated, only one segment is
 * guaranteed per process. Tag with an ID for the parent to be able to accept-
 * or reject properly.  Uses the segreq- substructure.
 */
	EVENT_EXTERNAL_SEGREQ,

/*
 * Used to indicated that some external entity tries to provide input data
 * (e.g. a vnc client connected to an encode frameserver) uses the key and
 * cursor substructure.
 */
	EVENT_EXTERNAL_KEYINPUT,
	EVENT_EXTERNAL_CURSORINPUT,

/*
 * [UNIQUE]
 * Hint how the cursor is to be rendered; i.e. if it's locally defined or a
 * user-readable string suggesting what kind of cursor image that could be
 * used. Uses the messagefield and the effect is implementation defined, though
 * suggested labels are:
 * [default, wait, select-inv, select, up, down, left-right, drag-up-down,
 * drag-up, drag-down, drag-left, drag-right, drag-left-right, rotate-cw,
 * rotate-ccw, normal-tag, diag-ur, diag-ll, drag-diag, datafield,
 * move, typefield, forbidden, help, vertical-datafield, drag-drop,
 * drag-reject ]
 *
 * The only mandated cursorhint is 'custom' which is treated as 'default'
 * UNLESS there is a CURSORHINT type subsegment mapped, then that will be used.
 */
	EVENT_EXTERNAL_CURSORHINT,

/*
 * Hint that video synchronization should only cover a subarea.  This is reset
 * to 0,0,w,h on a completed resize sequence.  Values outside the current range
 * (x+w > segw, y+h > segh) will be ignored or cause the connection to be
 * terminated.
 * Uses the viewport substructure.
 */
	EVENT_EXTERNAL_VIEWPORT,

/*
 * [UNIQUE]
 * Hint about local content state in regards to uses the content substructure.
 */
	EVENT_EXTERNAL_CONTENT,

/*
 * Hint that a specific input label is supported. Uses the labelhint
 * substructure and label is subject to A-Z,0-9_ normalization with * used
 * as wildchar character for incremental indexing.
 */
	EVENT_EXTERNAL_LABELHINT,

/* [ONCE]
 * Specify the requested subtype of a segment, along with a descriptive UTF-8
 * string (application title or similar) and a caller- selected 64-bit UUID.

 * The UUID is an unmanaged identifier namespace where the caller or
 * surrounding system tries to avoid collsions. The ID is primarily intended
 * for recalling user-interface (not security- related) properties (window
 * dimensions, ...).
 *
 * Although possible to call this multiple times, attempts at switching SEGID
 * from the established type will be ignored.
 */
	EVENT_EXTERNAL_REGISTER,

/*
 * Request attention to the segment or subsegment, uses the message substr
 * and multipart messages need to be properly terminated.
 */
	EVENT_EXTERNAL_ALERT,

/*
 * Request that the frameserver provide a monotonic update clock for events,
 * can be used both to drive the _shmif_signal calls and as a crude timer.
 * Uses the 'clock' substructure.
 */
	EVENT_EXTERNAL_CLOCKREQ,

	EVENT_EXTERNAL_ULIM = INT_MAX
};

/*
 * Skipmode are synchronization hints for how A/V/I synch
 * should be compensated for (if possible), uses ioval[0].iv
 */
enum ARCAN_TARGET_SKIPMODE {
/* Discard V frames if the period time will be overshot */
	TARGET_SKIP_AUTO =  0,
/* Never discard frames, prefer period to (period*2) time oscillation */
	TARGET_SKIP_NONE = -1,
/* Reverse- playback state */
	TARGET_SKIP_REVERSE  = -2,
/* Rollback video to (abs(v+TARGET_SKIP_ROLLBACK)+1) frames, apply
 * input then simulate forward */
	TARGET_SKIP_ROLLBACK = -3,
/* Single- stepping clock, stepframe events drive transfers */
	TARGET_SKIP_STEP = 1,
/* Only process every v-TARGET_SKIP_FASTWD+1 frames */
	TARGET_SKIP_FASTFWD  = 10,
	TARGET_SKIP_ULIM = INT_MAX
};

/*
 * Basic input event type grouping,
 * CATEGORY  => IO (used for masking, queuetransfer etc.)
 * KIND      => determines substructure
 * IDEVKIND  => hints at device origin (should rarely matter)
 * IDATATYPE => usually redundant against KIND, reserved for future tuning
 */
enum ARCAN_EVENT_IO {
	EVENT_IO_BUTTON = 0,
	EVENT_IO_AXIS_MOVE,
	EVENT_IO_TOUCH,
	EVENT_IO_STATUS,
	EVENT_IO_ULIM = INT_MAX
};

enum ARCAN_EVENT_IDEVKIND {
	EVENT_IDEVKIND_KEYBOARD = 0,
	EVENT_IDEVKIND_MOUSE,
	EVENT_IDEVKIND_GAMEDEV,
	EVENT_IDEVKIND_TOUCHDISP,
	EVENT_IDEVKIND_STATUS,
	EVENT_IDEVKIND_ULIM = INT_MAX
};

enum ARCAN_IDEV_STATUS {
	EVENT_IDEV_ADDED = 0,
	EVENT_IDEV_REMOVED,
	EVENT_IDEV_BLOCKED
};

enum ARCAN_EVENT_IDATATYPE {
	EVENT_IDATATYPE_ANALOG = 0,
	EVENT_IDATATYPE_DIGITAL,
	EVENT_IDATATYPE_TRANSLATED,
	EVENT_IDATATYPE_TOUCH,
	EVENT_IDATATYPE_ULIM = INT_MAX
};

/*
 * Used by networking frameserver only, the enable mask is bound
 * to that archetype and cannot be initiated by a non-auth connection
 */
enum ARCAN_EVENT_NET {
/* -- events from frameserver -- */
/* connection was forcibly broken / terminated */
	EVENT_NET_BROKEN,

/* new client connected, assumed non-authenticated
 * (state transfers etc. prohibited) */
	EVENT_NET_CONNECTED,

/* established client disconnected */
	EVENT_NET_DISCONNECTED,

/* used when initiating a connection that timed out */
	EVENT_NET_NORESPONSE,

/* used for frameserver launched in discover mode (query external
 * list server or using local broadcast) */
	EVENT_NET_DISCOVERED,

/* -- events to frameserver -- */
	EVENT_NET_CONNECT,
	EVENT_NET_DISCONNECT,
	EVENT_NET_AUTHENTICATE,
/* events to/from frameserver */
	EVENT_NET_CUSTOMMSG,
	EVENT_NET_INPUTEVENT,
	EVENT_NET_STATEREQ,
	EVENT_NET_ULIM = INT_MAX
};

/*
 * The following enumerations and subtypes are slated for removal here as they
 * only refer to engine- internal events. Currently, the structures and types
 * are re-used with an explicit filter-copy step (frameserver_queuetransfer).
 * Attempting to use them from an external source will get the connection
 * terminated.
 *
 * -- begin internal --
 */
enum ARCAN_EVENT_VIDEO {
	EVENT_VIDEO_EXPIRE,
	EVENT_VIDEO_CHAIN_OVER,
	EVENT_VIDEO_DISPLAY_RESET,
	EVENT_VIDEO_DISPLAY_ADDED,
	EVENT_VIDEO_DISPLAY_REMOVED,
	EVENT_VIDEO_ASYNCHIMAGE_LOADED,
	EVENT_VIDEO_ASYNCHIMAGE_FAILED
};

enum ARCAN_EVENT_SYSTEM {
	EVENT_SYSTEM_EXIT = 0,
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

enum ARCAN_EVENT_FSRV {
	EVENT_FSRV_EXTCONN,
	EVENT_FSRV_RESIZED,
	EVENT_FSRV_TERMINATED,
	EVENT_FSRV_DROPPEDFRAME,
	EVENT_FSRV_DELIVEREDFRAME
};
/* -- end internal -- */

typedef union arcan_ioevent_data {
	struct {
		uint8_t active;
	} digital;

	struct {
/* axis- values are first relative then absolute if set */
		int8_t gotrel;
		uint8_t idcount;
		uint8_t nvalues;
		int16_t axisval[4];
	} analog;

	struct {
		int16_t x, y;
		float pressure, size;
	} touch;

	struct {
/* match ARCAN_IDEV_STATUS */
		uint8_t action;
	} status;

	struct {
/* local index for translated devices, last bit signifies
 * X- compliant keysyms */
		uint8_t devid;
/* pressed or not */
		uint8_t active;
/* bitmask of key_modifiers */
		uint16_t modifiers;
/* possible utf8- match, if known, received events should
 * prefer these, if set. */
		uint8_t utf8[5];
/* depending on devid, SDL or X keysym */
		uint16_t keysym;
/* propagated device code, for identification and troubleshooting */
		uint8_t scancode;
	} translated;

} arcan_ioevent_data;

typedef struct {
	enum ARCAN_EVENT_IO kind;
	enum ARCAN_EVENT_IDEVKIND devkind;
	enum ARCAN_EVENT_IDATATYPE datatype;
	char label[16];

	union{
	struct {
		uint16_t devid;
		uint16_t subid;
	};
	uint16_t id[2];
	uint32_t iid;
	};

/* relative to connection start, for scheduling future I/O without
 * risking a saturated event-queue or latency blocks from signal */
	uint32_t pts;
	arcan_ioevent_data input;
} arcan_ioevent;

/*
 * internal engine only
 */
typedef struct {
	enum ARCAN_EVENT_VIDEO kind;

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

/*
 * internal engine only
 */
typedef struct {
	enum ARCAN_EVENT_FSRV kind;

	union {
		struct {
			int32_t audio;
			size_t width, height;
			size_t c_abuffer, c_vbuffer;
			size_t l_abuffer, l_vbuffer;
			int8_t glsource;
			uint64_t pts;
			uint64_t counter;
		};
		struct {
			char ident[32];
			int64_t descriptor;
		};
	};

	int64_t video;
	intptr_t otag;
} arcan_fsrvevent;

/*
 * internal engine only
 */
typedef struct {
	enum ARCAN_EVENT_AUDIO kind;

	int32_t source;
	uintptr_t* data;
} arcan_aevent;

/*
 * internal engine only
 */
typedef struct arcan_sevent {
	enum ARCAN_EVENT_SYSTEM kind;
	int errcode;
	union {
		struct {
			uint32_t hitag, lotag;
		} tagv;
		struct {
			char* dyneval_msg;
		} mesg;
		char message[64];
	};
} arcan_sevent;

/*
 * Biggest substructure, primarily due to discovery which needs
 * to cover both destination address, public key to use and ident-hint.
 */
typedef struct arcan_netevent{
	enum ARCAN_EVENT_NET kind;
/* tagged in queuetransfer */
	uint64_t source;

	union {
		struct {
/* public 25519 key, will be mapped to/from base64 at borders,
 * private key is only ever transmitted during setup as env-arg */
			char key[32];
/* text indicator of a subservice in ident packages */
			char ident[8];
/* max ipv6 textual representation, 39 + strsep + port */
			char addr[45];
		} host;

/* match size of host as we'd pad otherwise */
		char message[93];
	};

	uint8_t connid;
} arcan_netevent;

typedef struct arcan_tgtevent {
	enum ARCAN_TARGET_COMMAND kind;
	union {
		uint32_t uiv;
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
	enum ARCAN_EVENT_EXTERNAL kind;
	int64_t source;

	union {
/*
 * For events that set one or multiple short messages:
 * MESSAGE, IDENT, CURSORHINT, ALERT
 * Only MESSAGE and ALERT type has any multipart meaning
 */
		struct {
			uint8_t data[78];
			uint8_t multipart;
		} message;

/*
 * For user-toggleable options that can be persistantly tracked
 */
		struct {
			uint8_t index;
			uint8_t type; /* 0: key, 1: descr, 2: value, 3: current value */
			uint8_t data[77];
		} coreopt;

/*
 * Hint the current active size of a possible statetransfer along with
 * a user-defined type identifer. Tuple(identifier, size) should match
 * for doing a fsrv-fsrv state transfer. 0 indicates that state transfers
 * should be disabled (initial state).
 */
		struct {
			uint32_t size;
			uint32_t type;
		} stateinf;

/* Used for remoting, indicate state of (possibly multiple) cursors:
 * id - cursor identifier
 * x, y - cursor coordinates, not necessarily clamped against surface
 * buttons active - recipient must track to determine press/release events
 */
		struct {
			uint32_t id;
			uint32_t x, y;
			uint8_t buttons[5];
		} cursor;

/* Used for remoting, keysym is unfortunately XKeySym translated into SDL one
 * for legacy reasons. Type identifier and UTF-8 alternative should probably be
 * needed in the future when we look into SPICE or similar protocols to replace
 * VNC. */
		struct{
			uint8_t id;
			uint32_t keysym;
			uint8_t active;
		} key;

/* Used with the CLOCKREQ event for hinting how the server should provide
 * STEPFRAME events. if once is set, it is interpreted as a hint to register
 * as a separate / independent timer. If once is set, ID will be tracked and
 * used as iv[1] in the stepframe. */
		struct{
			uint32_t rate;
			uint8_t dynamic, once;
			uint32_t id;
		} clock;

/*
 * Indicate that the connection supports abstract input labels, along
 * with the expected data type (match EVENT_IDATATYPE_*)
 */
		struct {
			char label[16];
			int idatatype;
		} labelhint;

/* platform specific content needed for some platforms to map a buffer,
 * used internally by backend and user-defined values may cause the
 * connection to be terminated */
		struct{
			uint32_t pitch;
			uint32_t format;
		} bstream;

		struct {
			uint8_t langid[3]; /* country code */
			uint8_t streamid; /* key used to tell the decoder to switch */
			uint8_t datakind; /* 0: audio, 1: video, 2: text, 3: overlay */
		} streaminf;

/*
 * These are - reset - on a resize operation.
 *  (x+w), (y+h)   - position and cliped against actual surface dimensions
 *  border (px)    - how thick the border area
 *  parent (wndid) - can be 0 or the window-id we are relative against
 *   transfer      - !0 attempt to limit transfer operations to
 *	                specified area, hint- only.
 *	invisible      - hint that the segment does not need to have its
 *	                backing store synched or drawn at this point
 *  viewid         - for supporting multiple views on the same segment,
 *                  default to 0 value
 */
		struct {
			uint16_t x, y, w, h;
			uint32_t parent;
			uint8_t border;
			uint8_t transfer;
			uint8_t invisible;
			uint8_t viewid;
		} viewport;

/*
 * Used as hints for content (scrollbar etc.)
 * x_pos + x_sz - 0 <= n <= 1.0
 * y_pos + y_sz - 0 <= n <= 1.0
 * 0 lim disables the dimension
 */
		struct {
			float x_pos, x_sz;
			float y_pos, y_sz;
		} content;

/*
 * (ID)   - user-specified cookie, will propagate with req/resp
 * width  - desired width, will be clamped to PP_SHMPAGE_MAXW
 * height - desired height, will be clamped to PP_SHMPAGE_MAXH
 * xofs   - suggested offset relative to main segment (parent hint)
 * yofs   - suggested offset relative to main segment (parent hint)
 * kind   - desired type of the segment request, can be UNKNOWN
 */
		struct {
			uint32_t id;
			uint16_t width;
			uint16_t height;
			int16_t xofs;
			int16_t yofs;
			enum ARCAN_SEGID kind;
		} segreq;

/*
 * (title) - title-bar info or other short string to indicate state
 * (kind)  - only used for non-auth connection primary segments or
 *           for subseg requests that got accepted with an empty kind
 *           if called with the existing kind, titlebar is updated
 * (guid)  - numeric identifier (insecure, non-enforced unique ID)
 *           used for tracking settings etc. between session
 */
		struct {
			char title[64];
			enum ARCAN_SEGID kind;
			uint64_t guid;
		} registr;

		struct {
			uint8_t timestr[9]; /* HH:MM:SS\0 */
			uint8_t timelim[9]; /* HH:MM:SS\0 */
			float completion;   /* float 0..1 -> 8-bit */
			uint8_t streaming;  /* makes lim/completion unknown */
			uint32_t frameno;  /* simple counter */
		} streamstat;

		struct {
			uint32_t framenumber;
			uint64_t pts;
			uint64_t acquired;
			float fhint;
		} framestatus;
	};
} arcan_extevent;

typedef struct arcan_event {
	enum ARCAN_EVENT_CATEGORY category;

	union {
		arcan_ioevent io;
		arcan_vevent vid;
		arcan_aevent aud;
		arcan_sevent sys;
		arcan_tgtevent tgt;
		arcan_fsrvevent fsrv;
		arcan_extevent ext;
		arcan_netevent net;
	};
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
	ARKMOD_RESERVED = 0x8000,
	ARKMOD_LIMIT = INT_MAX
} key_modifiers;

#ifdef PLATFORM_HEADER
#include PLATFORM_HEADER
#endif

struct arcan_evctx {
/* time and mask- tracking, only used parent-side */
	uint32_t c_ticks;
	uint32_t c_leaks;
	uint32_t mask_cat_inp;

/* only used for local queues */
	uint8_t eventbuf_sz;

	arcan_event* eventbuf;

/* offsets into the eventbuf queue, parent will always
 * % ARCAN_SHMPAGE_QUEUE_SZ to prevent nasty surprises */
	volatile uint8_t* front;
	volatile uint8_t* back;

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
		volatile uint8_t* killswitch;
		sem_handle handle;

#ifdef ARCAN_SHMIF_THREADSAFE_QUEUE
		uint8_t init;
		pthread_mutex_t lock;
#endif
	} synch;

};

typedef struct arcan_evctx arcan_evctx;

#endif
