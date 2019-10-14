# About

This tool is a trivial dynamic interposition library for providing some arcan UI
interfacing for binaries that are either entirely non-graphical, or using
some translation service (e.g. wayland and X clients) and therefore does
not behave like a normal shmif application would.

Inside the __constructor of the library it will try and make an arcan shmif
connection as a TUI window that directly invokes the built-in debug interface.

# Compiling

The only external dependency is the arcan-shmif libraries via pkgtool and
meson as the build-system. If those can be found, simply run:

    meson build
		cd build ; ninja

# Running

The dynamic library itself need to be loaded into the target application
somehow. There are numerous public and not-so public techniques for that,
which will be left to your imagination.

Something trivial for demonstration purposes would be just using the normal
facilities of the dynamic linker via the "PRELOAD" environment like this:

    LD_PRELOAD=/path/to/adbginject.so /my/other/application

Note that this has implications for binaries that execute others, as the
inherited environment would preload- in this library as well. To reduce this,
and some related problems, the default behavior is for the constructor to
remove the PRELOAD environment after executing. This may have implications
for other libraries that you want interposed, so depending on your dynamic
linker you might want to either modify the source here and remove the setenv
call, or at the least put adbginject last in the list of libraries.
