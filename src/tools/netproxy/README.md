# arcan-net

This folder contains the subproject that provide per client net proxying
for shmif- based clients.

DISCLAIMER:This is in an early stage and absolutely not production ready
now or anytime soon. Treat it like a sample of what will come during the
0.6- series of releases or look at the TODO for things to help out with.

Two binaries are produced by building this tool. The 'simple' netpipe is
managed unencrypted over FIFOs that the caller manages. The more complex
arcan-net is currently built on TCP as a transport layer and do symmetric
encryption and authentication using pre-shared credentials.

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
- [x] Netpipe (FIFO)
- [x] net (TCP)
- [x] Raw binary descriptor transfers
- [x] Uncompressed Video / Video delta
- [ ] Uncompressed Audio / Audio delta
- [x] Compressed Video
	-  [x] x264
	-  [x] xor-PNG
- [ ] Subsegments
- [ ] Basic authentication / Cipher (blake+chaha20)

Milestone 2 - closer to useful (0.6.x)

- [ ] Compression Heuristics for binary transfers
- [ ] Quad-tree for DPNG
- [ ] "MJPG" mode over DPNG
- [ ] TUI- text channel
  - [ ] Local echo prediction
- [ ] A / V / E interleaving
- [ ] Progressive encoding
- [ ] Accelerated encoding of gpu-handles
- [ ] Traffic monitoring tools
- [ ] Output segments
- [ ] Basic privsep/sandboxing
- [ ] Splicing / Local mirroring

Milestone 3 - big stretch (0.6.x)

- [ ] UDP based carrier
- [ ] curve25519 key exchange
- [ ] 'ALT' arcan-lwa interfacing
- [ ] ZSTD
- [ ] Subprotocols (vobj, gamma, ...)
- [ ] Open3DGC
- [ ] Congestion control / dynamic encoding parameters
- [ ] Side-channel Resilience
- [ ] Local discovery Mechanism (pluggable)
- [ ] Add to arcan-net
- [ ] Special provisions for agp/alt channels
- [ ] Clean-up, RFC level documentation

# Security/Safety

Right now, assume that there is no guarantees on neither confidentiality,
integrity or availability. As can be seen in the todo list, this won't remain
the case but there are other priorities to sort out first.

For arcan-netpipe, you are expected to provide it through whatever tunneling
mechanism you chose - ssh is a good choice.

For arcan-net, you are currently restricted to symmetric primitives
derived from the password expected to be provided as env or on stdin.

# Hacking
To get a grasp of the codebase, the major components to understand for the
server side the "a12\_channel\_unpack" function. This function takes care of
buffering, authentication, decryption and dispatch. It is stateful, and based
on the current state it will forward a completed larger chunk to the
corresponding process\_(xxx) function.

For sending/prividing output, first build the appropriate control packet for
the basic command. When such a buffer is finished, send to the
"a12int\_append\_out" function.

    uint8_t hdr_buf[CONTROL_PACKET_SIZE];
    /* populate hdr_buf, see a12int_vframehdr_build */
    a12int_append_out(S, STATE_CONTROL_PACKET, hdr_buf, CONTROL_PACKET_SIZE, NULL, 0);

Continue in a similar way with any subpacket types, make sure to chunk output
in reasonably sized chunks so that interleaving of other packet types is
possible. This is needed in order to prevent audio / video from stuttering or
saturating other events.

"a12\_channel\_vframe" is probably the best example of providing output and
sending, since it needs to treat many options, large data and different
encoding schemes.

# Notes

A subtle thing that isn't correctly implemented at the moment is the flag
translation for dirty regions, the origo\_ll option, and alpha component
status.

# Protocol

This section mostly covers a rough draft of things as they evolve. A more
'real' spec is to be written separately towards the end of the subproject in
an RFC like style and the a12 state machine will be decoupled from the
current shmif dependency.

Each arcan segment correlates to a 'channel' that can be multiplexed over
one of these transports, with a sequence number used as a synchronization
primitive for re-linearization. For each channel, a number of streams can
be defined, each with a unique 32-bit identifier. A stream corresponds to
one binary, audio or video transfer operation. Multiple streams can be in
flight at the same time, and can be dynamically cancelled.

The symmetric encryption scheme is simply a preshared secret hashed using
BLAKE2 that has been salted with the salt provided as part of the initial
hello command and iterated a version-fixed number of times.

Each message has the outer structure of :

 |---------------------|
 | 16 byte MAC         |
 |---------------------|  |
 | 4 byte sequence     |  |
 | 1 byte command code |  | encrypted block
 | command-code data   |  |
 |---------------------|  |
 | command- variable   |  |

The payload is encrypt-then-MAC. The cipher is run in CTR mode where
server-to-client starts at [8bIV,8bCTR(0)] and the client-to-server
starts at [8bIV,8bCTR(1<<32)] and a possible rekey- command.

After the MAC comes a 4 byte LSB unsigned sequence number, and then a 1 byte
command code, then a number of command-specific bytes. The sequence number does
not necessarily increment between messages as v/a/b streams might be multipart.
It is used as a reference for stream- invalidation commands.

The different message types are:

1. control (128b fixed)
2. event, tied to the format of arcan\_shmif\_evpack()
3. vstream-data
4. astream-data
5. bstream-data

Event frames are likely to be interleaved between vframes/aframes/bstreams
to avoid input- bubbles, and there is only one a/v/b type of transfer going
on at any one time. The rest are expected to block- the source or queue up.

