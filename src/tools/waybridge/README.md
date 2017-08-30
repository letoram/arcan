Introduction
====
This tool bridges wayland connections with an arcan connection point. It is
currently in an alpha- state and as such not particularly useful for any other
purposes than development on the tool itself - though it's mostly feature-
mapping things that are already in place (see Limitations).

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

To debug, add WAYBRIDGE\_TRACE=level as env and very verbose call tracing
will be added.

tracelevels (bitmask so add)
    1   - allocations only
    2   - digital input events
    4   - analog input events
    8   - shell (wl\_shell, xdg\_shell, ...) events
    16  - region events
    32  - data-device events
    64  - seat events
    128 - surface events

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

Notes and Issues
====
1. DRM- buffer translation is incomplete - though the handles can be
   forwarded with some rather aggressive DRM tricks, we still don't
	 track/release correctly.

2. Mouse input, scroll wheel / scroll locking not really working

3. Stride - the shm- buffer blit doesn't take stride differences into
   account. This fails on MPV in SHM depending on source video size.

4. Buffering and recent Qt5 demos, for some reason the pyqt demos queues up
   a lot of frames and then just dies - unsure what is happening here though
	 it seems like it is connected to the part where we need to handle multiple
	 callbacks for the same surface.

Limitations
====
There are a number of arcan features that do not have a corresponding
Wayland translation, and will therefore be a no-op or hidden in whatever
scripts arcan is running. There are also some features where the translation
is not entirely compatible. Such incompatibilities/limitations are tracked
separately in the [arcan wiki](https://github.com/letoram/arcan/wiki/wayland).

XWayland
====
XWayland support will be enabled at some point since there isn't really much
we need to do other than some minor xcb parsing on a WM socket, and we can
borrow the setup from wlc - though for non-rootless mode, we prefer Xarcan
operation as that requires less translation and has access to more features.

TODO
====

(x - done, p - partial/possible-tuning, s - showstopper)
+ (for-each finished milestone, verify allocation/deallocation/validation)

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
		- [ ] Subsurfaces
    - [ ] XDG-shell
 		  - [x] Focus, buffers, cursors, sizing ...
			- [p] Forward shell events that can't be handled with shmif
			- [p] Positioners
    - [ ] Application-test suite and automated tests (SDL, QT, GTK, ...)]
    - [ ] XWayland (WM parts)
    - [ ] Output Rotation / Scaling
- [ ] Milestone 3, funky things
  - [ ] SHM to GL texture mapping
  - [ ] Transforms (Rotations/Scaling)
  - [ ] Multithread/multiprocess client processing
  - [ ] Dynamic Keyboard Translation table generation
  - [ ] Benchmarking/Inspection tools
  - [ ] Sandboxing
  - [ ] Migration/Reset/Crash-Recover
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
