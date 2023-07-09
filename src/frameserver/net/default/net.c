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
#include <inttypes.h>
#include <netdb.h>
#include "a12.h"
#include "a12_int.h"
#include "net/a12_helper.h"
#include "net/directory.h"
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
			return EXIT_FAILURE;
	}

	return rv == 0;
}

static struct {
	bool soft_auth;
} global;

static struct pk_response key_auth_local(uint8_t pk[static 32])
{
	struct pk_response auth = {0};
	char* tmp;
	uint16_t tmpport;

/*
 * here is the option of deferring pubk- auth to arcan end by sending it as a
 * message onwards and wait for an accept or reject event before moving on.
 */
	if (a12helper_keystore_accepted(pk, NULL) || global.soft_auth){
		auth.authentic = true;
		a12helper_keystore_hostkey("default", 0, auth.key, &tmp, &tmpport);
	}

	return auth;
}

static int discover_broadcast(struct arcan_shmif_cont* C, int trust)
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

static int discover_passive(struct arcan_shmif_cont* C, int trust)
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
			LOG("lost-known: %s\n", cur->name);
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
		.local_role = ROLE_PROBE,
		.pk_lookup = key_auth_local
	};
	struct anet_options opts =
	{
		.key = name,
		.opts = &a12opts
	};

/* don't need to do any allocation so early out the last entry */
	if (!name)
		return true;

	LOG("sweep: petname %s\n", name);
/* keystore gets released between each cl_setup call */
	if (!get_keystore(opt->C, &opts.keystore)){
		LOG("fail, couldn't access keystore\n");
		return false;
	}

/* some might want to provide another secret, this only matters for deep
 * as it won't apply until the authentication handshake takes place */
	if (opt->key){
		snprintf(a12opts.secret, sizeof(a12opts.secret), "%s", opt->key);
		LOG("setting custom secret (****)\n");
	}

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
			LOG("known-seen(%s)\n", name);
			goto out;
		}
		cur = &((*cur)->next);
	}

	*cur = malloc(sizeof(struct listent));
	**cur = (struct listent){
		.seen = true
	};
	snprintf((*cur)->name, 64, "%s", name);
	LOG("discovered:%s\n", name);

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

static int discover_test(struct arcan_shmif_cont* C, int trust)
{
/* A set of fake keys that we randomly mark as discovered or lost, will cycle
 * through, randomly discover or lose, sleep and repeat. This means that the
 * arcan end may well receive unpaired added/ removed and flipping types as
 * those are error cases to respond to. Each cycle adds 10 seconds to the delay
 * for interactive use. */

/* 0 == lost, 1 (source) 2 (sink) 4 (directory) */
	size_t step = 10;
	size_t counter = 1;
	struct arcan_event ev[] =
	{
		{ .ext.kind = ARCAN_EVENT(NETSTATE),
			.ext.netstate = {.state = 1, .type = 1, .name = "test_1"}
		},
		{ .ext.kind = ARCAN_EVENT(NETSTATE),
			.ext.netstate = {.state = 1, .type = 2, .name = "test_2"}
		},

		{ .ext.kind = ARCAN_EVENT(NETSTATE),
			.ext.netstate = {.state = 1, .type = 4, .name = "test_3"}
		},
		{ .ext.kind = ARCAN_EVENT(NETSTATE), /* invalid type */
			.ext.netstate = {.state = 1, .type = 5, .name = "test_4"}
		},
		{ .ext.kind = ARCAN_EVENT(NETSTATE), /* flip to all roles */
			.ext.netstate = {.state = 1, .type = (1 | 2 | 4), .name = "test_3"}
		},
	};

	bool found = false;
	while (flush_shmif(C)){
		sleep(1);
		counter -= 1;
		if (!counter){
			counter = step;
			step += 10;
		}
		for (size_t i = 0; i < COUNT_OF(ev); i++){
			int ot = ev[i].ext.netstate.type;
			if (found)
				ev[i].ext.netstate.type = 0;
			arcan_shmif_enqueue(C, &ev[i]);
			if (found)
				ev[i].ext.netstate.type = ot;
			sleep(1);
		}
		found = !found;
	}
	return EXIT_SUCCESS;
}

