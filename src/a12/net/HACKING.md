# Hacking

This section covers quick notes in using and modifying the code-base. The main
point of interest should be the a12 state machine and its decode and encode
translation units.

## Exporting shmif

The default implementation for this is in 'a12\_helper\_srv.c'

With exporting shmif we have a local shmif-server that listens on a connection
point, translates into a12 and sends over some communication channel to an
a12-server.

This is initiated by the 'a12\_channel\_open call. This takes an optional
authentication key used for preauthenticated setup where both have
performed the key-exchange in advance.

The connection point management is outside of the scope here, see the
arcan\_shmif\_server.h API to the libarcan-shmif-srv library, or the
corresponding a12\_helper\_srv.c

## Importing shmif

The default implementation for this is in 'a12\_helper\_cl.c'.

With importing shmif we have an a12-server that listens for incoming
connections, unpacks and maps into shmif connections. From the perspective of a
local arcan instance, it is just another client.

This is initiated by the 'a12\_channel\_build. This takes an optional
authentication key used for preauthenticated setup where both have
performed the key exchange in advance.

## Unpacking

In both export and import you should have access to a shmif\_cont. This
should be bound to a channel id via:

    a12_set_destination(S, &shmif_cont, 0)

There can only be one context assigned to a channel number, trying to call it
multiple times with the channel ID will replace the context, likely breaking
the internal state of the shmif context.

When data has been received over the communication channel, it needs to be
unpacked into the a12 state machine:

    a12_channel_unpack(S, my_data, number_of_bytes, void_tag, on_event)

The state machine will take care of signalling and modifying the shmif context
as well, but you will want to prove an 'on\_event' handler to intercept event
delivery. This will look like the processing after arcan\_shmif\_dequeue.

    on_event(struct arcan_shmif_cont*, int channel, struct arcan_event*, void_tag)

Forward relevant events into the context by arcan\_shmif\_enqueue:ing into it.

## Output

When the communication is available for writing, check with:

    out_sz = a12_channel_flush(S, &buf);
		if (out_sz)
		   send(buf, out_sz)

Until it no-longer produces any output. The a12 state machine assumes you are
done with the buffer and its contents by the next time you call any a12
function.

## Events

Forwarding events work just like the normal processing of a shmif\_wait or
poll call. Send it to a12\_channel\_enqueue and it will take care of repacking
and forwarding. There are a few events that require special treatment, and that
are those that carry a descriptor pointing to other data as any one channel
can only have a single binary data stream transfer in flight. There is a helper
in arcan\_shmif\_descrevent(ev) that will tell you if it is such an event or not.

If the enqueue call fails, it is likely due to congestion from existing transfers.
When that happens, defer processing and focus on flushing out data.

Some are also order dependent, so you can't reliably forward other data in between:

* FONTHINT : needs to be completed before vframe contents will be correct again
* BCHUNK\_OUT, BCHUNK\_IN : can be interleaved with other non-descriptor events
* STORE, RESTORE : needs to be completed before anything else is accepted
* DEVICEHINT : does not work cross- network
* PRIVDROP : not supposed to pass networked barriers

PRIVDROP should also be emitted on client to local server, in order to mark that
it comes from an external/networked source.

## Audio / Video

Both audio and video may need to be provided by each side depending on segment
type, as the ENCODE/sharing scenario changes the directionality, though it is
decided at allocation time.

The structures for defining audio and video parameters actually come from
the shmif\_srv API, though is synched locally in a12\_int.h. Thus in order
to send a video frame:

    struct shmifsrv_vbuffer vb = shmifsrv_video(shmifsrv_video(client));
    a12_channel_vframe(S, channel, &vb, &(struct a12_vframe_opts){...});

With the vframe-opts carrying hints to the encoder stage, the typical pattern
is to select those based on some feedback from the communication combined with
the type of the segment itself.

## Multiple Channels

One or many communication can, and should, be multiplexed over the same
carrier. Thus, there is a 1:1 relationship between channel id and shmif
contents in use. Since this is a state within the A12 context, use

    a12_channel_setid(S, chid);

