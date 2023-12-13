# arcan-net

This tool provides network translation for clients and services built using the
arcan-shmif IPC client library. The code is still in an immature state, tunnel
over VPN/SSH if you worry about the confidentiality, privacy and integrity of
your traffic.

# Basic Use

It can serve and access arcan-shmif clients over the a12 protocol in both a
'pull' fashion where you make an outbound connection to an a12 server that
serves you an application, and a 'push' one where you listen for inbound
connections and applications connect to you.

## Pull
The 'pull' model then is when you connect to an application 'server'.

The 'pull' mode is the simpler default setup, and arcan-net knows to use it due
to the absence of the '-s' argument or the ARCAN_CONNPATH=a12.. environment.

The server end is setup as follows:

    arcan-net -l 6680 -- /some/arcan/executable arg1 arg2 .. argn

Whenever a client connects and authenticates, the executable will be fired up
and presented to the client.

The client end then simply specifies:

    arcan-net remote.ip 6680

## Push

The 'push' model has traditionally been used with X11 implementations by
setting the DISPLAY environment variable or through some SSH tricks.

The corresponding version here is through ARCAN_CONNPATH:

    ARCAN_CONNPATH=a12://host:port some_arcan_client

You can also use a keyfile (see keystore further below)

    ARCAN_CONNPATH=a12://mytag@ some_arcan_client

There is also a 'service mode' that is easier for testing/debugging/development:

    arcan-net -s myname host:port
		ARCAN_CONNPATH=myname some_arcan_client
		ARCAN_CONNPATH=myname another_arcan_client

This is also suitable when using 'migration' where you explicitly redirect
a client to another 'connection point' (myname in the example above). How
this is activated depends on your window manager. For instance, in durden
it can be done through the /target/share/migrate=myname path.

There also needs to be something listening on the other end (of course)
that can bridge to the right arcan instance.

    arcan-net -l 6680
		ARCAN_CONNPATH=durden arcan-net -l 6680

# Directory

Another way of using arcan-net is to have it act in 'directory' mode. This is
experimental and currently actively developed.

In directory mode, the ARCAN\_APPLBASEPATH can be enumerated by connected
clients and any present appl can be downloaded and executed. Before enabling
a server in directory mode, one should verify that there is no sensitive data
in the path. On normal/default setups this is supported by appl output being
directed to a separate 'appltemp' namespace by default, letting applbase be
read-only.

If the public key a client uses is trusted (in keystore), it can also be used
as a state store for storing/restoring the appl execution state. It can also
be used to dynamically update the hosted appl, letting connected clients switch
automatically:

    arcan-net --push-appl myappl @myserver

It is also possible to share access to arcan clients dynamically:

    A12_IDENT=me ARCAN_CONNPATH=a12://myserver@ /usr/bin/afsrv_terminal

Would expose a single instance of 'afsrv\_terminal' as 'me', letting someone
else access it:

    arcan-net --keep-alive @myserver /me

The above would connect to the directory, wait for the 'me' source to be
announced as available and request to source it.

This retains end to end encryption of the data stream, and can be used to learn
about public keys from this trusted third party in order to reconnect with
their owners them through some other means later.

The default form of this creates a direct sink to source outbound connection.
In cases where that network traffic is not possible, the directory server can
act as a tunnel:

    arcan-net --tunnel

This is permitted by default by a directory server but can be toggled off with
--block-tunnel:

    arcan-net --directory --block-tunnel -l 6680

# Cache

Some types of A12 sources support letting the sink define the font that will be
used for rendering, notable the default arcan terminal.

For unicode features to work, both sides need to be aware of the capabilities
of the font set, which can add noticeable delays to startup. Since such
preferences tend to be static, font transfers can be preempted by setting a
cache.

This is defined through the A12\_CACHE\_DIR environment variable, if set, font
transfers will have the B64 form of their checksum stored locally. A transfer
that has a local match will be cancelled and substituted with the local form.

This feature is also intended for large base transfers, notably static base
images for sinks like Qemu - and possibly merkle-tree transfer/resume like
scenarios for large clipboard/drag-and-drop.

# Keystore

arcan-net does not mandate a specific public key infrastructure or necessarily
a 'trust on first use' kind of scheme, though there is some support for
enabling the later. The way cryptographic keys and identities are used are as
follows:

The argument '-b' is used to set a basedir. This directory is used for things
such as keystore as well as for caching for faster transfers and compression
(if the 'cache' subdirectory is present).

    arcan-net -b $HOME/.config/a12 -s test mymachine@

This would setup the 'push' mode to authenticate remotely using the host and
cryptographic keys specified in the keyfile for 'mymachine' within the keystore
in the basedir.

    $HOME/.config/a12/keys/mymachine

Where the keyfile name is restricted to visible [a-Z0-9] part of the ASCII set
of characters. The key is, per x25519, 32-bytes crypotgraphically secure
randomness. There can be multiple hosts per keyfile and the first whitespace on
each line separates key from b64 encoded private key.

    myhost1:port b64encoded-privk
		10.0.1.20:port b64encoded-privk

This means that you can simply reference:

    ARCAN_CONNPATH=a12://keyname@ some_software

And it will try the list in sequential priority until one connects, or migrate
should the server- end of the connection fail hard.

