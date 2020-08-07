Introduction
====
This tool bridges wayland connections with an arcan connection point. It is
currently in a beta- state and should be useful, but expecting quirks and
side-effects to exist.

Principal Articles
====
[Crash Resilient Wayland Compositing](https://arcan-fe.com/2017/12/24/crash-resilient-wayland-compositing/)

Compiling
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

Use
===
There are two ways of running arcan-wayland. One is as a background service
by simply invoking:

        arcan-wayland

This will create a wayland server listening on the default (0) wayland display
that clients try if there is no control environment set. By default, this does
not include 'Xwayland' which would allow X clients to connect as wayland ones,
but it can be enabled like this:

        arcan-wayland -xwl

The other mode is to run arcan-wayland in a 'single-client exec wrapper' mode.
This is safer and allows for better separation, at the cost of slightly higher
memory use:

        arcan-wayland -exec weston-terminal

This mode attempts to set any toolkit specific environment options that might
be needed. This way of running single clients works for X clients as well:

        arcan-wayland -exec-x11 xterm

The same caveat applies with the -xwl approach, both the wayland layer and the
Xorg layer and the meta- Xorg window manager will be run as separate processes
per client.

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

Wayland- level has its own environment triggered tracing, WAYLAND\_DEBUG.
Then for the arcan\_xwm tool (the window manager for xwayland) can be used
either through the setup above, or with Xarcan along with the normal X
debugging tools, e.g.

Mesa and EGL stacks also have their environment variables for enabling
debugging. EGL\_LOG\_LEVEL=debug, MESA\_DEBUG=...

tracing - xtruss
interactive querying - xwininfo, xprop
input-events - xev
pseudo-wm-commands - xdotool, wmctrl
other useful xwininfo: -tree -root

## Adding Protocols

Wayland, in all its COMplexity, is practically a huge tree of xml files that
may or may not be present, and may or may not be needed depending on the client.

To add support for a new 'protocol':

1. First find the xml definition somewhere. Add to the CMakeLists.txt list of protocol names.
2. Dry-run a build so the .h file gets generated (helps, not necessary)
3. (boilerplate.c) #include the derived .h file
4. wlimpl/myproto.c - create with the expected functions from #3.
5. (boilerplate.c) #include file from 4, add a faux vtable that pairs if struct with functions
6. (bondage.c) create a bind function that references the table from 5.
7. (waybridge.c) add a command-line toggle for the protocol, update help printout
8. (waybridge.c) append big if-else with an if myprotocol then add bind function to wl\_display
9. actually fill in the stubs from #4, 9 times out of 10, it results in a shmif\_enqueue
10. modify WM to pair corresponding features
11. (optional) bask in the glory of the 'simplicity', cry and die a little on the inside.


TODO
====

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
    - [p] XWayland (WM parts)
- [ ] Milestone 3, funky things
  - [x] SHM to GL texture mapping
	- [x] Single-exec launch mode (./arcan-wayland -exec gtk3-demo)
  - [p] Transforms (Rotations/Scaling - most is done server side already)
  - [p] Multithread/multiprocess client processing
	- [ ] Live icon discovery / mapping
  - [ ] Pulseaudio stripping
	- [ ] Dbus stripping
  - [ ] Dynamic Keyboard Translation table generation
  - [ ] Keycode remapping
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
	- [x] Dma- buf
	- [ ] Qt- specific protocols for SDL shutdown issue
