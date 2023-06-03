This file contains the bare minimum details for quickly getting to know what
the main components are and where to go for further information.

# Points of Information

A lot of information and articles about the engine and various features can be
found at the [wiki](https://github.com/letoram/arcan/wiki). For offline use,
you can also clone the repository itself. When the dust settles, these will
be cleaned up and consolidated into a more structured pdf.

    git clone https://github.com/letoram/arcan.wiki

The Lua scripting API is present in the 'doc' folder, with a .lua file
describing each exposed API function. The wiki has a set of exercises that
helps navigate the API itself, with solutions in the tests/exercises folder of
the main source repository.

# Development Structure

Development is currently discussed in the IRC channel, #arcan on irc.freenode.net.
Most activity goes into topic branches that are created and given a checklist
file of planned changes. When all changes in a topic branch are finished, it is
merged into master and tagged as a new minor release, then the branch is deleted.

Important bugs and bugfixes goes into master immediately, other changes should
be directed towards the topic branch in question. You can use `git branch -a` to
see the list of current branches, where the feature branches follow the pattern
of 'subsystem-version', such as shmif-056.

# Important Layers

* SHMIF, which resides in the src/shmif subdirectory, is the IPC subsystem
  that is used to glue all the pieces together. See the section further
	below for more details.

* Frameservers, found in the src/frameservers subdirectory, are default
  implementations of 'one-purpose' clients. Each fill one archetype out of
	'encode' (transform+output), 'decode' (acquisition+transform+input),
	'remoting' (connect to external system), 'net' (service discovery and
	communication), 'terminal' (special management for terminal emulators),
	'game' (special management for games). These are chainloaded via
	'arcan_frameserver' that do environment cleanup, sandbox setup and so on.

* Platform, found in src/platform, contains low level system integration
  primitives. It is further split up into video (display control), agp
	(accelerated graphics, a mid-level graphics API) and event (event driven
	input/ouput device control). Improved device support and so on goes here.

* Core engine: found in src/engine, contains the actual feature implementation
  and business logic. It is further broken down into a translation unit per
  logical group, e.g. audio, video, event processing, scheduling (conductor),
  and so on.

* Lua-engine: found in src/engine/arcan_lua.c, exposing the higher level API
  that is controlled via lua script files. Modifications to this layer are
	discouraged as they require a lot of additional testing, documentation and
	quality work. If you really need to extend the engine features at this level
	for your own projects, look into the system\_load facility for pulling in
	shared libraries that hook into the Lua VM.

* Lua-support: found in distr/scripts. These are built-in support scripts that
	other applications can re-use, but also for more generic hook-scripts that can
  be invoked regardless of application at startup.

* Database: found in engine/arcan\_db.c and a CLI tool in src/tools/db. Keeps
  both engine configuration, whitelist of external programs that can be launched
	and shared key/value configuration store for external programs and for scripts.

* Namespaces: the engine splits its inputs and outputs for persistant and temporary
  storage into multiple namespaces that regulate function and access permissions.
  See the arcan manpage for more details on these.

# Appl

This is the (shorthand for application) set of scripts that is running via the
Lua- part of the engine. They always follow the naming convention of a folder
with the base name of the appl with at least a .lua script file inside ith the
same base name (so myexample/myexample.lua) and a function that is invoked when
the engine is ready. This function also has the same basename.

An minimal example would thus be:

    mkdir test ; echo "function test() print('hi'); shutdown(); end" > test/test.lua

This should be runnable simply throught:

    /path/to/arcan ./test

# Client APIs

In addition to the high-level Lua scripts that drive the engine iteself, there
are APIs for extending engine capabilities and features externally. There is a
low-level API (shmif) and a high-level API (tui).

## SHMIF

SHMIF is the heart of the engine - it is the IPC system that is used both to
compartmentalise engine features into separate processes and used to implement
support for connecting external clients, input drivers, etc.

While the are many details to the API itself, refer to the
arcan\_shmif\_control.h and arcan\_shmif\_interop.h header files (primarily)
for functions and parameters.

Brief summary of the key concepts are as follows:

* 'Connection Point' : a single-use connection slot defined by the currently
  running appl. Think of it as an address to a UI component or role. It is
	consumed on use and has to be re-opened by the appl.

* Segment : a typed (type:hint to appl as to purpose) IPC container built
  on top of shared memory. By default, tt carries ring buffers for event
	transfers, as well as video and audio buffers. It can also be extended to
  handle accelerated graphics or specialised transfer modes for VR, colour
  management and so on.

* Primary Segment : The segment tied to a connection point.

* Subsegment : A segment that has been allocated through an existing
  segment rather than consuming a new connection point.

* Migration / Fallback : The act of reconstructing/renogiating a client
  from one connection point to another. The fallback is simply a default
	connection point that a client will migrate to if the current connection
	is severed.

If a client doesn't inherit a connection point handle in its environment,
the ARCAN\_CONNPATH environment is silently used to find the socket tied
to a connection point.

Examples of use can be found in tests/examples/frameservers.

## TUI

TUI is a higher level API for creating text-dominant (but support embedding
media contents) applications. It resides on a level of abstraction above
ncurses and the likes, but much below that of typical UI/widget toolkits.

More documentation and other language bindings will be written as the last
few features are getting finalized.

The strongest example of its use is that of the terminal frameserver, see
the code in src/frameservers/terminal/default.

# Tests and Examples

There are a number of different tests and examples to run. Most of them can
be found in the tests/ directory, where a README.md will point you further.

The exemption to this is the Lua API itself, as the .lua files in the doc
folder contains both passing tests /example of use, and failing tests.
These are extracted using a support script, docgen.rb inside of that folder.

# Debugging Tools

Since the engine runs under soft-realtime conditions, normal breakpoint based
debugging quickly becomes very disruptive, and tracing sources becomes more
important to get valuable information. In this section a few such sources and
tactics are listed.

## Tracy

Arcan has native optional built-in support for the Tracy tracer. Enabling it
comes with some caveats (-DENABLE_TRACY=ON). First is to expect that it will
hold a tcp port (default 8086) open and that any personal data exposed might
be accessed this way, which is part of the point. Thus is it not intended to
run on normal day-to-day production devices.

Second is that it collides with crash recovery, so regular Lua scripting
errors will become stalls. If running Arcan as the primary display server,
this means that the display will be unusable. Be sure to have a second
connection path, e.g. ssh or a12 into an afsrv\_terminal.


## Watchdog

When running a low level platform where arcan acts as the display server,
there is a watchdog active that will first SIGINT (causing the Lua VM to reset)
and if watchdog still isn't set, SIGKILL. When attaching a debugger, disable
the watchdog with:

    set arcan_watchdog_ping=0

which is allocated in arcan\_conductor\_enable\_watchdog().

## Engine invocation

The -q and -g arguments are useful tools for improving debugging. The -q
argument waits a certain number of 25Hz ticks, makes a snapshot of the scene
graph and metadata and shut down. The result will be stored in the
ARCAN\_LOGPATH environment.

The 'M' and 'O' arguments are also useful for debugging. These control the
sampling period and target (file or another arcan instance) for periodically
snapshotting in the same format as -q. This allows you to quickly write
inspection tools that track changes and so on.

The -g argument increases a DEBUGLEVEL variable in the Lua space, but also
increases the verbosity of stderr output from the engine itself.

## Lua Layer

The default 'debug' table of the lua language (e.g. debug.traceback()) is
included. The same snapshot feature that is invoked with -q can be triggered
via system\_snapshot() calls.

The lua\_tracetag() function allows you to assign an arbitrary string to
any video object refence, which is very useful for finding them in snapshots.

The benchmark\_enable and benchmark\_data functions provides continuous
measurements on frame timing data, rendering costs and so on.

There is also an appl specific hook, applname\_fatal(inmsg) that allows you to
append/expose more state in the returned string before the interpreter is shut
down and handover/crash recovery or shutdown is invoked.

Although you cannot call any engine functions anymore, you still have access to
the global state of your script, and can thus add your own crash state data to
make it easier to debug your scripts.

## Shmif/frameservers

The communication for a shmif client can be inspected by first setting the
ARCAN\_SHMIF\_DEBUG=1 variable.

For frameservers, the ARCAN\_FRAMESERVER\_DEBUGSTALL environment can be set
to a number of seconds that it should wait. This provides a time window for
attaching a debugger,

There is also a 'shmmon' tool that attempts
to snapshot and dump state of individual connections if given access to the
memory pages (proc like interface)

## Specialized 'DEBUG' windows

A unique feature to arcan is that segments can be pushed to a client as a
way of announcing desired input/output of a specific type. One such type is
'debug' and allows compliant applications to get dedicated IPC channels for
attaching debug data that can be composed and managed like any other client
window.

These can be created via calls to 'target\_alloc' using the vid of the
client as its target.

Should the client fail to provide such debug interface, a hidden one inside
shmif will take its place and provide more debugging options.
