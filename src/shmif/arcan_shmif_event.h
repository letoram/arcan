/*
 Arcan Shared Memory Interface, Event Namespace
 Copyright (c) 2014-2016, Bjorn Stahl
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
 * While not currently enforced, it is likely that (with real-world use data),
 * there will be a mask to queuetransfer+enqueue in ARCAN that will react
 * based on SEGID type (statetransfer for TITLEBAR, no..).
 *
 * Special flags (all not enforced yet, will be after hardening phase) :
 * [INPUT] data from server to client
 * [LOCKSTEP] signalling may block indefinitely, appl- controlled
 * [UNIQUE] only one per connection
 * [DESCRIPTOR_PASSING] for target commands where ioev[0] may be populated
 * with a descriptor. shmif_control retains ownership and may close after
 * it has been consumed, so continued use need to be dup:ed.
 *
 * [PREROLL, ACTIVATION] -
 * Preroll / activation is hidden by the shmif implementation and keeps a new
 * connection (not recovery/reset) in an event blocking/ pending state
 * until an activation event is received. This is to make sure that some events
 * that define client rendering properties, like language, dimensions etc. is
 * available from the start and is used to fill out the shmif_cont.
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

/* External Connection, non-interactive data source. */
	SEGID_MEDIA,

/* Specifically used to indicate a terminal- emulator connection */
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
 * [LOCKSTEP] Popup-window, use with viewport hints to specify
 * parent-relative positioning. Labelhints on this message can be used
 * to send a textual representation for server-side rendering or
 * accessibility (text-to-speak friendly) data. Prefix message with:
 * '-' to indicate a group separator.
 * '*' prefix to indicate the presence of a sublevel
 * '_' prefix to indicate inactive entry.
 * '|' terminates / resets the message position.
 * These can subsequently be activated as a DIGITAL input event with
 * the subid matching the 0-based index of the item.
 */
	SEGID_POPUP,

/*
 * [UNIQUE] Used for statusbar style visual alert / identification
 */
	SEGID_ICON,

/* [UNIQUE] Visual titlebar style for CSD, actual text contents is still
 * server-side rendered and provided as message on this segment or through
 * IDENT messages. Server-side rendering of global menus can also be
 * enabled here by indicating labelhints (and then attaching popups when
 * the label input arrives) */
	SEGID_TITLEBAR,

/* [UNIQUE] User- provided cursor, competes with CURSORHINT event. */
	SEGID_CURSOR,

/*
 * [UNIQUE]
 * Indicates that this segment is used to propagate accessibility related data;
 * High-contrast, simplified text, screen-reader friendly. Messages on this
 * segment should be text-to-speech friendly.
 *
 * A reject on such a segment request indicates that no accessibility options
 * have been enabled and can thus be used as an initial probe.
 */
	SEGID_ACCESSIBILITY,

/*
 * [UNIQUE] Clipboard style data transfers, for image, text or audio sharing.
 * Can also have streaming transfers using the bchunk mechanism.  Distinction
 * between Drag'n'Drop and Clipboard state uses the CURSORHINT mechanism.
 */
	SEGID_CLIPBOARD,

/*
 * [INPUT] Incoming clipboard data
 */
	SEGID_CLIPBOARD_PASTE,

/*
 * [UNIQUE] Not expected to have subwindows, no advanced input, no clipboards
 * but rather a semi-interactive data source that can be rendered and managed
 * outside the normal window flow.
 */
	SEGID_WIDGET,

/*
 * Used by the shmif_tui support library to indicate a monospaced text user
 * interface, with known behavior for cut/paste (drag/drop), state transfers,
 * resize response, font switching, ...
 */
	SEGID_TUI,

/*
 * Used in order to indicate system service integration, exposed as a control
 * panel, tray or desktop style icon that expose abstract/simplified information
 * and a control interface to the respective service.
 */
	SEGID_SERVICE,

/*
 * Used to indicate a protocol bridge and root windows
 * (where applicable and no other segtype or subsegtype- can be spawned).
 */
	SEGID_BRIDGE_X11,

