# arcan-net

This tool is the development sandbox for the arcan-net bridge used to link
single clients over a network.

DISCLAIMER: This is in an early stage and absolutely not production ready
now or anytime soon. Treat it like a sample of what is to come during the
0.6- series of releases - the real version will depend on the rendering
protocol that will be derived from a packing format of the lua API, the
serialization format used in TUI and A/V encoding formats to be decided
(likely h264-lowlatency for game content, HEVC for bufferable media,
zstd for uncompressed blob transfers, Open3DGC for 3dvobj data etc).

There are two modes to building this tool, a 'simple' (arcan-netpipe)
and the real (arcan-net).

Arcan-netpipe uses some unspecified channel for transmission, e.g.
piping via SSH and so on. As such, is has rather low performance and
the communication is entirely unprotected. It is valuable for testing,
development and debugging/fault-injection - and for quick and dirty
low- bandwidth bridging. It can also only bridge a single client per
instance.

# Use

Arcan netpipe version (testing example):

     mkfifo fifo
     cat fifo | arcan-netpipe -c test | arcan-netpipe -s > fifo
     ARCAN_CONNPATH=test afsrv_terminal

On the host local to the arcan instance where the client should originate
from, run arcan-net in listening mode like this:

    ./arcan-net -s authk.file dst-server dst-port

On the host where arcan is running as a display server, where the client
destination is, run arcan-net in server-mode like this:

    ./arcan-net -c authk.file local-port

This requires a pre-existing ARCAN\_CONNPATH to the local connection point
that connections should be bridged over.

# Todo

This subproject will stretch until the end of the 0.6 series topic, with
some sharing likely to be done with the afsrv\_net (i.e. the underlying
protocol, a12, used along with some service discovery feature and better
scripting API integration).

Milestone 1 - basic features (0.5.x)

- [ ] Basic API
- [ ] Control
- [ ] Uncompressed Video / Video delta
- [ ] Uncompressed Audio / Audio delta
- [ ] Raw binary descriptor transfers
- [ ] Netpipe working

Milestone 2 - closer to useful (0.6.x)

- [ ] basic h264 lowlatency
- [ ] TUI- text channel
- [ ] subchannel multiplexing
- [ ] UDT based carrier (full- proxy client)
- [ ] dealing with zero-copy buffer handles

Milestone 3 - big stretch (0.6.x)

- [ ] curve25519 key exchange
- [ ] stream-ciper
- [ ] rekeying
- [ ] 'ALT' arcan-lwa interfacing
- [ ] HEVC
- [ ] ZSTD
- [ ] Open3DGC
- [ ] congestion control / dynamic encoding parameters

# Security/Safety

Right now, there's barely any (there will be though) - a lot of the other
quality problems should be solved first, i.e. audio / video format encoding,
event packing format and so on.

The only required part right now is that there is a shared authentication key
file (0..64 bytes) that has been preshared over some secure channel, ssh is a
good choice. This key is used for building individual packet MACs.

ALL DATA IS BEING SENT IN PLAINTEXT,
ANYONE ON THE NETWORK CAN SEE WHAT YOU DO.

# Protocol

UDT is used to build the basic channel, and segments/subsegments correlate
1:1 to communication channels - each working on their own thread.

Encryption is built on Curve25519 + blake2-aes128-ctr

Everything is LE, because even though that makes IETF cry and it is the lesser
of the two options - it still won out.

Each message begins with a 16 byte MAC, keyed with the input auth-key for
the first message, then payload prefixed with the MAC from the last message.

The payload is encrypt-then=MAC (if there has been a session key negotiated)
The stream-cipher server-to-client starts at [8bIV,8bCTR(0)] and the
client-to-server starts at [8bIV,8bCTR(1<<32)].

After the MAC comes a 1-byte unsigned type selector, then a number of bytes
that depends on the specified type. The contents, including the type, is
encrypted when/if such a negotiation has occured (see control messages).

The different message types are:

1. control (128b fixed)
2. event (match 1 or many arcan-event samples packed, fixed to the packing
   size of the version of shmif on the running server, versions must match)
3. vstream-data
4. astream-data
5. bstream-data

