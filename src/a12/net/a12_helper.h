/*
 * Copyright: 2018-2020, Bjorn Stahl
 * License: 3-Clause BSD
 * Description: This is a set of helper functions to deal with the event loop
 * specifically for acting as a translation proxy between shmif- and a12. The
 * 'server' and 'client' naming is a misnomer as the 'server' act as a local
 * shmif server and remote a12 client, while the 'client' act as a local shmif
 * client and remote a12 server.
 */

#ifndef HAVE_A12_HELPER

enum a12helper_pollstate {
	A12HELPER_POLL_SHMIF = 1,
	A12HELPER_WRITE_OUT = 2,
	A12HELPER_DATA_IN = 4
};

struct a12_broadcast_beacon;
struct anet_discover_opts;
struct ipcfg;

struct a12helper_opts {
	struct a12_vframe_opts (*eval_vcodec)(
		struct a12_state* S, int segid, struct shmifsrv_vbuffer*, void* tag);
	void* tag;

/* Set to the maximum distance between acknowledged frame and pending outgoing
 * and halt releasing client vframe until that resets back to within tolerance.
 * This is a coarse congestion control mechanism, meant as a placeholder until
 * something more refined can be developed.
 *
 * At 'soft_block' only partial frame updates will be let through,
 * At 'block' all further updates will be deferred
 */
	size_t vframe_soft_block;
	size_t vframe_block;

/* a12cl_shmifsrv- specific: set to a valid local connection-point and incoming
 * EXIT_ events will be translated to DEVICE_NODE events, preventing the remote
 * side from closing the window */
 	const char* redirect_exit;

/* a12cl_shmifsrv- specific: set to a valid local connection-point and it will
 * be set as the DEVICE_NODE alternate for incoming connections */
	const char* devicehint_cp;

/* opendir to populate with b64[checksum] for fonts and other cacheables */
	int bcache_dir;
};

/*
 * Take a prenegotiated connection [S] and an accepted shmif client [C] and
 * use [fd_in, fd_out] (which can be set to the same and treated as a socket)
 * as the bitstream carrer.
 *
 * This will block until the connection is terminated.
 */
void a12helper_a12cl_shmifsrv(struct a12_state* S,
	struct shmifsrv_client* C, int fd_in, int fd_out, struct a12helper_opts);

/*
 * Setup a listening endpoint, and signal whenver there is data on the (optional)
 * shmif context or when there is a beacon that triggered something known.
 */
void
	a12helper_listen_beacon(
		struct arcan_shmif_cont* C,
		struct anet_discover_opts* O,

/*
 * We have a beacon match in whatever domain [socket], matching to a previous
 * key in 'accepted' - if the beacon is valid but unknown, 'tag' will be set
 * to NULL, otherwise tag might be set to empty (accepted but untagged) or the
 * actual keystore tagname. Addr is the resolved gethostname() result.
 *
 * The [nonce] is time sensitive, if it's to be used to initiate a connection
 * to host and used to tag the initial packet, it should be done so
 * immediately.
 *
 * There can be several on_beacon calls for one-beacon if there are multiple
 * matches in the set of identities tied to one beacon. Note that these can be
 * spoofed to provoke a result, i.e. by collecting Kpubs through some other
 * means and then sending them out in an active scan yourself.
 *
 * Return false to stop processing further beacons.
 */
		bool (*on_beacon)(
			struct arcan_shmif_cont* C,
			const uint8_t kpub[static 32],
			const uint8_t nonce[static 8],
			const char* tag,
			char* addr),
		bool (*on_shmif)(struct arcan_shmif_cont* C)
	);

/*
 * Generate two beacon packets based on your outbound keyset.
 *
 * This creates two dynamic allocations (one, and two) that the caller takes
 * responsibility for. These should be sent to a broadcast or unicast target to
 * hopefully get a beacon back signalling that the two parties know each-
 * other, with at least a second in between sending [one] and [two].
 *
 * Internally this sweeps the set of used outbound keys, generate their public
 * version and derives a random challenge + hash form.
 *
 * The beacons can't be re-used between calls as listeners require that the
 * challenge has not been seen before.
 */
struct keystore_mask;
struct keystore_mask*
	a12helper_build_beacon(
		struct keystore_mask* head,
		struct keystore_mask* tail,
		uint8_t** one,
		uint8_t** two, size_t* sz
	);

/*
 * Tradeoff between collision risk and number of keys that can fit in a single
 * broadcast packet. Changing this requires the same change for all
 * stakeholders so best done for controlled environments where the key size is
 * a bigger concern.
 */
#ifndef DIRECTORY_BEACON_MEMBER_SIZE
#define DIRECTORY_BEACON_MEMBER_SIZE 32
#endif

/*
 * Helpers for setting up listen_beacon and build_beacon
 */
struct anet_discover_opts {
	int limit; /* -1 infinite, 0 = once, > count down after each */
	int timesleep; /* seconds between beacon passes */
	const char* ipv6; /* set to bind to IPv6 multicast address */

	bool (*discover_beacon)(
		struct arcan_shmif_cont*,
		const uint8_t kpub[static 32],
		const uint8_t nonce[static 8],
		const char* tag, char* addr
	);

	struct ipcfg* IP; /* build with a12helper_discover_ipcfg(cfg) */
	bool (*on_shmif)(struct arcan_shmif_cont* C);
	struct arcan_shmif_cont* C;
};

void anet_discover_listen_beacon(struct anet_discover_opts* cfg);
void anet_discover_send_beacon(struct anet_discover_opts* cfg);

/*
 * build / setup socket into [cfg], returns NULL or error or a user-presentable
 * string as to why the configuration failed.
 */
const char* a12helper_discover_ipcfg(struct anet_discover_opts* cfg, bool beacon);

/*
 * Take a prenegotiated connection [S] serialized over [fd_in/fd_out] and
 * map to connections accessible via the [cp] connection point.
 *
 * If a [prealloc] context is provided, it will be used instead of the [cp].
 * Note that it should come in a SEGID_UNKNOWN/SHMIF_NOACTIVATE state so
 * that the incoming events from the source will map correctly.
 *
 * Returns:
 * a12helper_pollstate bitmap
 *
 * Error codes:
 *  -EINVAL : invalid connection point
 *  -ENOENT : couldn't make shmif connection
 */
int a12helper_a12srv_shmifcl(
	struct arcan_shmif_cont* prealloc,
	struct a12_state* S, const char* cp, int fd_in, int fd_out);

uint8_t* a12helper_tob64(const uint8_t* data, size_t inl, size_t* outl);
bool a12helper_fromb64(const uint8_t* instr, size_t lim, uint8_t outb[static 32]);

#endif
