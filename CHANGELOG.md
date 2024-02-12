## 0.6.4
## Core
 * Wired in rendertarget vobj export for hwenc, opt-in via target\_flags on rectgt

## Net
 * add -c file for assigning lua scriptable command-line overrides
 * headless runner for arcan-net host appl can be access via ANET\_RUNNER env.
 * spawning server-side Lua runner if matching appl found, controls message routing
 * introduce rekeying command for forward secrecy, placeholder PQ step-up and resumption

## 0.6.3
## Lua
 * inbound events now have a 'frame' tag for pairing with verbose-frame notification
 * util:random\_interval(low,high) added for CSPRNG non-biased interval RNG
 * util:random\_bytes(len) added for CSPRNG byte string
 * target_input long messages are now marked as multipart
 * convey tui/tpack state in resize events
 * target\_anchorhint added for informing clients about positioning and hierarchy
 * video\_displaymode expose eotf / coordinates for primaries and contents light levels
 * open\_nonblock can now adopt an existing iostream into a target vid
 * input\_remap\_translation overloaded form for serializing backing keymap
 * clockreq no longer forwarded for frameserver event handler
 * image\_metadata added for annotating a vid used when streaming/sharing/scanout HDR contents
 * functions creating files now apply a separate WRITEMASK (split from USERMASK)

## Core
 * respect border attribute in text rasteriser
 * added frame\_id to external events that pairs with shmif-SIGVID signals
 * optional tracy build for profiling (-DENABLE\_TRACY)
 * frameserver clock(stepframe) event handling extended (see shmif)

## Tui
 * nbio asynch type confusion fix (function becomes pcall:userdata)
 * nbio close without explicit flush
 * dock subtype exposed for bar/tray like integration
 * add 'swallow' request for new windows
 * cursor(caret) style and color override controls
 * readline: add completion style control (border)
 * readline: allow attached popup to replace in-band completion
 * readline: history traversal early-stop fixed
 * fixes for screencopy on proxy window
 * refactored deprecated tsm-screen away out of tui (1/2)

## Net
 * allow h264 passthrough, sidestepping local encode
 * re-add afsrv\_net, have it support directory, source and sink access modes.
 * split a12:// into a12:// and a12s:// ARCAN_CONNPATH with the former permitting connecting to unknowns
 * add interactive accept/reject/trust for arcan-net use
 * reserve 'outbound' domain for interactively added outbound keys
 * enforce domain separation for allowed pubkeys
 * directory mode now splits out into sandboxed worker processes
 * directory mode can now specify permissions per tag-group
 * directory mode dynamic push appl from client with permission
 * directory mode notification of appl updates and sources coming / leaving
 * directory mode registration of dynamic sinks
 * directory mode sourcing dynamic sinks (sink-inbound only)
 * directory mode source-sink pairing 'reachable source' and 'tunnel' transfer modes
 * changed packaging format for appls
 * net\_open("@stdin") can now be used to access a per-directory-appl messaging group
 * local broadcast domain discovery added, both through net\_discover and arcan-net

## Terminal
 * SGR reset fix, add CNL / CPL
 * Add interp=st for suckless terminal based state machine

## Platform
 * paths: prioritise \_APPL_TEMP over \_APPL in load order
 * audio: engine audio split out into platform bit
 * audio: stub platform added
 * egl-dri: evict streams
 * egl-dri: default to atomic over legacy
 * egl-dri: retain device tracking for unmapped display
 * egl-dri: add hdr infoframe metadata to platform

## Shmif
 * add audio only- segment type
 * wire up ext venc resize for compressed video passthrough
 * extend hdr vsub with more metadata
 * dropped unused rhints and rename hdr16f (version bump)
 * CLOCKREQ extended with options for latching to specific msc/vblank events

## Decode
 * defer REGISTER until proto argument has been parsed, let text register as TUI
 * libuvc path now uses FFMPEG for h264 and mjpeg

## Package / Build
 * console: added binding for shutdown
 * builtin/mouse: bugfixes to two-sample mode

## 0.6.2.1
## Lua
 * nbio-linebuffer callback read truncation edge case fixed
 * message\_target and valid\_vid now work on WORLDID for LWA
 * event handler can now be attached to WORLDID for outer WM integration
 * more shmif events mapped to arcantarget handlers (bchunk-io, state)
 * snapshot/restore did not respect namespace api change
 * nbio- read return value to cancel out
 * nbio read-to-tbl allow read\_cap field to limit lines per call

## Terminal
 * switch lash over to xpcall for better error messages
 * forward traw record to lash mode as well
 * improve altscreen- vt100 signalling races on resize storms
 * bitop inclusion stack garbage

## Tui
 * embedding modes improved and working
 * multiple fixes to subwindow processing being tagged to parent
 * readline: reduced reallocation frequency
 * readline: only right-complete when at end of string
 * readline+lua: allow hint- annotations (\0\0) to suggestions
 * lua: state transfer bchunk transfers fixed
 * nbio: write-queue fail to requeue fix for dgram
 * lua: expose 'unix' (domain/dgram) to tui-fopen

## Wayland
 * xdg-toplevel scale factor input regression

## Platform
 * evdev: masked SH+space not setting keysym

## Build
 * add stub builtin/legacy.lua
 * increase verbosity for debug builds (include macro expansion meta)

## 0.6.2

## Net
 * Protocol: add intent to HELLO (source or sink)
 * Drop connection on intent conflict (source connect to source or sink to sink)
 * Move keystore to statepath subdir (a12)
 * Added Sweep Discovery mode
 * Initial connection for host-tags should now be faster
 * Connpath=a12://tag@ resolution fixed for one-off source-push connections
 * Congestion control blocking issue resolved
 * First drafts of 'directory' mode for hosting arcan appls
 * Arcan-net can now list and download appls from an arcan-net directory server
 * Fonts now cache when A12\_CACHE\_DIR is provided
 * Binary transfers now stream-compress with zstd

