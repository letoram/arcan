# arcan-net

This tool provides network translation for clients and services built
using the arcan-shmif IPC client library. This is an opt-in tool and
not part of the 'net' frameserver for the time being due to the immature
state and _unverified_ _incomplete_ _unhardened_ state of the crypto
implementation (see HACKING.md).

Basic use is as follows:

On the receiving display server side where you want clients to be
presented, simply run:

    arcan-net -l 6666

Where 6666 is any port of your choice. On the side where you have
clients to forward, a few more arguments are needed:

    arcan-net -s cpoint 10.0.0.1 6666

Where the 10.0.0.1 is substituted with the IP or host of the server
that is running, with the port matching the one chosen there. This
will allow shmif clients to start with:

    ARCAN_CONNPATH=cpoint some_client

Individual clients can also perform setup with less effort:

    ARCAN_CONNPATH=a12://user@host:port some_client

# Compilation

For proper video encoding, the ffmpeg libraries (libavcodec, libswscale,
...) are required and must have h264 support. Due to patent or licensing
issues that may or may not apply, check you distribution and build.

If ffmpeg reports errors, is missing or is missing h264 support entirely
the system will fallback to raw- or only lightly- compressed buffers.

# Use / Testing

The easiest way to test on a local system that already has arcan and one
WM running with a terminal that has the ARCAN\_CONNPATH environment:

    arcan-net -l 6666
		arcan-net -s test localhost 6666
		ARCAN_CONNPATH=test afsrv_terminal

# Todo

The following are basic expected TODO points and an estimate as to where
on the timeline the respective features will be developed/available.

Milestone 1 - basic features (0.5.x)

- [x] Basic API
- [x] Control
- [x] net (TCP)
- [x] Uncompressed Video / Video delta
- [x] Uncompressed Audio / Audio delta
- [x] Compressed Video
	-  [x] x264
	-  [x] xor-PNG
- [x] Raw binary descriptor transfers
- [ ] Interactive compression controls
- [x] Subsegments
- [ ] Basic authentication / DH / Cipher (blake+chacha20+curve25519)
- [ ] Basic privsep/sandboxing
- [x] TUI- text channel
- [ ] Event key-code translation (evdev, sdl, ... to native)
- [ ] Cache process / directory for file operations
- [ ] Block push-segment types (DEBUG)

Milestone 2 - closer to useful (0.6.x)

- [ ] Output segments
- [ ] Add to encode, remoting (libify and compile into fsrv_encode)
- [ ] Modify ARCAN\_CONNPATH so that it can take a remote URL
- [ ] Compression Heuristics for binary transfers
- [ ] Quad-tree for DPNG
- [ ] "MJPG" mode over DPNG
- [ ] Frame Cancellation
- [ ] vframe- caching on certain types (first-frame on new, ...)
- [ ] vframe-runahead
- [ ] (Scheduling), better A / V / E interleaving
- [ ] Progressive / threaded video encoding frontend
- [ ] Accelerated encoding of gpu-handles
- [ ] Passthrough of compressed video sources
- [ ] Traffic monitoring tools
- [ ] Splicing / Local mirroring
- [ ] Rekeying / Key Deletion (Forward Secrecy)

Milestone 3 - big stretch (0.6.x)

- [ ] Embed binary transfer progress into parent window
- [ ] Dynamic audio resampling
- [ ] Media- segment buffering window, controls and progress
- [ ] UDP based carrier (UDT)
- [ ] 'ALT' arcan-lwa interfacing
- [ ] 'AGP' level- packing
- [ ] ZSTD with dictionary on whole source
- [ ] Subprotocols (vobj, gamma, ...)
- [ ] Open3DGC (vr, obj mode)
- [ ] HDR / gamma
- [ ] Defered input oscillator safety buffer
- [ ] Per type ephemeral key
- [ ] Congestion control / dynamic encoding parameters
- [ ] Side-channel Resistance
- [ ] Directory Server and auth-DoS protection (see MinimaLT)
- [ ] Special provisions for agp channels
- [ ] Add to arcan\_net
- [ ] Resume- session from different IP
- [ ] Secure keystore
- [ ] Clean-up, RFC level documentation

# Security/Safety

Right now, assume that there is no guarantees on neither confidentiality,
integrity or availability. As can be seen in the todo list, this won't remain
the case but there are other priorities to sort out first.

For arcan-net, you are currently restricted to symmetric primitives
derived from the password expected to be provided as env or on stdin.

# Licenses

arcan-net is (c) Bjorn Stahl 2017-2019 and licensed under the 3-clause BSD
license. It is dependent on BLAKE2- (CC or Apache-2.0, see COPYING.BLAKE2)
, on ChaCha20 (Public Domain) and Miniz (MIT-like, see miniz/LICENSE).

optional dependencies include ffmpeg- suite of video codecs, GPLv2 with
possible patent implications.
