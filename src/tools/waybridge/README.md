Introduction
====
This tool bridges wayland connections with an arcan connection point. It is
currently in a late alpha- state and should be useful, but expecting quirks and
side-effects to exist.

Building/Use
====
The build needs access to the arcan-shmif and arcan-shmifext libraries,
either detected through the normal pkgconfig or by explicitly pointing
cmake to the -DARCAN\_SOURCE\_DIR=/absolute/path/to/arcan/src

The appl- that arcan is running also needs to expose an approriate connection
point (some, like durden and prio expose this as an ARCAN\_CONNPATH env in
instances of the terminal emulator) and you need to set the appropriate
XDG\_RUNTIME\_DIR for both Waybridge and for any Wayland clients you wish to
connect to the point.

         mkdir build
         cd build
         cmake ../
         make
         XDG_RUNTIME_DIR=/tmp arcan-wayland

The build-scripts will download additional protocol specifications from the
wayland-protocols repository the first time the build is setup. If there's
no internet connection at that time, build will fail.

Hacking
====
The code has a somewhat odd structure:

    waybridge.c - setup and allocation/routing
    boilerplate.c - structures and tables
    shmifevmap.c - translate from arcan -> bridge/client/surfaces
    wlimpl/* - subprotocol function implementations

Some subprotocol implementations (those that call request\_surface)
also attach separate event handlers that override the mapping done in
shmifevmap.c. See also the part in the CMakeLists.txt that takes unstable
protocols and generate implementation files.

The main paths to follow to get some kind of comprehension of what is going
on is how surfaces are allocated and how the surface allocation request are
propagated.

To debug, add the -trace level argument and a call trace to stderr will be
added that cover (based on level argument bitmask, so add the values):

    1   - allocations only
    2   - digital input events
    4   - analog input events
    8   - shell (wl\_shell, xdg\_shell, ...) events
    16  - region events
    32  - data-device events
    64  - seat events
    128 - surface events
		256 - drm (accelerated buffers)
		512 - alerts

Allocation outputs are encoded as follows:

    'C' - client-bridge connection
    'S' - shell surface
    's' - shell subsurface
    'm' - pointer surface
    't' - xdg- toplevel surface
    'p' - xdg- popup surface
    'x' - dead
    'o' - unused

Then the correlated arcan events can be traced with ARCAN\_SHMIF\_DEBUG=1

All individual protocols can be disabled by the -no-(protocol alias) switch
in order to control client behavior as this may vary wildly from client
to client depending on the set of requested vs. available protocols.

Notes and Issues
====
1. Stride - the shm- buffer blit doesn't take stride differences into
   account. This fails on MPV in SHM depending on source video size.

2. Initial Control connection - this one should be deprecated and removed
   in favor of getting it from the client connection when it is created, the
	 current form is a remnant from before the -exec refactor.

Depending on what toolkit is being used, chances are that some magic dance is
needed in order to get a client to connect using wayland, and similarly for the
specific shell protocol to use when multiple are available, for the choice of
buffer passing (shm or egl) and for the GPU device actually being used. With
other Wayland compositors, chances are that this effect is masked by the client
in question falling back to XWayland and some clients will fail outright if
there's no XServer available even though the clients themselves actually only
use their respective Wayland paths. In short, it's a mess.

a. For SDL, check the environment variable for SDL\_VIDEODRIVER=wayland
b. For QT, try the -platform wayland argument.
c. For EFL, it's EVAS\_ENGINE=wayland\_shm or EVAS\_ENGINE=wayland\_egl along
with ELM\_DISPLAY=wl and optionally ELM\_ACCEL=none if there's issue with
gl acceleration.

The -exec mode sets these automatically.

Limitations
====
There are a number of arcan features that do not have a corresponding
Wayland translation, and will therefore be a no-op or hidden in whatever
scripts arcan is running. There are also some features where the translation
is not entirely compatible. Such incompatibilities/limitations are tracked
separately in the [arcan wiki](https://github.com/letoram/arcan/wiki/wayland).

XWayland
====

XWayland support is currently omitted for two reasons. One is that the Xarcan
approach is more efficient and blends better with the current arcan WMs
(durden/prio) due to the whole 'self contained' thing, along with the need to
have sharing-interception and not be explicitly dependent on wayland for X
support.

The other is that for XWayland support, one must write an entire window manager
(or import the one from weston or wlc, neither work flawlessly). Based on the
'Why isn't Xwayland just a Wayland Client' post (wayland-devel, 2017-sept.) it
seems like there's a chance we get patches that makes the special xwayland path
unecessary and thus it is better to wait and see.

BUGS
===
1. gnome-apps, mouse motion registers but not button presses on some
   popups, likely related to input regions and grabbing and the WM
	 script-side being guilty.
2. SDL2, buffer- size and mouse cursor alignment is off in ex. 0ad
3. gnome-apps, visible with calculator - some interaction between durden
   and subsurfaces etc. still seem to misbehave.

TODO
====

Rough estimate of planned changes and order:

1. fork- mode
2. input fixes (regions, D to A mouse wheel, ...)
3. data-device to clipboard
4. enforce stronger error handling (not allow surfaces to switch roles etc.)
5. move more 'decisions' that is part of the durden atype handling
6. make a simple automatable wayland-only WM appl

(x - done, p - partial/possible-tuning, s - showstopper, i - ignored for now)
+ (for-each finished milestone, verify allocation/deallocation/validation)

The many 'p's are simply that we lack a decent conformance suite to actually
determine if we are compliant or not, because Wayland.

- [ ] Milestone 1, basics
  - [x] Boilerplate-a-plenty
  - [x] 1:1 client to bridge mapping
    - [x] \*:1 client to bridge mapping
  - [ ] Seat
    - [p] Keyboard
    - [p] Mouse
    - [ ] Touch
  - [x] Mouse Cursor
  - [p] Popup
  - [p] EGL/drm
- [ ] Milestone 2
    - [p] Cut and Paste (full 'data device manager')
    - [p] Subsurfaces
    - [p] XDG-shell
      - [x] Focus, buffers, cursors, sizing ...
      - [p] Forward shell events that can't be handled with shmif
      - [p] Positioners
			- [p] zxdg-v6 to xdg-shell mapping
    - [i] Application-test suite and automated tests (SDL, QT, GTK, ...),
		      seems that canonical attempts to tackle this
    - [i] XWayland (WM parts)
- [ ] Milestone 3, funky things
  - [x] SHM to GL texture mapping
	- [x] Single-exec launch mode (./arcan-wayland -exec gtk3-demo)
  - [p] Transforms (Rotations/Scaling - most is done server side already)
  - [p] Multithread/multiprocess client processing
  - [ ] Dynamic Keyboard Translation table generation
  - [ ] Benchmarking/Inspection tools
  - [p] Sandboxing
  - [x] Migration/Reset/Crash-Recover
  - [ ] Drag and Drop (cursor states)

- [ ] Misc. protocols:
  - [ ] Idle Inhibit Unstable
  - [ ] Pointer Constraints
  - [ ] Pointer Gestures
  - [ ] Input Method
  - [ ] Keyboard Shortcuts
  - [ ] Tablet
  - [ ] Presentation Time
  - [ ] Viewporter
  - [ ] Xdg-output
  - [ ] Xdg-foreign
	- [ ] Dma- buf
