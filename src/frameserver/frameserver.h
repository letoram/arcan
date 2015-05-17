#ifndef _HAVE_AFSRV
#define _HAVE_AFSRV

/*
 * This header defines the possible archetype frameserver
 * slots. Frameservers are semi-trusted, authoritative
 * arcan- initiated shmif connections (requires no
 * connection points, many frameservers can be linked
 * statically and doesn't require mounted file-systems
 * etc.)
 *
 * This provides the ability to be more aggressive and
 * controlling when it comes to scheduling, process
 * control, sandboxing, priority, firewall rules etc.
 */

/* [decode]
 * A/V data provider, sensitive in regards to synchronization,
 * high I/O, possible handle passing, high risk of exploitable
 * parsers. Assymetric network load (high in, minimal out)
 */
int afsrv_decode(struct arcan_shmif_cont*, struct arg_arr*);

/* [encode]
 * Deals with sensitive data (e.g. user output), buffering
 * and latency tradeoff relevant. High CPU with lower risk
 * security wise (trusted input, partially trusted encoder,
 * untrusted streaming protocol implying partially trusted
 * destination server.
 */
int afsrv_encode(struct arcan_shmif_cont*, struct arg_arr*);

/* [remoting]
 * Deals with possibly hostile input in regards to keypresses,
 * and possibly hostile data in bchunks/state transfers.
 * Mitigation is done by making input reaction, etc. explicit
 * in the running appl. Latency vs. throughput balance in
 * favor of latency, asymetric network behavior (low in,
 * higher out).
 */
int afsrv_remoting(struct arcan_shmif_cont*, struct arg_arr*);

/* [Terminal]
 * Deals with untrusted/potentially hostile input- output
 * spanning multiple system privilege levels and different
 * sandboxes. Primarily event-driven with additional models
 * needed to distinguish between a terminal that is allowed
 * to spawn network connections etc. vs. terminals that are
 * not.
 */
int afsrv_terminal(struct arcan_shmif_cont*, struct arg_arr*);

/* [Gaming]
 * Interactive applications with high CPU/GPU/latency demands,
 * multiple input configurations and special cases for multi-
 * segment connections (e.g. HMD, monitor-mapping controls).
 */
int afsrv_game(struct arcan_shmif_cont*, struct arg_arr*);

/*
 * [generic A/V/input]
 * Fewer assumptions, primarily for hooking up customized
 * system-specific data sources (as other programs etc. might
 * as well use non-authoritative connections).
 */
int afsrv_avfeed(struct arcan_shmif_cont*, struct arg_arr*);

/*
 * [network client/server]
 * These are primarily intended for one shared protocol suitable
 * for working on a local area network, or remotely through
 * pre-shared credentials or trusted list servers.
 * Some of the rough ideas for what this will be used for is:
 *  - local (non-hostile) network discovery
 *    [pushing packaged appls or state]
 *    [latency sensitive small message passing, e.g. 'netplay']
 *    [design case for working with protective keystore
 *     and crypto usability experiments with curve25519]
 * The current implementation is in a very experimnental state.
*/
int afsrv_netcl(struct arcan_shmif_cont*, struct arg_arr*);
int afsrv_netsrv(struct arcan_shmif_cont*, struct arg_arr*);

#ifndef LOG
#define LOG(...) (fprintf(stderr, __VA_ARGS__))
#endif
#endif