static int discover_sweep(struct arcan_shmif_cont* C, int trust)
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

/*
 * the sequence:
 *  1. initial list
 *  2. forward as messages
 *  3. server-end sends a NEWSEGMENT with HANDOVER with the reqid we want
 *  4. shmif is marked as blocked (for now), BCHUNKSTATE sent to directory with the id
 *  5. server sends possible state blob
 *  6. server sends actual appl
 *  7. forward handover to arcan_lwa
 *  8. monitor control lwa
 *  9. state changes are requested (periodically, at shut down or not at all)
 *  10. any update is sent
 */

/*
 * there are quite a few nuances missing with this:
 *  1. signing states, appls and verifying signature
 *  2. better metadata forwarding
 *  3. cleaner monitor control and crash collection
 *  4. autoupdate if appl changes
 *  5. channel messaging
 *  6. resource funnelling (btransfers within the active appl)
 *
 */
struct dircl_meta {
	int pending_reqid;
	char* pending_reqname;

	bool waiting_for_segment;
	arcan_event segev;
};

static void dircl_event(struct arcan_shmif_cont* C, int chid, struct arcan_event* ev, void* tag)
{
	LOG("event=%s", arcan_shmif_eventstr(ev, NULL, 0));
}

static struct a12_bhandler_res dircl_bevent(
	struct a12_state* S, struct a12_bhandler_meta M, void* tag)
{
	struct a12_bhandler_res res = {
		.fd = -1,
		.flag = A12_BHANDLER_DONTWANT
	};

/* so:
 * INITIALIZE:
 * COMPLETED:
 * CANCELLED:
 */
	return res;
}

/* returning false here would break us out of the ioloop */
static bool dircl_dirent(struct a12_state* S, struct appl_meta* M, void* tag)
{
  struct arcan_shmif_cont* C = arcan_shmif_primary(SHMIF_INPUT);
	struct directory_meta* dir = tag;
	struct dircl_meta* client = C->user;

/* are we just enumerating appls or do we have a pending request? */
	while (M){
		if (client->pending_reqname){
			if (strcmp(M->applname, client->pending_reqname) == 0){
				struct arcan_event ev =
				{
					.ext.kind = ARCAN_EVENT(BCHUNKSTATE),
					.category = EVENT_EXTERNAL,
					.ext.bchunk = {
						.input = true,
						.hint = false
					}
				};
				snprintf(
					(char*)ev.ext.bchunk.extensions, 6, "%"PRIu16, M->identifier);
				a12_channel_enqueue(S, &ev);
				break;
			}
		}
		else if (client->pending_reqid > 0){
		}

/* This is not good enough, should make better use of the short_descr and
 * possibly other formats. One approach is to send the extended information as
 * packed data in the actual bchunk on the ID, but it is an unnecessary step. */
 		else {
			struct arcan_event out = {
				.ext.kind = ARCAN_EVENT(BCHUNKSTATE),
				.ext.bchunk.hint = 1,
			};

			snprintf((char*)out.ext.bchunk.extensions,
				COUNT_OF(out.ext.bchunk.extensions), "%s:%d", M->applname, M->identifier);

			if (M->next)
				out.ext.bchunk.hint |= 4;

			arcan_shmif_enqueue(C, &out);
		}

		M = M->next;
	}

	return true;
}

static void dircl_userfd(struct a12_state* S, void* tag)
{
/* just flush the regular path unless we're blocked */
  struct arcan_shmif_cont* C = arcan_shmif_primary(SHMIF_INPUT);
	struct directory_meta* cbt = tag;
	struct dircl_meta* cm = C->user;

	if (cm->pending_reqid > 0)
		return;

/* if we get a new segment with a handover, the ID is the directory appl id
 * we are after - so re-request dirlist and mark as pending */
	arcan_event ev;
	while (arcan_shmif_poll(C, &ev) > 0){
	}
}

