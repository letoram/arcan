/*
 * This is just re-using the same code-paths as in arcan-net with a different
 * routine to argument parsing and debug output.
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
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <poll.h>

#include "a12.h"
#include "a12_int.h"
#include "net/a12_helper.h"
#include "../../util/anet_helper.h"
#include "net/directory.h"

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

static bool get_keystore(struct arcan_shmif_cont*, struct keystore_provider*);

static struct {
	bool soft_auth;
	const char* trust_domain;
} global =
{
	.trust_domain = "outbound"
};

static struct pk_response key_auth_local(uint8_t pk[static 32], void* tag)
{
	struct pk_response auth = {0};
	char* tmp;
	uint16_t tmpport;

/*
 * here is the option of deferring pubk- auth to arcan end by sending it as a
 * message onwards and wait for an accept or reject event before moving on.
 */
	bool trusted = a12helper_keystore_accepted(pk, global.trust_domain);
		if (trusted || global.soft_auth){
			if (!trusted)
				LOG("accept_soft_unknown\n");
		uint8_t key_priv[32];
		auth.authentic = true;
		a12helper_keystore_hostkey("default", 0, key_priv, &tmp, &tmpport);
		a12_set_session(&auth, pk, key_priv);
	}

	return auth;
}

static int discover_broadcast(
	struct arcan_shmif_cont* C, struct arg_arr* arg, int trust)
{
	struct keystore_provider ks = {.directory.dirfd = -1};

	if (!get_keystore(C, &ks) || !a12helper_keystore_open(&ks)){
		arcan_shmif_last_words(C, "couldn't open keystore");
		return EXIT_FAILURE;
	}

	struct anet_discover_opts cfg = {
		.limit = -1,
		.timesleep = 10
	};

	arg_lookup(arg, "ipv6", 0, &cfg.ipv6);

	const char* err = a12helper_discover_ipcfg(&cfg, true);
	if (err){
		arcan_shmif_last_words(C, err);
		LOG("%s", err);
		return EXIT_FAILURE;
	}

	anet_discover_send_beacon(&cfg);

	return EXIT_SUCCESS;
}

/*
 * This just passively listens for broadcast beacons from discover_broadcast.
 *
 * For TRUST_KNOWN case any matches are filtered against the list of previously
 * accepted ones and beam an active discovery reply with the discovery keyset
 * to match to a preset tag.
 */
static bool on_disc_shmif(struct arcan_shmif_cont* C)
{
	int pv;
	arcan_event ev;
	while ((pv = arcan_shmif_poll(C, &ev)) > 0){
		if (ev.category == EVENT_TARGET &&
				ev.tgt.kind == TARGET_COMMAND_EXIT){
			arcan_shmif_drop(C);
			return false;
		}

/* There is the option of using TARGET_MESSAGE as a way to tell us to probe
 * or otherwise connect to the source-to-tag pairing ourselves, but since the
 * other modes (remoting, a12-encode, ...) also need to override key with src
 * information from here, it's probably better to just spawn a new process
 * and let those functions deal with it. The caveat is if we would want to
 * use the challenge as an authentication key, but there has not really been
 * an argument for that. */
	}

	if (pv == -1){
		arcan_shmif_drop(C);
		return false;
	}

	return true;
}

static bool on_disc_beacon(
	struct arcan_shmif_cont* C,
	const uint8_t kpub[static 32],
	const uint8_t nonce[static 8],
	const char* tag, char* addr)
{
	uint8_t nullk[32] = {0};
	if (memcmp(kpub, nullk, 32) == 0){
		a12int_trace(A12_TRACE_DIRECTORY, "bad_beacon:source=%s", addr);
		return true;
	}

	arcan_event ev = {
		.ext.kind = ARCAN_EVENT(NETSTATE),
		.ext.netstate = {
			.state = 1
		}
	};

/* First set tag and multipart, we ignore the default 'outbound' that just say
 * we've seen this device before but we don't know the context. If it is used
 * as a suffix, we strip that assuming that there is a tag with [outbound-]tag.*/
	if (tag){
		if (strcmp(tag, "outbound") == 0)
			return true;

		if (strncmp(tag, "outbound-", 9) == 0){
			tag += 9;
		}

		snprintf(ev.ext.netstate.name,
			COUNT_OF(ev.ext.netstate.name), "%s", tag);
		ev.ext.netstate.state = 2;
		arcan_shmif_enqueue(C, &ev);
	}

/* then send the corresponding IP */
	snprintf(ev.ext.netstate.name,
		COUNT_OF(ev.ext.netstate.name), "%s", addr);
	ev.ext.netstate.state = 1;
	arcan_shmif_enqueue(C, &ev);

	return true;
}