Before enqueueing events or video. On the importer side, every-time a
new segment gets allocated, it should be mapped via:

    a12_set_destination(S, shmif_context, chid);

The actual allocation of the channel ids is performed in the server itself
as part of the event unpack stage with a NEWSEGMENT. In the event handler
callback you can thus get an event, but a NULL segment and a channel ID.
That is where to setup the new destination.

Basically just use the tag field in the shmif context to remember chid
and there should not be much more work to it.

Internally, it is quite a headache, as we have '4' different views of
the same action.

1. (opt.) shmif-client sends SEGREQ
2. (opt.) local-server forwards to remote server.
3. (opt.) remote-server sends to remote-arcan.
4. (opt.) remote-arcan maps new subsegment (NEWSEGMENT event).
5. remote-server maps this subsegment, assigns channel-ID. sends command.
6. local-server gets command, converts into NEWSEGMENT event, maps into
   channel.

## Packet construction

Going into the a12 internals, the first the to follow is how a packet is
constructed.

For sending/providing output, first build the appropriate control command.
When such a buffer is finished, send it to the "a12int\_append\_out"
function.

    uint8_t hdr_buf[CONTROL_PACKET_SIZE];
    /* populate hdr_buf, see a12int_vframehdr_build as an example */
    a12int_append_out(S, STATE_CONTROL_PACKET, hdr_buf, CONTROL_PACKET_SIZE, NULL, 0);

This will take care of buffering, encryption and updating the authentication
code.

Continue in a similar way with any subpacket types, make sure to chunk output
in reasonably sized chunks so that interleaving of other packet types is
possible. This is needed in order to prevent audio / video from stuttering or
saturating other events.

"a12\_channel\_vframe" is probably the best example of providing output and
sending, since it needs to treat many options, large data and different
encoding schemes.

# Notes / Flaws

* vpts, origo\_ll and alpha flags are not yet covered

* custom timers should be managed locally, so the proxy server will still
  tick etc. without forwarding it remote...

* should we allow session- resume with a timeout? (pair authk in HELLO)

# Critical Path / Security Notes

The implementation is intended to be run as a per-user server with the same
level of privileges that the user would have on the server through any ssh-
like session. Therefore, the normal culprits, video/image decoders, are not
as vital - though they should still be subject to further privsep, the main
culprits are the ones that work on data while it is unauthenticated or when
negotiating keys.

The following functions should be the hotpath for vulnerability research:

- a12.c:a12\_unpack (input buffer)
- a12.c:process\_srvfirst
- a12.c:process\_nopacket
- a12.c:process\_control (MAC check + HELLO command)
- a12.c:process\_event   (up until MAC check)
- a12.c:process\_video   (up until MAC check)
- a12.c:process\_audio   (up until MAC check)
- a12.c:process\_blob    (up until MAC check)

For directory server mode there are more details to consider. One is the
introduction of transitive trust - a client can learn about other clients
that the directory trusts through dynamic sources and directories joining.

These are initially opened (DIROPEN) where connection primitives and Kpub
are mediated. This naturally puts the directory in a MiTM position in two
ways. One is to block any requests for negotiating a direct connection
between the two parties (i.e. force-relaying). The other is to force- swap
key exchanges similar to how an SSH MiTM would work. This is conceptually
similar to how CAs can abuse their position of trust in PKIs.

The main counter measure is that the force- relaying part can be detected
by having two clients with a side-band to probe for a directory doing this,
and by leveraging other discovery methods (e.g. being on the same LAN or
another more trusted directory) to verify that the same Kpubs are being
exchanged.

# Protocol

This section mostly covers a rough draft of things as they evolve. A more
'real' spec is to be written separately towards the end of the subproject in an
RFC like style and the a12 state machine will be decoupled from the current
shmif dependency.

