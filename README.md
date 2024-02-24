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

* For community contact, check out the IRC channel #arcan on irc.libera.chat
  and/or the [discord (invite-link)](https://discord.com/invite/sdNzrgXMn7)

* For developer information, see the HACKING.md

The github repository is going defunct thanks to Microsofts incresingly abusive
practices, and we are thus moving to self-hosted Fossil. The repository will be
synched to github for the time being, but no active development activities
there. See [fossil.arcan-fe.com](https://fossil.arcan-fe.com).

Getting Started
====

Some distributions, e.g. [voidlinux](https://voidlinux.org) have most of arcan
as part of its packages, so you can save yourself some work going for one of
those. Other ones with an active community would be through Nix (for example:
nix-shell -p arcan.all-wrapped).

Docker- container templates (mainly used for headless development and testing)
can be found here, quality varies wildly from bad to poor (just like Docker):
[dockerfiles](https://github.com/letoram/arcan-docker).

## Compiling from Source

There are many ways to tune the build steps in order to reduce dependencies.
There are even more ways to configure and integrate the components depending
on what you are going for; running as a native desktop or as an application
runtime inside another desktop?

Most options are exposed via the build output from running cmake on the src
directory.

For the sake of simplicity over size, there is a build preset, 'everything'
which is the one we will use here.

### Dependencies

Specific package names depend on your distribution, but common ones are:

    sqlite3, openal-soft, sdl2, opengl, luajit, gbm, kms, freetype, harfbuzz
    libxkbcommon

For more encoding and decoding options you might also want:

    libvlc-core (videolan), the ffmpeg suite, leptonica + tesseract (ocr)
    libvncserver libusb1, v4l2-loopback, mupdf

First we need some in-source dependencies that are cloned manually for now:

    git clone https://github.com/letoram/arcan.git
    cd arcan/external/git
    ./clone.sh
    cd ../../

These are typically not needed, the main use is for ensuring certain build
options that might vary between distributions (luajit) and to ensure that a
recoverable desktop can be statically linked and executed in an otherwise
broken userspace (so embedded bringup). The one exception is OpenAL which is
patched to be used by a special (arcan-lwa) build. This is slated for
refactoring to remove that dependency, but there are other priorities in the
way.

### Compiling

Now we can configure and build the main engine:

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

'welcome' is a name of a simple builtin welcome screen, *that will shut down
automatically after a few seconds*.

For something of more directly useful, you can try the builtin appl 'console':

    arcan console

Which should work just like your normal console command-line, but with the
added twist of being able to run (arcan compatible) graphical applications
as well. For other projects, see the 'Related Projects' further below.

If input devices are misbehaving, the quick and dirty 'eventtest' in:

    arcan /path/to/arcan/tests/interactive/eventtest

Might be useful in figuring out who to blame.

### SUID Notes

The produced egl-dri platform 'arcan' binary installs suid by default. This is
not strictly necessary unless some specific features are desired, e.g. laptop
backlight controls on Linux as those require access to sysfs and friends.

If that is not relevant, you can strip the suid property on the binary, but do
note that your current user still requires access to relevant /dev/input/event
and /dev/dri/cardN and /dev/dri/renderN files to work properly -- otherwise
input and/or graphics devices might not be detected or useable.

The binary does split off into a non-suid part that the main engine runs off
of, see posix/psep\_open.c for auditing what is being run with higher
privileges as well as the code for dropping privileges. The privileged process
is responsible for negotiating device access, implementing virtual-terminal
switching and as a watchdog for recovering the main process on live locks or
some GPU failures.

### Hook-Scripts

Another way to extend engine behavior regardless of the appl being used are
so called hook-scripts. These reside inside the 'system script path' covered
by the -T command-line argument, or the default of shared/arcan/scripts.

The idea is that these should be able to provide 'toggle on' features that
would need cooperation from within the engine, in order to do quick custom
modifications or help bridge other tools.

A good example is 'external\_input':

    arcan -H hooks/external_input.lua -H hooks/external_input.lua myappl

This would open up two connection points, 'extio\_1', 'extio\_2' that will
allow one client to connect and provide input that will appear to the 'myappl'
appl as coming from the engine.

These are covered in more detail in the manpage.

### Networking

Arcan-net is a binary that allows you to forward one or many arcan clients over
a network. It is built by default, and can be triggered both as a separate
network tool as well as being launched indirectly from shmif by setting
ARCAN\_CONNPATH=a12://id@host:port, or when issuing a migration request by the
window manager.

See also: src/a12/net/README.md and src/a12/net/HACKING.md.

### Wayland

The 'arcan-wayland' or 'waybridge', as it is refered to in some places is
binary adds support for wayland and X clients (via Xwayland). It can be run as
either a global system service, e.g.

    arcan-wayland -xwl

Or on a case by case basis, like:

    arcan-wayland -exec weston-terminal

For a compliant wayland client, and:

    arcan-wayland -exec-x11 xterm

For an X client. The 'per case' basis is recommended as it is safer and more
secure than letting multiple clients share the same bridge process, at a
negilable cost. The downside is that some complex clients that rely on making
multiple distinct wayland connections may fail to work properly. Firefox is a
known offender.

There is a number of tuning and troubleshooting options due to the complexity
of using wayland, consult the manpage and the --help toggle.

### Database

All runtime configuration is consolidated into a database, either the default
'arcan.sqlite' one or an explicitly set one (arcan -d mydb.sqlite).

This is used for platform specific options, engine specific options and for
trusted clients that the running scripts are allowed to start. It is also used
as a configuration key-value store for any arcan applications that are running.

As a quick example, this is how to inspect and modify keys that 'Durden'
are currently using:

    arcan_db show_appl durden
    arcan_db add_appl_kv durden shadow_on true

Advanced configuration for some video platforms can be set via the reserved
arcan appl name. This would, for instance, set the primary graphics card
device name for the 'egl-dri' platform version:

    arcan_db add_appl_kv arcan video_device=/dev/dri/card2

To add 'launch targets', you can use something like:

    arcan_db add_target net BIN /usr/bin/arcan-net -l netfwd
    arcan_db add_config arcan-net default 10.0.0.10 6666
    arcan_db add_target xterm BIN /usr/bin/arcan-wayland -exec-x11

This allow applications to start a program as a trusted child (that inherits
its connection primitives rather than to try and find them using some OS
dependent namespace). The example above would have spawned arcan-net in the
local mode where clients connecting to the 'netfwd' connpath would be
redirected to the server listening at 10.0.0.10:6666.

There are many controls and options for this tool, so it is suggested that you
look at its manpage for further detail and instructions.

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

Funding
=======

This project is funded through [NGI0 Entrust](https://nlnet.nl/entrust), a fund
established by [NLnet](https://nlnet.nl) with financial support from the
European Commission's [Next Generation Internet](https://ngi.eu) program. Learn
more at the [NLnet project page](https://nlnet.nl/Arcan-A12).

[<img src="https://nlnet.nl/logo/banner.png" alt="NLnet foundation logo" width="20%" />](https://nlnet.nl)
[<img src="https://nlnet.nl/image/logos/NGI0_tag.svg" alt="NGI Zero Logo" width="20%" />](https://nlnet.nl/entrust)

Related Projects
================

If you are not interested in developing something of your own, you will
likely find little use with the parts of this project alone. Here are some
projects that you might want to look into:

* [Durden](https://github.com/letoram/durden) is the main desktop
  environment that uses this project as its display server.

* [Safespaces](https://github.com/letoram/safespaces) is an experimental
  VR/3D desktop environment.

* [Pipeworld](https://github.com/letoram/pipeworld) is a dataflow
  (think excel) programming environment

* [Arcan-Devices](https://github.com/letoram/arcan-devices) accumulates
  extra drivers.

To get support for more types of clients and so on, there is also:

* Wayland support (see Wayland section above, and src/wayland/README.md).

* [QEmu](https://github.com/letoram/qemu) a patched QEmu version that
  adds a -ui arcan option.

* [Xarcan](https://github.com/letoram/xarcan) is a patched Xorg that
  allows you to run an X session 'as a window'.

* [nvim-arcan](https://github.com/letoram/nvim-arcan) is a neovim frontend
  that act as a native arcan client.

Tools
=====

There is also a number of helper tools that can be used to add certain
features, such as support for VR devices and tray-icons. These are built
separately and can be found in the tools/ subdirectory. They have their
own separate build systems and corresponding README.md files.

They work on the assumption that arcan and its respective libraries have been
built and installed. They are lockstepped and versioned to the engine, so if
you upgrade it, make sure to rebuild the tools as well.

The main tools of interest are:

## Acfgfs

Acfgfs is a tool that lets you mount certain arcan applications as a FUSE
file-system. The application has to explicitly support it. For the Durden
desktop environment, you can use global/settings/system/control=somename
and then:

    arcan_cfgfs --control=/path/to/durden/ipc/somename /mnt/desktop

And desktop control / configuration should be exposed in the specified
mountpoint.

## Aclip

Aclip is a clipboard manager similar to Xclip. It allows for bridging the
clipboard between a desktop environment like Durden, and that of an X server.

This requires that clipboard bridging has been allowed (disabled by default for
security reasons). In Durden this is activated via
global/settings/system/clipboard where you can control how much clipboard
access the tool gets.

## Aloadimage

Aloadimage is a simple sandboxing image loader, similar to xloadimage. It is
useful both for testing client behavior when developing applications using
arcan, but also as an image viewer in its own right, with reasonably fast image
loading, basic playlist controls and so on.

## Vrbridge

VR bridge is an optional input driver that provides the arcan\_vr binary which
adds support for various head-mounted displays. More detailed instructions on
its setup and use can be found as part of the Safespaces project mentioned in
the 'Related Projects 'section.

## Trayicon

Arcan-trayicon is a tool that chain-loads another arcan client, along with two
reference images (active and inactive). It tries to register itself in the
icon-tray of a running arcan application, though it must explicitly enable the
support. In Durden, this is done via the path:

    global/settings/statusbar/buttons/right/add_external=tray

Then you can use:

    ARCAN_CONNPATH=tray arcan-trayicon active.svg inactive.svg afsrv_terminal

Or some other arcan client that will then be loaded when the tray button is
clicked, confined into a popup and then killed off as the popup is destroyed.
This is a quick and convenient way to wrap various system services and external
command scripts.
