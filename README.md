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

* For community contact, check out the IRC channel #arcan on irc.freenode.net.

* For developer information, see the HACKING.md

Getting Started
====

Some distributions, e.g. [voidlinux](https://voidlinux.org) have most of arcan
as part of its packages, so you can save yourself some work going for one of
those.

## Compiling from Source

There are many ways to tune the build steps in order to reduce dependencies.
There are even more ways to configure and integrate the components depending
on what you are going for,

Most options are exposed via the build output from running cmake on the src
directory.

For the sake of simplicity over size, there is a build preset, 'everything'
which is the one we will use here.

### Dependencies

Specific package names depend on your distribution, but common ones are:

    sqlite3, openal-soft, sdl2, opengl, luajit, gbm, kms, freetype, harfbuzz
		libxkbcommon

For encoding and decoding options you would also want:

    libvlc-core (videolan), the ffmpeg suite, leptonica, tesseract
		libvncserver libusb1

First we need some in-source dependencies that are cloned manually:

    git clone https://github.com/letoram/arcan.git
		cd external/git
		../clone.sh
		cd ../arcan

### Compiling

Then we can configure and build the main engine:

		mkdir build
		cd build
		cmake -DBUILD_PRESET="everything" ../src

Like with other CMake based projects, you can add:

    -DCMAKE_BUILD_TYPE=Debug

To switch from a release build to a debug one.

When it has finished probing dependencies, you will get a report of which
dependencies that has been found and which features that were turned on/off,
or alert you if some of the required dependencies could not be found.

Make and install like normal (i.e. make, sudo make install). A number of
binaries are produced, with the 'main' one being called simply arcan. To
test 'in source' (without installing) you should be able to run:

     ./arcan -T ../data/scripts -p ../data/resources ../data/appl/welcome

The -T argument sets our built-in/shared set of scripts, the -p where shared
resources like fonts and so on can be found, and the last argument being
the actual 'script' to run.

With installation, this should reduce to:

     arcan welcome

It will automatically try to figure out if it should be a native display
server or run nested within another or even itself based on the presence
of various environment variables (DISPLAY, WAYLAND\_DISPLAY, ARCAN\_CONNPATH).

'welcome' is a name of a simple builtin welcome screen, that will shut down
automatically after a few seconds of use. For something of more directly
useful, you can try the builtin appl 'console':

    arcan console

Which should work just like your normal console command-line, but with the
added twist of being able to run (arcan compatible) graphical applications
as well.

### Headless Mode

The 'everything' build option should also produce a binary called
'arcan\_headless', at least on BSDs and Linux. This binary can be used to run
arcan without interfering with your other graphics and display system. Given
access to a 'render node' (/dev/dri/renderD128 and so on) and it should also
work fine inside containers and other strict sandboxing solutions.

To make it useful, it can record/stream to a virtual screen. An example of
such a setup following the example above would be:

    ARCAN_VIDEO_ENCODE=protocol=vnc arcan_headless console

Assuming the build-system found the libvncserver dependency, this should
leave you with an exposed (insecure, unprotected, ...) vnc server at
localhost+5900. See afsrv\_encode for a list of arguments that can be added
to the encode environment in order to control what happens.

### Related Projects

If you are not interested in developing something of your own, you will
likely find little use with the parts of this project alone. Here are some
projects that you might want to look into:

* [Durden](https://github.com/letoram/durden) is the main desktop
  environment that uses this project as its display server.

* [Safespaces](https://github.com/letoram/safespaces) is an experimental
  VR/3D desktop environment.

* [Prio](https://github.com/letoram/prio) is a simple window manager
  that mimics Plan9- Rio.

To get support for more types of clients and so on, there is also:

* [QEmu](https://github.com/letoram/qemu) a patched QEmu version that
  adds a -ui arcan option.

* [Xarcan](https://github.com/letoram/xarcan) is a patched Xorg that
  allows you to run an X session 'as a window'.

### Configuration Tool (arcan\_db)

All runtime configuration is consolidated into a database, either the default
'arcan.sqlite' one or an explicitly set one (arcan -d mydb.sqlite). This is
used for platform specific options, engine specific options and for specifying
trusted clients that the running scripts are allowed to start.

This database can be inspected and modified using the 'arcan\_db' binary
that the build produces. See its specific manpage for more details on its
various uses.

### Tools

The default build above does not include any support tools other than the
configuration tool, arcan\_db. There are others, located in the 'tools'
subdirectory. Refer to their specific READMEs for further instructions.

The main tools of interest are:

* acfgfs : a FUSE driver for mounting some application config as a file system
* aclip : clipboard manager similar to 'xclip'
* aloadimage : simple sandboxing image viewer
* netproxy : tools for routing clients over a network
* vrbridge : device drivers for vr support
* waybridge : service for enabling Wayland clients
