
pub fn __init() void {
    return .{
        .title = "Software Demystified",
        .subtitle = "Part V · Ch 2 · a12 over Tailscale",
        .part_id = 5,
        .chapter_id = 2,
        .body = .{
            .{
                .kind = "epigraph",
                .body = "The key principle for a toolchain is that a series " ++ ("of tools is to be applied where the output from one " ++ "tool is the input to the next."),
                .cite = "Mellstrand & Ståhl 2012, p. 43",
            },
            .{
                .kind = "text",
                .body = "For a network protocol the toolchain is the protocol " ++ ("stack: each layer's output is the next layer's input. " ++ ("Eight layers from source to a sink rendering a remote " ++ ("appl, with the directory as the rendezvous between " ++ "stages 4 and 5."))),
            },
            .{
                .kind = "h2",
                .body = "2.1  Source",
            },
            .{
                .kind = "text",
                .body = "src/a12/{a12,a12_encode,a12_decode,a12_types}.zig holds " ++ ("the protocol; src/a12/crypto_shim.zig wraps blake3 and " ++ ("the symmetric primitives; the keystore is in " ++ ("src/a12/keystore.zig. The source is small enough that " ++ ("reading it cold takes a couple of hours, and the read " ++ ("is well-spent — every cause-of-fault investigation " ++ "ends in one of those files."))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| find /home/x/next/arcan/src/a12",
                .note = "the source surface",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/src/a12/a12.zig",
                .note = "the protocol surface",
            },
            .{
                .kind = "h2",
                .body = "2.2  The handshake",
            },
            .{
                .kind = "text",
                .body = "TOFU on first contact: each side records the other's " ++ ("public key and trusts it from then on. Role negotiation " ++ ("follows: Source (the one running the appl), Sink (the " ++ ("one rendering it), Directory (the rendezvous-only " ++ ("third party). The role determines what the rest of " ++ ("the session is allowed to do — a Sink cannot push " ++ ("frames at the Source. The handshake is the first place " ++ ("version drift fails; if it fails here at all, the " ++ "session aborts before any frame data flows."))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| grep handshake /home/x/next/arcan/src/a12",
                .note = "every handshake site in the source",
            },
            .{
                .kind = "h2",
                .body = "2.3  Frame encoding",
            },
            .{
                .kind = "text",
                .body = "Video, audio, blob, and event channels. The shmif event " ++ ("taxonomy maps onto a12 frames one-to-one: an " ++ ("EVENT_NEWSEGMENT becomes a frame the receiver decodes " ++ ("into a local segment open. Video and audio frames are " ++ ("compressed (zstd for the binary frames, the per-format " ++ ("audio codec for audio); event frames are short and " ++ ("uncompressed. The encoder side runs in arcan-net, the " ++ "decoder in the same binary on the other end.")))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/src/a12/a12_encode.zig",
                .note = "the encoder",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/src/a12/a12_decode.zig",
                .note = "the decoder",
            },
            .{
                .kind = "h2",
                .body = "2.4  The directory",
            },
            .{
                .kind = "text",
                .body = "The rendezvous point. A directory advertises the appls " ++ ("it hosts and the endpoints they are reachable through; " ++ ("clients LIST against it to discover what is available. " ++ ("The [notify] flag turns the LIST into a subscription, " ++ ("so a new appl appearing in the directory pushes to " ++ ("subscribed clients. Per the 2026-01-26 'Weaving a " ++ ("Different Web' article, the directory also runs " ++ ("controller hooks (appl_load, appl_store) that shape " ++ "what travels — see §2.7."))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| arcan-net keystore",
                .note = "today's view of which directories this host trusts",
            },
            .{
                .kind = "h2",
                .body = "2.5  The package",
            },
            .{
                .kind = "text",
                .body = "A signed appl bundle: the Lua source tree under data/" ++ ("appl/<name>/, a manifest declaring entry points and " ++ ("permissions, and per-user state slots reserved by name. " ++ ("Reserved slots: .index (search), .monitor (live " ++ ("telemetry stream), .debug (diagnostic dumps), .report " ++ ("(post-mortem). The package is signed by the publisher " ++ ("and verified by the sink against the publisher's " ++ "pinned key. Push fails closed on signature mismatch.")))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| find /home/x/next/arcan/data/appl/sysdebug",
                .note = "this very appl, as the package would see it",
            },
            .{
                .kind = "h2",
                .body = "2.6  The wire to Tailscale",
            },
            .{
                .kind = "text",
                .body = "arcan-net binds a regular TCP socket on the host's " ++ ("Tailscale-assigned IP; Tailscale handles routing, NAT " ++ ("traversal, and authentication of the network layer " ++ ("underneath. From a12's perspective the carriage is " ++ ("transparent — a TCP socket is a TCP socket — but the " ++ ("Tailnet's MTU can differ from the local LAN's, and the " ++ ("differences sometimes show up as fragmentation that " ++ "a12's frame pacing has to absorb.")))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| procfs $(pidof arcan-net) fd",
                .note = "the actual TCP sockets, with the Tailscale-side " ++ "addresses visible",
            },
            .{
                .kind = "h2",
                .body = "2.7  Server-side controllers",
            },
            .{
                .kind = "text",
                .body = "Per the 'Weaving a Different Web' story, the " ++ ("directory side runs config.lua hooks: appl_load fires " ++ ("when a client requests an appl, appl_store fires when " ++ ("a publisher pushes an updated package. The hooks shape " ++ ("what travels — they can rewrite the manifest, reject " ++ ("the request, or capture an audit trail. Misconfigured " ++ ("hooks are a class of bug invisible from the client " ++ ("side except as 'why is this LIST result missing the " ++ "appl I expect to see'."))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| grep -r appl_load /home/x/next/arcan",
                .note = "every reference to the controller hook in the source",
            },
            .{
                .kind = "h2",
                .body = "2.8  The future",
            },
            .{
                .kind = "text",
                .body = "zig-native a12. Today arcan-net links the C shmif " ++ ("library; tomorrow, after ticket 0100 lands, it will " ++ ("be the first end-to-end zig-self-host build of a non-" ++ ("trivial arcan binary. From the consumer's side nothing " ++ ("changes — same protocol, same wire format, same " ++ ("directory verbs — but the build pipeline simplifies " ++ ("considerably and the LLVM dependency drops out of the " ++ ("network path. This is the arc the appl exists to " ++ "support."))))))),
            },
            .{
                .kind = "ticketref",
                .id = "0100-refactor-posix-libc",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0100-refactor-posix-libc",
                .note = "the cluster gating the future",
            },
            .{
                .kind = "h2",
                .body = "Closing",
            },
            .{
                .kind = "text",
                .body = "Eight stages from source to sink. Ch 3 takes the four-" ++ ("action spine and lands it on the wire — including the " ++ ("subsystem split that puts the analyst on the wrong side " ++ "of the partition some of the time.")),
            },
            .{
                .kind = "crosslink",
                .target = "05_a12_tailscale:ch3_principal_debugging",
            },
        },
        .cross_links = .{
            "05_a12_tailscale:ch1_introduction",
            "05_a12_tailscale:ch3_principal_debugging",
            "00_foundations:ch2_software_demystified",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 5,
                .chapter = 2,
            },
        },
        .tickets = .{
            "0100-refactor-posix-libc",
            "0034-shmif-native-guide-for-external-agents",
        },
    };
}
