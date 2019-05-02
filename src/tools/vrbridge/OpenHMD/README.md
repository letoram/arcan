# OpenHMD
This project aims to provide a Free and Open Source API and drivers for immersive technology, such as head mounted displays with built in head tracking.

## License
OpenHMD is released under the permissive Boost Software License (see LICENSE for more information), to make sure it can be linked and distributed with both free and non-free software. While it doesn't require contribution from the users, it is still very appreciated.

## Supported Devices
For a full list of supported devices please check https://github.com/OpenHMD/OpenHMD/wiki/Support-List

## Supported Platforms
  * Linux
  * Windows
  * OS X
  * Android
  * FreeBSD

## Requirements
  * Option 1: Meson + Ninja
    * http://mesonbuild.com
    * https://ninja-build.org
  * Option 2: GNU Autotools (if you're building from the git repository)
  * Option 3: CMake
  * HIDAPI
    * http://www.signal11.us/oss/hidapi/
    * https://github.com/signal11/hidapi/

## Language Bindings
  * GO bindings by Marko (Apfel)
    * https://github.com/Apfel/OpenHMD-GO
  * Java bindings by Joey Ferwerda and Koen Mertens
    * https://github.com/OpenHMD/OpenHMD-Java
  * .NET bindings by Jurrien Fakkeldij
    * https://github.com/jurrien-fakkeldij/OpenHMD.NET
  * Perl bindings by CandyAngel
    * https://github.com/CandyAngel/perl-openhmd
  * Python bindings by Lubosz Sarnecki
    * https://github.com/lubosz/python-rift
  * Rust bindings by The\_HellBox
    * https://github.com/TheHellBox/openhmd-rs

## Other FOSS HMD Drivers
  * libvr - http://hg.sitedethib.com/libvr

## Compiling and Installing
Using Meson:

With Meson, you can enable and disable drivers to compile OpenHMD with.
Current available drivers are: rift, deepon, psvr, vive, nolo, wmr, external, and android.
These can be enabled or disabled by adding -Ddrivers=... with a comma separated list after the meson command (or using meson configure ./build -Ddrivers=...).
By default all drivers except android are enabled.

    meson ./build [-Dexamples=simple,opengl]
    ninja -C ./build
    sudo ninja -C ./build install

Using make:

    ./autogen.sh # (if you're building from the git repository)
    ./configure [--enable-openglexample]
    make
    sudo make install

Using CMake:

With CMake, you can enable and disable drivers to compile OpenHMD with.
Current Available drivers are: OPENHMD_DRIVER_OCULUS_RIFT, OPENHMD_DRIVER_DEEPOON, OPENHMD_DRIVER_WMR, OPENHMD_DRIVER_PSVR, OPENHMD_DRIVER_HTC_VIVE, OPENHMD_DRIVER_NOLO, OPENHMD_DRIVER_EXTERNAL and OPENHMD_DRIVER_ANDROID.
These can be enabled or disabled adding -DDRIVER_OF_CHOICE=ON after the cmake command (or using cmake-gui).

    mkdir build
    cd build
    cmake ..
    make
    sudo make install

### Configuring udev on Linux
To avoid having to run your applications as root to access USB devices you have to add a udev rule (this will be included in .deb packages, etc).

A full list of known usb devices and instructions on how to add them can be found on:
https://github.com/OpenHMD/OpenHMD/wiki/Udev-rules-list

After this you have to unplug your device and plug it back in. You should now be able to access the HMD as a normal user.

### Compiling on Windows
CMake has a lot of generators available for IDE's and build systems.
The easiest way to find one that fits your system is by checking the supported generators for you CMake version online.
Example using VC2013.

	cmake . -G "Visual Studio 12 2013 Win64"

This will generate a project file for Visual Studio 2013 for 64 bit systems.
Open the project file and compile as you usually would do.

### Cross compiling for windows using mingw
Using Make:

    export PREFIX=/usr/i686-w64-mingw32/ (or whatever your mingw path is)
    PKG_CONFIG_LIBDIR=$PREFIX/lib/pkgconfig ./configure --build=`gcc -dumpmachine` --host=i686-w64-mingw32 --prefix=$PREFIX
    make

the library will end up in the .lib directory, you can use microsoft's lib.exe to make a .lib file for it

Using CMake:

For MinGW cross compiling, toolchain files tend to be the best solution.
Please check the CMake documentation on how to do this.
A starting point might be the CMake wiki: http://www.vtk.org/Wiki/CmakeMingw

### Static linking on windows
If you're linking statically with OpenHMD using windows/mingw you have to make sure the macro OHMD_STATIC is set before including openhmd.h. In GCC this can be done by adding the compiler flag -DOHMD_STATIC, and with msvc it can be done using /DOHMD_STATIC.

Note that this is *only* if you're linking statically! If you're using the DLL then you *must not* define OHMD_STATIC. (If you're not sure then you're probably linking dynamically and won't have to worry about this).

## Pre-built packages
A list of pre-built backages can be found on http://www.openhmd.net/index.php/download/

## Using OpenHMD
See the examples/ subdirectory for usage examples. The OpenGL example is not built by default, to build it use the --enable-openglexample option for the configure script. It requires SDL2, glew and OpenGL.

An API reference can be generated using doxygen and is also available here: http://openhmd.net/doxygen/0.1.0/openhmd_8h.html