static int dircl_loop(
	struct arcan_shmif_cont* C, struct anet_cl_connection* A, struct arg_arr* args)
{
/* request dirlist and set to receive notification on changed appls */
	a12int_request_dirlist(A->state, true);
  arcan_shmif_setprimary(SHMIF_INPUT, C);

/* a mess glueing this together, but directory.h wasn't designed for the kind
 * of use we want here, at the same time maintaining two implementations of the
 * same idea would hinder progress */
	struct dircl_meta dmeta = {
	};

	struct anet_dircl_opts clcfg = {
	};

	struct directory_meta dircfg = {
		.S = A->state,
		.clopt = &clcfg,
	};

	C->user = &dmeta;
	a12_set_bhandler(A->state, dircl_bevent, &dmeta);
	anet_directory_ioloop(A->state, &dircfg,
		A->fd, A->fd, C->epipe, dircl_event, dircl_dirent, dircl_userfd);

	return EXIT_FAILURE;
}

static int discover_directory(struct arcan_shmif_cont* C, int trust)
{
	LOG("EIMPL: discover-directory\n");
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

static int connect_to_host(
	struct arcan_shmif_cont* C, struct arg_arr* args)
{
	struct keystore_provider prov;
	if (!get_keystore(C, &prov))
		return EXIT_FAILURE;

	struct a12_context_options a12opts = {
		.local_role = ROLE_SINK,
		.pk_lookup = key_auth_local
	};

	a12_set_trace_level(4095, stderr);

	const char* name;
	if (!arg_lookup(args, "host", 0, &name) || name == NULL || !strlen(name)){
		arcan_shmif_last_words(C, "missing host argument");
		return EXIT_FAILURE;
	}

	char* work = strdup(name);

/* With the afsrv_net:net_open path we are after a sink to source,
 * directory/xxx or a directory/appl as a download or as inter-appl messaging.
 * The case for acting as an outbound source comes through
 * afsrv_encode:define_recordtarget.
 *
 * For the appl case, we connect to a directory first, then send a message for
 * the resource we want.
 */
	struct anet_options opts =
	{
		.opts = &a12opts,
		.keystore = prov,
	};

/* There are several keystore options that hit here, we might want:
 *
 * 1. a known and trusted key that resolves to a possible host (name@).
 * 2. an explicit host, generating a new key and name with a custom secret ('tofu to petname').
 * 3. an explicit host, a default key and default or custom secret. ('dontcare').
 * 4. an explicit host, a throwaway key and default or custom secret. ('incognito').
 *
 * 2. is ignored for now as it lets the process mutate the keystore and the
 * implications for that are far reaching - ideally the decision should be
 * deferred to the appl level so that it can provide another interface for
 * authentication the Kpub (and it is mostly there).
 *
 * starting with option 1. */
	char* toksep = strrchr(work, '@');
	if (toksep){
		opts.key = work;
	}
/* apparently not, 3..4 */
	else {
		opts.host = work;
		if (!arg_lookup(args, "port", 0, &opts.port) || !strlen(opts.port)){
			opts.port = "6680";
		}
		global.soft_auth = true;
	}

/* some might want to provide another secret, this only matters for deep
 * as it won't apply until the authentication handshake takes place */
	const char* secret;
	if (arg_lookup(args, "secret", 0, &secret) && secret && strlen(secret)){
		snprintf(a12opts.secret, sizeof(a12opts.secret), "%s", opts.key);
	}

/* this will depth- first the tag, and if a connection is there, the 'deep'
 * option will also attempt to authenticate before shutting down the socket */
	struct anet_cl_connection con = anet_cl_setup(&opts);
	if (con.errmsg || !con.state){
		LOG("couldn't connect: %s", con.errmsg ? con.errmsg : "(unknown)");
		arcan_shmif_last_words(C, con.errmsg);
		arcan_shmif_drop(C);
		return EXIT_FAILURE;
	}

	if (a12_remote_mode(con.state) == ROLE_DIR){
		LOG("directory-client");
		return dircl_loop(C, &con, args);
	}
	else if (a12_remote_mode(con.state) == ROLE_SINK){
		arcan_shmif_last_words(C, "host-mismatch:role=sink");
		return EXIT_FAILURE;
	}

	arcan_shmif_enqueue(C, &(struct arcan_event){
			.ext.kind = ARCAN_EVENT(SEGREQ),
			.ext.segreq.kind = SEGID_HANDOVER
		});

	arcan_event acq_event;
	struct arcan_event* evpool = NULL;
	ssize_t evpool_sz;

	if (!arcan_shmif_acquireloop(C, &acq_event, &evpool ,&evpool_sz)){
		arcan_shmif_last_words(C, "client handover-req failed");
		return EXIT_FAILURE;
	}

	struct arcan_shmif_cont S =
		arcan_shmif_acquire(C, NULL, SEGID_UNKNOWN, SHMIF_NOACTIVATE);
	if (!S.addr){
		arcan_shmif_last_words(C, "couldn't map new segment");
		return EXIT_FAILURE;
	}

/* more can be done here with the original context to provide data / state and
 * a logpath, easiest is probably just to convert to TUI and let it use a
 * bufferwnd */
	a12helper_a12srv_shmifcl(&S, con.state, NULL, con.fd, con.fd);
	arcan_shmif_drop(C);
	return EXIT_SUCCESS;
}

static int show_help()
{
	fprintf(stdout,
		"Net (client) should be run authoritatively (spawned from arcan)\n"
		"Running from the command-line is only intended for developing/debugging\n\n"
		"ARCAN_ARG (environment variable, key1=value:key2:key3=value), arguments: \n"
		" Outobund connection: \n"
		"  key     \t   value   \t   description\n"
		"----------\t-----------\t-----------------\n"
		" host     \t  dsthost  \t Specify host or keystore tag@ to connect to\n"
		" mode     \t  role     \t Source, Sink or Directory\n"
		" name     \t  resname  \t For mode=directory set an explicit resource\n"
  	"\n"
		" Discovery:\n "
		"  key   \t   value   \t   description\n"
		"--------\t-----------\t-----------------\n"
		" discover \t  method   \t Set discovery mode (method=sweep,test,passive,\n"
		"          \t           \t                     broadcast or directory)\n"
	);

	return EXIT_FAILURE;
}

int afsrv_netcl(struct arcan_shmif_cont* C, struct arg_arr* args)
{
/* lua:net_discover maps to this */
	const char* dmethod = NULL;
	if (arg_lookup(args, "help", 0, &dmethod)){
		return show_help();
	}

	if (arg_lookup(args, "host", 0, &dmethod)){
		return connect_to_host(C, args);
	}
	else if (arg_lookup(args, "discover", 0, &dmethod)){
		const char* trust = NULL;
		const char* opt = NULL;

		arg_lookup(args, "trust", 0, &trust);
		int trustm = TRUST_KNOWN;

		if (strcmp(dmethod, "sweep") == 0){
			return discover_sweep(C, trustm);
		}
		else if (strcmp(dmethod, "passive") == 0){
			return discover_passive(C, trustm);
		}
		else if (strcmp(dmethod, "broadcast") == 0){
			return discover_broadcast(C, trustm);
		}
		else if (strcmp(dmethod, "directory") == 0){
			return discover_directory(C, trustm);
		}
		else if (strcmp(dmethod, "test") == 0){
			return discover_test(C, trustm);
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
	return EXIT_FAILURE;
}
