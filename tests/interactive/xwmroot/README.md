This appl is for testing Xarcan in the 'forced decomposition' mode where
a single composed root is broken up into surfaces baseed on xarcan sending
metadata and the compositing end is slicing that up into local surfaces.

It requires more work in the appl end, but has a lower overhead than letting
Xarcan redirect each surface. Both has their uses.

setting things up here requires a bit more:

    arcan_db BIN xarcan /path/to/Xarcan -wmexec wmaker

with wmaker substituted for whatever window manager to test as a 'driver'. To
troubleshoot, use F5 to generate .lua, .svg and .dot snapshot outputs.

The .dots can be viewed with:

    dot -Tsvg xorg_blabla.dot > test.svg