## Lua
 * net\_discover added, use this to find other a12 clients
 * define\_linktarget semantics reworked
 * open\_nonblock class functions (nbio) extended with more read/write options
 * net\_open re-enabled for use with tags from net\_discover
 * target\_displayhint extended with forwarding subsegment cookie for embedded surfaces
 * viewport events now propagate embedded surface scaling preferences
 * input events can now carry a destination segment cookie
 * list\_namespaces for enumerating namespaces, nsname:/path to all resource functions
 * glob\_resource second argument form string type for user namespaces

## Terminal
 * permit ARCAN\_STATEPATH to propagate into child env
 * the basic/recovery cli (arg=cli) now has a lua shell mode(cli=lua) with tui-lua bindings
 * add controls for stderr propagation
 * add control for tpackani recording from start

## Shmif
 * add EXTERNAL\_NETSTATE for fsrv\_net to convey known-set changes
 * add handover\_exec\_pipe mode call with better fd inheritance semantics
 * fixed bug with TPACK- window sometimes causing null-deref on resize storms
 * TPACK- window size cap bumped
 * TPACK size calculation wasn't correctly applied, with edge-case force-disconnects

## Tui
 * Readline: added history navigation inputs
 * Readline: cleaned up API for history/completion controls, reduced callbacks
 * Readline: delete last word implemented
 * Readline: draw/navigate completion set on request
 * Readline: add insertion prefix controls
 * Readline: add paste forward control
 * General: fixes to view-state and other handler propagations
 * General: handover-embed and other wnd-hints working
 * General: tpackani format added for recording
 * Input: added send\_key and send\_mouse

## Frameservers
 * Encode: (linux) add support for a v4l2-loopback sink
 * Encode: synched to ffmpeg-5.0 api
 * Net: added 'sweep' discovery mode
 * Decode: added protocol=pdf (dependency, mupdf) mode
 * Decode: added protocol=list for probing

## Engine
 * Added -C, (control) mode for replacing ANR watchdog with debug-interface
 * Monitor modes now disable default scripting error state dump
 * -O monitoring mode behaviour / output reworked
 * Negative monitoring samplerate will only write crash dumps

## Build
 * Vendored static freetype build evicted

## 0.6.1

## Engine
 * Disable watchdog during launch_external
 * Require a full scanout cycle before marking crash recover as over
 * Use attachment density if no displayhint on fsrv with tpack font-init
 * Re-add event queue drain management
 * More aggressive pipeline dirty state tracking
 * Fixed jpeg identification courtesy of Salotz

## Frameservers
 * ARCAN_FRAMESERVER_DEBUGSTALL is now performed after \_open and the pid is sent as 'ident'
 * Terminal: added autofit argument to keep\_alive
 * Terminal: save and rebuild 'dead' terminal window on resize
 * Terminal: 'pipe' mode sidesteps pty
 * Terminal: live-redefinition of colours, overlay server-side palette on terminal one
 * Terminal: exec-mode sets ident to command
 * Terminal: (cli) ident is updated with path and execution mode
 * Terminal: (cli) forward error messages on handover allocation rejection
 * Terminal: (cli) add 'debugstall' command to add time for debug- attach

## Tui
 * Lowered the constraint for wndhint to also work for main window
 * Tpack is now the only output, local rasterization is dead - long live server side text
 * Recolor/runtime palette remapping through target\_graphmode
 * Extended colour slots to cover a 16- legacy group
 * Allow indexed cell attribute flag (fg.r, bg.r becomes colour slot index + lookup)
 * add FAILURE message notification type
 * Add handlers for seeking contents and content\_size call to indicate scrolling support

## Lua
 * Whitelist os.date
 * Add 'forget' analogfilter option to discard/release device
 * Extend map\_video\_display to allow layer-index and offsets
 * Extend video\_displaymodes with controls for depth (low, deep, hdr) and vrr- target rate
 * target\_fonthint and target\_displayhint return the last known cell w/h that tpack might use
 * Allow suspend\_target, resume\_target for controlling preroll state transition
 * bond\_target sent the wrong pipe pair ends
 * Set default font density to match platform ppcm on init
 * update HPPCM/VPPCM on rendertarget\_reconfigure on WORLDID
 * Strictened definition of launch\_target
 * Add target\_geohint for dynamic language/position updates
 * added input\_remap\_translation for runtime input platform tuning
 * relink\_target now properly accounts for different anchor points
 * reduce unnecessary pushstrings where pushlstring/pushliteral would suffice
 * image\_parent - add overloaded form for testing full hierarchy
 * add input\_raw entry point for out-of-loop io event processing (footgun warning)
 * add mapping hint for ROTATE\_180
 * add placeholder user-namespace selector for glob-resource

## Build
 * A whole lot of FreeBSD build fixes courtesy of J.Beich
 * Wrong ALIGNED\_SIMD args set courtesy of moon-chilled
 * sdl2 first-build fix courtesy of Lahvuun

## Distribution
 * New hookscript: 'hook/alloc\_debug.lua' that forces backtrace into image-tag for all allocations
 * builtin/string.lua: add string.unpack\_shmif\_argstr
 * builtin/mouse.lua: simplified convenience patterns added to mouse\_setup/mouse\_input

## Shmif
 * Shmifext- allocator interface for server- directed FBO color allocation
 * Add graphmode palette definition to preroll stage
 * Preroll EAGAIN kernel race causing premature shutdown fixed
 * Ensure control socket or page never gets allocated on 0,1,2
 * Two edge condition races on crash- triggered migration during resize
 * shmif-server: spawn\_client support function added/working

