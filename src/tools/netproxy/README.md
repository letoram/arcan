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

# Use

On the host local to the arcan instance where the client should originate
from, run arcan-net in listening mode like this:

    ./arcan-net -s authk.file dst-server dst-port

On the host where arcan is running as a display server, where the client
destination is, run arcan-net in server-mode like this:

    ./arcan-net -c authk.file local-port

This requires a pre-existing ARCAN\_CONNPATH to the local connection point
that connections should be bridged over.

# Security/Safety

Right now, there's barely any (there will be though) - a lot of the other
quality problems should be solved first, i.e. audio / video format encoding,
event packing format and so on.

The only required part right now is that there is a shared authentication
key file (0..64 bytes) that has been preshared over some secure channel,
ssh is a good choice.

ALL DATA IS BEING SENT IN PLAINTEXT,
ANYONE ON THE NETWORK CAN SEE WHAT YOU DO.

# Protocol

UDT is used to build the basic channel, and segments/subsegments correlate
1:1 to communication channels - each working on their own thread.

Encryption is built on Curve25519 + blake2-aes128

Each message begins with a 16 byte MAC, keyed with the input auth-key for the
first message, then with the MAC from the last message.

Then there's a 1 byte type selector (plain text) and a blob that depends
on type and encryption status of the channel.

The different message types are:

1. control (128b fixed)
2. event (match 1 or many arcan-event samples packed, fixed to the packing
   size of the version of shmif on the running server, versions must match)
3. bstream-begin (used for file descriptor transfers)
4. bstream-cont (builds on the data from a previous begin block)
5. vframe-begin
6. vframe-cont
7. aframe-begin
8. aframe-cont

Event frames are likely to be interleaved between vframes/aframes/bstreams
to avoid input- bubbles, and there is only one a/v/b type of transfer going
on at any one time. The rest are expected to block- the source or queue up.

All data is little-endian.

[Control]
sequence number : uint64
last-seen seqnr : uint64
entropy         : uint8[8]
control command : uint8

[Control:command=0] : shutdown
[Control:command=1] : enc-negotiation

[Control:command=2] : channel-rekey
Switch into rekeying state, opens a small window where MAC failures will be
tested against both the expected and the new auth key, after the first package
that authenticated against the new key, this one is used. Rekeying is initiated
by the server side, typically early and then after a certain number of bytes.

MAC : uint8[16]
Pubk: uint8[32]

[Control:command=3] : channel-negotiation

(this maps to some subsegment requests)
control messages always contain some entropy (random bytes) that can be
mixed in locally to assist rekeying etc. but also to provide replay
protection.

[Control:command=4] : subprotocol negotiation

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