static int discover_passive(
	struct arcan_shmif_cont* C, struct arg_arr* arg, int trust)
{
	struct anet_options ks = {.keystore.directory.dirfd = -1};
	if (!get_keystore(C, &ks.keystore) || !a12helper_keystore_open(&ks.keystore)){
		arcan_shmif_last_words(C, "couldn't open keystore");
		return EXIT_FAILURE;
	}


	struct anet_discover_opts cfg = {
		.discover_beacon = on_disc_beacon,
		.on_shmif = on_disc_shmif,
		.C = C
	};

	arg_lookup(arg, "ipv6", 0, &cfg.ipv6);
	const char* err = a12helper_discover_ipcfg(&cfg, true);

	anet_discover_listen_beacon(&cfg);

	return EXIT_SUCCESS;
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
 * callback.
 *
 * Furthermore with changes to migrate() there is now a DEVICE_NODE event
 * for setting the access token to a hardware keystore. This is yet to be
 * exposed for use here.
 */
static bool get_keystore(
	struct arcan_shmif_cont* C, struct keystore_provider* prov)
{
	static struct keystore_provider ks = {.directory.dirfd = -1};

	if (ks.directory.dirfd == -1){
		ks.type = A12HELPER_PROVIDER_BASEDIR;
		const char* err = NULL;
		ks.directory.dirfd = a12helper_keystore_dirfd(&err);
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
 * those are error cases to respond to. */

/* 0 == lost, 1 (source) 2 (sink) 4 (directory) */
	size_t step = 1;
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
			.ext.netstate = {.state = 1, .type = (1 | 2), .name = "test_3"}
		},
	};

