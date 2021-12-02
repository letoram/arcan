/*
 * This is just re-using the same code-paths as in arcan-net with a different
 * routine to argument parsing and debug output.
 *
 * What it needs 'extra' is basically a rendezvous / dictionary server used for
 * local / p2p service exchange to learn of keys.
 *
 * Another worthwhile distinction is that remoting and encode also provides
 * some a12 client/server functionality, but those are for working with
 * 'composited' desktops, while this one is between arcan clients across a12.
 */

#include <arcan_shmif.h>
#include <arcan_shmif_server.h>

#define KEYSTORE_ERRMSG "couldn't open keystore"

#ifndef COUNT_OF
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include "a12.h"
#include "../../util/anet_helper.h"

enum trust {
	TRUST_KNOWN,
	TRUST_VERIFY_UNKNOWN,
	TRUST_TRANSITIVE
};

static bool flush_shmif(struct arcan_shmif_cont* C)
{
	int rv;
	arcan_event ev;

	while ((rv = arcan_shmif_poll(C, &ev)) > 0){
		if (ev.category == EVENT_TARGET && ev.tgt.kind == TARGET_COMMAND_EXIT)
			return false;
	}

	return rv == 0;
}

static int discover_broadcast(struct arcan_shmif_cont* C, int trust, const char* opt)
{
/* first iteration:
 *
 * 0. keystore - remember the accepted key that was used with a tag.
 *    this is used for the search for (1).
 *
 *    bool a12helper_keystore_mark_tag(
 *         const char* tag, const uint8_t pubk[static 32]);
 *
 *    void a12helper_keystore_match_mark(
 *         const uint8_t nonce[static 8], const uint8_t hash[static 32],
 *         void (*match)(void* tag,
 *                       const char* tag, const uint8_t pubk[static 32], void*
 *                      ), void* tag
 *         );
 *
 * 1. fetch Kpub.default
 * 2. generate nonce, H(Kpub.default | nonce) - broadcast, bloomfilter(nonce)
 * 3. wait 1s.
 * 4. generate nonce, H(Kpub.default | nonce.old+1), bloomfilter(nonce)
 * 5. wait for incoming packets.
 *    6. incoming packages are treated like discover_passive here but without
 *       the reply stack.
 * 6. periodically flush filter.
 */
	return EXIT_FAILURE;
}

static int discover_passive(struct arcan_shmif_cont* C, int trust, const char* opt)
{
/*
 * related to discover_passive so the implementation for this should be in the helper
 * so that arcan-net can make use of it as well.
 *
 * 0. bind broadcast- listen.
 * 1. on incoming packet
 *    check nonce against bloom(nonce, nonce+1) : match? ignore.
 *
 * 2. each key: check H(nonce, Kpub.accepted) for match against
 */
	return EXIT_FAILURE;
}

struct listent;
struct listent {
	char name[64];
	bool seen;
	struct listent* next;
};

struct tagopt {
	struct arcan_shmif_cont* C;
	int delay;
	bool alive;
	const char* key;
	struct listent* first;
};

static void reset_seen(struct listent* cur)
{
	while (cur){
		cur->seen = false;
		cur = cur->next;
	}
}

static void mark_lost(struct arcan_shmif_cont* C, struct listent** first)
{
	struct listent** last = first;
	struct listent* cur = *first;

/* sweep through all known nodes and if one wasn't visited this sweep,
 * send an event marking it as unknown and then unlink from the list */
	while (cur){
		if (!cur->seen){
			arcan_event ev = {
				.ext.kind = ARCAN_EVENT(NETSTATE),
				.ext.netstate = {0}
			};
			snprintf(ev.ext.netstate.name,
				COUNT_OF(ev.ext.netstate.name), "%s", cur->name);
			arcan_shmif_enqueue(C, &ev);

			(*last) = cur->next;
			free(cur);
			cur = *last;
		}
		else{
			last = &cur->next;
			cur = cur->next;
		}
	}
}

/* Singleton accessor workaround, the anet_helper_keystore API wasn't really
 * designed / built for this use - anet_cl_setup will swap active keystore
 * which releases current if the contents doesn't match. The tags_ callback is
 * not reliable if the keystore gets modified (open/release) from within the
 * callback. */
static bool get_keystore(
	struct arcan_shmif_cont* C, struct keystore_provider* prov)
{
	static struct keystore_provider ks = {.directory.dirfd = -1};

	if (ks.directory.dirfd == -1){
		ks.type = A12HELPER_PROVIDER_BASEDIR;
		const char** err = NULL;
		ks.directory.dirfd = a12helper_keystore_dirfd(err);
		if (-1 == ks.directory.dirfd){
			arcan_shmif_last_words(C, KEYSTORE_ERRMSG);
			return false;
		}
	}

	*prov = ks;
	return true;
}