If the most significant bit of the sequence number is set, it is a discard-
message used to mess with side-channel analysis for cases where bandwidth is a
lesser concern than confidentiality. It means that both sides can keep a queue
of discarded packets and re-inject them without being aware of the rest of the
protocol.

## Control (1)
- [0..7]    last-seen seqnr : uint64
- [8..15]   entropy : uint8[8]
- [16]      channel-id : uint8
- [17]      command : uint8

The last-seen are used both as a timing channel and to determine drift.
If the two sides start drifting outside a certain window, measures to reduce
bandwidth should be taken, including increasing compression parameters,
lowering sample- and frame- rates, cancelling ongoing frames, merging /
delaying input events, scaling window sizes, ... If they still keep drifting,
show a user notice and destroy the channel. The entropy contents can be used
as input to a local CSPRNG, while also protecting against replay even if other
measures should fail.

### command = 0, hello
- [0] version major (match the shmif- version until we have a finished protocol)
- [1] version minor (match the shmif- version until we have a finished protocol)
- [2..10] Authentication salt
- [11..43] Curve25519 public key (if asymmetric)

### command = 1, shutdown
The nice way of saying that everything is about to be shut down, remaining
bytes may contain the 'last words' - user presentable message describing the
the reason for the shutdown.

### command = 4, stream-cancel
- stream-id : uint32
- code : uint8

This command carries a 4 byte stream ID, which is the counter shared by all
bstream, vstream and astreams. The code dictates if the cancel is due to the
information being dated (0) or encoded in an unhandled format (1).

### command = 5, channel negotiation
- sequence number : uint64
- primary : uint8
- segkind : uint8

This maps to subsegment requests and bootstraps the keys, rendezvous, etc.
needed to initiate a new channel. If 'primary' is set, the server side will
treat the channel as a new 'client' connection, otherwise it is
bootstrapped over the channel itself.

### command - 6, command failure
- sequence number : uint64
- segkind : uint8

### command - 7, define vstream
- [18..21] : stream-id: uint32
- [22    ] : format: uint8
- [23..24] : surfacew: uint16
- [25..26] : surfaceh: uint16
- [27..28] : startx: uint16 (0..outw-1)
- [29..30] : starty: uint16 (0..outh-1)
- [31..32] : framew: uint16 (outw-startx + framew < outw)
- [33..34] : frameh: uint16 (outh-starty + frameh < outh)
- [35    ] : dataflags: uint8
- [36..39] : length: uint32
- [40..43] : expanded length: uint32
- [44]     : commit: uint8

The format field defines the encoding method applied. Current values are:
 R8G8B8A8 = 0 : raw 8-bit red, green, blue and alpha values
 R8G8B8 = 1 : raw 8-bit red, green and blue values
 RGB565 = 2 : raw 5 bit red, 6 bit green, 5 bit red
 DMINIZ = 3 : DEFLATE packaged block, set as ^ delta from last
 MINIZ =  4 : DEFLATE packaged block

This defines a new video stream frame. The length- field covers how many bytes
that need to be buffered for the data to be decoded. This can be chunked up
into 1..n packages, depending on interleaving and so on.

Commit indicates if this is the final (1) update before the accumulation
buffer can be forwarded without tearing, or if there are more blocks to come.

The length field indicates the number of total bytes for all the payloads
in subsequent vstream-data packets.

### command - 8, define astream

- [18..21] : stream-id uint32
- [22]     : format
- [23]     : encoding
- [24]     : n-samples

The format fields determine the size of each sample, multiplied over the
number of samples to get the size of the stream. The field in [22]

### command - 9, define bstream
- [18..21] : stream-id
- [22..28] : stream-size, 0 if 'streaming source'

After the completion of a bstream transfer, there must always be an event
packet with the corresponding event that is to 'consume' the binary stream,
then the data itself.

##  Event (2), fixed length
- sequence number : uint64
- channel-id : uint8

This follows the packing format provided by the SHMIF- libraries themselves,
which have their own pack/unpack/versioning routines. When the SHMIF event
model itself is finalized, it will be added to the documentation here.

## Vstream-data (3), Astream-data (4), Bstream-data (5) (variable length)
- channel-id : uint8
- stream-id : uint32
- length : uint32

The data messages themselves will make out the bulk of communication, and
ties to a pre-defined channel/stream.

# Compressions and Codecs

To get audio/video/data transfers bandwidth efficient, the contents must be
compressed in some way. This is a rats nest of issues, ranging from patents
in less civilized parts of the world to dependency hell.

The current approach to 'feature negotiation' is simply for the sender to try
the best one it can, and fall back to inefficient safe-defaults if the
recipient returns a remark of the frame as unsupported.

# Event Model

The more complicated interactions come from events and their ordering,
especially when trying to interleave or deal with data carrying events.

The only stage this 'should' require special treatment is for font transfers
for client side text rendering which typically only happen before activation.

For other kinds of transfers, state and clipboard, they act as a mask/block
for certain input events.

Input events are the next complication in line as any input event that relies
on a 'press-hold-release' pattern interpreted on the other end may be held for
too long, or with clients that deal with raw codes and repeats, cause
extraneous key-repeats or 'shadow releases'. To minimize the harm here, a more
complex state machine will be needed that tries to determine if the channel
blocks or not by relying on a ping-stream.

# Licenses

arcan-net is (c) Bjorn Stahl 2017-2019 and licensed under the 3-clause BSD
license. It is dependent on BLAKE2- (CC or Apache-2.0, see COPYING.BLAKE2)
and on ChaCha20 (Public Domain).

optional dependencies include ffmpeg- suite of video codecs, GPLv2 with
possible patent implications.
