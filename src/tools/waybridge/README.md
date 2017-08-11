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
's' - shell surface
'm' - pointer surface
't' - xdg- toplevel surface
'p' - xdg- popup surface
'x' - dead
'o' - unused

Then the correlated arcan events can be traced with ARCAN\_SHMIF\_DEBUG=1

Notes and Issues
====
1. Mesa picks the wrong render-node
At the moment, EGL/drm is stuck on what seems like a bug in Mesa. If we bind
the bridge to a render-node, a client will get somewhere in the nasty backtrace
to (drm\_handle\_device) - the reference to /dev/dri/card128 rather than
/dev/dri/renderD128. A quick hack around this bug is to simply create the
render-node under the name mesa is looking for.

The other option is to tell arcan to start arcan with the
ARCAN\_VIDEO\_ALLOW\_AUTH environment set and start waybridge with
ARCAN\_RENDER\_NODE pointing to the card device arcan uses. This will push the
privilege level of waybridge to be on par with arcan.

Limitations
====
There are a number of arcan features that do not have a corresponding
Wayland translation, and will therefore be a no-op or hidden in whatever
scripts arcan is running. There are also some features where the translation
is not entirely compatible. Such incompatibilities/limitations are tracked
separately in the [arcan wiki](https://github.com/letoram/arcan/wiki/wayland).

XWayland
====
XWayland support will be enabled at some point, though it will likely just
derive from the implementation WLC has. instead, A separate
[Xarcan](https://github.com/letoram/xarcan) implementation is maintained for a
number of resons, such as better controls of how/ and which/ features gets
translated (matters when looking into sharing, display-hw synch, segmentation,
...), for performance (going xwayland -> arcan-wayland -> arcan has some costly
friction in translation that is not worth paying for).

TODO
====
- [ ] Milestone 1, basics
  - [x] Boilerplate-a-plenty
  - [x] 1:1 client to bridge mapping
    - [x] \*:1 client to bridge mapping
  - [ ] Seat
    - [p] Keyboard
    - [p] Mouse
    - [ ] Touch
  - [ ] Mouse Cursor
  - [ ] Popup
  - [ ] EGL/drm
- [ ] Milestone 2
    - [ ] Positioners
    - [ ] Cut and Paste (full 'data device manager')
    - [ ] Full XDG-shell (not just 90% boilerplate)
    - [ ] Application-test suite and automated tests (SDL, QT, GTK, ...)]
    - [ ] XWayland (WLC- level)
    - [ ] Output Rotation / Scaling
- [ ] Milestone 3, funky things
  - [ ] SHM to GL texture mapping
  - [ ] Transforms (Rotations/Scaling)
  - [ ] Multithread/multiprocess client processing
  - [ ] Dynamic Keyboard Translation table generation
  - [ ] Benchmarking/Inspection tools
  - [ ] Sandboxing
  - [ ] Migration/Reset/Crash-Recover
  - [ ] Drag and Drop
