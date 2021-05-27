setting things up here requires a bit more:

    arcan_db BIN xarcan /path/to/some/xarcan.sh

inside Xarcan.sh (corresponds to your startx like script)

    ID=`/path/to/Xarcan -displayfd 1 2>/dev/null &'
		DISPLAY=":$ID"
		export DISPLAY
		wmaker

with wmaker substituted for whatever window manager to test
as a 'driver'. To troubleshoot, use F5 to generate .lua,
.svg and .dot snapshot outputs.

The .dots can be viewed with:

    dot -Tsvg xorg_blabla.dot > test.svg