Each arcan segment correlates to a 'channel' that can be multiplexed over one
of these transports, with a sequence number used as a synchronization primitive
for drift measurement, scheduling re-keying and (later) out-of-order processing.

For each channel, a number of streams can be defined, each with a unique 32-bit
identifier.

A stream corresponds to one binary, audio or video transfer operation.

One stream of each type (i.e. binary, audio and video) can be in flight at the
same time.

The first message has the structure of:

 |---------------------|
 | 8 bytes MAC         |
 | 8 bytes nonce       | | from CSPRNG
 |---------------------|
 | 8 byte sequence     | | encrypted block
 | 1 byte command-code | | encrypted block   (HELLO command)
 | command-code data   | | keymaterial       (HELLO command)
 |----------------------

The MAC comes from BLAKE3 in keyed mode (normally, output size of 16b) using a
pre-shared secret or the default 'SETECASTRONOMY' that comes from BLAKE3 in KDF
mode using the message "arcan-a12 init-packet".

The forced encryption of the first packet is to avoid any predictable bytes
(forcing fingerprinting to be based on packet sizes, rate and timestamps rather
than any metadata) and hide the fact that X25519 is used. The use of pre-shared
secrets and X25519 is to allow for a PKI- less first-time authentication of public
keys.

Only the first 8 byte of MAC output is used for the first HELLO packet in order
to make it easier for implementations to avoid radically different code paths in
parsing for these packets.

KDF(secret) -> Kmac.

The cipher is strictly Chacha8 (reduced rounds from normal 20 due to cycles per
byte, see the paper 'Too much Crypto' by JP et al.) with nonce from message and
keyed using:

KDF(Kmac) -> Kcl.
KDF(Kcl) -> Ksrv.

The subsequent HELLO command contains data for 1 or 2 rounds of X25519. If 2
round-trips is used, the first round is using ephemeral key-pairs to further
hide the actual key-pair to force active MiM in order for Eve to log/track Kpub
use.

Each message after completed key-exchange has the outer structure of :

 |---------------------|
 | 16 byte MAC         |
 |---------------------|  |
 | 8 byte sequence     |  |
 | 1 byte command code |  | encrypted block
 | command-code data   |  |
 |---------------------|  |
 | command- variable   |  |

The 8-byte LSB sequence number is incremented for each message.

## Commands

The command- code can be one out of the following types:

1. control (128b fixed size)
2. event, tied to the format of arcan\_shmif\_evpack()
3. video-stream data chunk
4. audio-stream data chunk
5. binary-stream data chunk

Starting with the control commands, these affect connection status, but is
also used for defining new video/audio and binary streams.

## Control (1)
- [0..7]    last-seen seqnr : uint64
- [8..15]   entropy         : uint8[8]
- [16]      channel-id      : uint8
- [17]      command         : uint8

The last-seen are used as a timing channel, to determine drift and for
scheduling rekeying.

If the two sides start drifting outside a certain window, measures to reduce
bandwidth should be taken, including increasing compression parameters,
lowering sample- and frame- rates, cancelling ongoing frames, merging /
delaying input events, scaling window sizes, ... If they still keep drifting,
show a user notice and destroy the channel. The drift window should also be
used with a safety factor to determine the sequence number at which rekeying
occurs.

The entropy contents can be used as input to the mix pool of a local CSPRNG to
balance out the risk of a runtime-compromised entropy pool. For multiple HELLO
roundtrips doing x25519 exchange, the entropy field is also used for cipher
nonce.

The channel ID will have a zero- value for the first channel, and after
negotiation via [define-channel], specify the channel the command effects.
Discard messages to an unused channel (within reasonable tolerances) as
asynch- races can happen with data in-flight during channel tear-down from
interleaving.

### command = 0, hello
- [18]      Version major : uint8 (shmif-version until 1.0)
- [19]      Version minor : uint8 (shmif-version until 1.0)
- [20]      Mode          : uint8
- [21+ 32]  x25519 Kpub   : blob
- [54]      Primary flow  : uint8
- [55+ 16]  Petname       : UTF-8

