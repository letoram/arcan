Introduction
====
This tool bridges wayland connections with an arcan connection point. It is
currently in a very alpha- state and as such not particularly useful for any
other purposes than development on the tool itself.

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

Issues to Investigate(tm)
====
At the moment, EGL/drm is stuck on what seems like a bug in Mesa. If we
bind the bridge to a render-node, a client will get somewhere in the nasty
backtrace to (drm\_handle\_device) - the reference to /dev/dri/card128 rather
than /dev/dri/renderD128.

Limitations
====
There are a number of arcan features that do not have a corresponding
Wayland translation, and will therefore be a no-op or hidden in whatever
scripts arcan is running. There are also some features where the translation
is not entirely compatible. Such incompatibilities/limitations are tracked
separately in the [arcan wiki](https://github.com/letoram/arcan/wiki/wayland).

TODO
====
- [ ] Milestone 1, basics
  - [x] Boilerplate-a-plenty
  - [ ] 1:1 client to bridge mapping
    - [ ] \*:1 client to bridge mapping
  - [ ] Seat
    - [ ] Keyboard
    - [ ] Mouse
    - [ ] Touch
    - [ ] shm to GL texture mapping
  - [ ] Shell
    - [ ] Qt- applications working
    - [ ] SDL2 applications working
    - [ ] MPV working
    - [ ] Other relevant wayland capable backends? retroarch?
  - [ ] EGL/drm

- [ ] Milestone 2, (z)xdg-shell
- [ ] Milestone 3, funky things
  - [ ] Multithreaded client processing
  - [ ] Dynamic Keyboard Translation table generation
