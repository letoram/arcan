#!/bin/sh
# arcan-desktop.sh — Source this from .bashrc/.zshrc to make desktop apps
# "just work" under arcan/durian.
#
# What it does:
#   - Qt apps:      sets QT_QPA_PLATFORM=arcan (uses qtarcan plugin)
#   - X11 apps:     auto-starts Xarcan, sets DISPLAY
#   - Wayland apps: auto-starts arcan-wayland, sets WAYLAND_DISPLAY
#   - Games:        provides arcan-gamescope wrapper
#
# Usage:
#   echo '. /usr/share/arcan/arcan-desktop.sh' >> ~/.bashrc
#
# Or with a custom install prefix:
#   ARCAN_PREFIX=/home/x/test/arcan/zig-out . /path/to/arcan-desktop.sh

# Only activate under arcan (ARCAN_CONNPATH is set by arcan for child processes)
[ -z "$ARCAN_CONNPATH" ] && return 2>/dev/null

_arcan_prefix="${ARCAN_PREFIX:-/usr/local}"
_arcan_runtime="${XDG_RUNTIME_DIR:-/tmp}/arcan-desktop-$$"

# ── Qt apps (qtarcan QPA plugin) ──
if [ -d "${_arcan_prefix}/lib/qt/plugins/platforms" ]; then
    export QT_QPA_PLATFORM=arcan
    export QT_PLUGIN_PATH="${_arcan_prefix}/lib/qt/plugins${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
fi

# ── X11 apps (Xarcan) ──
# Auto-start Xarcan if not already running and binary exists
_arcan_start_xarcan() {
    command -v Xarcan >/dev/null 2>&1 || return

    # Already have a DISPLAY? Don't interfere
    [ -n "$DISPLAY" ] && return

    # Check if another arcan session already started Xarcan
    local lockfile="${XDG_RUNTIME_DIR:-/tmp}/.arcan-xarcan-display"
    if [ -f "$lockfile" ]; then
        local saved_display
        saved_display=$(cat "$lockfile")
        # Verify the X server is still running
        if [ -e "/tmp/.X11-unix/X${saved_display#:}" ]; then
            export DISPLAY="$saved_display"
            return
        fi
        rm -f "$lockfile"
    fi

    # Find a free display number
    local n=1
    while [ -e "/tmp/.X${n}-lock" ] || [ -e "/tmp/.X11-unix/X${n}" ]; do
        n=$((n + 1))
    done

    export DISPLAY=":${n}"
    Xarcan "$DISPLAY" >/dev/null 2>&1 &
    echo "$DISPLAY" > "$lockfile"
}
_arcan_start_xarcan

# ── Wayland apps (arcan-wayland bridge) ──
_arcan_start_wayland() {
    command -v arcan-wayland >/dev/null 2>&1 || return

    # Already have WAYLAND_DISPLAY? Don't interfere
    [ -n "$WAYLAND_DISPLAY" ] && return

    local lockfile="${XDG_RUNTIME_DIR:-/tmp}/.arcan-wayland-display"
    if [ -f "$lockfile" ]; then
        local saved
        saved=$(cat "$lockfile")
        if [ -e "${XDG_RUNTIME_DIR:-/tmp}/${saved}" ]; then
            export WAYLAND_DISPLAY="$saved"
            return
        fi
        rm -f "$lockfile"
    fi

    # arcan-wayland creates its own socket name
    export WAYLAND_DISPLAY="arcan-wayland-0"
    arcan-wayland -xwl >/dev/null 2>&1 &
    echo "$WAYLAND_DISPLAY" > "$lockfile"
}
# Uncomment to auto-start wayland bridge:
# _arcan_start_wayland

# ── gamescope wrapper ──
# Usage: arcan-gamescope [gamescope-opts] -- command [args...]
# Example: arcan-gamescope -w 1920 -h 1080 -- steam
arcan-gamescope() {
    if command -v gamescope >/dev/null 2>&1; then
        gamescope "$@"
    else
        echo "gamescope not found in PATH" >&2
        return 1
    fi
}

# Add arcan binaries to PATH if not already there
case ":$PATH:" in
    *":${_arcan_prefix}/bin:"*) ;;
    *) export PATH="${_arcan_prefix}/bin:$PATH" ;;
esac

unset _arcan_prefix _arcan_runtime