The hello message contains key-material for normal x25519, according to
the Mode byte [20].

Accepted encryption values:
0 : no-exchange - Keep using the shared secret key for all communication

1 : X25519 direct - Authenticate supplied Pk, return server Pk and switch
auth and cipher to computed session key for all subsequent packets.

2 : X25519 nested - Supplied Pk is ephemeral, return ephemeral Pk, switch
to computed session key and treat next hello as direct.

The primary flow is one of the following:
0 : don't care
1 : source
2 : sink

It is used to indicate what each end is expecting from the connection, a client
that is configured to push (x11-style forwarding) want to act as a source and
would send 1 in its first HELLO, otherwise 2 (sink). If this does not match the
configuration/expectations of the other end, the connection MUST be terminated.

The petname in the direct HELLO state is treated as a suggested (valid utf-8)
visible simplified user presentable handle.

The Resumption hint can be used to indicate that the connection is a
reconnection after a previous loss. This is used by the listening endpoint to
repair with a worker dispatch that has yet to time out. The purpose is to allow
re-use of expensive server side primitives, e.g. per-worker sandboxing and
hardware video encoder/decoder allocation. The ticket comes from the last
inbound REKEY command. The regular authentication process still applies and
the Kpub used for hashing is the Kpub used for initial authentication.

### command = 1, shutdown
- [18..n] : last\_words : UTF-8

Destroy the segment defined by the header command-channel.
Destroying the primary segment kills all others as well.

### command = 2, define-channel
- [18]     channel-id : uint8
- [19]     type       : uint8
- [20]     direction  : uint8 (0 = seg to srv, 1 = srv to seg)
- [21..24] cookie     : uint32

This corresponds to a slightly altered version of the NEWSEGMENT event,
which should be absorbed and translated in each proxy.

### command = 3, stream-cancel
- [18..21] stream-id : uint32
- [22]     code      : uint8
- [23]     type      : uint8

This command carries a 4 byte stream ID that refers to the identifier
of an ongoing video, audio or bstream.

The code dictates if the cancel is due to the information being dated or
undesired (0), encoded in an unhandled format (1) or data is already known
(cached, 2).

In the event on vstreams or astreams receiving an unhandled format, (possible
for H264 and future hardware-/ licensing- dependent encodings), the client
should attempt to resend / reencode the buffer with one of the built-in
formats.

The type indicates if the idea of the stram is video (0), audio (1) or binary
data (2).

### command - 4, define vstream
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
 R8G8B8   = 1 : raw 8-bit red, green and blue values
 RGB565   = 2 : raw 5 bit red, 6 bit green, 5 bit red
 DMINIZ   = 3 : [deprecated] DEFLATE compressed block, set as ^ delta from last
 MINIZ    = 4 : [deprecated] DEFLATE compressed block
 H264     = 5 : h264 stream
 TZ       = 6 : [deprecated] DEFLATE compressed tpack block
 TZSTD    = 7 : ZSTD compressed tpack block
 ZSTD     = 8 : ZSTD compressed block
 DZSTD    = 9 : ZSTD compressed block, set as ^ delta from last

This list is likely to be reviewed / compressed into only ZSTD and H264
variants, as well as allowing a FourCC passthrough block for hardware decoding.

This defines a new video stream frame. The length- field covers how many bytes
that need to be buffered for the data to be decoded. This can be chunked up
into 1..n packages, depending on interleaving and so on.

Commit indicates if this is the final (1) update before the accumulation
buffer can be forwarded without tearing, or if there are more blocks to come.

The dataflags field is a bitmask that indicate if there is any special kind of
post-processing to apply. The currently defined one is origo_ll (1) which means
that the completed frame is to be presented with the y axis inverted.

The length field indicates the number of total bytes for all the payloads
in subsequent vstream-data packets.

### command - 5, define astream
- [18..21] stream-id  : uint32
- [22]     channel    : uint8
- [23]     encoding   : uint8
- [24..25] nsamples   : uint16
- [26..29] rate       : uint32

