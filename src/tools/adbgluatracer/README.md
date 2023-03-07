# About

This is a debug utility for tracing realtime Arcan appl LuaJIT VM state.

# Compiling

The external dependencies are the arcan-shmif libraries and luajit library
which are resolved using pkgtool. The used build system is meson.
If those can be found, simply run:

    meson build
    cd build ; meson compile

# Running

The dynamic library itself need to be loaded into the target application
somehow. There are numerous public and not-so public techniques for that,
which will be left to your imagination.

Something trivial for demonstration purposes would be just using the normal
facilities of the dynamic linker via the "PRELOAD" environment like this:

    LD_PRELOAD=/path/to/adbgluatracer.so /my/other/application

Note that this has implications for binaries that execute others, as the
inherited environment would preload- in this library as well. To reduce this,
and some related problems, the default behavior is for the constructor to
remove the PRELOAD environment after executing. This may have implications
for other libraries that you want interposed, so depending on your dynamic
linker you might want to either modify the source here and remove the setenv
call, or at the least put adbginject last in the list of libraries.
