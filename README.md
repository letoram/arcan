Arcan
=====

Arcan is a powerful development framework for creating virtually anything between
user interfaces for specialized embedded applications all the way to
 full-blown standalone desktop environments.

At its heart lies a robust and portable multimedia engine, with a well-tested
and well-documented interface, programmable in Lua. At every step of the way,
the underlying development emphasizes security, performance and debuggability
guided by a principle of least surprise in terms of API design.

Among the more uncommon features we find:

 * A multi-process way of hooking up dynamic data-sources ("frameservers")
   such as online video streams, capture devices, and even other running
   programs as programmable objects for both graphics, audio and input.
   This permits aggressive sandboxing for what has historically been
   error-prone and security challenged tasks.

 * Capable of being its own compositor, display server and window manager at
   the same time. There are two build outputs, arcan and arcan\_lwa
   ('lightweight'). Arcan uses the underlying hardware to present aural and
   visual information and obtains input from external devices. Arcan\_lwa
   re-uses most of the same codebase and API, but uses arcan for input
   and output.

 * Built-in monitoring and crash-dump analysis. The engine can serialize vital 
   internal state to a Lua script ("crash dump") or to another
   version of itself periodically ("monitoring") to allow external filters and
   tools to be written quickly in order to track down bugs or suspicious
   activity.

 * Fallbacks -- Should the running application fail due to a programming error,
   (which can, of course, happen to any moderately complicated application),
   the engine will try to gracefully hand-over external data sources and
   connections to a fallback application that adopts control and tries to
   recover seamlessly.

 * Fine-grained sharing -- Advanced tasks that are notably difficult in some
   environments, e.g. recording / streaming controlled subsets of audio and
   video data sources (including 'desktop sharing') requires little more than
   a handful of lines of code to get going.

The primary development platforms are FreeBSD and Linux, but releases are
actively tested on both Windows and Mac OS X. While it works under various
display and input subsystems e.g. SDL, X etc. a primary goal is for the
framework applications to run with as few layers of ''abstraction'' in the
way as possible.

Getting Started
=====
The rest of this readme is directed towards developers. As an end- user,
you would probably do best to look/wait/encourage the development of-
applications that uses this project as a backend, or at the very least,
wait until it is available as a package in your favorite distribution.
For developers, the first step is, of course, getting the engine 
running (see building, below).

After that is done, there is a set of challenges and exercises in the wiki
to help you get a feel for the API, navigating documentation and so on.

Compiling
=====
There are a lot of build options for fine-grained control over your arcan
build. In this section we will just provide the bare essentials for a build
on linux, BSD or OSX (windows can cheat with using the prebuilt installer
binaries) and you can check out the relevant sections in the wiki for more
detailed documentation. For starters, the easiest approach is to do the following:

     git clone https://github.com/letoram/arcan.git
     cd arcan
     mkdir build
     cd build
     cmake -DCMAKE_BUILD_TYPE="Debug" -DENABLE_LWA=OFF 
         -DVIDEO_PLATFORM=sdl -DENABLE_NET=OFF -DENABLE_VIDDEC=OFF 
         -DENABLE_VIDENC=OFF -DENABLE_VIDENCVNC=OFF -DENABLE_REMOTING=OFF ../src
     make -j 12

The required dependencies for this build is cmake for compilation, and then
libsdl1.2, openal, opengl, glew and freetype. Enabling other features
introduces additional dependencies (apr for NET, libvlc for VIDDEC,
ffmpeg for VIDENC, vnc for VIDENCVNC and REMOTING).

You can then test the build with:

     ./arcan -p ../../data/resources/ ../../data/welcome

Which tells us to use shared resources from the ../../data/resources directory,
and launch an application that resides as ../../data/appl/welcome.

Other quick and dirty applications to test are those in ../../test/interactive.

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

Filesystem Layout
=====
The git-tree has the following structure:

    data/ -- files used for default packaging and installation (icons, etc.)
    doc/*.lua -- specially formatted script files (1:1 between Lua API
                 functions and .lua file in this folder) that is used
                 by doc/mangen.rb to generate manpages, test cases etc.
    doc/*.1   -- manpages for the binaries
    doc/*.pdf -- presentation slides (updated yearly)
    examples/ -- miniature projects that showcase some specific
                 non-obvious features

    src/
        engine/ -- main engine code-base
        external/ -- external dependencies that may be built in-source
        frameserver/ -- individual frameservers and support functions
        hijack/ -- interpose libraries for different data sources
        platform/ -- os/audio/video/etc. interfacing
        shmif/ -- engine<->frameserver IPC

    tests/ -- (fairly incomplete, development focus target now)
          api_coverage -- dynamically populated with contents from doc/
          benchmark -- scripts to pinpoint bottlenecks, driver problems etc.
          interactive -- quick/messy tests that are thrown together during
                         development to test/experiment with some features.
          security -- fuzzing tools, regression tests for possible CVEs etc.
          regression -- populated with test-cases that highlight reported bugs.
          exercises -- solutions to the exercises in the wiki.