## Platform
 * Egl-dri: don't forward modifiers for linear/invalid
 * Lwa: use shmifext allocator interface for mapped rendertargets
 * Lwa: set last-words on script-error / arcan\_fatal
 * Lwa: forward density to font renderer
 * Lwa: fix buffer-export fail handling
 * Agp/Video: add support for hardware composition layers
 * Agp/Video: Allow mapped vstores to support dirty regions
 * Agp/Video: fixes to float/half-float FBO allocation
 * Egl-dri: direct-scanout of 'sane- video objects' (e.g. FBO without post-processing)
 * Egl-dri: let preferred display buffer resolution drive map_video_display
 * Egl-dri: single-buffered drawing mode for fullscreen mapped tui/terminal clients
 * Egl-dri: set platform buffer decay flush on transition eglSurface <-> FBO
 * Egl-dri: add buffer quality mode transitions (LDR-SDR-Deep-HDR)
 * Sdl2: mouse wheel/button input fixes
 * Sdl2: automatic window resizes HIDPI resize-loop fixes
 * Evdev: runtime switching xkb keylayout (libxkbcommon builds)

## Wayland
 * arcan-wayland did not pack drm/dma-buf right, causing import failures
 * egl-shm mode working (bridge converts to dma-buf before fwd)
 * enable dma-buf by default
 * drop zxdg-shell-unstable-v6
 * older client termination on mouse-wheel version check fixed
 * xdg-decor set with the wrong surface state
 * link in pulse/native in -exec tmpdir pulse/native
 * handle no XDG\_RUNTIME\_DIR case for normal and -exec

## Tools
 * added tool arcan-dbgcapture for use as a /proc/core\_pattern to help core dump management

## Networking
 * enable redirect_exit connection point immediately on client connection
 * Swap out DEFLATE for ZSTD
 * added experimental keystore
 * add 'forward' connection modes (arcan-net -l port -exec shmif-bin) (arcan-net host)
 * add basic congestion control on video backpuffer pressure
 * respect origo-ll flags (y-axis inversion for some clients)
 * refactoring / cleanup to logging and control structures, preparing for video passthrough

## 0.6.0
## Engine
 * Position fix to anchor_image/center_image when using CR anchor
 * Automatically switch/re-exec to _sdl / _lwa depending on env (in X, WL, ...)
 * Consolidated synchronization strategies from platform into 'conductor'
 * Conductor gets strategies for latency/powersave (immediate, processing, powersave, adaptive, tight)
 * Multiple hookscripts can now be chained together regardless of appl
 * New hookscript: external_input, allow external input drivers
 * New hookscript: shutdown, add automatic timer driven shutdown
 * New hookscript: timed/periodic dumps, snapshot the engine scene graph for easier debugging
 * OpenCTM support/parsing removed from 3d core
 * Rendertarget proxies, let platform layers intercept FBO drawing
 * render_text no longer preserves style across invocation
 * vrbridge: fallback to bin/arcan_vr if ext_vr database entry could not be found
 * db-tool: incorrect constraints fixed on sql-ddl
 * server-side rendering for Tpack backed windows

## Networking
 * a12 protocol implementation added, proxy-tool and connection manager arcan-net added
 * afsrv_net dropped in favor of arcan-net (lua:net_listen will still route through it)

## Shmif
 * segment request extended with split-dir and position-dir hints
 * input events extended with eyetracker inputs
 * keyinput/cursor input dropped (only used by encode-vnc)
 * cleaned up some of the error/status logging
 * HANDOVER allocation / exec should now work properly, so one connection can be used to negotiate another
 * fixes to live-lock race condition in some crash recovery scenarios.
 * a12:// handling for CONNPATH added
 * support for default implementation handlers for certain segment types (DEBUG)
 * crash recovery speeds more aggressive on linux with inotify support on connpoint
 * default debug-interface added, safe gdb/lldb attach bootstrap
 * handover token provided for handover- embedding with child-parent or parent-child control
 * arcan_shmif_bgcopy helper function aded for threaded bchunk etc. response
 * contents hints now cover both min/max constraints as well as h/v scrolling metadata
 * when TPACK buffer format is used, size calculation is based on packed size
 * _VOBJ apad storage type support for providing 2D/3D vector data
 * default event-queue sizes bumped to 127/127)
 * dequeue overwrites event store on use (0xff)
 * SEGREQ now takes desired dimensions hit to avoid possible resize roundtrip
 * default maximum segment size bumped

## Tui
 * COPY_WINDOW feature extended with annotation tools, editing and highlighting
 * Color selection extended with attribute for UI element (status-menu bar)
 * Multiple fixes to customised exposed bindings
 * Bufferwnd component added, acts as a quick-embed text/hex-editor
 * Listwnd component added, act as a basic menu/popup/option list
 * Removed the 'screens-' abstraction, turned out to not be useful enough
 * getxy(), scrolling, keyinput propagation bugs fixed
 * Bindings moved to separate repository, github.com/letoram/tui-bindings
 * Renders to 'RPACK' format for offloading text rendering to server side if TUI_RPACK env. is set.
 * ALTERNATE screen mode now default, pending removal of line mode (re-add as linewnd widget)
 * mouse behaviour preference moved to context flag
 * (BREAKING) moved bitfield to bitmask in order to make bindings less of a pain
 * add a bchunk-handler for stdin/stdout to allow runtime redirection

## Frameservers
 * Terminal: Loosened default restriction on exec control after spawn
 * Terminal: Add first draft 'Vt100'-free CLI
 * Decode: Video shutdown on some libvlc builds fixed
 * Decode: Refactored to support more format cores
 * Decode: Added text-to-speach
 * Decode: UVC capture supports more formats
 * Decode: Added type-probe and 3D model hooks
 * Encode: Added support for A12 output, VNC input translation fixes
 * Remoting: Added support for connecting to A12 servers

