Introduction
====
This tool provides command-line integration with the CLIPBOARD interface as
part of the arcan-shmif API. For actual use, see the manpage.

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
=====
The appl arcan runs must also explicitly expose a connection point which
accepts a SEGID\_CLIPBOARD as the primary segment type (which no normal window
would).

In durden, for instance, this needs to be explicitly enabled as it can be used
to monitor and manipulate global clipboard activity, which should be avoided if
that is crucial to your threat model. It can be controlled through the
global/config/system/clipboard bridge menu path.

Another quirk, due to design/API limitations in arcan, a paste-operation relies
on an outbound connection, and these are only defined as subsegments (there
must be a primary segment around). They are therefore slightly more expensive
in terms of resource consumption and connection setup.

TODO
====
- [ ] audio support
- [ ] video support
- [ ] binary blob support