The encoding field determine the size of each sample, multiplied over the
number of samples multiplied by the number of channels to get the size of
the stream. The nsamples determins how many samples are sent in this stream.

The size of the sample is determined by the encoding.

The following encodings are allowed:
 S16 = 0 : signed- 16-bit

### command - 6, define bstream
- [18..21] stream-id   : uint32
- [22..29] total-size  : uint64 (0 on streaming source)
- [30]     stream-type : uint8 (0: state, 1:bchunk, 2: font, 3: font-secondary, 4: debug, 5: appl, 6:appl-resource)
- [31..34] id-token    : uint32 (used for bchunk pairing on \_out/\_store)
- [35 +16] blake3-hash : blob (0 if unknown)
- [52    ] compression : 0 (raw), 1 (zstd)
- [53 +16] ext.name    : utf8

This defines a new or continued binary transfer stream. The block-size sets the
number of continuous bytes in the stream until the point where another transfer
can be interleaved. There can thus be multiple binary streams in flight in
order to interrupt an ongoing one with a higher priority one. The appl and
appl-resource stream types are used only in directory mode and use the extended
name field.

### command - 7, ping
- [18..21] stream-id : uint32

The stream-id is that of the last completed stream (if any).

### command - 8, rekey
- [18     ] mode 
- [19  +32] mode = 0     new Kpub   : uint8[32]

The rekey command is used to rotate keys for forward secrecy. When receiving
a rekey key, calculate a new shared secret as per X25519 with [8..15] used as
the nonce.

Rekeying must be issued in a ping-pong manner. The listening endpoint has
initiative. After it issues a rekeying, it is the outbound, then the listening
and so on.

This new shared secret should only be used for decoding and authenticating
inbound packets after seeing the rekey. The KDF is still using BLAKE3 keyed
with "arcan-a12 rekey", and key for HMAC being H(ssecret).

Other modes are reserved for future step-up to PQ resistant KEMs and for
establishing a resumption ticket in order to make a reconnection faster in the
event of a connection loss.

### command - 9, directory-list
- [18     ] notify : uint8

This command is respected if the receiver is running in directory mode. If
permitted (rate limit, key access restrictions, ...) it will result in a series
of directory-state and directory-discover events giving the current set of
available appls, sources or directories.

If notify is set to !0, the sender requests that any changes to the set will
be provided dynamically without the caller polling through additional
directory-list commands.

### command - 10, directory-state
- [18..19 ] identifier : uint16   server-local identifier
- [20..21 ] catbmp     : uint16   category bitmap
- [22..23 ] permbmp    : uint16   permission bitmap
- [24..27 ] hash       : uint8(4) (blake3-hash on uncompressed appl tar)
- [28..35 ] size       : uint64   state-size
- [36..54 ] name       : user presentable applname (0 or len terminates)
- [55+    ] descr      : geohint adjusted short description

This is sent as a reply to the directory list command and is used to notify
about the update, removal, creation or presence of a retrievable application.
An empty identifier terminates. The applname or server-identifier can be used
as the extension field of a BCHUNKSTATE event to initiate the actual transfer.

### command - 11, directory-discover
- [18     ] role    : uint8 (0) source, (1) sink, (2) directory
- [19     ] state   : uint8 (0) added, (1) lost
- [20  +16] petname : UTF-8 identifier
- [36  +32] Kpub (x25519)

This is provided when a new source or sink has flagged for availability
(state=0) or been disconnected (state=1). The petname is provided on initial
source/sink/directory HELLO or chosen by the directory server due to local
policy or name collision.

### command - 12, directory-open
- [18    ] Mode     : (1: direct-inbound, 2: direct-outbound, 4: tunnel)
- [19+ 32] Kpub-tgt : (x25519)

This is used to request a connection / connection request to the provided
petname. Kpub-tgt is the identifier previously received from a discover event
while Kpub-me is the public key that the source will connect through in order
to differentiate between the credential used to access the directory versus the
credential used to access the source.