static bool tagh(const char* name, void* tag)
{
	struct tagopt* opt = tag;
	struct a12_context_options a12opts = {
		.local_role = ROLE_PROBE
	};
	struct anet_options opts =
	{
		.key = name,
		.opts = &a12opts
	};

/* don't need to do any allocation so early out the last entry */
	if (!name)
		return true;

/* keystore gets released between each cl_setup call */
	if (!get_keystore(opt->C, &opts.keystore)){
		return false;
	}

/* some might want to provide another secret, this only matters for deep
 * as it won't apply until the authentication handshake takes place */
	if (opt->key)
		snprintf(a12opts.secret, sizeof(a12opts.secret), "%s", opt->key);

/* this will depth- first the tag, and if a connection is there, the 'deep'
 * option will also attempt to authenticate before shutting down the socket */
	struct anet_cl_connection con = anet_cl_setup(&opts);

/* flush the shmif connection to determine if we should stop */
	if (!flush_shmif(opt->C)){
		opt->alive = false;
		return false;
	}

	if (con.errmsg){
		free(con.errmsg);
	}

/* connection didn't go through, move on to the next tag */
	if (-1 == con.fd){
		goto out;
	}

/* already known? then just re-mark as seen and move on */
	struct listent** cur = &opt->first;
	while (*cur){
		if (strcmp((*cur)->name, name) == 0){
			close(con.fd);
			(*cur)->seen = true;
			goto out;
		}
		cur = &((*cur)->next);
	}
	*cur = malloc(sizeof(struct listent));
	**cur = (struct listent){
		.seen = true
	};
	snprintf((*cur)->name, 64, "%s", name);

/* if deep is desired, perform authentication and set (type) to
 * 1: source, 2: sink or 4: directory. */
	arcan_event ev = {
		.ext.kind = ARCAN_EVENT(NETSTATE),
		.ext.netstate = {
			.state = 1,
			.type  = a12_remote_mode(con.state)
		}
	};
	snprintf(ev.ext.netstate.name,
		COUNT_OF(ev.ext.netstate.name), "%s",name);
	arcan_shmif_enqueue(opt->C, &ev);

out:
	if (-1 != con.fd){
		shutdown(con.fd, SHUT_RDWR);
		close(con.fd);
	}

	a12_free(con.state);

	if (opt->delay)
		sleep(opt->delay);

	return true;
}

static int discover_sweep(struct arcan_shmif_cont* C, int trust, const char* opt)
{
	struct tagopt tag = {
		.C = C,
		.delay = 1,
		.alive = true
	};
	int sweep_pause = 10;

	struct keystore_provider prov;
	if (!get_keystore(C, &prov))
		return EXIT_FAILURE;

	if (!a12helper_keystore_open(&prov)){
		arcan_shmif_last_words(C, KEYSTORE_ERRMSG);
		arcan_shmif_drop(C);
		return EXIT_FAILURE;
	}

	while (flush_shmif(C)){
		reset_seen(tag.first);
		a12helper_keystore_tags(tagh, &tag);
		mark_lost(C, &tag.first);
		sleep(sweep_pause);
	}

	arcan_shmif_drop(C);
	return EXIT_SUCCESS;
}

static int discover_directory(struct arcan_shmif_cont* C, int trust, const char* opt)
{
/*
 * 1. grab tag from opt, connect to it.
 * 2. authenticate, check directory type.
 * 3. store list of known hosts (just regular DISCOVER events)
 *
 * 4. question: should we be able to act as directory as well? (i.e. build tree)
 *              this opens up scaling issues, cycle detection
 *              device search pubk
 *
 * 5. nat-punch request.
 * 6. query applications, proxy/resolve names.
 *
 * 7.           wilder things - register as cache? (file-swarm..)
 */
	return EXIT_FAILURE;
}

int afsrv_netcl(struct arcan_shmif_cont* C, struct arg_arr* args)
{
/* lua:net_discover maps to this */
	const char* dmethod = NULL;
	if (arg_lookup(args, "discover", 0, &dmethod)){
		const char* trust = NULL;
		const char* opt = NULL;

		arg_lookup(args, "trust", 0, &trust);
		arg_lookup(args, "opt", 0, &opt);
		int trustm = TRUST_KNOWN;

		if (strcmp(dmethod, "sweep") == 0){
			return discover_sweep(C, trustm, opt);
		}
		else if (strcmp(dmethod, "passive") == 0){
			return discover_passive(C, trustm, opt);
		}
		else if (strcmp(dmethod, "broadcast") == 0){
			return discover_broadcast(C, trustm, opt);
		}
		else if (strcmp(dmethod, "directory") == 0){
			return discover_directory(C, trustm, opt);
		}
		else {
			arcan_shmif_last_words(C, "unsupported discovery method");
			arcan_shmif_drop(C);
			return EXIT_FAILURE;
		}
	}

	arcan_shmif_last_words(C, "basic net_open behaviour unfinished");
/* just resolve, connect and handover-exec into arcan-net */
	return EXIT_FAILURE;
}

int afsrv_netsrv(struct arcan_shmif_cont* c, struct arg_arr* args)
{
/* just bind socket, wait for connection, then request subsegment and handover
 * exec with subsegment and socket into arcan-net */
	return EXIT_FAILURE;
}
