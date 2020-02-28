# arcan-trayicon

This is a simple tool that connects to arcan as an ICON. When you click on it,
it will negotiate for a 'handover' connection (an unidentified/ untyped child)
then execute a command-line specified program which inherits this connection.
If that is successful, the icon switches shape for as long as the child is
alive.

This is used to wrap most arcan- capable clients as a 'tray popup', but it can
potentially be used for other cases as well, be it an 'android homescreen' like
panel of app launchers, desktop icons and similar cases.

# building/compiling

The only external dependency is the arcan-shmif libraries via pkgtool and meson
as the build-system. If those can be found, it shouldn't be more work than:

    meson build
		cd build ; ninja

# running

Recall that the scripts running server side (appl, window-manager) needs to
actually expose connection points which permit the tray- kind of behavior.

In Durden, this is enabled and configured by going to (user-facing names):

    /Config/Statusbar/Buttons/Right/Add External

with the symbolic reference being something like:

    /global/settings/statusbar/buttons/right/add_external=tray

This should allow you to start:

    ARCAN_CONNPATH=tray arcan_trayicon /path/to/passive.svg /path/to/alive.svg /some/program/to/run

Which should appear up as an icon in your statusbar tray. Consult the Durden
documentation for more specific details on tuning the look and feel.

## text- mode

Trayicon can also be used to add text buttons with contents from a script or
from the commandline by using the source and width arguments. The following:

    ARCAN_CONNPATH=tray ./script.sh | arcan_trayicon --stdin -w 20

Would read lines from stdin, clamp them to -width output cells. The included
arcan-barsplit.rb ruby scripts reads lines from STDIN, and splits up into
multiple arcan\_trayicon invocations.