/*
 * The current semantics for wayland (subject to change):
 * note that all subsegment allocations are made relative to the primary
 * wayland subsegment and not as hierarchical subreq on a subseg.
 * [ primary segment: SEGID_BRIDGE_WAYLAND ] ->
 *        subsegment: APPLICATION (message to indicate shell)
 *        subsegment: MEDIA (act as a subsurface)
 *        subsegment: POPUP (VIEWPORT hint to show relationships)
 *        subsegment: CURSOR (bound to a "seat", we always have 1:1)
 *        subsegment: CLIPBOARD (container for DnD, ...)
 *        subsegment: ICON (can reparent to application or clipboard for DnD)
 *        subsegment: SEGID_BRIDGE_X11 (Xwayland surfaces)
 */
	SEGID_BRIDGE_WAYLAND,

/*
 * Used as a forwarding primitive, meaning that the current connection will act
 * as a mediator / router for a new connection, so the subsegment will not be a
 * proper subsegment but internally promoted to a primary one. The management
 * scripts should suspend the source segment if this is accepted, and keep it
 * suspended until the new segment terminates. Other behavior should simply
 * create a normal connection point and forward connection data there.
 */
	SEGID_HANDOVER,

/* Can always be terminated without risk, may be stored as part of debug format
 * in terms of unexpected termination etc. */
	SEGID_DEBUG = 255,

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
 * ioevs[0].iv represents the number of frames,
 * ioevs[1].iv can contain an ID (see CLOCKREQ)
 * ioevs[2].uiv (on CLOCKREQ) 0 or seconds (NTP- jan 1900 64-bit format)
 * ioevs[3].uiv (on CLOCKREQ) fractional second ( - " - ) in GEOHINT- tz
 */
	TARGET_COMMAND_STEPFRAME,

/*
 * Set a specific key-value pair. These have been registered
 * in beforehand through EVENT_EXTERNAL_COREOPT.
 * Uses coreopt substructure.
 */
	TARGET_COMMAND_COREOPT,

/*
 * [DESCRIPTOR_PASSING]
 * Comes with a single descriptor in ioevs[0].iv that should be dup()ed before
 * next shmif_ call or used immediately for (user-defined) binary
 * store/restore. The conversion between socket- transfered descriptor and
 * ioev[0] is handled internally in shmif_control.c
 */
	TARGET_COMMAND_STORE,
	TARGET_COMMAND_RESTORE,

/*
 * [DESCRIPTOR_PASSING]
 * Similar to store/store, but used to indicate that the data source and binary
 * protocol carried within is implementation- defined. It is used for advanced
 * cut/paste or transfer operations, possibly with zero-copy mechanisms like
 * memfd.
 * ioevs[0].iv will carry the file descriptor
 * ioevs[1].iv, lower-32 bits of the expected size (if possible)
 * ioevs[2].iv, upper-32 bits of the expected size
 * message field will carry extension or other type identifier string.
 */
	TARGET_COMMAND_BCHUNK_IN,
	TARGET_COMMAND_BCHUNK_OUT,

/*
 * User requested that the frameserver should revert to a safe initial state.
 * This is also an indication that the current application state is undesired.
 * ioevs[0].iv == 0, normal / "soft" (impl. defined) reset
 * ioevs[0].iv == 1, hard reset (as close to initial state as possible)
 * ioevs[0].iv == 2, recovery- reset, parent has lost tracking states
 * ioevs[0].iv == 3, recovery- reconnect, connection was broken but has been
 * re-established. This will still cause reset subsegments to terminate.
 * In this state, a lot of the internals of the shmif- context
 * has been modified. Most importantly, the epipe is no-longer
 * the same. The old file-descriptor number (already closed at) this stage is
 * returned in ioevs[1].iv in order to allow updates to polling structures.
*/
	TARGET_COMMAND_RESET,

/*
 * Suspend operations, _EXIT, _PAUSE, _UNPAUSE, _DISPLAYHINT, _FONTHINT should
 * be valid events in this state. If state management is left to the backend
 * shmif implementation, the latest DISPLAYHINT, FONTHINT will be queued and
 * appear on UNPAUSE. Indicates that the server does not want the client to
 * consume any system- resources. Will be sent at user request or as part of
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
 * ioev[0].iv : 0 = seek_relative, 1 = seek_absolute
 * if (seek_relative)
 *  ioevs[1].iv = y-axis: step 'n' logic steps (impl. defined size)
 *  ioevs[2].iv = x-axis: step 'n' logic steps (impl. defined size)
 * if (seek_absolute)
 *  ioevs[1].fv = y-axis: set content position (ignore < 0 <= n <= 1)
 *  ioevs[2].fv = x-axis: set content position (ignore < 0 <= n <= 1)
 */
	TARGET_COMMAND_SEEKCONTENT,

/* [PREROLL/UNIQUE/AGGREGATE]
 * This event hints towards current display properties or desired display
 * properties.
 *
 * Changes in width / height from the current segment size is
 * a hint to call shmif_resize if the client can handle drawing in different
 * resolutions without unecessary scaling UNLESS the specified dimensions
 * are 0, 0 (indication that only hintflags are to be changed). These will
 * all be aggregated to the last displahint in queue.
 *
 * Changes to the hintflag indicate more abstract states: e.g.
 * more displayhint events to come shortly, segment not being used or shown,
 * etc.
 *
 * Changes to the RGB layout or the density are hints to improve rendering
 * quality in regard to a physical display (having things displayed at a
 * known physical size and layout)
 *
 * ioevs[0].iv = width,
 * ioevs[1].iv = height,
 * ioevs[2].iv = bitmask hintflags: 0: normal, 1: drag resize,
 *               2: invisible, 4: unfocused, 8: maximized, 16: fullscreen
 * ioevs[3].iv = RGB layout (0 RGB, 1 BGR, 2 VRGB, 3 VBGR)
 * ioevs[4].fv = ppcm (pixels per centimeter, square assumed), < 0 ignored.
 *
 * There are subtle side-effects from the UNIQUE/AGGREGATE approach,
 * some other events may be relative to current display dimensions (typically
 * analog input). In the cases where there is a queue like:
 * (DH : displayhint, AIO : analog IOev.)
 * DH, AIO, AIO, AIO, DH this will be 'optimized' into
 * AIO, AIO, AIO, DH possibly changing the effect of the AIO. If this corner
 * case is an actual risk, it should be taken into consideration by the ARCAN-
 * APPL side.
 */
	TARGET_COMMAND_DISPLAYHINT,

/* Hint input/device mapping (device-type, input-port),
 * primarily used for gaming / legacy applications.
 * ioevs[0].iv = device_type,
 * ioevs[1].iv = input_port
 */
	TARGET_COMMAND_SETIODEV,

/*
 * [UNIQUE]
 * Request substream switch.
 * ioev[0].iv - Streamid, should match previously provided STREAMINFO data
 *              (or be ignored!)
 */
	TARGET_COMMAND_STREAMSET,

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
 * Signals that a new subsegment has arrived, either as the reply to a previous
 * user request, or as an explicit feature announce when there is no matching
 * request cookie.
 *
 * ioev[0].iv carries the file descriptor used to build the new segment
 * connection. This can safely be ignored as the cleanup or handover is
 * managed by the next event command or by the acquire call.
 *
 * ioev[1].iv is set to !0 if the segment is used to receive rather than send
 * data.
 *
 * ioev[2].iv carries the current segment type, which should pair the request
 * (or if the request is unknown, hint what it should be used for).
 *
 * ioev[3].iv carries the client- provided request cookie -- or as an explicit
 * request from the parent that a new window of a certain type should be
 * created (used for image- transfers, debug windows, ...)
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
 * [PREROLL/DESCRIPTOR_PASSING]
 * Provide a handle to a specific device node, the [1].iv determines type and
 * intended use.
 * ioev[0].iv = handle (or BADFD)
 * ioev[1].iv =
 *              1: switch render node, handle is a reference to the new node
 *                 or -1 to indicate render mode switch
 *              2: switch local connection:
 *                 message field will contain new _CONNPATH otherwise
 *                 connection primitive will be passed as handle.
 *              3: switch remote connection:
 *                 message field will contain new _CONNPATH otherwise
 *                 connection primitive will be passed handle.
 *              4: hint alternative connection, will not be forwarded but
 *                 tracked internally to use as a different connection path
 *                 on parent failure. Uses message field.
 *              5: reply to a request for privileged device access,
 *                 this is special magic used for bridging DRI2 and will
 *                 weaken security.
 *
 * [for [1].iv == 1]
 * ioev[2].iv = 0: indirect-, output handles for buffer passing will be used
 *                 for internal processing and do not need scanout capable
 *                 memory
 *              1: direct, output handles should be of a type that can be used
 *                 as display scanout type (e.g. GBM_BO_USE_SCANOUT),
 *              2; disabled, hardware acceleration is entirely lost
 *
 * ioev[3].iv = 0: buffer synchronisation method is GBM
 *              1: buffer synchronisation method is Alloc/Streams
 *
 * ioev[4].iv = n bytes of MESSAGE used for modifier description
 * MESSAGE contains modifier metadata
 *
 * [for [1].iv == 2..4]
 * 128-bit guid is packed in [2..5] as 64bit little-endian,
 * (low-32, high-32), (low-32, high-32)
 *
 * [for [1].iv == 5]
 * ioev[2].iv = 0: (unsigned) corresponds to a drm authentication token
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
 * [PREROLL/DESCRIPTOR_PASSING]
 * A hint in regards to how text rendering should be managed in relation to
 * the display regarding filtering, font, and sizing decision.
 * ioev[0].iv = BADFD or descriptor of font to use
 * ioev[1].iv = DEPRECATED
 * ioev[2].fv = desired normal font size in mm, <= 0, unchanged from current
 * ioev[3].iv = hinting: 0, off. 1, monochromatic, 2. light, 3. medium,
 *  -1 (unchanged), 0: off, 1..16 (implementation defined, recommendation
 *  is to range from light to strong). DISPLAYHINT should also be considered
 *  when configuring font rendering.
 *  ioev[4].iv = group:
 *  <= 0 : ignore.
 *  1 : continuation, append as a chain to the last fonthint.
 *  (other values are reserved)
 */
	TARGET_COMMAND_FONTHINT,

/*
 * [PREROLL]
 * A hint to active positioning and localization settings
 * ioev[0].fv = GPS(lat)
 * ioev[1].fv = GPS(long)
 * ioev[2].fv = GPS(elev)
 * ioev[3].cv = ISO-3166-1 Alpha 3 code for country + \'0'
 * ioev[4].cv = ISO-639-2, Alpha 3 code for language (spoken) + \'0'
 * ioev[5].cv = ISO-639-2, Alpha 3 code for language (written) + \'0'
 * ioev[6].iv = timezone
 */
	TARGET_COMMAND_GEOHINT,

/*
 * [PREROLL]
 * geometrical constraints, while-as DISPLAYHINT events convey how the
 * target will be presented, the OUTPUT hints provide an estimate of the
 * capabilities. Shmif will track these properties internally and use
 * it to limit _resize commands (but server does not assume that the client
 * is cooperating).
 *
 * ioev[0].iv = max_width,
 * ioev[1].iv = max_height,
 * ioev[2].iv = rate (Hz, 0 for dynamic)
 * ieov[3].iv = min_width,
 * ioev[4].iv = min_height,
 * ioev[5].iv = output_id
 */
	TARGET_COMMAND_OUTPUTHINT,

/*
 * [ACTIVATION/INTERNAL]
 * Used to indicate the end of the preroll state. _open (and only _open) is
 * blocking until this command has been received. It is used to populate the
 * shmif_cont with strong UI dominant properties, like density, font, ...
 *
 * It is also used as part of a transition to an extended context request,
 * i.e. shmifext_open(...) where device access is privileged. This is needed
 * for some platforms when we can't operate from a lesser-privileged device
 * access ('render-node').
 *
 * ioev[0].iv = lower 32-bit of user access token
 * ioev[1].iv = higher 32-bit of user access token
 * This token can be used to re-authenticate in the event of a server crash
 */
	TARGET_COMMAND_ACTIVATE,

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
 * switched between. Uses the streaminf substructure.
 */
	EVENT_EXTERNAL_STREAMINFO,

/*
 * [UNIQUE]
 * Playback information regarding completion, current time, estimated length
 * etc. Uses the streamstat substructure.
 */
	EVENT_EXTERNAL_STREAMSTATUS,

/*
 * [UNIQUE]
 * hint that serialization operations (STORE / RESTORE) are possible and how
 * much buffer data / which transfer limits that apply.
 * Uses the stateinf substructure.
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
 * (e.g. a vnc client connected to an encode frameserver or cursor warping on
 * a CURSOR subsegment) uses the key and cursor substructure, not the full range
 * of ioevents.
 */
	EVENT_EXTERNAL_KEYINPUT,
	EVENT_EXTERNAL_CURSORINPUT,

/*
 * [UNIQUE]
 * Hint which cursor representation to use; This complements the CURSOR
 * subsegment type (for entirely custom drawn cursors). If a CURSOR subsegment
 * exist, CURSORHINTs should be routed through that, otherwise it is valid to
 * switch cursors on any segment.
 *
 * For legacy reasons, this uses the message field though the cursor name is
 * implementation defined. Suggested labels are:
 *
 * [wait, select-inv, select, up, down, left-right, up-down, drag-up-down,
 * drag-up, drag-down, drag-left, drag-right, drag-left-right, rotate-cw,
 * rotate-ccw, normal-tag, diag-ur, diag-ll, drag-diag, datafield, move,
 * typefield, forbidden, help, hand, vertical-datafield, drag-drop,
 * drag-reject]
 *
 * The reserved/special names are:
 * 'default' : revert to CURSOR subsegment contents or system default
 * 'hidden'  : don't show/draw the cursor at all
 * 'hidden-rel' : no visual change, but try to provide/bias relative samples
 * 'hidden-abs' : no visual change, but try to provide/bias absolute samples
 * 'hidden-hot:x:y' : for CURSOR subsegment, define the hotspot
 */
	EVENT_EXTERNAL_CURSORHINT,

/*
 * Indicate spatial relationship and visibility details relative to some
 * fictive world anchor point or to an explicit relative parent.
 */
	EVENT_EXTERNAL_VIEWPORT,

/*
 * [UNIQUE]
 * Hints that indicate there is scrolling/panning contents and the estimated
 * range and position of the currently active viewport.
 * Uses the content substructure.
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
 * string (application title or similar) and a caller- selected 128-bit UUID.

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

/*
 * Update an estimate on how the connection will hand bchunk transfers.
 * Uses the 'bchunk' substructure.
 * This MAY prompt actions in the running appl, e.g. showing a file- open/
 * /save dialog.
 */
	EVENT_EXTERNAL_BCHUNKSTATE,

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

	/* subid on a IDATATYPE = DIGITAL on IDEVKIND = MOUSE */
	enum ARCAN_MBTN_IMAP {
		MBTN_LEFT_IND = 1,
		MBTN_RIGHT_IND,
		MBTN_MIDDLE_IND,
		MBTN_WHEEL_UP_IND,
		MBTN_WHEEL_DOWN_IND
	};

	enum ARCAN_EVENT_IDEVKIND {
		EVENT_IDEVKIND_KEYBOARD = 0,
		EVENT_IDEVKIND_MOUSE,
		EVENT_IDEVKIND_GAMEDEV,
		EVENT_IDEVKIND_TOUCHDISP,
		EVENT_IDEVKIND_LEDCTRL,
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
		EVENT_VIDEO_DISPLAY_CHANGED,
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
		EVENT_FSRV_DELIVEREDFRAME,
		EVENT_FSRV_PREROLL,
		EVENT_FSRV_APROTO,
		EVENT_FSRV_GAMMARAMP,
		EVENT_FSRV_ADDVRLIMB,
		EVENT_FSRV_LOSTVRLIMB
	};
	/* -- end internal -- */

	typedef union arcan_ioevent_data {
		struct {
			uint8_t active;
		} digital;

	/*
	 * Packing in this field is poor due to legacy.
	 * axisval[] works on the basis of 'just forwarding whatever we can find' where
	 * [nvalues] determine the number of values used, with ordering manipulated
	 * with the [gotrel] field.
	 *
	 * [if gotrel is set]
	 * nvalues = 1: [0] relative sample
	 * nvalues = 2: [0] relative sample, [1] absolute sample
	 * nvalues = 3; same as [2], with 'unknown' sample data in [3]
	 * nvalues = 4; same as [2] but an extra axis (2D sources) in [3,4]
	 *
	 * [if gotrel is not set, the order between relative and absolute are changed]
	 *
	 * A convention for mouse cursors is to EITHER split into two samples on subid
	 * 0 (x) and 1 (y), or use subid (2) with all 4 samples filled out. The point
	 * of that is that we still lack serialization and force a 'largest struct wins'
	 * scenario, meaning that a sample consumes unreasonable memory sizes. There is
	 * also the option for ONE mouse device to be mapped directly into the shmif
	 * page directly without going through the event queue.
	 */
		struct {
			int8_t gotrel;
			uint8_t nvalues;
			int16_t axisval[4];
		} analog;

		struct {
			uint8_t active;
			int16_t x, y;
			float pressure, size;
		} touch;

		struct {
	/* match ARCAN_IDEV_STATUS */
			uint8_t action;
			uint8_t devkind;
			uint16_t devref;
			uint8_t domain;
		} status;

		struct {
	/* possible utf8- match, if known, received events should
	 * prefer these, if set. "waste" 1 byte to protect cascade from
	 * missing \0 */
			uint8_t utf8[5];
	/* pressed or not */
			uint8_t active;
	/* propagated device code, for identification and troubleshooting */
			uint8_t scancode;
	/* depending on devid, SDL or X keysym */
			uint32_t keysym;
	/* bitmask of key_modifiers */
			uint16_t modifiers;
		} translated;

	} arcan_ioevent_data;

	enum ARCAN_EVENT_IOFLAG {
	/* Possibly used by mouse, touch, gamedev  etc. where some implementation
	 * defined gesture descriptions comes in label, suggested values follow
	 * the google terminology (gestures-touch-mechanics):
	 * touch, dbltouch, click, dblclick, drag, swipe, fling, press, release,
	 * drag, drop, openpinch, closepinch, rotate.
	 * n- finger variations will fire an event each, subid gives index.
	 */
		ARCAN_IOFL_GESTURE = 1,
		ARCAN_IOFL_ENTER = 2,
		ARCAN_IOFL_LEAVE = 4,
	};

	typedef struct {
		enum ARCAN_EVENT_IO kind;
		enum ARCAN_EVENT_IDEVKIND devkind;
		enum ARCAN_EVENT_IDATATYPE datatype;
		char label[16];
		uint8_t flags;

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
		uint64_t pts;
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
				int flags;
				float vppcm;
				int displayid;
				int ledctrl;
				int ledid;
				int cardid;
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
				int8_t glsource;
				uint64_t pts;
				uint64_t counter;
				uint8_t message[32];
			};
			struct {
				char ident[32];
				int64_t descriptor;
			};
			struct {
				int aproto;
			};
			struct {
				unsigned limb;
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
			uint8_t cv[4];
		} ioevs[8];

		int code;
		union {
			char message[78];
			uint8_t bmessage[78];
		};
	} arcan_tgtevent;

	typedef struct arcan_extevent {
		enum ARCAN_EVENT_EXTERNAL kind;
		int64_t source;

		union {
	/*
	 * For events that set one or multiple short messages:
	 * MESSAGE, IDENT, CURSORHINT, ALERT
	 * Only MESSAGE and ALERT type has any multipart meaning
	 * (data) - UTF-8 (complete, valid)
	 * (multipart) - !0 (more to come, terminated with 0)
	 */
			struct {
				uint8_t data[78];
				uint8_t multipart;
			} message;

	/*
	 * For user-toggleable options that can be persistantly tracked,
	 * per segment related key/value store
	 * (index) - setting index
	 * (type)  - setting type, 0: key, 1: description, 2: value, 3: current value,
 * (data)  - UTF-8 encoded, type specific value. Limitations on key are similar
 *           to arcan database key (see arcan_db man)
 */
		struct {
			uint8_t index;
			uint8_t type;
			uint8_t data[77];
		} coreopt;

/*
 * Hint the current active size of a possible statetransfer along with a
 * user-defined type identifer. Tuple(identifier, size) should match for doing
 * a fsrv-fsrv state transfer, disabled (initial state).
 *
 * (size) - size, in bytes, of the state (0 to disable)
 * (type) - application/segment identifier (spoofable, no strong identity)
 */
		struct {
			uint32_t size;
			uint32_t type;
		} stateinf;

/* Used for remoting, indicate state of (possibly multiple) cursors:
 * (id)      - cursor identifier
 * (x, y)    - absolute coordinates, not necessarily clamped against surface
 * (buttons) - state list mask of active buttons
 */
		struct {
			uint32_t id;
			uint32_t x, y;
			uint8_t buttons[5];
		} cursor;

/* Used for remoting, indicate keyboard button state change:
 * (id)     - numeric key ID, for use when we have translation tables
 * (keysym) - currently horrible, XKeySym with SDL- related translation (legacy)
 * (active) - & !0 > 0 active (pressed)
 */
		struct{
			uint8_t id;
			uint32_t keysym;
			uint8_t active;
		} key;

/* Used with the CLOCKREQ event for hinting how the server should provide
 * STEPFRAME events. if once is set, it is interpreted as a hint to register as
 * a separate / independent timer.
 * (once) - & !0 > 0, fire once or use as periodic timer
 * (rate) - if once is set, relative to last tick otherwise every n ticks.
 * (id)   - caller specified ID that will be used in stepframe reply
 * (dynamic) - set to !0 if it should be hooked to video frame delivery rather
 *             than an approximate monotonic clock
 *
 * there is one automatic clock- slot per connection, and will always have
 * ID 1 in the reply.
 */
		struct{
			uint32_t rate;
			uint8_t dynamic, once;
			uint32_t id;
		} clock;

/*
 * Used with the BCHUNKSTATE event for hinting to the server that the
 * application wants to- or is capable of- receiving or writing bchunkdata.
 * (size)      - (input == 0, estimation of upper limit or 0 if unknown)
 * (input)     - set to !0 to indicate that the support is for open/read,
 * (hint)      - set to 0 to indicate that the state- support it immediate,
 *               e.g. an open/save dialog. set to 1 to hint that the bchunk-
 *               support indicates capability.
 * (stream)    - !0 if a streaming data store is acceptable or it needs to be
 *               seekable / mappable
 * (extensions)- 7-bit ASCII filtered to alnum with ; separation between
 *               accepted extensions. * for wildcard support or empty [0]='\0'
 *               to indicate no-support for input/output.
  */
	struct {
		uint64_t size;
		uint8_t input;
		uint8_t hint;
		uint8_t stream;
		uint8_t extensions[68];
	} bchunk;

/*
 * Indicate that the connection supports abstract input labels, along
 * with the expected data type (match EVENT_IDATATYPE_*)
 * (label)     - 7-bit ASCII filtered to alnum and _
 * (initial)   - suggested default sym from the table used in
 *               arcan_shmif_tuisym.
 * (descr)     - short 8-bit UTF description, if localization is avail.
 *               also follow the language from the last GEOHINT
 * (subv)      - > 0, use subid as pseudonym for this label (reduce string use)
 * (idatatype) - match IDATATYPE enum of expected data
 * (modifiers) - bitmap of desired modifiers (arkmod)
 */
		struct {
			char label[16];
			uint16_t initial;
			char descr[58];
			uint16_t subv;
			uint8_t idatatype;
			uint16_t modifiers;
		} labelhint;

/*
 * Platform specific content needed for some platforms to map a buffer, used
 * internally by backend and user-defined values may cause the connection to be
 * terminated, check arcan_shmif_sighandle and corresponding platform code
 * (pitch)  - row width in bytes
 * (format) - color format, also platform specific value
 */
		struct{
			uint32_t pitch;
			uint32_t format;
		} bstream;

/*
 * Define the arrival of a new data stream (for decode),
 * (streamid) - caller specific identifier (to specify stream),
 *
 */
		struct {
			uint8_t streamid; /* key used to tell the decoder to switch */
			uint8_t datakind; /* 0: audio, 1: video, 2: text, 3: overlay */
			uint8_t langid[4]; /* country code */
		} streaminf;

/*
 * The viewport hint is used to provide additional information about
 * different regions of a segment, possible decorations, hierarchical
 * relations, visibility, anchoring and ordering.
 *
 *  (borderpx)[tlrd] - indicate a possible border/shadow/decoration area
 *                     that can be cropped away or ignored in position
 *                     calculations.
 *
 *  (parent) (tok)   - can be 0 or the window-id we are relative against,
 *                     useful for popup subsegments etc. tok comes from
 *                     shmif_page segment_token
 *
 *	(invisible)      - hint that the current content segment backing store
 *	                   contains no information that is visibly helpful,
 *	                   this is typically flipped back and forth in order
 *	                   to save connection setup overhead.
 *
 *	(focused)        - Hint that for all the hierarchies in the connection,
 *	                   this is the one that should have focus.
 *
 *  (anchor-edge)    - enable anchoring to parent.
 *
 *  (anchor-pos)     - enable anchor positioning selection within an area
 *                     in a surface-relative coordinate space.
 *
 *	(edge)           - parent-relative anchoring edge:
 *	                   0 - doesn't matter
 *	                   1 - UL        2 - UC      3 - UR
 *	                   4 - CL        5 - C       6 - CR
 *	                   7 - LL        8 - LC      9 - LR
 *
 *  (x+w, y+h)       - positioning HINT relative to parent UL origo,
 *                     describing the possible anchor region.
 *
 *  (order)          - parent-relative drawing order (+- #segments)
 *
 *  viewports may become invalidated on shrinking resize, though
 *  border- properties for still-valid areas are retained.
 */
		struct {
			int32_t x, y;
			uint16_t w, h;
			uint32_t parent;
			uint8_t border[4];
			uint8_t edge;
			int8_t order;
			uint8_t invisible : 1;
			uint8_t focus : 1;
			uint8_t anchor_edge : 1;
			uint8_t anchor_pos : 1;
		} viewport;

/*
 * Used as hints for content which may be used to enable scrollbars.
 * SZ determines how much of the contents is being showed, x,y + sz
 * is therefore in the range 0.00 <= n <= 1.0
 * (x,y_pos) - < 0.000, disable, +x_sz > 1.0 invalid (bad value)
 * (x,y_sz ) - < 0.000, invalid, > 1.0 invalid
 */
		struct {
			float x_pos, x_sz;
			float y_pos, y_sz;
		} content;

/*
 * (ID)     - user-specified cookie, will propagate with req/resp
 * (width)  - desired width, will be clamped to PP_SHMPAGE_MAXW
 * (height) - desired height, will be clamped to PP_SHMPAGE_MAXH
 * (xofs)   - suggested offset relative to parent segment (parent hint)
 * (yofs)   - suggested offset relative to parent segment (parent hint)
 * (kind)   - desired type of the segment request, can be UNKNOWN
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
 * (uid )  - numeric identifier (insecure, non-enforced unique ID)
 *           used for tracking settings etc. between session
 */
		struct {
			char title[64];
			enum ARCAN_SEGID kind;
			uint64_t guid[2];
		} registr;

/*
 * (timestr, timelim) - 7-bit ascii, isnum : describing HH:MM:SS\0
 * (completion)       - 0..1 (start, 1 finish)
 * (streaming)        - dynamic / unknown source
 * (frameno)          - incremental counter
 */
		struct {
			uint8_t timestr[9];
			uint8_t timelim[9];
			float completion;
			uint8_t streaming;
			uint32_t frameno;
		} streamstat;

/*
 * (framenumber) - incremental counter
 * (pts)         - presentation time stamp, ms (0 - source start)
 * (acquired)    - delievered time stamp, ms (0 - source start)
 * (fhint)       - float metadata used for quality, or similar indicator
 */
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
		uint8_t min_sz[128];
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
	ARKMOD_REPEAT= 0x8000,
	ARKMOD_LIMIT = INT_MAX
} key_modifiers;

#ifdef PLATFORM_HEADER
#include PLATFORM_HEADER
#endif

struct arcan_evctx {
/* time and mask- tracking, only used parent-side */
	int32_t c_ticks;
	uint32_t mask_cat_inp;

/* only used for local queues */
	uint32_t state_fl;
	int exit_code;
	void (*drain)(arcan_event*, int);
	uint8_t eventbuf_sz;

	arcan_event* eventbuf;

/* offsets into the eventbuf queue, parent will always % ARCAN_SHMPAGE_QUEUE_SZ
 * to prevent nasty surprises. these were set before we had access to _Atomic
 * in the standard fashion, and the codebase should be refactored to take that
 * into account */
	volatile uint8_t* volatile front;
	volatile uint8_t* volatile back;

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
