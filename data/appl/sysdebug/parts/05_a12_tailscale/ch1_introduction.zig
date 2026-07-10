
pub fn __init() void {
    return .{
        .title = "Introduction",
        .subtitle = "Part V · Ch 1 · a12 over Tailscale",
        .part_id = 5,
        .chapter_id = 1,
        .body = .{
            .{
                .kind = "epigraph",
                .body = "'Transparency' is evaluated from the perspective of " ++ ("the user; it is not even desirable for the underlying " ++ ("layers to operate identically locally versus across " ++ "networks.")),
                .cite = "Ståhl, arcan-fe.com, 2020-10-28",
            },
            .{
                .kind = "text",
                .body = "a12 is the arcan network protocol. Today it ships as " ++ ("part of arcan; tomorrow it runs zig-native (the posix_libc " ++ ("shim work in Part III is the gating dependency). Once " ++ ("the zig path is clean, the production deployment is a12 " ++ ("over Tailscale: every device the user owns runs an a12 " ++ ("endpoint and a directory mediates discovery. Part V " ++ ("documents debugging when the fault may be on the other " ++ ("side of the Tailnet — when the symptom is local but the " ++ ("cause is on a machine you do not currently have a shell " ++ "on.")))))))),
            },
            .{
                .kind = "h2",
                .body = "1.1  Demarcation",
            },
            .{
                .kind = "text",
                .body = "What is in scope: the a12 protocol, its directory " ++ ("rendezvous, the appl_load and appl_store hooks, the " ++ ("Tailnet as the carriage. Out of scope: replacing " ++ ("Tailscale. The choice of substrate is orthogonal to the " ++ ("protocol; if Tailscale ceased to exist tomorrow, a12 " ++ ("would still need a routed transport, and the Wireguard-" ++ ("style story is the leading candidate. We use Tailscale " ++ ("because it works and the keystore story is already " ++ "compatible. Other carriages are a separate ticket."))))))),
            },
            .{
                .kind = "ticketref",
                .id = "0034-shmif-native-guide-for-external-agents",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0100-refactor-posix-libc",
                .note = "the gating dep for zig-native a12",
            },
            .{
                .kind = "h2",
                .body = "1.2  Software-intensive across the wire",
            },
            .{
                .kind = "epigraph",
                .body = "Software-intensive systems are composed of many " ++ ("different kinds of software, running on a variety " ++ ("of machines in close collaboration with other " ++ ("kinds of devices and processes both mechanical and " ++ "human."))),
                .cite = "Mellstrand & Ståhl 2012, p. 10",
            },
            .{
                .kind = "text",
                .body = "a12 makes the original's 'variety of machines' literal. " ++ ("The shmif segment now has a network counterpart: an " ++ ("a12_session that carries the same event taxonomy " ++ ("(EVENT_EXTERNAL_MESSAGE, EVENT_NEWSEGMENT, the audio " ++ ("and video buffer signals) over a stream of encoded " ++ ("frames. The analyst's mental model has to include " ++ ("partition tolerance — the protocol is designed to " ++ ("survive the wire dropping mid-frame, but 'designed to " ++ ("survive' is not the same as 'always survives', and " ++ "the gap is where the chapter's bugs live.")))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| ps name=arcan-net",
                .note = "every live a12 endpoint on this host",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/src/a12/a12.zig",
                .note = "the protocol surface",
            },
            .{
                .kind = "h2",
                .body = "1.3  Cause and panic across the wire",
            },
            .{
                .kind = "text",
                .body = "The Ståhl quote at the head of this chapter is the " ++ ("framing: transparency is evaluated from the user's " ++ ("perspective, and the underlying layers should not " ++ ("behave identically. They do not. A rendering glitch " ++ ("that looks like a renderer bug may be packet " ++ ("reordering across the Tailnet. An auth failure that " ++ ("looks like a config bug may be clock skew between the " ++ ("two endpoints (TLS hates clock skew). The user " ++ ("experiences both as 'arcan misbehaving'; the cause is " ++ "in neither end's arcan.")))))))),
            },
            .{
                .kind = "text",
                .body = "The proximal/distal split applies and is harsher: " ++ ("proximal cause may be on a machine the analyst does " ++ ("not have shell on. The distal cause is almost always " ++ ("in the directory configuration or the keystore, both " ++ ("of which the analyst does have access to. The " ++ ("discipline is to walk distal-first, because the local " ++ "evidence is the cheap evidence."))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| arcan-net keystore",
                .note = "the keystore on this host; pair with the directory " ++ "config on the other host",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /home/x/.arcan/logs net",
                .note = "the network-bucketed engine log",
            },
            .{
                .kind = "h2",
                .body = "1.4  Origin of anomalies",
            },
            .{
                .kind = "h3",
                .body = "Protocol-version drift",
            },
            .{
                .kind = "text",
                .body = "One side upgraded, the other did not. a12 negotiates " ++ ("version on handshake and the protocol promises " ++ ("backwards compatibility, but the promise is only as " ++ ("good as the test matrix. A handshake-side version drift " ++ ("appears as a refused-connection error; an in-session " ++ ("drift appears as a frame the receiver cannot parse and " ++ ("drops, which the user sees as missing audio or video " ++ "with no error in either log.")))))),
            },
            .{
                .kind = "h3",
                .body = "Key trust assumptions",
            },
            .{
                .kind = "text",
                .body = "TOFU at first contact, certificate-pinning thereafter. " ++ ("The trust mistake is bypassing TOFU on a host that " ++ ("should have demanded it — usually because the keystore " ++ ("was copied from another host without re-pinning. The " ++ ("symptom is auth-fail with no obvious 'why this host'; " ++ ("the diagnostic is comparing the keystore byte-for-byte " ++ "between the two hosts."))))),
            },
            .{
                .kind = "h3",
                .body = "Directory misconfig",
            },
            .{
                .kind = "text",
                .body = "The directory is the rendezvous point. A misconfigured " ++ ("directory advertises endpoints that do not exist or " ++ ("fails to advertise endpoints that do; either way the " ++ ("user's LIST request shows the wrong set. Reading the " ++ ("directory's config.lua is the one-step fix when the " ++ ("directory is on a host you control; it is a " ++ "research project when it is not."))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| find /home/x/next/arcan/src/a12 grep version",
                .note = "every version-handshake site in the source",
            },
            .{
                .kind = "h2",
                .body = "1.5  Methodology",
            },
            .{
                .kind = "text",
                .body = "The four actions, with one twist: Subdivide gets a new " ++ ("meaning. Where in the other parts Subdivide is per-" ++ ("compile-unit or per-frameserver, here it is per-side-of-" ++ ("the-wire. The local arcan, the local arcan-net, the " ++ ("directory (third machine), the remote arcan-net, the " ++ ("remote arcan. Five subsystems, four of which the " ++ ("analyst probably has incomplete access to. The " ++ ("methodology is to make each side's contribution " ++ ("explicitly observable from the local side, via " ++ ("anet_session captures and the (proposed) .monitor " ++ "stream verb."))))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| ps name=arcan-net",
                .note = "the local subsystems, two of the five",
            },
            .{
                .kind = "h2",
                .body = "1.6  Concluding",
            },
            .{
                .kind = "text",
                .body = "Ch 2 walks the protocol from handshake through frames " ++ ("through the directory through the package manifest. " ++ ("Ch 3 lands the four-action spine across the wire. " ++ ("Ch 4 names the verbs — including the recursive case " ++ ("where this very appl is read over a12 from a remote " ++ ("sink, validating the visibility rule survives " ++ "transport."))))),
            },
            .{
                .kind = "crosslink",
                .target = "05_a12_tailscale:ch2_software_demystified",
            },
        },
        .cross_links = .{
            "00_foundations:ch1_introduction",
            "05_a12_tailscale:ch2_software_demystified",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 5,
                .chapter = 1,
            },
        },
        .tickets = .{
            "0100-refactor-posix-libc",
            "0034-shmif-native-guide-for-external-agents",
        },
    };
}