For verifying the identity of the other end, a different folder is used:

    basedir/allowed_keys/*

Each file in that format will be treated as a raw binary x25519 public key.
Anyone with a matching private key in there will be allowed to connect.

These can be populated by allowing a one-time auth session:

    cat 'my_preshared_password_file' | arcan-net -a 2 -l 6666

Which would accept the next (n=2 here) public keys that authenticate with what
was in the preshared password file and write into the keystore.

This is strictly for bootstrapping a system where it is inconvenient to add the
public key using some other media.

If the '--soft-auth' long argument is used, all public keys will be accepted
but not added to the keystore. This reduces the system to simply using the secret
as a 'password', and if no secret is provided -- a completely open server.

This might be desired in trusted networks or public servers acting in directory
mode. Such keys will not have access to storing state or other privileged
directory operations.

# Compilation

For proper video encoding, the ffmpeg libraries (libavcodec, libswscale, ...)
are required and must have h264 support. Due to patent or licensing issues that
may or may not apply, check you distribution and build.

If ffmpeg reports errors, is missing or is missing h264 support entirely the
system will fallback to raw- or only lightly- compressed buffers.

# Todo

The following are basic expected TODO points and an estimate as to where
on the timeline the respective features will be developed/available. The
parts marked with (a) refer to arcan-net tool, (o) omitted (p) the
protocol, and (x) for extended/engine/aux parts.

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
- [x] Subsegments (p)
- [x] Basic authentication / DH / Cipher (blake2+chacha8+x25519) (ap)
- [x] One-time password for key-auth (p)
- [x] TUI- text channel (p)
- [x] Cache process / directory for file operations (a)
- [x] ARCAN\_CONNPATH=a12:// handover support (ax)
- [x] Add to encode, remoting (x)
- [x] Complete naive-local key-store management (a)

Milestone 2 - closer to useful (0.6.x)

- [ ] Interactive compression controls (a)
- [ ] Block push-segment types (DEBUG) (a)
- [ ] Event key-code translation (evdev, sdl, ... to native) (a)
- [ ] Basic privsep/sandboxing (a)
- [ ] External key-provider / negotiation (a)
  -  [ ] FIDO2 (through libfido2) (a)
- [x] Preferred-hosts list migration / handover (a)
  - [x] Config for retry limits, sleep delays and backoff (a)
- [ ] Output segments (p)
- [o] Bchunk compression controls (o) (omitted, zstd is good enough)
    [o] Entropy estimator per packet
		[o] Compress low-entropy per chunk
- [ ] Quad-tree for DPNG (p)
  - [ ] Tile-map and caching (p)
	- [x] Remove DEFLATE and move to ZSTD
	- [ ] varDCT
	- [ ] XYB colorspace
- [x] Frame Cancellation / dynamic framerate on window drift (p)
- [ ] vframe-caching on certain types (first-frame on new, ...) (p)
- [ ] vframe-runahead / forward latency estimation (a)
- [ ] (Scheduling), better A / V / E interleaving (a)
- [p] Passthrough of compressed video sources (a)
- [ ] Traffic monitoring tools (re-use proxy code + inherit mode) (x)
- [ ] Splicing / Local mirroring (a)
- [ ] Rekeying / Key Deletion (Forward Secrecy) (p)
- [ ] Add TUI- mode for -net with statistics / controls (a)
  - [ ] Show unauthenticated public keys as QR code in window (a)
- [ ] Fexec(self) handover on completed negotiation (p)(a)
- [ ] Compression tunable .configuration file
- [ ] Shadow channel (as a pseudo progressive option)

Milestone 3 - big stretch (0.6.x)

- [ ] Embed binary transfer progress into parent window (p)
- [ ] switch to arcan style malloc/free API (p)
- [ ] Dynamic audio resampling (p)
- [ ] Media- segment buffering window, controls and progress (p)
- [ ] UDP based carrier (UDT) (a)
- [ ] 'ALT' arcan-lwa interfacing (px)
- [ ] 'AGP' level- packing (px)
- [ ] Ramp-up transfer based on timestamp to reduce cache loss (b)
- [ ] Optimized version of ChaCha / BLAKE (avx, neon, ...) (p)
  - [ ] Evaluate in-place merged encrypt+mac instead of enc then mac
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
- [p] Directory/Rendezvous Server (axp)
  - [x] serve appl- (.tar)
	- [x] enumerate / fetch / execute appl
	- [x] register as source
	- [x] register as sink
	- [x] notify on new source/sink
	- [x] relay a12 traffing between source/sink
	- [ ] NAT-punch between source/sink
	- [x] state store/restore
- [x] Add to afsrv\_net (x)
- [ ] Fast-forward known partial binary transfer (resume)
- [ ] Resume- session from different IP (ap)
- [ ] N-Key connection-unlock and monitors (a)
- [ ] Clean-up, RFC level documentation (p)

# Licenses

arcan-net is (c) Bjorn Stahl 2017-2022 and licensed under the 3-clause BSD
license. It is dependent on BLAKE3- (CC or Apache-2.0, see COPYING.BLAKE3)
, on ChaCha8, x25519 (Public Domain) and Miniz (MIT-like, see miniz/LICENSE).

optional dependencies include ffmpeg- suite of video codecs, GPLv2 with
possible patent implications.