	bool found = false;
	while (flush_shmif(C)){
		sleep(step);
		step++;
		for (size_t i = 0; i < COUNT_OF(ev); i++){
			int ot = ev[i].ext.netstate.type;
			ev[i].ext.netstate.state = found;
			arcan_shmif_enqueue(C, &ev[i]);
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
 *  3. server-end sends a MESSAGE with a matching ID, we download
 *  4. on completed download, segreqs for it
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

	struct {
		int id;
		int statefd;
		int applfd;
	} appl;

	arcan_event segev;
};

static void *dircl_alloc(struct a12_state* S, struct directory_meta* dir)
{
	struct arcan_shmif_cont* C = arcan_shmif_primary(SHMIF_INPUT);
	arcan_shmif_enqueue(C, &(struct arcan_event){
			.ext.kind = ARCAN_EVENT(SEGREQ),
			.ext.segreq.kind = SEGID_HANDOVER
		});

	arcan_event acq_event;
	struct arcan_event* evpool = NULL;
	ssize_t evpool_sz;

	if (!arcan_shmif_acquireloop(C, &acq_event, &evpool ,&evpool_sz)){
		LOG("server rejected allocation\n");
		return NULL;
	}

/* nothing principally stopping us from processing this, but right now there
 * really shouldn't be any event in flight as we get to this point from an
 * explicit 'run/block this appl */
	if (evpool_sz){
		LOG("ignoring_pending:%zu\n", evpool_sz);
		free(evpool);
	}

/* need to track this, the dircl_exec function will be called later and this
 * event will be grabbed and re-used then */
	struct dircl_meta* client = C->user;
	client->segev = acq_event;

	return client;
}

static char* resolve_path(char* path, const char* fn)
{
	char test[PATH_MAX];
	char* dir;
	while ((dir = strsep(&path, ":"))){
		if (*dir == '\0')
			dir = ".";
		if (snprintf(test, sizeof(test), "%s/%s", dir, fn) >= (int) sizeof(test))
			continue;
		if (access(test, X_OK) == 0)
			return strdup(test);
	}
	return NULL;
}

static pid_t dircl_exec(struct a12_state* S,
	struct directory_meta* dir, const char* name, void* tag, int* inf, int* outf)
{
/* make sure the identifier match what was requested */
	struct arcan_shmif_cont* C = arcan_shmif_primary(SHMIF_INPUT);
	struct dircl_meta* client = C->user;

	char* path = getenv("PATH");
	if (!path)
		path = ".";
	path = strdup(path);

	char* lwabin = resolve_path(path, "arcan_lwa");
	free(path);

	if (!lwabin){
		LOG("couldn't locate/access arcan_lwa in PATH\n");
		return 0;
	}

/* we are cwd:ed to where the appl is unpacked */
	char buf[strlen(name) + sizeof("./")];
	snprintf(buf, sizeof(buf), "./%s", name);

	int pstdin[2], pstdout[2];
	if (-1 == pipe(pstdin) || -1 == pipe(pstdout)){
		LOG("Couldn't setup control pipe in arcan handover\n");
		return 0;
	}
	char logfd_str[16];
	snprintf(logfd_str, 16, "LOGFD:%d", pstdout[1]);

/* The set of arcan namespaces isn't manipulated or forwarding, which is a
 * clear concern without good portable solutions. Same goes for blocking /
 * masking frameservers or having a different set of them altogether.
 *
 * Some notes:
 * afsrv_net should be swapped to a form that tunnels over the monitor
 *           connection.
 *
 * afsrv_decode / encode should also have a mechanism to go that route.
 *
 * appltemp should go to an in-memory or otherwise volatile / temporary
 *          filesystem that we clean
 *
 */

	char* argv[] = {
		"arcan_lwa",
		"--database",     ":memory:",
		"--monitor",      "-1",       /* monitor but don't periodically snapshot */
		"--monitor-out",  logfd_str,  /* monitor out to specific fd */
		"--monitor-ctrl",             /* stdin is controller interface */
		buf, NULL                     /* applname */
	};

	const char* keys[] = {"TERM", "SHELL", "ARCAN_LOGPATH", "HOME",
		"ARCAN_RESOURCEPATH", "ARCAN_STATEPATH", "XDG_RUNTIME_DIR", "PATH", NULL};
	char* envv[COUNT_OF(keys)] = {0};

	size_t j = 0;
	for (size_t i = 0; keys[i]; i++){
		if (!getenv(keys[i]))
			continue;
		if (-1 != asprintf(&envv[j], "%s=%s", keys[i], getenv(keys[i])))
			j++;
	}

	int* fds[4] = {&pstdin[0], NULL, NULL, &pstdout[1]};
	pid_t res =
		arcan_shmif_handover_exec_pipe(C, client->segev, lwabin, argv, envv, 0, fds, 4);

	for (size_t i = 0; envv[i]; i++)
		free(envv[i]);

	close(pstdin[0]);
	*inf = pstdin[1];
	*outf = pstdout[0];
	close(pstdout[1]);

	free(lwabin);

	return res;
}

static void dircl_event(struct arcan_shmif_cont* C, int chid, struct arcan_event* ev, void* tag)
{
	LOG("event=%s\n", arcan_shmif_eventstr(ev, NULL, 0));

/* this also deviates from what is done in a12/net/dir_cl, as we don't do appl
 * pushes, there should be a shared part for when dealing with loading
 * server-side resources though */
	struct ioloop_shared* I = tag;

	a12int_trace(A12_TRACE_DIRECTORY, "event=%s", arcan_shmif_eventstr(ev, NULL, 0));
	if (ev->category == EVENT_EXTERNAL &&
		ev->ext.kind == EVENT_EXTERNAL_MESSAGE){
		arcan_shmif_enqueue(&I->shmif, ev);
		return;
	}
}

void req_id(struct ioloop_shared* I, uint16_t identifier)
{
	struct arcan_shmif_cont* C = arcan_shmif_primary(SHMIF_INPUT);
	struct dircl_meta* client = C->user;

	struct arcan_event ev =
	{
		.ext.kind = ARCAN_EVENT(BCHUNKSTATE),
		.category = EVENT_EXTERNAL,
		.ext.bchunk = {
			.input = true,
			.hint = false
		}
	};

	LOG("shmif:download:%"PRIu16"\n", identifier);
	snprintf(
		(char*)ev.ext.bchunk.extensions, 6, "%"PRIu16, identifier);
	a12_channel_enqueue(I->S, &ev);

/* it would be possible to queue multiples here, just keep 1:1 for the time being */
	client->appl.id = identifier;
	client->appl.applfd = -1;
	client->appl.statefd = -1;
}

static void cl_got_dyn(struct a12_state* S, int type,
	const char* petname, bool found, uint8_t pubk[static 32], void* tag)
{
	struct arcan_shmif_cont* C = arcan_shmif_primary(SHMIF_INPUT);
	arcan_event disc = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_NETSTATE,
		.ext.netstate = {
			.type = type,
			.space = 5,
			.state = found
		}
	};
	snprintf(disc.ext.netstate.petname, 16, "%s", petname);
	memcpy(disc.ext.netstate.pubk, pubk, 32);

	arcan_shmif_enqueue(C, &disc);
}

/* returning false here would break us out of the ioloop */
static bool dircl_dirent(struct ioloop_shared* I, struct appl_meta* M)
{
  struct arcan_shmif_cont* C = arcan_shmif_primary(SHMIF_INPUT);
	struct directory_meta* dir = I->cbt;
	struct dircl_meta* client = C->user;

/* are we just enumerating appls or do we have a pending request? */
	while (M){
		if (client->pending_reqname){
			if (strcmp(M->appl.name, client->pending_reqname) == 0){
				snprintf(dir->clopt->applname, 16, "%s", M->appl.name);
				req_id(I, M->identifier);
				break;
			}
		}

/* This is not good enough, should make better use of the short_descr and
 * possibly other formats. One approach is to send the extended information as
 * packed data in the actual bchunk on the ID, but it is an unnecessary step. */
 		else {
			struct arcan_event out = {
				.ext.kind = ARCAN_EVENT(BCHUNKSTATE),
				.ext.bchunk.hint = 1,
			};

			LOG("appl_found:%s", M->appl.name);
			snprintf((char*)out.ext.bchunk.extensions,
				COUNT_OF(out.ext.bchunk.extensions), "%s;%d", M->appl.name, M->identifier);

			if (M->next)
				out.ext.bchunk.hint |= 4;

			arcan_shmif_enqueue(C, &out);
		}

		M = M->next;
	}

	return true;
}

static void request_source(
	struct ioloop_shared* I, bool tunnel, const char* msg)
{
	uint8_t pubk[32];
	if (!a12helper_fromb64((uint8_t*) msg, 32, pubk)){
		LOG("request_source=invalid_pubk:%s\n", msg);
		return;
	}

/* pre-alloc the handover first */
	struct arcan_shmif_cont* C = arcan_shmif_primary(SHMIF_INPUT);
	arcan_shmif_enqueue(C, &(struct arcan_event){
			.ext.kind = ARCAN_EVENT(SEGREQ),
			.ext.segreq.kind = SEGID_HANDOVER
		});

