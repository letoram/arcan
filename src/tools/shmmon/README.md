Introduction
====
This tool is a simple shmif- debugging aid. You either hand it a descriptor
or a path to where one might be found (os-specific) and it will periodically
sample the contents of the page and dump to command-line output.

Licensing
====
The EDID parser was lifted from the EDS project, see COPYING.eds.

Building
====
The build needs access to the arcan-shmif either detected through the normal
pkgconfig or by explicitly pointing cmake to the
-DARCAN\_SOURCE\_DIR=/absolute/path/to/arcan/src

         mkdir build
         cd build
         cmake ../
         make

Notes
===
This will only present the contents of the connection that are on the
negotiation/disputed shared memory page. The local client- state tracking
and the corresponding server- state tracking are not available. The same
goes for content that has been transferred as opaque handles. To get access
to that kind of data, the client will need to be proxied.

Status
======
[x] Basic Metadata
[ ] Subsegment- tracking
[x] Subprotocol support
[ ] Semaphore control
[ ] TUI-based UI
[ ] System mode (/proc or cooperation with arcan)
[ ] Snapshot / logging