Event frames are likely to be interleaved between vframes/aframes/bstreams
to avoid input- bubbles, and there is only one a/v/b type of transfer going
on at any one time. The rest are expected to block- the source or queue up.

If the most significant bit of the sequence number is set, it is a discard-
message used to mess with side-channel analysis for cases where bandwidth is a
lesser concern than security.

## Control (1)
- sequence number : uint64
- last-seen seqnr : uint64
- entropy : uint8[8]
- channel-id : uint8
- command : uint8

The sequence number and last-seen are used both as a timing channel and to
determine drift. If the two sides start drifting outside a certain window,
measures to reduce bandwidth should be taken, including increasing compression
parameters, lowering sample- and frame- rates, cancelling ongoing frames,
merging / delaying input events, scaling window sizes, ...
If they still keep drifting, show a user notice and destroy the channel.

control messages always contain some entropy (random bytes) that can be
mixed in locally to assist rekeying etc. but also to provide replay
protection.

### command = 0, hello
First message sent of the channel, it's rude not to say hi.

### command = 1, shutdown
The nice way of saying that everything is about to be shut down.

### command = 2, encryption negotiation
- K(auth) : uint8[16]
- K(pub) : uint8[32]
- IV : uint8[8]

### command = 3, channel rekey
- K(auth) : uint8[16]
- K(sym) : uint8[32]
- IV : uint8[8]

Switch into rekeying state, opens a small window where MAC failures will be
tested against both the expected and the new auth key, after the first package
that authenticated against the new key, this one is used. Rekeying is initiated
by the server side, authoritative and infrequent; typically early and then
after a certain number of bytes.

### command = 4, stream-cancel
- stream-id : uint32

This command carries a 4 byte stream ID, which is the counter shared by all
bstream, vstream and astreams.

### command = 5, channel negotiation
- sequence number : uint64
- channel-id : uint8
- segkind : uint8

This maps to subsegment requests and bootstraps the keys, rendezvous, etc.
needed to initiate a new channel as part of a subsegment setup.

### command - 6, command failure
- sequence number : uint64
- channel-id : uint8
- segkind : uint8

### command - 7, define vstream
- stream-id: uint32
- format: uint8
- surfacew: uint16
- surfaceh: uint16
- startx: uint16 (0..outw-1)
- starty: uint16 (0..outh-1)
- framew: uint16 (outw-startx + framew < outw)
- frameh: uint16 (outh-starty + frameh < outh)
- dataflags: uint8
- length: uint32

This defines a new video stream frame. The length- field covers how many bytes
that need to be buffered for the data to be decoded. This can be chunked up
into 1..length packages, depending on interleaving and so on. The vstream
counter increases incrementally and is shared between the v/a/b streams.

Outw/Outh can change frequently (corresponds to window resize).

If there is already an active frame, it will be cancelled out and replaced
with this one - similar to if a stream-cancel command had been issued.

### command - 8, define astream
incomplete

### command - 9, define bstream
incomplete

##  Event (2), fixed length
- sequence number : uint64
- channel-id : uint8

This follows the packing format provided by the SHMIF- libraries themselves,
which have their own pack/unpack/versioning routines. When the SHMIF event
model itself is finalized, it will be added to the documentation here.

## Vstream-data (3), Astream-data (4), Bstream-data (5) (variable length)
- sequence number : uint64
- channel-id : uint8
- stream-id : uint32

# Notes

The more complicated part will be resize, it's not a terrific idea to make
that part of the control channel as such, better to make that an effect of
vframe-begin, aframe-begin - though the one that needs more thinking is
some of the subprotocols (gamma ramps, ...) though that is quite far down
the list.

some subsegments should not be treated as such, notably clipboard - as the
lack of synchronisity between the channels will become a problem, i.e. msg
is added to clipboard for paste, user keeps on typing, paste arrives after
the intended insertion point. There are very few other such points in the
IPC system though.

# Licenses

arcan-net is (c) Bjorn Stahl 2017 and licensed under the 3-clause BSD
license. It is dependent on BLAKE2- (CC or Apache-2.0, see COPYING.BLAKE2)
and on UDT (Apache-2.0 / 3-clause BSD).