	arcan_event acq_event;
	struct arcan_event* evpool = NULL;
	ssize_t evpool_sz;

	if (!arcan_shmif_acquireloop(C, &acq_event, &evpool ,&evpool_sz)){
		LOG("server rejected allocation");
		return;
	}

	if (evpool_sz){
		LOG("ignoring_pending:%zu", evpool_sz);
		free(evpool);
		return;
	}

/* map the handover segment but mark it as unknown and defer registration until
 * the the source- setup is done and the a12 to shmif mapping gets the events
 * from the other side */
	struct arcan_shmif_cont* handover = malloc(sizeof(struct arcan_shmif_cont*));
	*handover = arcan_shmif_acquire(C, NULL, SEGID_UNKNOWN, SHMIF_NOACTIVATE);

	I->handover = handover;
	LOG("request_source=%s\n", pubk);
	a12_request_dynamic_resource(I->S, pubk, tunnel, dircl_source_handler, I);
}

static void switch_dir(
	struct ioloop_shared* C, bool tunnel, const char* name)
{
}

static void dircl_userfd(struct ioloop_shared* I, bool ok)
{
/* just flush the regular path unless we're blocked */
  struct arcan_shmif_cont* C = arcan_shmif_primary(SHMIF_INPUT);
	struct directory_meta* cbt = I->cbt;
	struct dircl_meta* cm = C->user;

	if (cm->pending_reqid > 0)
		return;

/* if we get a new segment with a handover, the ID is the directory appl id
 * we are after - so re-request dirlist and mark as pending */
	arcan_event ev;
	while (arcan_shmif_poll(C, &ev) > 0){
		if (ev.category != EVENT_TARGET){
			continue;
		}

		switch (ev.tgt.kind){
		case TARGET_COMMAND_MESSAGE:{
			LOG("shmif:message=%s", ev.tgt.message);
			char* err = NULL;
			size_t i = 0;
			bool tunnel = false;

/* force-tunnel connection (assuming it is permitted, we don't know that yet,
 * though it should probably be communicated through the initial hello when we
 * have authenticated .. */
			if (ev.tgt.message[0] == '|'){
				tunnel = true;
				i++;
			}

/* The message prefix determines action, e.g. switch directory. This is likely
 * a case we want to optimize by having a bchunkstate convey the index of that
 * directory, on the other hand that would not convey a possible user-specific
 * index */
			if (ev.tgt.message[i] == '/'){
				switch_dir(I, tunnel, (char*) &ev.tgt.message[i+1]);
				continue;
			}

			if (ev.tgt.message[i] == '<'){
				request_source(I, tunnel, (char*) &ev.tgt.message[i+1]);
				continue;
			}

			long id = strtoul(ev.tgt.message, &err, 10);
			if (*err != '\0' || id < 0 || id > 65535){
				LOG("shmif:bad_req_id");
				return;
			}
/* re-resolve ID to applname for the folder name to match as the same arcan
 * rules apply for applname/applname.lua with initialiser function applname(argv) */
			struct appl_meta* am = a12int_get_directory(I->S, NULL);
			while (am){
				if (am->identifier == id){
					snprintf(cbt->clopt->applname, 16, "%s", am->appl.name);
					req_id(I, am->identifier);
					return;
				}
				am = am->next;
			}
			LOG("shmif:unknown_req_id=%d", (int)id);
			return;
		}
		break;

/* Right now we can't mutate our role - if we want to act as a source, we need
 * to connect as one. The case where the other point would be interesting is if
 * we navigate transitively somewhere (dir / dir / dir) and want to source into
 * it. Then we'd want the arcan appl to throw us a socket that some other shmif
 * client will migrate into, and we'd map up the other end of the pair. */
		case TARGET_COMMAND_NEWSEGMENT:
			LOG("shmif:newsegment_without_request");
		break;
		case TARGET_COMMAND_REQFAIL:
		break;
		default:
			LOG("shmif:event=%s", arcan_shmif_eventstr(&ev, NULL, 0));
		break;
		}
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
		.allocator = dircl_alloc,
		.executor = dircl_exec,
		.basedir = -1, /* let unpack generate tmp folder */
	};

	struct directory_meta dircfg = {
		.S = A->state,
		.clopt = &clcfg,
		.state_in = -1,
	};

	struct ioloop_shared ioloop = {
		.S = A->state,
		.fdin = A->fd,
		.fdout = A->fd,
		.userfd = -1,
		.userfd2 = C->epipe,
		.on_event = dircl_event,
		.on_directory = dircl_dirent,
		.on_userfd2 = dircl_userfd,
		.lock = PTHREAD_MUTEX_INITIALIZER,
		.cbt = &dircfg,
	};

	C->user = &dmeta;
	a12_set_destination_raw(A->state, 0,
		(struct a12_unpack_cfg){
		.on_discover = cl_got_dyn,
		.on_discover_tag = &ioloop,
		}, sizeof(struct a12_unpack_cfg));
	a12_set_bhandler(A->state, anet_directory_cl_bhandler, &ioloop);
	anet_directory_ioloop(&ioloop);

	return EXIT_SUCCESS;
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

	struct anet_options opts =
	{
		.opts = &a12opts,
		.keystore = prov,
	};

#ifdef DEBUG
	a12_set_trace_level(8191, stderr);
#endif

/* this does not respect the trust mode currently unless we set tag */
	global.soft_auth = true;

	const char* tag = NULL;
	if (arg_lookup(args, "tag", 0, &tag) && tag && strlen(tag)){
		if (arg_lookup(args, "probe", 0, NULL)){
			a12opts.local_role = ROLE_PROBE;
			LOG("probe_only\n");
		}
		global.trust_domain = tag;
		opts.key = tag;
		global.soft_auth = false;
		LOG("use_tag=%s\n", tag);
	}

/* edge cases we want to use a tag to get keymaterial, but ignore the list
 * of hosts it goes to and swap in our own */
	const char* name;
	if (!arg_lookup(args, "host", 0, &name) || name == NULL || !strlen(name)){
		if (!tag){
			arcan_shmif_last_words(C, "missing host argument");
			return EXIT_FAILURE;
		}
	}
	else{
		opts.ignore_key_host = true;
		opts.host = strdup(name);
		LOG("use_host=%s\n", opts.host);
	}

	if (!arg_lookup(args, "port", 0, &opts.port) || !strlen(opts.port)){
		opts.port = "6680";
	}

/* the secret will augment the encoding of the hello packet, so unless the
 * other end expects it, it will come out as jibberish and no connection can be
 * established. */
	const char* secret;
	if (arg_lookup(args, "secret", 0, &secret) && secret && strlen(secret)){
		snprintf(a12opts.secret, sizeof(a12opts.secret), "%s", opts.key);
	}

/* this will depth- first the tag, and if a connection is there, the 'deep'
 * option will also attempt to authenticate before shutting down the socket */
	struct anet_cl_connection con = anet_cl_setup(&opts);

	if (con.errmsg || !con.state){
		LOG("con_failed=%s\n", con.errmsg ? con.errmsg : "(unknown)");
		arcan_shmif_last_words(C, con.errmsg);
		arcan_shmif_drop(C);
		return EXIT_FAILURE;
	}
	LOG("authenticated\n");

	if (a12opts.local_role == ROLE_PROBE){
		arcan_event ev = {
			.category = EVENT_EXTERNAL,
			.ext.kind = ARCAN_EVENT(MESSAGE),
		};

		char* modedst = (char*) ev.ext.message.data;
		size_t modedst_sz = COUNT_OF(ev.ext.message.data);

		if (a12_remote_mode(con.state) == ROLE_DIR){
			snprintf(modedst, modedst_sz, "directory");
		}
		else if (a12_remote_mode(con.state) == ROLE_SOURCE){
			snprintf(modedst, modedst_sz, "source");
		}
		else if (a12_remote_mode(con.state) == ROLE_SINK){
			snprintf((char*)ev.ext.message.data, COUNT_OF(ev.ext.message.data), "sink");
		}

		arcan_shmif_enqueue(C, &ev);

	/* just wait for exit */
		while(arcan_shmif_wait(C, &ev)){
		}

		shutdown(con.fd, SHUT_RDWR);
		close(con.fd);
		arcan_shmif_drop(C);
		return EXIT_SUCCESS;
	}

/* With the afsrv_net:net_open path we are after a source to sink,
 * directory/xxx or a directory/appl as a download or as inter-appl messaging.
 * The case for acting as an outbound source comes through
 * afsrv_encode:define_recordtarget.
 *
 * For the appl case, we connect to a directory first, then send a message for
 * the resource we want.
 */
	if (a12_remote_mode(con.state) == ROLE_DIR){
		LOG("directory-client");
		return dircl_loop(C, &con, args);
	}
	else if (a12_remote_mode(con.state) == ROLE_SINK){
		arcan_shmif_last_words(C, "host-mismatch:role=sink");
		shutdown(con.fd, SHUT_RDWR);
		close(con.fd);
		arcan_shmif_drop(C);
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
		" Outbound connection: \n"
		"  key     \t   value   \t   description\n"
		"----------\t-----------\t-----------------\n"
		" host     \t  dsthost  \t Specify host to connect to\n"
		" tag      \t  tag      \t Set tag (and host unless host is set) to connect\n"
		" ipv6     \t  group    \t Set IPV6 multicast group address\n"
  	"\n"
		" Discovery:\n "
		"  key   \t   value   \t   description\n"
		"--------\t-----------\t-----------------\n"
		" discover \t  method   \t Set discovery mode (method=sweep,test,passive,\n"
		"          \t           \t                     broadcast or directory)\n"
		" ipv6     \t  group    \t Set IPV6 multicast group address\n"
	);

	return EXIT_FAILURE;
}

int afsrv_netcl(struct arcan_shmif_cont* C, struct arg_arr* args)
{
/* lua:net_discover maps to this */
	const char* dmethod = NULL;
	signal(SIGPIPE, SIG_IGN);
	signal(SIGCHLD, SIG_IGN);

	if (arg_lookup(args, "help", 0, NULL)){
		return show_help();
	}

	if (arg_lookup(args, "host", 0, NULL) || arg_lookup(args, "tag", 0, NULL)){
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
			return discover_passive(C, args, trustm);
		}
		else if (strcmp(dmethod, "broadcast") == 0){
			return discover_broadcast(C, args, trustm);
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

	arcan_shmif_last_words(C, "missing connection mode");
/* just resolve, connect and handover-exec into arcan-net */
	return EXIT_FAILURE;
}

int afsrv_netsrv(struct arcan_shmif_cont* c, struct arg_arr* args)
{
/*
 * for this mode we need a few options,
 *
 *   0. just listen
 *   1. announce presence via lan
 *   2. announce presence via directory
 *   3. request directory to relay or hole-punch
 */
	return EXIT_FAILURE;
}