Mode can be treated as a bitmap of supported open-modes but is a hint as the
initiator cannot necessarily know the topology of the source.

If mode is set to direct-inbound the request is that the other end connects to
the request originator (TCP). This will provide the source-IP that was used to
connect to the directory.

If mode is set to direct-outbound, the request is that the other end listens
for a connection (TCP) and on receiving a directory-opened reply, the source
commits to connecting within some implementation defined timeout as outer
bounds. Implementations SHOULD ignore repeated open-request to prevent
denial-of-service.

If mode is set to tunnel:ed, the active connection will be used to route
traffic to/from the nested connection. This is a workthrough for cases where a
direct connection cannot be established, corresponding carriers for NAT
traversal (UDP blocked, misconfigured routers) and might not be permitted by
the server connection.

### command - 13, directory-opened
- [18    ] Status  : (0 failed, 1 direct-in ok, 2 direct-out ok, 3 tunnel ok)
- [19 +46] Address : (string representation, \0 terminated)
                     Status = 1, IPv4,6 address to the host,
                     Status = 2, IPv4,6 address to the host,
                     Status = 3, channel-id (>= 1)
- [65..66] Port    : connection port or tunnel-id (status=2)
- [67 +12] Secret  : alphanumerical random secret to use with first HELLO
                     packet to authenticate.
- [79 +32] Kpub    : the other end key.

This will be sent to source/source-directory and to sink in response to a
directory-open request. The connection handshake is just like the initial
one for the directory, but using the authentication secret to protect the
initial HELLO. It is advised to use an ephemeral keypair and the two stage
HELLO to be able to differentiate the keypair used when authenticating to
the directory versus authenticating to the source.

If the address is a tunnel, a channel is reserved similarly to define-bstream.
data transfers work the same, except it is always streaming with no finite
limit and data can flow in both directions.

### command - 14, tunnel-drop
- [18] : tunnel-id

Mark the channel used for a tunnel as being in a broken state. This is to
let both source and sink to free related resources.

##  Event (2), fixed length
- [0..7] sequence number : uint64
- [8   ] channel-id      : uint8
- [9+  ] event-data      : special

The event data does not currently have a fixed packing format as the model is
still being refined and thus we use the opaque format from
arcan\_shmif\_eventpack.

Worthy of note is that this message type is the most sensitive to side channel
analysis as input device events are driven by user interaction. Combatting this
by injecting discard- events is kept outside the protocol implementation, and
deferred to the UI/window manager.

## Vstream-data (3), Astream-data (4), Bstream-data (5) (variable length)
- [0   ] channel-id  : uint8
- [1..4] stream-id   : uint32
- [5..6] length      : uint16

The data messages themselves will make out the bulk of communication, and ties
to a pre-defined channel/stream.

Bstream data applies compression based on each individual chunk rather than
stream-scope.

# Compressions and Codecs

To get audio/video/data transfers bandwidth efficient, the contents must be
compressed in some way. This is a rats nest of issues, ranging from patents
in less civilized parts of the world to complete dependency and hardware hell.

The current approach to 'feature negotiation' is simply for the sender to
try the best one it can, and fall back to inefficient safe-defaults if the
recipient returns a remark of the frame as unsupported.

# Event Model

The more complicated interactions come from events and their ordering,
especially when trying to interleave or deal with data carrying events.

The only stage this 'should' require special treatment is for font transfers
for client side text rendering which typically only happen before activation.

For other kinds of transfers, state and clipboard, they act as a mask/block
for certain other events. If a state-restore is requested for instance, it
makes no sense trying to interleave input events that assumes state has been
restored.

Input events are the next complication in line as any input event that relies
on a 'press-hold-release' pattern interpreted on the other end may be held for
too long, or with clients that deal with raw codes and repeats, cause
extraneous key-repeats or 'shadow releases'. To minimize the harm here, a more
complex state machine will be needed that tries to determine if the channel
blocks or not by relying on a ping-stream.