## Built-in Helpers
 * Added builtin/decorator.lua for quick- surface decoration controls
 * Added builtin/wayland.lua for meta-wayland/xwayland compositor helper
 * Added builtin/osdkbd.lua for an on-screen keyboard factory

## Packaging / Build
 * egl-dri / sdl platform builds can now coexist on the same machine
 * egl-dri BUILD_PRESET=everything added, builds arcan, arcan_sdl, arcan_headless
 * egl-dri HYBRID_SDL, HYBRID_HEADLESS options added
 * egl-dri nvidia/EGLstreams initialisation/scanout changes for > 385
 * cmake build system simplified (thanks L. Bobrov)
 * sdl2 - add basic window drag resize support
 * the simple 'console' window manager is now included in the default install
 * hook scripts are moved from builtin/scripts/hook to builtin/hooks
 * basic work- docker images in github.com/letoram/arcan-docker
 * arcan-net and libarcan-a12 built by default
 * small -DCLIENT_LIBRARY_BUILD added, which provides only shmif+tui+a12/net code
 * osx/big sur fixes (requires homebrew)

## Lua
 * Added focus_target to specify a frameserver that gets latency/synch priority
   when deciding what to synch to which display
 * target flag option for blocking adopt / handover
 * loadstring() is now permitted on debuglevels > 0
 * appl_arguments() function added, lets script re-retrieve initial argv
 * added rendertarget_bind function to reassign rendertarget to output segment
 * stepframe_target can now provide dirty region information
 * deprecated load_movie removed (use launch_decode)
 * define_arcantarget expanded to cover more shmif- features
 * instant_image_transform/reset_image_transform now takes an optional slot mask
 * coroutines added to whitelist
 * target_seek now also allows seeking in z axis
 * benchmark functions now allow appending to the trace buffer
 * play_audio/load_asample now take tables for buffer creation as well
 * rendertarget_metrics added to get stats about ongoing transforms
 * image_shader is allowed on rendertarget for bindtargets
 * bond_target and open_nonblock now allows extended type hints
 * image_clip functions now allow an out-of-hierarchy clipping target
 * (lwa) add arcantarget_hint for sending labelhints
 * allow link_image to match scale with parent (for W/H)
 * add relink_image for retaining world-space coordinates at link time
 * image_resize_storage on rendertargets can now change scissor/viewport

## Platform/Egl-Dri
 * Change CRTC allocation / management
 * Better dirty region tracking
 * Direct Scanout heuristics reworked
 * Defer KD_GRAPHICS until first frame
 * Add FP16, 1010102 output modes
 * Add hooks for fencing
 * Mode selection heuristics that biases on higher refresh
 * Buffer import consolated into one set of helper functions in shmifext
 * (+agp) Buffer import layering reworked to account for modifiers/multiplane/mailbox
 * Work towards adaptive FBO- indirection or FBO-color0 from scanout memory

## Platform
 * sdl2: various mouse / input fixes
 * sdl2: fixed GL crashes when on linux/mesa drivers
 * sdl2: basic drag resize implementation
 * lwa/agp: better response during resizes
 * agp: wire up context robustness to crash recovery
 * agp: multiple fixes to blend-mode setup
 * headless platform: provide encode-frameserver virtual display "output"
 * openbsd: add rendernode support

## Wayland
 * arcan-wayland now has basic support for Xwayland, with per X client isolation
 * tracing groups can now be set through text-name (e.g. -trace xwl,alloc,seat)
 * wiring for zwp_dma_buf and zwp_confined_pointer

## Vrbridge
 * added in-source build of OpenHMD

## Misc. Tools
 * new tool, arcan-trayicon - generic wrapper for registering clients as tray icons
 * new tool, adbginject - for force- opening a DEBUG segment inside a process
 * external input driver for eye trackers (github.com/letoram/arcan-devices)
 * external input driver for stream decks (github.com/letoram/arcan-devices)

## 0.5.5
## Engine
* added support for sliced vstores (cubemap, 3d texture)
* rendertarget_ids are now exposed as a uniform (for stereo rendering)
* ugly 1-tick animation timer discard bug fixed
* fixed video layer display- duplication bug on crash recovery
* synchronization layer refactor for future multi-GPU/on-demand and multithreaded
  client processing
* added system scripts namespace for better sharing between projects
* expose target_flag controls for deferred / script-locked resize control

## Lua
* Switched the default careful usermask to match usermask
* updated function, build_3dbox - added face split option
* depth function controls added
* new function, image_storage_slice - for converting and synching a sliced store
* new function + builtin uniform, rendertarget_id => rtgt_id - for distinguishing
  between target rendertarget at the shader stage
* new functions for 3d mesh and navigation: build_sphere, build_cylinder, step3d_model
* updated 3d motion functions to accept interpolation function arguments
* exit_silent argument added to shutdown so clients switch to recover state
* displayhint constants fixed for maximized and fullscreen states
* mesh_shader now behaves like image_shader (string and numerical ids accepted)
* histogram_impose can now work with row offsets
* update_handler on frameserver in terminal state will be _fatal rejected
* load_fail forward fix to asynchronous image loading
* build_plane now also permits a vertically oriented mesh
* image_tesselation function now expose depth buffer controls
* resample_image extended to allow source vstore snapshotting
* fix to crash recovery being misinterpreted for -b :self
* open_nonblock now also supports domain sockets
* new function, rendertarget_range for masking out rendering of objects based on order
* add EXIT_SILENT option to shutdown() to allow clients to live on after display server shutdown
* resettransform now returns remaining time for each transform slot
* improved (debug build only) trace output on script errors in callback
* added entry point _fatal(msg)->str triggered on scripting error for better custom error reporting

## Packaging
* voidlinux - packages upstreamed for (arcan, durden, arcan-wayland, xarcan, aclip, aloadimage)

