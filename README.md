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
roadmap, changelogs and so on, please refer to the
[arcan-wiki](https://github.com/letoram/arcan/wiki) and to the
[website](https://arcan-fe.com).

Getting Started
=====
The rest of this readme is directed towards developers. As an end- user,
you would probably do best to wait for- or encourage- the development
applications that uses this project as a backend, or at the very least-
wait until it is available as a package in your favorite distribution.

For developers, the first step is, of course, getting the engine
up and running (see building, below).

After that is done, there is a set of challenges and exercises in the wiki
to help you get a feel for the API, navigating documentation and so on.

Compiling
=====
There are a lot of build options for fine-grained control over your arcan
build. In this section we will just provide the bare essentials for a build
on Linux, BSD or OSX (windows can cheat with using the prebuilt installer
binaries) and you can check out the relevant sections in the wiki for more
detailed documentation on specialized build environments, e.g. an X.org-free
KMS/DRM. (https://github.com/letoram/arcan.wiki/linux-egl)

For starters, the easiest approach is to do the following:

     git clone https://github.com/letoram/arcan.git
     cd arcan
     mkdir build
     cd build
     cmake -DCMAKE_BUILD_TYPE="Debug" -DVIDEO_PLATFORM=sdl ../src
     make -j 12

The required dependencies for this build is cmake for compilation, and then
libsdl1.2, openal, opengl and freetype. There is also support for building some
of these dependencies statically, e.g.

     git clone https://github.com/letoram/arcan.git
     cd arcan/external/git
     ./clone.sh
     cd ../../
     mkdir build
     cd build
     cmake -DCMAKE_BUILD_TYPE="Debug" -DVIDEO_PLATFORM=sdl
      -DSTATIC_SQLITE3=ON -DSTATIC_OPENAL=ON -DSTATIC_FREETYPE=ON ../src
     make -j 12

LWA support is also disabled in the build configuration above. LWA stands for
lightweight arcan and provides a specialized build (arcan\_lwa) that uses the
arcan shared memory interface as an audio/video/input platform, allowing one
instance of arcan to act as a display server for others. It is a somewhat more
complex build in that it pulls down and builds a specialized/patched version
of OpenAL.

You can then test the build with:

     ./arcan -p ../data/resources/ ../data/appl/welcome

Which tells us to use shared resources from the ../data/resources directory,
and launch an application that resides as ../data/appl/welcome. If this path
isn't specified relative to current path (./ or ../) or absolute (/path/to),
the engine will try and search in the default 'applbase', which varies with
OS, but typically something like /usr/local/share/arcan/appl or to the current
user: /path/to/home/.arcan/appl

Now what?
One is to try out some of the more complex appls, like the desktop environment,
'durden'. Clone the repo:

    git clone https://github.com/letoram/durden.git
    arcan -p /my/home /path/to/checkout/durden

note that it's the durden subdirectory in the git, not the root. The reason
for the different sdtart path (-p /my/home) is to give read-only access to
the appl for the built-in resource browser.

Database
=====

Among the output binaries is one called arcan\_db. It is a tool that
can be used to manipulate the sqlite- database that the engine requires
for some features, e.g. application specific key/value store for settings,
but also for whitelisting execution.

An early design decision was that the Lua VM configuration should be very
restrictive -- no arbitrary creation / deletion of files, no arbitrary execution
etc. The database tool is used to specify explicitly permitted execution that
should not be modifable from the context of the running arcan application.

The following example attempts to illustrate how this works:

        arcan_db db.sqlite add_target example_app /some/binary -some -args
        arcan_db db.sqlite add_config example_app more_args -yes -why -not

An arcan application should now be able to:

        launch_target("example_app", "more_args", LAUNCH_EXTERNAL);

or

        vid = launch_target("example_app",
            "more_args", LAUNCH_INTERNAL, callback_function);

The first example would have the engine minimize and release as much
resources as possible (while still being able to resume at a later point),
execute the specified program and wake up again when the program finishes.

The second example would execute the program in the background, expect it to
be able to handle the engine shmif- API for audio/video/input cooperatively
or through an interposition library.

Frameservers
=====
It can be cumbersome to set up database entries to just test something.
Frameservers is a way of separating sensitive or crash-prone functions from
the main engine for purposes such as running games or playing back video.

In a default installation, they are prefixed with afsrv_ [game, encode,
decode, ...] and while they are best managed from the appl itself, you can
run them from the terminal as well. Which ones that are available depend on
the dependencies that were available at build time, but for starting a
libretro core for instance:

    ARCAN_ARG=core=/path/to/core:resource=/path/to/resourcefile afsrv_game

or video playback:

    ARCAN_ARG=file=/path/to/moviefile.mkv afsrv_decode

Filesystem Layout
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
				tools/ -- database tools, keymap conversion
        shmif/ -- engine<->frameserver IPC

    tests/ -- (fairly incomplete, development focus target now)
          api_coverage -- dynamically populated with contents from doc/
          benchmark -- scripts to pinpoint bottlenecks, driver problems etc.
          interactive -- quick/messy tests that are thrown together during
                         development to test/experiment with some features.
          security -- fuzzing tools, regression tests for possible CVEs etc.
          regression -- populated with test-cases that highlight reported bugs.
          exercises -- solutions to the exercises in the wiki.
          examples -- quick examples / snippets

