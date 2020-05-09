# arcan-net

This tool provides network translation for clients and services built
using the arcan-shmif IPC client library. The code is still in an
immature state, tunnel over VPN/SSH if you worry about the safety of
your traffic.

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

    ARCAN_CONNPATH=a12://keyfile@host:port some_client

Host and keys are resolved from a path structure using a basedir
set on the command-line:

    arcan-net -b $HOME/.config/a12 -s test keyfile@myhost

or as an environment:

    A12_BASE_DIR=$HOME/.config/a12 arcan-net -s test myhost

In that case, the user argument will be used to grab private key from:

    basedir/keys/keyfile

Where the keyfile name is restricted to visible [a-Z0-9] part of the ASCII set
of characters. The key is, per x25519, 32-bytes crypotgraphically secure
randomness. If the file has that size, it will be interpreted as such. If it is
larger than that, all leading bytes will be treated as a line separated list of
hosts. e.g.

    myhost1:port
		10.0.1.20:port
		myhost20:port
		<32b random>

This means that you can simply reference:

    ARCAN_CONNPATH=a12://keyname some_software

And it will try the list in sequential priority until one connects, or migrate
should the server- end of the connection fail hard.

For the server side, authenticated public keys are retrieved from:

    basedir/allowed_keys/*

These can be populated by allowing a one-time auth session:

    echo 'temporarypassword' | arcan-net -a 1 -l 6666

Which would accept the next public key that authenticate with
'temporarypassword' and write into the keystore.

This is strictly for bootstrapping a system where it is inconvenient to add the
public key using some other media.

There is no equivalent to the "I don't know this key please just type yes"
form of key authentication that SSH allows.

To provide an authentication word to your key:

    ARCAN_CONNPATH=a12://keyname
		echo 'temporarypassword' | arcan-net -a -s test host port

If the _cache_ subdirectory is present in the basedir, it will be used
as a scratch folder for caching some binary transfers, e.g. fonts.

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
on the timeline the respective features will be developed/available. The
parts marked with (a) refer to arcan-net tool, (p) the protocol, and (x)
for extended/engine/aux parts.

Milestone 1 - basic features (0.5.x)

- [x] Basic API (p)
- [x] Control (p)
- [x] net (TCP) (a)
- [x] Uncompressed Video / Video delta (p)
- [x] Uncompressed Audio / Audio delta (p)
- [x] Compressed Video (p)
	-  [x] x264 (p)
	-  [x] D-PNG (d- frames is Zlib(X ^ Y) (p)
- [x] Raw binary descriptor transfers (p)
- [ ] Interactive compression controls (a)
- [x] Subsegments (p)
- [x] Basic authentication / DH / Cipher (blake2+chacha8+x25519) (ap)
- [x] One-time password for key-auth (p)
- [x] TUI- text channel (p)
- [ ] Cache process / directory for file operations (a)
- [x] ARCAN\_CONNPATH=a12:// handover support (ax)
- [ ] Block push-segment types (DEBUG) (a)
- [x] Add to encode, remoting (x)

Milestone 2 - closer to useful (0.6.x)

- [ ] Event key-code translation (evdev, sdl, ... to native) (a)
- [ ] Complete local key-store management (a)
- [ ] Basic privsep/sandboxing (a)
- [ ] External key-provider / negotiation (a)
  -  [ ] FIDO2 (through libfido2) (a)
- [ ] Preferred-hosts list migration / handover (a)
  - [ ] Config for retry limits, sleep delays and backoff (a)
- [ ] Output segments (p)
- [ ] Compression Heuristics for binary transfers (entropy estimation)(p)
- [ ] Pipe pack/unpack option (a)
- [ ] Quad-tree for DPNG (p)
  - [ ] Tile-map and caching (p)
	- [ ] Evaluate if LZ4 is a better fit than DEFLATE
- [ ] Jpeg-XL progressive mode (p)
- [ ] Frame Cancellation / dynamic framerate on window drift (p)
- [ ] vframe-caching on certain types (first-frame on new, ...) (p)
- [ ] vframe-runahead / forward latency estimation (a)
- [ ] (Scheduling), better A / V / E interleaving (a)
- [ ] Passthrough of compressed video sources (a)
- [ ] Traffic monitoring tools (re-use proxy code + inherit mode) (x)
- [ ] Splicing / Local mirroring (a)
- [ ] Rekeying / Key Deletion (Forward Secrecy) (p)
- [ ] Add TUI- mode for -net with statistics / controls (a)
  - [ ] Show unauthenticated public keys as QR code in window (a)
- [ ] Fexec(self) handover on completed negotiation (p)(a)

Milestone 3 - big stretch (0.6.x)

- [ ] Embed binary transfer progress into parent window (p)
- [ ] Dynamic audio resampling (p)
- [ ] Media- segment buffering window, controls and progress (p)
- [ ] UDP based carrier (UDT) (a)
- [ ] 'ALT' arcan-lwa interfacing (px)
- [ ] 'AGP' level- packing (px)
- [ ] Optimized version of ChaCha / BLAKE (avx, neon, ...) (p)
  - [ ] Evaluate in-place merged encrypt+mac instead of enc then mac
- [ ] ZSTD with dictionary on whole source (p)
- [ ] Subprotocols (p)
  - [ ] VR
	- [ ] HDR
	- [ ] 3DOBJ
	- [ ] Open3DGC
- [ ] Defered input oscillator safety buffer (a)
- [ ] Per stream-type key (p)
- [ ] Externalize A/V decoding (p)
- [ ] Dynamic encoding parameters (p)
- [ ] Side-channel Resistance (ax)
- [ ] Directory/Rendezvous Server (axp)
- [ ] Add to afsrv\_net (x)
- [ ] Fast-forward known partial binary transfer (resume)
- [ ] Resume- session from different IP (ap)
- [ ] N-Key connection-unlock and monitors (a)
- [ ] Clean-up, RFC level documentation (p)

# Licenses

arcan-net is (c) Bjorn Stahl 2017-2020 and licensed under the 3-clause BSD
license. It is dependent on BLAKE3- (CC or Apache-2.0, see COPYING.BLAKE3)
, on ChaCha8, x25519 (Public Domain) and Miniz (MIT-like, see miniz/LICENSE).

optional dependencies include ffmpeg- suite of video codecs, GPLv2 with
possible patent implications.