## Platform
* restructure to allow more complicated accelerated handle passing
* egl-dri: tty- switch regression fix
* egl-dri: context management reworked in preparation of threaded/mixed 10-bit/8-bit outputs
* linux/openbsd: much improved privilege separation support

## Shmif
* devicehint- now carries metadata about accepted buffer formats
* default handlers (when client provides no implementation) for pushed segments are now supported
* ground work for hidden fallback implementation of force-pushed subsegments
* last_word mechanism added to communicate a user-readable string for abnormal termination
* ground work for 'per-scanline' like dirty transfers
* add helper function, arcan_shmif_handover_exec for delegating subwindows to child processes

## Terminal
* reworked timing code (again)
* force-push debug segment now provides a default state debug output window

## Decode
* Add support for starting position hint
* Noaudio argument added
* Add default bindings for seek controls
* Add optional (default off) libuvc based webcam access

## Waybridge
* Added support for xdg_wm_base protocol
* eglSwapBuffer() client livelock race fixed
* mouse wheel scrolling fixes
* added controls for specifying temp folder prefix in -exec mode

## VRbridge
* Add support for resetting default "forward" orientation

## Tui
* subwindow semantics simplified
* add support for dynamic loading
* controls for setting semantic label to color mapping
* fix to writestr / erase_region dirty- tracking

## Tools
* added acfgfs tool to mount durden- like menus as a FUSE filesystem

## Build
* multiple rpath / osx build fixes
* add controls for manual disable fsrv archetypes
* dropped a number of < 3.0 cmake behaviors and bumped required version
* egl-dri platform now defaults to adding arcan binary suid
*

## 0.5.4
### Engine
* VR support now covers the full path from bridge communicating metadata and limb
  discovery/loss/map/updates.
