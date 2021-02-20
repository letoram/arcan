# arcan-dbgcapture

This is a quick and dirty debugging tool that uses arcan-tui as a frontend to
launch a debugger or otherwise interactively control what to do with a process
that has crashed.

# building/compiling

The only external dependency is the arcan-shmif libraries via pkgtool and meson
as the build-system. If those can be found, it shouldn't be more work than:

    meson build
    cd build ; ninja

# running

Set as the core-dump handler. This requires root privileges, but as soon as the
relevant proc data has been scraped, will be dropped to username. If this
cannot be resolved, the process will remain as root.

    arcan-dbgcapture corepath username xdgrtpath connpoint pid

Where corepath should be '-' for stdin, xdgrtpath (depending on os/dist/user)
must match the XDG_RUNTIME_DIR that the user running the arcan instance with
the connection point is also using.

Due to how the core_pattern handler is invoked, any failures won't be visible.
'username' is the user that the capture will switch to after it has retreived
the core dump and source binary.

On linux, this typically becomes:

    echo "|/usr/bin/arcan-dbgcapture - root /path/to/runtimedir durden %P" > /proc/sys/kernel/core_pattern

The core pattern needs an absolute path for the tool to be invoked. You can
also use it on a preset core file with a pid argument, but that is mainly
intended for testing.

Interestingly enough, a networked connpath can also be set, e.g.

    dbgcapture - root /tmp a12://some.host %P

Be careful with this one though, arcan-net will run as the marked user with all
the dangers that implies. home-lab or from container to outside is the intended
context.

# Notes

Internally, the core-dump will be written to a temporary file, which is unlinked
after gdb has opened it. The file can still be accessed via the normal tui means
for server-side initiated 'save', optionally also with the source binary.
