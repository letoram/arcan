# Tools

This folder contains optional tools that extend or complement Arcan
extending its feature-set or providing command-line wrappers for
engine features.

## Acfgfs
This tools is built separately and provides a virtual filesystem
for working with the format that durden (and others) provide over
a domain socket as means of accessing configuration 'as a file'.
It depends on FUSE3 and an OS that has an implementation for it.

## Aclip
This tool is built separately and provides clipboard integration,
similarly to how 'xclip' works for Xorg.

## Db
This tool is already built as part of the normal engine build, and
provides command-line access to updating database configuration.

## Aloadimage
This is a sandboxed image loader, supporting multi-process privilege
separation, playlists and so on - similar to xloadimage.

## VRbridge
This tools aggregates samples from VR related SDKs and binds into a
single avatar in a way that integrates with the core engine VR path.

## Waybridge
This tool act as a wayland service so that clients which speaks the
wayland protocol can connect to an arcan instance.

## Adbginject
This tool is used as an interposition library for bootstrapping
shmif-debugif with clients that otherwise do not use shmif.