* (71939f) -0,-1 pipes and filters input setup added, covered in
  [AWK for Multimedia](https://arcan-fe.com/2017/10/05/awk-for-realtime-multimedia/).
* format-string render functions extended with vid-subimage blit
* generate GUIDs for launched frameservers

### Lua
* New function: define_linktarget used to create an offscreen render pipeline that
  is tied to the pipeline of another rendertarget.
* New function: subsystem_reset used to rebuild subsystems (video only for now) to
  allow live driver upgrades, active GPU switching and so on - without losing state
* Updated function: camtag_model, change to allow forcing destination rendertarget
* Updated function: image_tesselation, expose index access
* Updated function: render_text, added evid,w,h and Evid,w,h,x1,y1,x2,y2
* Updated function: launch_avfeed, added guid as return
* Forward current cached GUID on device hint

### SHMIF
* Persist GUID across migration
* Allow incoming devicehint events to update 'last known guid'
* Removed reconnect backoff delay

### Terminal/Tui
* Support for ligatures improved
* Highlighting/Inverse/Full-Block cursor changed for better visibility
* Added controls to "screenshot" the current window into a new (input label: COPY_WINDOW)
* Copy Windows can be set to be the primary clipboard receiver (input label: SELECT_TOGGLE)

### Platform
* Add preinit stage to event and video subsystems for acquiring / dropping privileges
* Added chacha20 csprng and cipher
* OpenBSD: added mouse support
* Egl-Dri: swap-GPU slot added to db- based configuration
* SDL2: improved keyboard and mouse support

### Tools/VRbridge
* Initial support for OpenHMD

### Tools/Xarcan
* Ported to OpenBSD

### Tools/Waybridge
* Fixes to subsurface allocations
* -egl-shm argument added, perform shm->dma_buf conversion in bridge to offload server
* single exec mode (arcan-wayland -exec /my/bin) for stronger separation between clients
* add support for rebuilding client (crash recovery and migration) described in (crash-resilient wayland compositing)[https://arcan-fe.com/2017/12/24/crash-resilient-wayland-compositing/]
* basic seccomp syscall filtering

### Tools/Netproxy
* First draft version, will be the main focus of the 0.6- series of releases.

## 0.5.3
### Engine
* Refactored frameserver- spawning parts to cut down on duplicated code paths and make
  setup/control more streamlined.
* Added support for tessellated 2D object, with more fine-grained control over individual
  vertices.
* Extended agp_mesh_store to cover what will be needed for full glTF2.
* Crash-recovery procedure for external clients now also applies to scripting layer
  errors when there is no fallback appl set.
* Reworked font/format string code to bleed less state and automatically re-raster if the
  outer object is attached to a rendertarget with a different output density.
* Added additional anchoring points to linked images
  (center-left, center-top, center-right, center-bottom)
* VR- mapping work for binding external sensor "limbs" to 3d models.

### Lua
* New function: image_tesselation, used to change subdivisions in s and t directions,
  and to access and change individual mesh attributes.
* New function: rendertarget_reconfigure, used to change the target density of a
  rendertarget.
* New functions: vr_map_limb, vr_metadata
* Updated function: define_rendertarget. It now returns status, accepts more mode flags
  (MSAA) and allows target density specification.
* Updated function: alloc_surface. It now allows additional backend storage formats,
  (FP16, FP32, alpha-less, RGB565, ...)
* Updated function: link_image, added additional anchoring points

### SHMIF
* New library, arcan-shmif-server. This is used for proxying / multiplexing additional
  connection unto an established one. Primary targets for this lib is a networking proxy
  and for TUI/Terminal to support delegating decode/rendering to other processes.
* Added support for HANDOVER subsegments, these are subsegments that mutate into primary
  segments in order to reuse a connection to negotiate new clients without exposing a
  listening channel.

### TUI/Terminal
* Dissemination article: https://arcan-fe.com/2017/07/12/the-dawn-of-a-new-command-line-interface/
* support for bitmapped fonts (PSFv2) as an optional path for faster rendering on weak hardware.
* Built-in bitmapped terminus for three densities/sizes (small, normal, large) as fallback.
* Added dynamic color-scheme updates.
* Rendering-layer reworked to support shaping, custom blits, ...
* Experimental double buffered mode (ARCAN_ARG=dblbuf)
* Experimental smooth scrolling in normal mode (ARCAN_ARG=scroll=4)
* Experimental shaping mode kerning for non-monospace fonts (ARCAN_ARG=shape)
* Experimental ligature/substitution mode for BiDi/i8n/"code fonts" via Harfbuzz (ARCAN_ARG=substitute)
* Lua bindings and tool for testing them out (src/tools/ltui)

### Platform
* Refactored use of environment variables to a configuration API
* EGL-DRI: VT switching should be noticeably more robust, EGL libraries can now be dynamically
  loaded/reloaded to account for upgrades or per-GPU sets of libraries.
* AGP: Updated GLES2 backend to work better with BCM drivers.
* Evdev: Added optional support for using xkblayouts to populate the utf8 field.
* EGL-GLES: quick fixes to bring BCM blobs back to life on rPI.
* OpenBSD: initial port bring-up, keyboard input and graphics working.
* SDL2: added SDL2 based video/event platform implementation, some input issues left to sort
  out before 1.2 support can be deprecated and this be the default on OSX.

### Tools
* Aloadimage: basic support for SVG images
* Doc: started refactoring lua API documentation format to double as IDL for re-use of lua API
  as privileged drawing and WM- protocol.

### Tools/Waybridge
* XKB- Layout transfer support, basic pointer and pointer surface (wl_seat)
* Damage Regions, dma-buf forwarding (wl_surf)
* More stubs (data_device/data_device manager/data_offer/data source)
* zxdg-shell mostly working (toplevel, positioners, popup)
* added support for relative_pointer motion

## 0.5.2
### Engine
* LED subsystem reworked: Support hotplug, synthesized LED devices, added support for a
  FIFO protocol for communicating with external LED controllers
* Accelerated Graphics: refactored to be dynamically (re-)loadable, getting closer to
  multi-vendor-multi-GPU support and GPU hotplugging.
* Driver backend update: external-launch reloads accelerated graphics library, getting
  closer to runtime driver upgrades
* Initial HMD/VR support: Early stages, spawn a subprocess for device control and input
  fusion/sampling with mapping to a virtual skeleton
* Allow direct-to-drain enqueue for out-of-band high-priority events

### Tools (src/tools) / Backends (separate repositories)
* waybridge: (new) (alpha state, see wiki wayland notes) wayland protocol service
* xarcan: (new) xserver with shmif driver backend
* qemu: input state- fixes, closer to working multi-display and virgil support
* SDL: improved synchronization, mouse and multi-window support
* vrbridge: (new) basic integration skeleton and partial PSVR support (unusable)
* aclip: (new) clipboard manager for translation between appl- and command-line
* aloadimage: (new) image viewer with parser sandboxing
* shmmon: (new) debugging tool for inspection of shmif- connection dumps or single client
          state from scraping proc
* openal: patched backend can now be built standalone, back to working state for LWA

### Shmif
* New segid subtypes: WIDGET, BRIDGE\_X11, BRIDGE\_WL, SERVICE
* Two new sub-libraries: shmif\_ext (extended accelerated rendering setup convenience) and
  shmif\_tui (text user interface)
* _open_ext added exposing additional initial-registration fields
* Extended connection protocol to include a preroll stage which act as a collection
  phase for fonts, outputs, language, etc. in order to cut down on initial setup complexity
  and reduce connect-to-draw latency.
* added \_initial structure that conveys information gathered during the preroll stage
* add VSIGNAL RHINT to support event- based notification on frame delivery for some I/O
  multiplexation edge cases
* Engine-side reservable misc- buffer added to shmpage layout for specialized I/O devices
  that would saturate the event queues when dealing with latency-sensitive high-samplerate
  input devices
* Negotiable extended mapping for synchronizing gamma/color information
* Negotiable (placeholder/incomplete) extended mapping for supporting HDR source contents
* Negotiable (placeholder/incomplete) extended mapping for vector content transfer

### Platform
* egl-dri: backlight support exposed as a LED controller, VT switch stability fixes,
  EGLStreams support moved from the egl-nvidia platform, removed egl-nvidia, add switchable
  synchronization strategies for fast, adaptive or conservative.
* evdev: devices with LEDs now get mapped to a corresponding LED controller.
* agp: exposed more color packing formats.

### Terminal
* Tuning to resize/- refresh cpu v latency tradeoffs
* Refactored codebase and split out drawing/shmif- integration etc. into using shmif\_tui.
* Minor bugfixes related to color parsing, added blink speed control

### Lua
* Deprecated: LED\_CONTROLLERS constant
* target- event propagation extended:
* Added functions: hmd\_setup, define\_arcantarget (LWA only, experimental)
* Updated functions: controller\_leds, set\_led, set\_led\_intensity, set\_led\_rgb,
                     open\_nonblock, audio\_gain, video\_displaygamma, decode\_modifiers,
                     target\_flags, add\_3dmesh
* Added constants: TARGET\_ALLOW(CM,LODEF,HDR,VECTOR,INPUT)
* Added aliases: image\_surface, image\_surface\_storage,
                 image\_surface\_resolve (dropped properties suffix)
* Updated events: display\_state (additional fields for backlight)
                  input (status: extended label fields, device reference, device domain)
                  target (expose "bchunkstate", "preroll")

### LWA
 * partial/incomplete: requesting/rendering to subsegments
   (icon, titlebar, popup, ...) via define\_arcantarget
 * improvements to runtime DPI switching and automated resize-response
 * runtime server controlled 'default font' and 'default font size' switching

## 0.5.1
### Lua
		* New functions: target_devicehint (control accelerated device use and connection points),
		                 video_displaygamma (access low-level display gamma ramps),
		                 rendertarget_vids (enumerate rendertarget- attachments)
		* Update functions: target_displayhint(synch controls), set_context_attachment(can now query),
		                    rendertarget_forceupdate(change rate after creation), target_seek(can now
		                    specify seek domain), system_collapse (can now disable frameserver-vid
                                    adoption)
### Shmif
		* Added shmif_ext support library for reusing the boiler plate in setting up
                  egl surfaces, creating contexts and performing handle passing.
		* Audio buffer negotiation is now allowed to  now switch samplerate
		* Structure for specifying viewport-border region extended to handle varying t/l/d/r
		* Support for live migration between connection points
		* Extended the number of RESET states to account for server crash recovery

### Engine
		* image loading and guard thread stack size and safety edge condition fixes
		* allow shmif- connections to negotiate deviating audio samplerate

### Frameservers
		* Added optional tesseract-ocr support to encode frameserver.
		* Removed resamplers from game
		* Terminal: mouse protocol support, better resize filtering, better scrolling step size
		controls, fixed font descriptor leak, OSC set title and bracket paste support

### Platform
		* Support for egl-dri on BSDs
		* Input platform for FreeBSD/console
		* Display mapping semantics improved for SDL/egl-dri
		* Improved synch- control for multiple displays
		* linux/event, renamed to evdev, better (but still not good) VT switching support
		* evdev, MT event formatting fixes
		* evdev, better recovery in the event of SIGTERM

### Hijack
		* sdl12 hijack library reworked to use dummy- drivers for A/V
		* xlib hijack library for partially broken SDL12/SDL2 games that rely on dangling
		  X/GLX symbols

## 0.5.0
### Lua
		* New functions: net_discover, video_synchronization, resize_video_canvas,
		video_displaydscr, video_displaymodes, map_video_display, system_identstr,
		system_collapse, switch_appl, build_pointcloud, image_state,
		cursor_setstorage, cursor_position, move_cursor, nudge_cursor,
		resize_cursor, image_mipmap, alloc_surface, tag_image_transform,
		resample_image, target_reject, target_updatehandler, pacify_target,
		bond_target, rendertarget_detach, rendertarget_forceupdate,
		rendertarget_noclear, target_flags, target_parent, target_displayhint,
		target_fonthint, target_alloc, open_nonblock, accept_target,
		define_feedtarget, define_nulltarget, util:hash, util:to_base64,
		util:from_base64, get_keys, match_keys, list_target_tags,
		target_configurations, audio_buffer_size, crop_image, center_image,
		image_access_storage, image_resize_storage, image_matchstorage,
		build_pointcloud, system_defaultfont, frameserver_debugstall,
		input_capabilities, input_samplebase, set_context_attachment,
		video_display_state, shader_ugroup

		* Removed deprecated: launch_target_capabilities, game_cmdline,
		switch_theme, list_games, game_info, game_family, game_genres pause_audio,
		instance_image, camtaghmd_model, default_movie_queueopts,
		default_movie_queueopts_override, net_refresh

		* New constants: GL_VERSION, SHADER_LANGUAGE, FRAMESERVER_MODES, APPLID,
		API_ENGINE_BUILD KEY_CONFIG, KEY_TARGET, HINT_FIT, HINT_CROP, HINT_YFLIP,
		HINT_ROTATE_CW_90, HINT_ROTATE_CCW_90, SHARED_RESOURCE, SYS_APPL_RESOURCE,
		ALL_RESOURCES, INTERP_LINEAR, INTERP_SINE, INTERP_EXPIN, INTERP_EXPOUT,
		INTERP_EXPINOUT, ANCHOR_UL, ANCHOR_UR, ANCHOR_LL, ANCHOR_LR, ANCHOR_C,
		VRES_AUTORES, EXIT_SUCCESS, EXIT_FAILURE, MAX_TARGETW, MAX_TARGETH,
		TYPE_FRAMESERVER, TYPE_3DOBJECT, TARGET_SYNCHRONOUS, TARGET_NOALPHA,
		TARGET_VSTORE_SYNCH, TARGET_VERBOSE, TARGET_AUTOCLOCK,
		TARGET_NOBUFFERPASS, DISPLAY_STANDBY, DISPLAY_OFF, DISPLAY_SUSPEND,
		DISPLAY_ON, RENDERTARGET_NOSCALE, RENDERTARGET_SCALE, READBACK_MANUAL,
		HISTOGRAM_SPLIT, HISTOGRAM_MERGE, HISTOGRAM_NOALPHA, TD_HINT_CONTINUED,
		TD_HINT_INVISIBLE, TD_HINT_UNFOCUSED, TD_HINT_IGNORE, FONT_PT_SZ,
		CRASH_SOURCE

    * Calctarget callback table get, histogram_impose and frequency
    * Frameserver_terminated events renamed to terminated
    * Support for coverage tracking trace build
    * Added color support to output messages
    * Added interpolation function specifier to move/rotate/blend/resize
		* Transformation chains can have callback tags associated with completion,
			this also works as a timer implementation.
		* Added support for native/accelerated cursor rendering
    * System_collapse for switching running appl or dropping all resource
    * Allocations that are not strictly connected to frameservers
    * _display_state callback
    * Input class for frameserver/remoting originated input (cursor_input, key_input)
    * Net discovery events propagated
    * Automated frameserver- looping dropped,
      in favour of manual management on terminated events
    * Monitor state format properly escape Lua strings
		* Text rendering functions provide additional metrics and has a tabled
			version where %2 indices ignore format string characters
    * Link_image can now specify anchor point

### Engine
    * Database module rewritten, target/configuration/appl key-value store
    * Namespace rewritten, RESOURCE/APPL split into multiple fine-grained namespaces
    * Interpolation state exposed as shader built-in
    * Output dimensions exposed as shader built-in
    * Better transformation caching and dirty invalidation
    * Bugfixes to 2D/3D picking
    * Support for post- Lua init hook scripts (primarily intended for testing and
      automation purposes).
    * First refactoring of memory allocation resources using different
      interface that tracks alignment, metatype etc.
    * Support for adoption / fallback application in the event of an
      error in the Lua state machine
    * Dropped support for framequeues
		* Font rendering support for default- system font and specifying format
		  related to system font
		* Fallback font chains to switch other fonts when glyphs are missing
		* Cheap, "shallow" clipping added to reduce stencil- buffer use
		* More fine grained control over frameserver data routing
		* Support for shader instancing through uniform groups
		* Framesets now act as null_surface + sharestorage calls

### Platform
    * EGL-GLES split into regular EGL-GLES primarily for
      ARM devices, and the Linux/KMS specific EGL-DRI with the distant
			relative EGL-NVIDIA.
    * Interface expanded to support multi-monitor, dynamic synchronization switching
    * X11 and Linux (evdev) platform support expanded with better input management
    * Support for DRI render-nodes, accelerated buffering passing
    * OpenGL used stripped from video/3d/frameserver
      into AGP (arcan graphics platform) to support lower level graphics APIs
      and software rendering.

### General
    * Much improved documentation, automated testing, build tracking and tagging.
    * Re-organized large parts of the source tree
    * Switched majority of component licensing from GPL to BSD
		* AWB / Gridle moved out to own .gits, defunct/unsupported
		* Added support for LWA, lightweight arcan. A special build that uses
			another arcan instance as display server.
		* Much improved support for HDPI and mixed-DPI displays

### Shmif
    * Support for non-authoritative connections via CONNPATH and CONNKEY
    * Support for multiple- segments,
    * More aggressive cookie/dynamic integrity check
    * Cleanup / simplify connection and setup API
    * Shmif resize heuristics switched to reduce stalls / latency
		* Support for multiple video buffers / segment
		* Support for multiple audio buffers / segment
		* Support for Communicating buffer dimensions
		* More fine-grained control over I/O multiplexation, guard threads,
		  synchronization, blocking vs tearing
		* Type-model changes, SEGID can register as: LWA, NETWORK_SERVER,
			NETWORK_CLIENT, MEDIA, TERMINAL, REMOTING, ENCODER, SENSOR, GAME,
			APPLICATION, BROWSER, VM, HMD_SBS, HMD_L, HMD_R, POPUP, ICON, TITLEBAR,
			CURSOR, ACCESSIBILITY, CLIPBOARD, CLIPBOARD_PASTE
		* target_command- changes: -FDTRANSFER, +BCHUNK_IN, +BCHUNK_OUT,
			+SEEKCONTENT, +DISPLAYHINT, +STREAMSET, +MESSAGE, +FONTHINT, +GEOHINT
		* external_command- changes: +FAILURE, +BUFFERSTREAM, +STATESIZE, +FLUSHAUD,
			+SEGREQ, +KEYINPUT, +CURSORINPUT, +CURSORHINT, +VIEWPORT, +CONTENT,
			+LABELHINT, +REGISTER, +ALERT, +CLOCKREQ

### Frameservers
    * Added terminal frameserver
    * ARCAN_FRAMESERVER_DEBUGSTALL switched to allow infinite or specific- sleep
    * VNC server support added to encode
    * Remoting frameserver added (primitive at the moment, support vnc client)
    * Decode_ default switched from av/ffmpeg to libvlc
    * Libretro graphing moved to a possible debug secondary segment

## 0.4.0
### General
- Monitoring mode now uses the same namespace as themes, can now load .lua crashdumps
- The core-engine builds and runs on arm/egl devices (e.g. raspberry PI), no working input layer or resolution switching controls yet. _math performance is horrible before we get working ARMv6 + NEON optimized options.
- Frameserver API cleaned up, reworked build-system and source organisation.
- Optional avfeed- frameserver added, this is just a skeleton to ease writing custom data sources ( corresponding lua calls are launch_avfeed) and needs to be enabled build-time.
- Frameservers can now (except on windows) be built in a split- mode, where each subtype (movie, encode, libretro etc.) gets its own binary.
- Alignment issues when running SIMD optimized math adjusted
- OSX support partially re-added, no packaging / UI work as of yet.
- Monitoring mode changed slightly, instead of forking, we now set envvar and re-exec ourselves to accommodate for systems with broken broken fork() support (seriously OSX...)

### LUA
- initial API documentation coverage now at 100%, language and descriptive qualities for individual pages still have a lot to go, this will be improved gradually.
- system_load now accepts an optional trigger to disable _fatal calls when asked to load a broken script
- target_coreopt added to force key,val options to target frameserver
- target_verbose hints frameservers and their internal processing to expose more detailed data (e.g. pts/framecount/frameskipping for decode and encode)
- define_calctarget added, similar in style to a recordtarget (without any audio) that exposes buffer data as a callback to a provided lua function
- target_synchronous disables PTS enforcement and blocks on sync with frameserver and with GPU (only for very specific uses)
- exposing lua api to the VM is delayed until just before the themename() entry-point
- all C<->LUA functions are now mapped to a LUA_TRACE(luasymbolname) macro (where ctx refers to the lua_State pointer) for engine dev. to ease customized tracing, by default, the macro is just empty.
- system_snapshot function added (similar to a crashdump but can be invoked by script dev.)
- image_children now returns correct VIDs
- more functions aggressively shut down if a broken VID is provided

### Frameservers/Libretro
- Support for Core Options
- Support for 3D Cores (may cause some problems with certain window managers
    as we need to spawn full windows to get access to an off-screen FBO)
- Improved support for analog devices and filtering
- Rollback based input latency masking support added (experimental)

### Database tool
- Improved builddb times and fixes for libretro core scanning
- Now adds support for .descr files in games/target folder to disable and override scanning
