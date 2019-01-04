Arcan
=====

Arcan is a powerful development framework for creating virtually anything from
user interfaces for specialized embedded applications all the way to full-blown
standalone desktop environments.

At its heart lies a robust and portable multimedia engine, with a well-tested
and well-documented Lua scripting interface. The development emphasizes
security, debuggability and performance -- guided by a principle of least
surprise in terms of API design.

For more details about capabilities, design, goals, current development,
roadmap, changelogs, notes on contributing and so on, please refer to the
[arcan-wiki](https://github.com/letoram/arcan/wiki).

There is also a [website](https://arcan-fe.com) that collects other links,
announcements, releases, videos / presentations and so on.

For developer contact, check out the IRC channel #arcan on irc.freenode.net.

The current release version is roughly that the master branch will always have
bugfixes pushed as soon as possible, and after a new (0.n.m.p) update to the m
version number - a blog post is pushed and then a set of the next big features
gets selected, and each pushed as a new branch. When that feature is completed
we interactive-rebase-squish-merge unto the main branch and tag a '.p' version
update. When there are no branches left, the 'm' version gets a new update and
the cycle repeats anew.

# Table of Contents
1. [Getting Started](#started)
    1. [Compiling](#compiling)
2. [Database / Configuration](#database)
3. [Compatibility](#compatibility)
4. [Other Tools](#tools)
5. [Appls to Try](#appls)
6. [Git layout](#gitlayout)

Getting Started <a name="started"></a>
====

The rest of this readme is directed towards developers or very advanced end-
users as there is no real work or priority being placed on wrapping/packaging
the project and all its pieces at this stage.

Compiling
----
There are a lot of build options for fine-grained control over your Arcan
build. In this section we will just provide the bare essentials for a build
on Linux, BSD or OSX. and you can check out the relevant sections in the wiki
for more detailed documentation on specialized build environments, e.g. an
X.org-free KMS/DRM. (https://github.com/letoram/arcan/wiki/egl-dri)

For starters, the easiest approach is to do the following:

     git clone https://github.com/letoram/arcan.git
     cd arcan
     mkdir build
     cd build
     cmake -DCMAKE_BUILD_TYPE="Debug" -DVIDEO_PLATFORM=sdl ../src
     make -j 12

The required dependencies for this build are: cmake for compilation,
libsdl1.2, openal-soft, opengl and freetype. There is also support
for building some of these dependencies statically:

     git clone https://github.com/letoram/arcan.git
     cd arcan/external/git
     ./clone.sh
     cd ../../
     mkdir build
     cd build
     cmake -DCMAKE_BUILD_TYPE="Debug" -DVIDEO_PLATFORM=sdl
      -DSTATIC_SQLITE3=ON -DSTATIC_OPENAL=ON -DSTATIC_FREETYPE=ON ../src
     make -j 12

You can then test the build with:
 
     ./arcan -T ../data/scripts/ -p ../data/resources/ ../data/appl/welcome

This tells us to use shared scripts from the ../data/scripts directory
(which implements keymaps, mouse gestures etc.), to use shared resources
from the ../data/resources directory and launch an application that resides
at ../data/appl/welcome.

If these paths aren't specified relative to current path (./ or ../) or
absolute (/path/to) the engine will try and search in the default 'applbase'.
This path varies with the OS, but is typically something like
/usr/local/share/arcan/appl or to the current user: /path/to/home/.arcan/appl

The 'recommended' setup is to have a .arcan folder in your user home directory
with a resources and appl subdirectory. Symlink/bind-mount the data you want
accessible into the .arcan/resources path, and have the runable appls in
.arcan/appl.

There are other, more XDG compatible, setups - with some template for a
support launcher script that can be found in data/distr/launch.

A big note about compilation is how central the 'shmif' set of libraries are.
These are used for all external tools, but are tied to the inner workings of
your arcan build, and particularly the 'video' platform used. The short
explanation as to why this is, is that there's no universal solution for which
packing formats and so on it is that is the most efficient for all possible
hardware combinations. Your needs on a low level are possible much different
from on a higher level where there's another display system involved. While it
is possible to account for such variations at runtime with some degree of
uncertainty, the solution contributes to a huge state space explosion in a way
that we don't have the resources to support, and it makes application
development harder on both sides of the shmif- barrier. Therefore, the decision
was made to have a 'native color format' and a 'native audio format' that
is as hard-wired as 'endianness' is for CPUs. While builds are made out of
source, one file, shmif/arcan\_shmif\_cfg.h, is generated during build time
in the normal source tree. Therefore, trying out multiple builds from the
same source checkout will likely result in wrong colors unless you rebuild
everything that uses SHMIF. This is one of the reasons why SHMIF- is treated
as an 'internal API' rather than some protocol or external API for others to
use. This situation is subject to change, but there are no such plans in that
direction at the moment.

Database / Configuration
=====
Among the output binaries is one called arcan\_db. It is a tool that can be
used to manipulate the sqlite- database that the engine requires for some
features, e.g. application specific key/value store for settings, but also for
whitelisting execution and as a generic configuration mechanism.

The database itself is split into a number of tables with key=value stores,
and a special set of tables (targets and config) for referencing programs
that can be launched (also refered to as 'launch targets'). Internally,
the tables are prefixed appl\_applname, with 'arcan' and 'arcan\_lwa' being
reservered for engine configuration.

Modifying an appl- kv store is as simple as;

        arcan_db add_appl_kv myappl key value

While the current set of kv pairs can be enumerated via:

        arcan_db show_appl myappl

Refer to the arcan\_db tool and manpage for more detailed explanation.

The various input, graphics and event platforms can be all configured
either via environment variables or via the database. In case of a conflict,
the environment variables will take presedence.

The environment variables follow the pattern: ARCAN\_SUBSYS\_XXX where
SUBSYS can be VIDEO, EVENT, AUDIO, GRAPHICS - or via the database.

Running arcan without any arguments should give you an enumeration of the
various values for XXX that the current platform setup accepts.

The database- configuration takes a similar pattern, e.g. subsys\_xxx (note
that the ARCAN prefix is dropped as it is implied in the database context
and the key is in lower case). Example:

        arcan_db add_appl_kv arcan event_verbose 1

Would set the 'verbose' option to enabled for the event subsystem.

For execution targets, it's slightly more complicated. An early design decision
was that the Lua VM configuration should be very restrictive -- no arbitrary
creation / deletion of files, no arbitrary execution etc. The database tool is
used to specify explicitly permitted execution that should not be modifable
from the context of the running arcan application.

One target comprise one binary, a binary format and base
environment/command-line arguments, including a list of libraries to preload.
It also has one or many different configurations that append additional
arguments - but both targets and configurations also act as key-value stores in
order to track per-application configurations in the same place and with the
same toolset/interface as the rest of the system. Furthermore, arguments are
subject to namespace expansion.

The following example attempts to illustrate how this works:

        arcan_db db.sqlite add_target example_app /some/binary -some -args
        arcan_db db.sqlite add_config example_app more_args -yes -why -not
        arcan_db add_target mycore RETRO [ARCAN_RESOURCEPATH]/.cores/core.so
        arcan_db add_config mycore myconfig RETRO /path/to/somefile

An arcan application should now be able to:

        launch_target("example_app", "more_args", LAUNCH_EXTERNAL);

or

        vid = launch_target("example_app",
            "more_args", LAUNCH_INTERNAL, callback_function);

The first example would have the engine minimize and release as many
resources as possible (while still being able to resume at a later point),
execute the specified program and wake up again when the program finishes.
This can be used to share the GPU with dedicated fullscreen applications that
benefit from minimal overhead, or for use as features like explicit suspend
(where the target- you execute is your 'save to mem and shutdown' utility.

The second example would execute the program in the background, expect it to
be able to handle the engine shmif- API for audio/video/input cooperatively
or through an interposition library.

It can be cumbersome to set up database entries to just test something.
Frameservers is a way of separating sensitive or crash-prone functions from
the main engine for purposes such as running games or playing back video.

In a default installation, they are prefixed with afsrv\_ [game, encode,
decode, ...] and while they are best managed from the appl itself, you can
run them from the terminal as well. Which ones that are available depend on
the dependencies that were available at build time, but for starting a
libretro core for instance:

    ARCAN_ARG=core=/path/to/core:resource=/path/to/resourcefile afsrv\_game

or video playback:

    ARCAN_ARG=file=/path/to/moviefile.mkv afsrv_decode

but they are all best managed from the engine and its respective scripts.

Compatibility
====
The follow options exist for running 3rd party software that use arcan as
a display server:

1. Arcan-LWA - this allows for nested execution of different scripts, if
   the dependencies were fulfilled during compile time, you should already
   have this binary.

2. Wayland - use the separate tool found in src/tools/waybridge to
   enable on a per- client basis or as a translation service.

3. XArcan - there is a patched Xorg server at
   https://github.com/letoram/xarcan

4. QEmu - there is a patched QEmu backend at
   https://github.com/letoram/qemu

5. SDL2 - there is a patched SDL2 backend at
   https://github.com/letoram/SDL2
   but it is better to run SDL2 applications through wayland.

There is also the option of using hijack (LD\_PRELOAD and similar) for
hacky ways to access legacy software, should XArcan/Wayland not work.
You can enable this with the build-time -DDISABLE\_HIJACK=OFF and get
access to a SDL1.2 lib (libahijack\_sdl12.so).

Other Tools<a name="tools"></a>
====

Depending on build-time configuration and dependencies, a number of other
binaries may also have been produced. The particularly relevant ones are:

arcan\_lwa: specialized build that connects/renders to an existing Arcan
instance, similar in some ways to Xnest or ephyr.

arcan\_frameserver: a chainloader used to setup/configure the environment
for the individual frameservers.

Frameservers are an important part of the engine. They can be considered
specialized or privileged separate processes for offloading or isolating
sensitive and bug-prone tasks like parsing and decoding media files. One
frameserver implements a single 'archetype' out of the set (decode, net,
encode, remoting, terminal, game, avfeed). The running appl- scripts can
then use these to implement features like desktop sharing, accessibility
tools, screen recorders, etc. with a uniform interface for system-access
policies and granular sandboxing controls.

afsrv\_terminal: the default terminal emulator implementation.

afsrv\_decode: media decoding and rendering implementation, default version
uses libvlc.

afsrv\_encode: used for transforming/recording/streaming media.

afsrv\_net: (experimental/broken) used for negotiating/discovering
local networking services.

afsrv\_remoting: client-side for bridging with remote desktop style protocols,
with the default using VNC.

afsrv\_game: implementation of the [libretro](http://libretro.com) API that
allows you to run a large number of game engines and emulators.

afsrv\_avfeed: custom skeleton for testing/ quick- wrapping some A/V device.

Inside the tools directory, there are a number of additional tools that
are built separately. These are:

aclip: clipboard manager / CLI integration

aloadimage: sandboxed image loader

shmmon: shmif- dump/inspection tool

waybridge: wayland client support

leddec: example of an external LED controller

vrbridge: add support for virtual-reality related hardware

Appls to try<a name="appls"></a>
====

With the engine built, and the welcome- test appl running, what to try next?
That depends on your fancy. For appl- development you have some basic scripting
tutorials and introduction documentation on the wiki.

For desktop environment use, there are two usable ones available right now,
'durden' and 'prio'. 'Durden' is an attempt at evolving a complete, customizable,
heavily integrated approach to the keyboard dominant management/use style promoted
by tiling window managers like Xmonad or i3.

'Prio' is instead a much simpler skeleton for a composable desktop where third
party providers can be set to be responsible for different parts of the UI. Its
window management model is an homage to the 'Rio' system used as part of the
Plan9 operating system.

Demonstrating how more advanced applications can be built, there is also
[senseye](https://github.com/letoram/senseye/wiki), which is an research- level
data visualization, debugging and reverse engineering tool - but senseye is likely
to only be of use to those few that have an unhealthy interest in such areas.

To try out durden or prio:

    git clone https://github.com/letoram/durden.git
    arcan -p /my/home /path/to/checkout/durden/durden

    git clone https://github.com/letoram/prio.git
    arcan -p /my/home /path/to/checkout/prio

The basic format for starting is arcan:
    [engine arguments] applname [appl arguments]

Note that it's the durden subdirectory in the git, not the root. The reason
for the different start path (-p /my/home) is to give read-only access to
the appl for the built-in resource browser. It is possible that (depending
on platform, time of day, the use of bastard devices like KVMs etc.) the
detected resolution is wrong. You can explicitly override that for now by
using -w desiredwidth -h desiredheight as arguments to the engine.

For details on configuring and using durden or prio, please refer to the
respective README.md provided in each git. There are also demonstration
videos on the [youtube-channel](https://www.youtube.com/user/arcanfrontend).

Filesystem Layout<a name="gitlayout"></a>
=====
The git-tree has the following structure:

    data/ -- files used for default packaging and installation (icons, etc.)

    doc/*.lua -- specially formatted script files (1:1 between Lua API
                 functions and .lua file in this folder) that is used
                 by doc/mangen.rb to generate manpages, test cases,
                 editor syntax highlighting etc.

    doc/*.1   -- manpages for the binaries
    doc/*.pdf -- presentation slides (updated yearly)
    external/ -- external dependencies that may be built in-source

    src/
        engine/ -- main engine code-base
        frameserver/ -- individual frameservers and support functions
        hijack/ -- interpositioning libraries for different data sources
        platform/ -- os/audio/video/etc. interfacing
        tools/ -- database tools, keymap conversion, protocol/device bridges
        shmif/ -- engine<->frameserver IPC

    tests/
          api_coverage -- dynamically populated with contents from doc/
          benchmark -- scripts to pinpoint bottlenecks, driver problems etc.
          core -- for core libraries (shmif-server etc.)
          interactive -- quick/messy tests that are thrown together during
                         development to test/experiment with some features.
          frameservers -- specialized testing clients
          security -- fuzzing tools, regression tests for possible CVEs etc.
          regression -- populated with test-cases that highlight reported bugs.
          exercises -- solutions to the exercises in the wiki.
          examples -- quick examples / snippets
          modules -- system_load()able lua extensions

