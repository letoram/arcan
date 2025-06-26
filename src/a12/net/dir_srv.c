#include <arcan_shmif.h>
#include <arcan_shmif_server.h>

#include <ftw.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <stdlib.h>
#include <ctype.h>
#include <inttypes.h>
#include <stdint.h>
#include <signal.h>
#include <assert.h>
#include <pthread.h>

#include "../a12.h"
#include "../a12_int.h"
#include "a12_helper.h"
#include "anet_helper.h"
#include "directory.h"
#include "../../engine/arcan_mem.h"

#include <sys/types.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <dirent.h>
#include <fcntl.h>
#include <poll.h>

#include <stdatomic.h>
#include <pthread.h>

#define LUA_NOREF (-2)

extern bool g_shutdown;

struct source_mask;
struct source_mask {
	int applid;
	uint8_t pubk[32];
	char identity[16];
	uint8_t dstpubk[32];
	struct source_mask* next;
};

static struct {
	pthread_mutex_t sync;
	struct dircl root;
	struct anet_dirsrv_opts* opts;
	char* dirlist;
	size_t dirlist_sz;
	struct source_mask* masks;
} active_clients = {
	.sync = PTHREAD_MUTEX_INITIALIZER
};

/*
 * The a12_state struct is a beefy one (~200k), since it contains all the
 * channels with queues etc. while minimizing internal allocation calls.
 *
 * initially the trace-macro didn't forward the S-> state and when multiple
 * state machines were running, started to stomp on eachother in the log,
 * and for more advanced tracing tools we are likely to need more state so
 * just rewriting all trace() calls is bad in that way.
 *
 * To avoid running out of stack space these are allocated here for the
 * time being, but it's also not a good solution.
 */
static struct a12_state main_trace_state = {.tracetag = "main"};
static struct a12_state lua_trace_state = {.tracetag = "lua"};

#define A12INT_DIRTRACE(...) do { \
	if (!(a12_trace_targets & A12_TRACE_DIRECTORY))\
		break;\
	struct a12_state* S = &main_trace_state;\
	dirsrv_global_lock(__FILE__, __LINE__);\
		a12int_trace(A12_TRACE_DIRECTORY, __VA_ARGS__);\
	dirsrv_global_unlock(__FILE__, __LINE__);\
	} while (0);

#define A12INT_DIRTRACE_LOCKED(...) do { \
	if (!(a12_trace_targets & A12_TRACE_DIRECTORY))\
		break;\
	struct a12_state* S = &main_trace_state;\
	a12int_trace(A12_TRACE_DIRECTORY, __VA_ARGS__);\
	} while (0);

static void rebuild_index();
static struct source_mask*
	apply_source_mask(struct dircl* source, struct dircl* dst);

void dirsrv_global_lock(const char* file, int line)
{
#ifdef DEBUG_LOCK
	fprintf(stderr,
		"[%"PRIdPTR"] lock: %s:%d\n",
		(intptr_t) pthread_self(), file, line);
#endif
	pthread_mutex_lock(&active_clients.sync);
}

void dirsrv_global_unlock(const char* file, int line)
{
#ifdef DEBUG_LOCK
	fprintf(stderr,
		"[%"PRIdPTR"] unlock: %s:%d\n",
		(intptr_t) pthread_self(), file, line);
#endif
	pthread_mutex_unlock(&active_clients.sync);
}

/*
 * wrapped around accessor here in order to later differentiate
 */
extern struct global_cfg global;
struct global_cfg* dirsrv_static_opts()
{
	return &global;
}

struct anet_dirsrv_opts* dirsrv_static_config()
{
	return active_clients.opts;
}

/*
 * assumes we have appl_meta lookup set locked and kept for the lifespan
 * of the returned value as the set/identifiers can mutate otherwise.
 */
static struct appl_meta* locked_numid_appl(uint16_t id)
{
	struct appl_meta* cur = &active_clients.opts->dir;

	while (cur){
		if (cur->identifier == id){
			return (struct appl_meta*) cur;
		}
		cur = cur->next;
	}

	return NULL;
}

/* Check for petname collision among existing instances, this is another of
 * those policy decisions that should be moved to a scripting layer to also
 * apply geographically appropriate blocklists for the inevitable censors */
static bool got_source_name(struct dircl* source, struct arcan_event ev)
{
	bool rv = false;

	dirsrv_global_lock(__FILE__, __LINE__);
		struct dircl* C = active_clients.root.next;
		while (C){
			if (C == source){
				C = C->next;
				continue;
			}

			if (strncasecmp(
					(char*)C->petname.ext.netstate.name,
					(char*)ev.ext.netstate.name,
					COUNT_OF(ev.ext.netstate.name)) == 0){
				rv = true;
				break;
			}

			C = C->next;
		}
	dirsrv_global_unlock(__FILE__, __LINE__);

	return rv;
}

/* convert a buffer to a tempfile worth sending - this comes from the worker
 * thread that converse with the worker process so other blocking behaviour is
 * not a concern. */
static int buf_memfd(const char* buf, size_t buf_sz)
{
	char template[] = "anetdirXXXXXX";
	int out = mkstemp(template);
	if (-1 == out)
		return -1;

/* regular good ol' unsolvable posix fs race */
	unlink(template);
	size_t pos = 0;

	while (buf_sz){
		ssize_t nw = write(out, &buf[pos], buf_sz);

		if (-1 == nw){
			if (errno == EINTR || errno == EAGAIN)
				continue;
			close(out);
			return -1;
		}

		buf_sz -= nw;
		pos += nw;
	}

	lseek(out, 0, SEEK_SET);
	return out;
}

static void dirlist_to_worker(struct dircl* C)
{
	if (!active_clients.dirlist)
		return;

	int fd = buf_memfd(active_clients.dirlist, active_clients.dirlist_sz);
	if (-1 == fd)
		return;

	shmifsrv_enqueue_event(C->C,
		&(struct arcan_event){
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_BCHUNK_IN,
			.tgt.ioevs[1].iv = active_clients.dirlist_sz,
			.tgt.message = ".appl-index"
		}, fd);

	close(fd);
}

static void dynopen_appl_host(struct dircl* C, struct arg_arr* entry)
{
	const char* pubk = NULL;
	char* msg = NULL;

	if (!arg_lookup(entry, "pubk", 0, &pubk) || !pubk)
		goto send_fail;

	uint8_t pubk_dec[32];
	if (!a12helper_fromb64((const uint8_t*) pubk, 32, pubk_dec))
		goto send_fail;

/* locate the appl and build the shmifsrv_ handover setup. */
	return;

send_fail:
	A12INT_DIRTRACE("dirsv:worker:dynopen_fail");
	shmifsrv_enqueue_event(C->C, &(struct arcan_event){
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_REQFAIL
		}, -1
	);
}

/*
 * This will spawn a client directed source of a specified appl. It is a separate
 * permission as it involves both server-side client private store and hosting an
 * arcan_lwa instance with all that entails.
 *
 * Implementation-wise it is similar to a directed launch_target but the
 * execution setup uses a static arcan_lwa config with database etc. pointing
 * to the related state store.
 */
static void applhost_to_worker(struct dircl* C, struct arg_arr* entry)
{
	const char* appid = NULL;
	if (!arg_lookup(entry, "applid", 0, &appid) || !appid){
		shmifsrv_enqueue_event(C->C, &(struct arcan_event){
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_MESSAGE,
			.tgt.message = "a12:applhost:missing_arg"
		}, -1);
		return;
	}

	if (!active_clients.opts->applhost_path){
		A12INT_DIRTRACE("applhost:error=missing_cfg:paths.applhost_loader");
		return;
	}

	uint16_t applid = strtoul(appid, NULL, 10);
	dirsrv_global_lock(__FILE__, __LINE__);
		struct appl_meta* meta = locked_numid_appl(applid);
	dirsrv_global_unlock(__FILE__, __LINE__);

	if (!meta){
		A12INT_DIRTRACE("applhost:error=bad_applid=%"PRIu16, applid);
		return;
	}

	if (!a12helper_keystore_accepted(
		C->pubk, active_clients.opts->allow_applhost)){
		shmifsrv_enqueue_event(C->C, &(struct arcan_event){
			.category = EVENT_TARGET,
			.tgt.kind = TARGET_COMMAND_MESSAGE,
			.tgt.message = "a12:applhost:fail:reason=eperm"
		}, -1);
		return;
	}

/* We have the target, checked permissions, and worker process - build the lwa
 * launch arguments and map namespaces. There are quite a few considerations
 * here when it comes to sandboxing profiles (use a separate launcher), target
 * GPU device (could have several and load-balance), frameserver basepath, and
 * how this should be handled in config.lua and onwards.
 *
 * Other security considerations is if the same BASEPATH as for applhosting
 * should be used as that opens up for system_collapse switching which might
 * be desired, but if we add masking that means a client could simply swap and
 * enumerate (if the hosted appl exposes something like that).
 *
 * Some of this should be regulated with the .manifest now so that the engine
 * will restrict things without further configuration, particularly
 * afsrv_terminal that opens everything else up.
 */
	char* argvv[] = {
		active_clients.opts->applhost_path,
		"--database",
		"/tmp/test.sqlite",
		meta->appl.name
	};

	const char* basepath = getenv("ARCAN_APPLBASEPATH");
	if (!basepath){
		A12INT_DIRTRACE("applhost:error:no_applbase");
		return;
	}

	char pathenv[strlen(basepath)+sizeof("ARCAN_APPLBASEPATH=")];
	snprintf(pathenv, COUNT_OF(pathenv), "ARCAN_APPLBASEPATH=%s", basepath);

	char* envv[] = {
		pathenv
	};

	struct arcan_strarr argv = {
		.count = COUNT_OF(argvv),
		.data = argvv
	};

	struct arcan_strarr env = {
		.count = COUNT_OF(envv),
		.data = envv
	};

/* note that we actually don't send the applid in the exec source as that would
 * cause it to only broadcast to the target as registered in the applgroup */
		anet_directory_dirsrv_exec_source(
			C, 0, NULL,
			active_clients.opts->applhost_path,
			&argv,
			&env
	);
}

static void dynopen_to_worker(struct dircl* C, struct arg_arr* entry)
{
	const char* pubk = NULL;
	char* msg = NULL;

	if (!arg_lookup(entry, "pubk", 0, &pubk) || !pubk)
		goto send_fail;

	uint8_t pubk_dec[32];
	if (!a12helper_fromb64((const uint8_t*) pubk, 32, pubk_dec))
		goto send_fail;

	dirsrv_global_lock(__FILE__, __LINE__);
		struct dircl* cur = active_clients.root.next;
		while (cur){
			if (cur == C || !cur->C || !cur->petname.ext.netstate.name[0]){
				cur = cur->next;
				continue;
			}

/* got match, an open question here is if the sources should be consume on use
 * or let the load balancing / queueing etc. happen at the source stage. Right
 * now in the PoC we assume the source is the listening end and the sink the
 * outbound one. We also have a default port for the source (6680) that should
 * be possible to change. */
			if (memcmp(pubk_dec, cur->pubk, 32) == 0){
				arcan_event to_src = {
					.category = EVENT_EXTERNAL,
					.ext.kind = EVENT_EXTERNAL_NETSTATE,
/* this does not conflict with dynlist notifications, those are only for SINK */
					.ext.netstate = {
						.space = 5
					}
				};

/* here is the heuristic spot for setting up NAT hole punching, or allocating a
 * tunnel or .. */
				arcan_event to_sink = cur->endpoint;

/* for now blindly accept tunneling if requested and permitted, other option
 * is to route the request through config.lua and let the script determine */
				if (arg_lookup(entry, "tunnel", 0, NULL)){
					if (!active_clients.opts->allow_tunnel){
						goto send_fail;
					}

					int sv[2];
					if (0 != socketpair(AF_UNIX, SOCK_STREAM, 0, sv))
						goto send_fail;
					arcan_event ts = {
						.category = EVENT_TARGET,
						.tgt.kind = TARGET_COMMAND_BCHUNK_IN,
						.tgt.message = ".tun"
					};

					shmifsrv_enqueue_event(cur->C, &ts, sv[0]);
					shmifsrv_enqueue_event(C->C, &ts, sv[1]);
					close(sv[0]);
					close(sv[1]);
				}

				memcpy(to_src.ext.netstate.name, C->pubk, 32);

/*
 * This could ideally be arranged so that the ordering (listening first)
 * delayed locally based on the delta of pings, but then we'd need that
 * estimate from the state machine as well. It would at least reduce the
 * chances of the outbound connection having to retry if it received the
 * trigger first. The lazy option is to just delay the outbound connection in
 * the dir_cl for the time being. */

/* Another protocol nuance here is that we're supposed to set an authk secret
 * for the outer ephemeral making it possible to match the connection to our
 * directory mediated connection versus one that was made through other means
 * of discovery. This means that the source end might need to (if it should
 * support multiple connection origins) enumerate secrets on the first packet
 * increasing the cost somewhat. */
				arcan_event ss = {
					.category = EVENT_TARGET,
					.tgt.kind = TARGET_COMMAND_MESSAGE
				};

				uint8_t secret[8];
				arcan_random(secret, 8);
				unsigned char* b64 = a12helper_tob64(secret, 8, &(size_t){0});
				snprintf((char*)ss.tgt.message,
					COUNT_OF(ss.tgt.message), "a12:dir_secret=%s", b64);

				shmifsrv_enqueue_event(C->C, &ss, -1);
				shmifsrv_enqueue_event(cur->C, &ss, -1);
				shmifsrv_enqueue_event(cur->C, &to_src, -1);
				shmifsrv_enqueue_event(C->C, &to_sink, -1);

				if (0 < asprintf(&msg,
					"tunnel:source=%s:sink=%s", cur->petname.ext.netstate.name,
					C->petname.ext.netstate.name)){
					msg = NULL;
				}

				cur->tunnel = C->tunnel;
				free(b64);
				break;
			}
			cur = cur->next;
		}
	dirsrv_global_unlock(__FILE__, __LINE__);
	if (msg){
		A12INT_DIRTRACE("%s", msg);
		free(msg);
	}

	return;

send_fail:
	A12INT_DIRTRACE("dirsv:worker:dynopen_fail");
	shmifsrv_enqueue_event(C->C, &(struct arcan_event){
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_REQFAIL
		}, -1
	);
}

static void forward_appl_sources(struct dircl* C, int applid)
{
/* already locked when entering here */
	struct dircl* cur = active_clients.root.next;

/* sweep clients and forward any sources that also match applid, for large N of
 * clients there is probably a point to track sources in a separate list .. */
	while (cur){
		struct source_mask* mask;

		if (cur != C && cur->C &&
			(mask = apply_source_mask(cur, C)) && mask->applid == applid){
			arcan_event ev = cur->petname;
			size_t nl = strlen(ev.ext.netstate.name);
			ev.ext.netstate.name[nl] = ':';
			ev.ext.netstate.state = 1;
			memcpy(&ev.ext.netstate.name[nl+1], cur->pubk, 32);
			shmifsrv_enqueue_event(C->C, &ev, -1);
		}
		cur = cur->next;
	}
}

static void dynlist_to_worker(struct dircl* C)
{
	dirsrv_global_lock(__FILE__, __LINE__);
	struct dircl* cur = active_clients.root.next;
	while (cur){
		if (cur != C && cur->C && !apply_source_mask(cur, C)){
/* and the dynamic sources separately */
			arcan_event ev = cur->petname;
			size_t nl = strlen(ev.ext.netstate.name);
			ev.ext.netstate.name[nl] = ':';
			memcpy(&ev.ext.netstate.name[nl+1], cur->pubk, 32);
			shmifsrv_enqueue_event(C->C, &ev, -1);
		}
		cur = cur->next;
	}
	dirsrv_global_unlock(__FILE__, __LINE__);
}

/*
 * split a worker provided resource identifier id[.resource] into its components
 * and return the matching appl_meta pairing with [id] (if any)
 */
enum {
	IDTYPE_APPL  = 0,
	IDTYPE_STATE = 1,
	IDTYPE_DEBUG = 2,
	IDTYPE_RAW   = 3,
	IDTYPE_ACTRL = 4,
	IDTYPE_MON   = 5,
	IDTYPE_REPORT = 6
};

int identifier_to_appl(char* sep)
{
	int res = IDTYPE_RAW;
	if (strcmp(sep, ".state") == 0)
		res = IDTYPE_STATE;
	else if (strcmp(sep, ".debug") == 0)
		res = IDTYPE_DEBUG;
	else if (strcmp(sep, ".report") == 0)
		res = IDTYPE_REPORT;
	else if (strcmp(sep, ".appl") == 0)
		res = IDTYPE_APPL;
	else if (strcmp(sep, ".ctrl") == 0)
		res = IDTYPE_ACTRL;
	else if (strcmp(sep, ".monitor") == 0)
		res = IDTYPE_MON;
	else if (strlen(sep) > 0){
		res = IDTYPE_RAW;
	}
	return res;
}

void dirsrv_flush_report(const char* appl)
{
	uintptr_t ref = 0;
	uint8_t outk[32];
	char fnbuf[64];
	snprintf(fnbuf, 64, "%s.debug", appl);

	while (a12helper_keystore_enumerate(&ref, outk)){
		a12helper_keystore_stateunlink(outk, fnbuf);
	}
}

int dirsrv_build_report(const char* appl)
{
	uintptr_t ref = 0;
	uint8_t outk[32];
	char fnbuf[64];
	snprintf(fnbuf, 64, "%s.debug", appl);

	char* buf;
	size_t buf_sz;
	FILE* out = open_memstream(&buf, &buf_sz);

	if (!out)
		return -1;

	while (a12helper_keystore_enumerate(&ref, outk)){
		int fd = a12helper_keystore_statestore(outk, fnbuf, 0, "r");
		if (-1 == fd)
			continue;

		struct stat sbuf;
		if (-1 == fstat(fd, &sbuf)){
			close(fd);
			continue;
		}

		FILE* fin = fdopen(fd, "r");
		if (!fin)
			continue;

		unsigned char* b64 = a12helper_tob64(outk, 32, &(size_t){0});
		fprintf(out, "source=%s:length=%zd\n", b64, (ssize_t) sbuf.st_size + 1);
		free(b64);

		while (!feof(fin)){
			char buf[4096];
			size_t nr = fread(buf, 1, 4096, fin);
			fwrite(buf, nr, 1, out);
		}
		fputc('\n', out);

		fclose(fin);
	}

	fclose(out);

	int fd = buf_memfd(buf, buf_sz);
	free(buf);
	return fd;
}

static int get_state_res(struct dircl* C, char* appl, const char* name, int fl)
{
	char fnbuf[64];
	int resfd = -1;
	dirsrv_global_lock(__FILE__, __LINE__);
		snprintf(fnbuf, 64, "%s%s", appl, name);

/*
 * It's the keystore that is responsible for permission check for private data
 * and any associated quotas etc. tied to its underlying backing store. Should
 * the write eventual fail, the worker would cancel_stream the ongoing transfer
 * and the other end alert the user that the stream was cancelled mid-flight.
 */
		resfd =
			a12helper_keystore_statestore(C->pubk,fnbuf, 0, fl & O_RDONLY ? "r" : "w+");
	dirsrv_global_unlock(__FILE__, __LINE__);
	return resfd;
}

static int access_private_store(struct dircl* C, const char* name, bool input)
{
	char fnbuf[64];
	snprintf(fnbuf, sizeof(fnbuf), "%s", name);
	return a12helper_keystore_statestore(C->pubk, fnbuf, 0, input ? "r" : "w+");
}

static bool tag_outbound_name(struct arcan_event* ev, uint8_t kpub[static 32])
{
/* pack and append the authenticated pubk */
	size_t len = strlen(ev->ext.netstate.name);
	if (len > COUNT_OF(ev->ext.netstate.name) - 34){
		A12INT_DIRTRACE("dirsv:kind=warning_register:name_overflow");
		return false;
	}

	ev->ext.netstate.name[len] = ':';
	memcpy(&ev->ext.netstate.name[len+1], kpub, 32);

	return true;
}

static struct source_mask*
	apply_source_mask(struct dircl* source, struct dircl* dst)
{
	if (!dst->type || dst->type != ROLE_SINK || source->type != ROLE_SOURCE)
		return NULL;

	struct source_mask* cur = active_clients.masks;

/* find the mask matching the source */
	while (cur){
		if (memcmp(cur->pubk, source->pubk, 32) == 0)
			break;

		cur = cur->next;
	}

	if (!cur)
		return NULL;

/* it's a masked source, is the destination not in the mask? */
	if (cur->applid && dst->in_appl != cur->applid)
		return NULL;

/* is it also limited to an identity or a specific key? */
	if (cur->identity[0] && strcmp(cur->identity, cur->identity) != 0)
		return NULL;

	uint8_t emptyk[32] = {0};
	if (memcmp(cur->dstpubk, emptyk, 32) == 0)
		return cur;

	if (memcmp(cur->dstpubk, dst->pubk, 32) != 0)
		return NULL;

/* otherwise pass */
	return cur;
}

static void register_source(struct dircl* C, struct arcan_event ev)
{
	const char* allow = active_clients.opts->allow_src;

	if (ev.ext.netstate.type == ROLE_DIR)
		allow = active_clients.opts->allow_dir;

/* first defer the action to the script, if it does not consume it, use the
 * default behaviour of first checking permission then broadcast to all
 * listening clients */
	dirsrv_global_lock(__FILE__, __LINE__);
		int rv = anet_directory_lua_filter_source(C, &ev);
	dirsrv_global_unlock(__FILE__, __LINE__);

	if (rv == 1){
		return;
	}

	if (!a12helper_keystore_accepted(C->pubk, allow)){
		unsigned char* b64 = a12helper_tob64(C->pubk, 32, &(size_t){0});

		A12INT_DIRTRACE(
			"dirsv:kind=reject_register:title=%s:role=%d:eperm:key=%s",
			ev.ext.netstate.name,
			ev.ext.netstate.type,
			b64
		);

		free(b64);
		return;
	}

/* sanitize, name identifiers should be alnum and short for compatiblity */
	char* title = ev.ext.registr.title;
	for (size_t i = 0; i < COUNT_OF(ev.ext.registr.title) && title[i]; i++){
		if (!isdigit(title[i]) && !isalpha(title[i]))
			title[i] = '_';
	}

/* No duplicates, if there is a config script it gets to manage collisions so
 * this is only a fallback if it didn't or doesn't care. Depending on
 * source_mask collisions could be permitted if the authentication key match as
 * to provide round-robin-like balancing and have a fleet of runners. */
	if (got_source_name(C, ev)){
		A12INT_DIRTRACE(
			"dirsv:kind=warning_register:collision=%s", ev.ext.registr.title);

/* generate random name so that directed sources would work */
		while (got_source_name(C, ev)){
			anet_directory_random_ident(ev.ext.netstate.name, 16);
			ev.ext.netstate.name[16] = '\0';
		}
		return;
	}

	unsigned char* b64 = a12helper_tob64(C->pubk, 32, &(size_t){0});
	A12INT_DIRTRACE(
		"dirsv:kind=register:name=%s:pubk=%s", ev.ext.registr.title, b64);
	free(b64);

/* if we just change state / availability, don't permit rename */
	if (C->petname.ext.netstate.name[0]){
		if (strcmp(C->petname.ext.netstate.name, ev.ext.netstate.name) != 0){
			A12INT_DIRTRACE("dirsv:kind=warning_register:rename_blocked");
			return;
		}
	}

	ev.ext.netstate.state = 1;
	C->petname = ev;

/* finally ack the petname and broadcast */
	if (!tag_outbound_name(&ev, C->pubk))
		return;

	C->type = ev.ext.netstate.type;

/* notify everyone interested and eligible about the change, the local state
 * machine will determine whether to forward or not */
	dirsrv_global_lock(__FILE__, __LINE__);
		struct dircl* cur = active_clients.root.next;
		while (cur){
			if (cur == C || !cur->C){
				cur = cur->next;
				continue;
			}

/* mask will only return if the destination client is eligible, but if it's the
 * only eligible destination (identity set) then we should mark that in the
 * NETSTATE event we send to instruct the SINK to request open immediately */
			struct source_mask* mask = apply_source_mask(C, cur);
			if (mask){
				if (mask->identity[0] || memcmp(mask->dstpubk, cur->pubk, 32) == 0){
					ev.ext.netstate.state = 2; /* mark as new-dynamic-immediate */
				}
				ev.ext.netstate.ns = mask->applid;
				shmifsrv_enqueue_event(cur->C, &ev, -1);
			}

			cur = cur->next;
		}
	dirsrv_global_unlock(__FILE__, __LINE__);
}

static void handle_bchunk_completion(struct dircl* C, bool ok)
{
	if (-1 == C->pending_fd){
		A12INT_DIRTRACE("dirsv:bchunk_state:complete_unknown_fd");
		return;
	}

	if (!ok){
		A12INT_DIRTRACE("dirsv:bchunk_state:cancelled");
		close(C->pending_fd);
		return;
	}
	ok = false;

	dirsrv_global_lock(__FILE__, __LINE__);
	struct appl_meta* cur = &active_clients.opts->dir;
	while (cur){
		if (cur->identifier != C->pending_id){
			cur = cur->next;
			continue;
		}
		ok = true;
		break;
	}

	if (!ok){
		A12INT_DIRTRACE_LOCKED("dirsv:bchunk_state:complete_unknown");
		dirsrv_global_unlock(__FILE__, __LINE__);
		close(C->pending_fd);
		C->pending_fd = -1;
		return;
	}

	lseek(C->pending_fd, 0, SEEK_SET);

/* notify any runner, that will take care of unpacking and validating
 * and also take ownership of C->pending_fd */
	if (C->type == IDTYPE_ACTRL){
		anet_directory_lua_update(cur, C->pending_fd);
		C->pending_fd = -1;
		dirsrv_global_unlock(__FILE__, __LINE__);
		return;
	}

/*
 * If the appl is a new install we need to validate format and persist to
 * backing store and give it a name from the package (and check so it doesn't
 * collide). If it is an update, we need to verify that the signing match the
 * signer of the previous version update key or recovery key.
 *
 * Verification/basename extraction goes through
 *     dir_supp.c: verify_appl_pkg(char* buf, size_t buf_sz,
 *                                 uint8_t[static 64] outsig_pk,
 *                                 uint8_t[static 64] insig_pk);
 *
 * If the appls grow large enough to warrant the complexity, there is also a
 * point to splitting the appl into a code and a data portion that gets
 * signed and updated independently.
 *
 * For both cases we should also sweep linked workers and propagate the update
 * (remember that the index is server-local and the actual name is a flat
 * namespace).
 */
	FILE* fpek = fdopen(C->pending_fd, "r");
	if (!fpek){
		close(C->pending_fd);
		C->pending_fd = -1;
		dirsrv_global_unlock(__FILE__, __LINE__);
		return;
	}

	char* dst;
	size_t dst_sz;
	FILE* handle = file_to_membuf(fpek, &dst, &dst_sz);
	C->pending_fd = -1;

/* file to membuf takes over fpek so not our concern */
	if (!handle){
		dirsrv_global_unlock(__FILE__, __LINE__);
		return;
	}

/* time to replace the backing slot, rebuild index and notify listeners */
	cur->buf_sz = dst_sz;
	cur->buf = dst;
	cur->handle = handle;

/* the hashing here is for the entire transfer in order to provide caching it
 * is not for the content itself - header and datablocks (can) have separate
 * signed hashes. */
	blake3_hasher hash;
	blake3_hasher_init(&hash);
	blake3_hasher_update(&hash, dst, dst_sz);
	blake3_hasher_finalize(&hash, (uint8_t*)cur->hash, 4);

/* is there a signature on the appl entry? then check that the client actually
 * owns the signing key before trying to verify manifest / contents */
	uint8_t nullk[SIG_PUBK_SZ] = {0};
	if (memcmp(cur->sig_pubk, nullk, SIG_PUBK_SZ) != 0){
		if (memcmp(C->pubk_sign, cur->sig_pubk, SIG_PUBK_SZ) != 0){
			A12INT_DIRTRACE_LOCKED(
				"dirsv:bchunk_state:update_fail:reason=client signature - appl mismatch");
				dirsrv_global_unlock(__FILE__, __LINE__);
			return;
		}
	}

	const char* errmsg;

	char* name = verify_appl_pkg(dst, dst_sz, C->pubk_sign, cur->sig_pubk, &errmsg);

	if (!name){
		A12INT_DIRTRACE_LOCKED(
			"dirsv:bchunk_state:appl_verify_fail:reason=%s", errmsg);
		fclose(handle);
		dirsrv_global_unlock(__FILE__, __LINE__);
		return;
	}

/* New install rather than update has different action. There is a possible
 * race here if two workers try to install the same appl in the same time
 * window as the first to complete would be the install and the second the
 * update. Unless they use the same signature the first to win would own the
 * signature and the second would have to sign with the same. */
	if (!cur->appl.name[0]){
		for (size_t i = 0; i < COUNT_OF(cur->appl.name)-1 && name[i]; i++)
			cur->appl.name[i] = name[i];

		A12INT_DIRTRACE_LOCKED(
			"dirsv:bchunk_state:new_appl=%d:name=%s",
			(int) cur->identifier, name
		);
	}
	else
		A12INT_DIRTRACE_LOCKED(
		"dirsv:bchunk_state:appl_update=%d", (int) cur->identifier);

/* Persist to disk, in the prepackaged form. There may be more relevant options
 * here - backup the old one and support a 'revert' as an admin API command, as
 * well as unpack to make sure the extracted form match. The main use for that
 * is triaging - when a dump arrives from a client, sample the extracted code
 * around the file:line values and add into the report for quicker inspection.
 */
	char fn[strlen(name) + sizeof(".fap")];
	snprintf(fn, sizeof(fn), "%s.fap", name);

	int fapfd = openat(
		active_clients.opts->basedir, fn, O_RDWR | O_CREAT | O_TRUNC, 0600);
	if (-1 != fapfd){
		FILE* fout = fdopen(fapfd, "w");
		fwrite(cur->buf, cur->buf_sz, 1, fout);
		fclose(fout);
	}
/* while a failure point it is recoverable */
	else
		A12INT_DIRTRACE_LOCKED(
			"dirsv:bchunk_state:appl_sync:fail_open=%s", fn);

/* need to unlock as shmifsrv set will lock again, it will take care of
 * rebuilding the index and notifying listeners though. */
	dirsrv_global_unlock(__FILE__, __LINE__);
	anet_directory_shmifsrv_set(
		(struct anet_dirsrv_opts*) active_clients.opts);
	free(name);

	fclose(fpek);
	return;
}

/*
 * appl_install is a separate permission, this should be a rare event so only
 * apply to new connections that hasn't enumerated the index yet. The exception
 * would be linked workers as that might propagate.
 */
static struct appl_meta* allocate_new_appl(uint16_t id, uint16_t* mid)
{
	struct appl_meta* new_appl = NULL;
	dirsrv_global_lock(__FILE__, __LINE__);
	struct appl_meta* cur = &active_clients.opts->dir;

/*
 * there shouldn't be a collision at this point as the _allocate path is only
 * reached when there isn't a match, but since we need the sweep anyhow it is
 * free.
 */
	uint16_t last_id = 1;

	while (cur){
		if (id == cur->identifier)
			goto out;

/*
 * list is empty-item terminated
 */
		if (!cur->identifier)
			break;

		last_id = cur->identifier;
		cur = cur->next;
	}

/* out of slots */
	if (last_id >= 65534)
		goto out;

	new_appl = malloc(sizeof(struct appl_meta));
	if (!new_appl)
		goto out;

/*
 * don't actually populate the slot with anything, the actual data comes with
 * the completed transfer, including the name (as we read from the FAP header).
 */
	*cur = (struct appl_meta){.identifier = last_id + 1};
	cur->next = new_appl;
	*new_appl = (struct appl_meta){0};

	*mid = last_id + 1;

out:
	dirsrv_global_unlock(__FILE__, __LINE__);
	return new_appl;
}

/*
 * We have an incoming BCHUNKSTATE for a worker. We need to parse and unpack the
 * format used to squeeze the request into the event type, then check permissions
 * for retrieval or creation. This is a prime candidate for splitting out into a
 * dir_srv_resio.c when we add external cache oracles for ctrl<->resource mapping.
 */
static void handle_bchunk_req(struct dircl* C, size_t ns, char* ext, bool input)
{
	int mtype = 0;
	uint16_t mid = 0;
	char* outsep = NULL;
	bool closefd = true;
	int resfd = -1;
	size_t ressz = 0;

/* shortpath private access as it doesn't require access to any appl meta, the
 * admin path is a special case that work more like debugging an appl in that
 * MESSAGE becomes a control channel and the output back gets bound into
 * scripting space. */
	if (ns == 0){
		if (strcmp(ext, ".admin") == 0){
			if (a12helper_keystore_accepted(C->pubk, active_clients.opts->allow_admin)){

/* repeated request for the same resource? terminate existing channel and set
 * new, this is irreversible and the case for reverting on pipe-fail etc. isn't
 * worth the complication. */
				if (C->admin_fdout > 0){
					close(C->admin_fdout);
					C->admin_fdout = -1;
				}

	/* create a pipe, add the write-end to C and route any MESSAGE into the Lua VM
	 * for the admin_command call into config.lua */
				int pair[2] = {-1, -1};
				if (-1 != pipe(pair)){
					resfd = pair[0];
					C->admin_fdout = pair[1];
					C->in_admin = true;
					fcntl(C->admin_fdout, F_SETFD, FD_CLOEXEC);
				}
			}
		}
		else {
			resfd = access_private_store(C, ext, input);
		}

		if (-1 != resfd)
			goto ok;
		else
			goto fail;
	}

/* Lock enumeration so we don't run into stepping the list when something
 * might be appending to it, the contents itself won't change for any of
 * the fields we are interested in as long as we are append only. */
	dirsrv_global_lock(__FILE__, __LINE__);
		struct appl_meta* meta = locked_numid_appl(ns);
	dirsrv_global_unlock(__FILE__, __LINE__);

	int reserved = -1;
	mtype = identifier_to_appl(ext);

/* Special case, for (new) appl-upload we need permission and register an
 * identifier for the new appl, as well as update the backend store. */
	if (!meta){
		if (mtype == IDTYPE_APPL && !input){
			if (
				C->dir_link ||
				a12helper_keystore_accepted(C->pubk, active_clients.opts->allow_install)){
				A12INT_DIRTRACE("dirsv:accepted_new=%s", ext);
				meta = allocate_new_appl(ns, &mid);
			}
			else
				A12INT_DIRTRACE("dirsv:rejected_new=%s:permission", ext);
		}

		if (!meta)
			goto fail;
	}
	else
		mid = meta->identifier;

	if (input){
		switch (mtype){
		case IDTYPE_APPL:
/* Make a locked copy of the currently cached latest appl for the identifier,
 * since the contents is passed to a lower privilege process we need an explicit
 * copy so that a compromised worker wouldn't mutate the descriptor backing
 * and causing code injection on the other end. This should be further enforced
 * with signing later. */
			dirsrv_global_lock(__FILE__, __LINE__);
				resfd = buf_memfd(meta->buf, meta->buf_sz);
				ressz = meta->buf_sz;
			dirsrv_global_unlock(__FILE__, __LINE__);
		break;

/* State store retrieval is part of the regular key-local store and we just
 * prefix with the resolved appl name (as the identifier could be reset between
 * runs). */
		case IDTYPE_STATE:
			resfd = get_state_res(C, meta->appl.name, ".state", O_RDONLY);
		break;

/* DEBUG is more special since it's a report that can append from multiple
 * sources. First when there is a scripting error on the appl side the .lua is
 * generated and sent as a bstream with STATEDUMP type. This can then be
 * triaged and routed around (see 'output' implementation further below) and
 * the end result from all that is what we want to get back.
 */
		case IDTYPE_DEBUG:
			resfd = get_state_res(C, meta->appl.name, ".debug", O_RDONLY);
		break;

/* Downloading the controller for a specific appl- slot is something that is
 * needed for a linked directory but otherwise only permitted for
 * administration or developer purposes. */
		case IDTYPE_ACTRL:
			if (a12helper_keystore_accepted(C->pubk, active_clients.opts->allow_admin))
			{
/* need a way to package this similar to how we'd do with an appl otherwise. */
			}
		break;

/* For debugging a specific appl we'd treat it similar to a _join so the input
 * channel just becomes the bstream and the worker process routes MESSAGES to
 * it, and we accept a12: prefix as a way to send kill SIGUSR1 to the worker.
 *
 * The _monitor call return true means the bchunk response has been sent so we
 * shouldn't try and propagate failure or other reply.
 * */
		case IDTYPE_MON:
			if (a12helper_keystore_accepted(C->pubk, active_clients.opts->allow_appl))
			{
				if (!meta->server_tag)
					anet_directory_lua_spawn_runner(meta, true);

				if (anet_directory_lua_monitor(C, meta)){
					return;
				}
			}
		break;

/* For getting a debug report, we have two paths. If a controller is attached
 * it is responsible for doing initial triaging and mapping to tickets (if such
 * as system is attached) or routing through .monitor. */
		case IDTYPE_REPORT:
			if (a12helper_keystore_accepted(C->pubk, active_clients.opts->allow_appl))
			{
				if (meta->server_tag)
					goto fail;

				resfd = dirsrv_build_report(meta->appl.name);
				if (active_clients.opts->flush_on_report)
					dirsrv_flush_report(meta->appl.name);

				goto ok;
			}
		break;

/* request raw access to a file in the server-side (shared) applstore- path,
 * this only comes through here if the source hasn't joined an appl controller,
 * and is intended for developer access. Other paths are routed there and it
 * initiates the storage request. */
		case IDTYPE_RAW:
		if (a12helper_keystore_accepted(C->pubk, active_clients.opts->allow_ctrl))
		{
			int dfd = openat(
				active_clients.opts->appl_server_datadfd,
				meta->appl.name, O_RDONLY | O_DIRECTORY);

/* is the store directory actually allocated (can be omitted to prevent a
 * specific appl from having on-disk store) */
			if (-1 != dfd){
				resfd = openat(dfd, meta->appl.name, O_RDONLY);
				close(dfd);
			}
		}
		break;
		}
	}
	else {
		switch (mtype){
	/* Need to check if we have permission to swap out an appl, if so we also
	 * need to be notified when the actual binary transfer is over so that we can
	 * swap it out in the index (optionally on-disk) atomically and notify anyone
	 * listening that it has been updated. This is done using STREAMSTAT with the
	 * [completion] argument. */
			case IDTYPE_APPL:
			if (
				C->dir_link ||
				a12helper_keystore_accepted(C->pubk, active_clients.opts->allow_appl)){
				A12INT_DIRTRACE("accept_update=%d", (int) mid);
				resfd = buf_memfd(NULL, 0);
				if (-1 != resfd){
					C->type = mtype;
					C->pending_fd = resfd;
					C->pending_stream = true;
					C->pending_id = mid;
					closefd = false; /* need it around */
				}
			}
			else {
				A12INT_DIRTRACE("reject_update=%d:reason=keystore_deny", (int) mid);
				goto fail;
			}
		break;
/* same as for IDTYPE_APPL but we have different trigger action when the
 * transfer is completed */
		case IDTYPE_ACTRL:
			if (
				C->dir_link ||
				a12helper_keystore_accepted(C->pubk, active_clients.opts->allow_ctrl)){
				A12INT_DIRTRACE("accept_ctrl_update=%d", (int) mid);
				resfd = buf_memfd(NULL, 0);
				if (-1 != resfd){
					C->type = mtype;
					C->pending_fd = resfd;
					C->pending_stream = true;
					C->pending_id = mid;
					closefd = false;
				}
			}
			else {
				A12INT_DIRTRACE("reject_ctrl_update=%d:reason=keystore_deny", (int) mid);
				goto fail;
			}
		break;
		case IDTYPE_STATE:
			resfd = get_state_res(C, meta->appl.name, ".state", O_WRONLY);
		break;
		case IDTYPE_DEBUG:
			resfd = get_state_res(C, meta->appl.name, ".debug", O_WRONLY);
		break;
		case IDTYPE_RAW:
		if (a12helper_keystore_accepted(C->pubk, active_clients.opts->allow_ctrl))
		{
			int dfd = openat(
				active_clients.opts->appl_server_datadfd,
				meta->appl.name, O_RDONLY | O_DIRECTORY);

/* is the store directory actually allocated (can be omitted to prevent a
 * specific appl from having on-disk store) */
			if (-1 != dfd){
				resfd = openat(dfd, ext, O_RDWR | O_CREAT | O_CLOEXEC, 0700);
				close(dfd);
			}
		}
		break;
		}
	}

ok:
	if (-1 != resfd){
		struct arcan_event ev = (struct arcan_event){
			.category = EVENT_TARGET,
			.tgt.kind =
				input ? TARGET_COMMAND_BCHUNK_IN : TARGET_COMMAND_BCHUNK_OUT,
			.tgt.ioevs[1].iv = ressz,
/* this is undocumented use, only relevant when uploading an appl */
			.tgt.ioevs[3].iv = mid
		};
		snprintf(ev.tgt.message, COUNT_OF(ev.tgt.message), "%"PRIu16, mid);

		if (!shmifsrv_enqueue_event(C->C, &ev, resfd)){
			A12INT_DIRTRACE("bchunk_req:fail=send_to_worker:code=%d", errno);
		}

		if (closefd)
			close(resfd);
	}
	else {
		goto fail;
	}
	return;

fail:
	shmifsrv_enqueue_event(C->C, &(struct arcan_event){
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_REQFAIL,
		.tgt.ioevs[0].uiv = mid
	}, -1);
}

static void msgqueue_worker(struct dircl* C, arcan_event* ev)
{
/* appl = 0 is the private namespace, no real use-case has motivated it,
 *          but it would be possible to join and use that as a broadcast domain
 *          between multiple logins with the same authentication key.
 */
 if (C->in_appl <= 0 && !C->in_admin){
		return;
	}
	else if (C->in_appl > 0) {
/* force- prefix identity: */
		if (!C->message_ofs){
			snprintf(C->message_multipart, 16, "from=%s:", C->identity);
			C->message_ofs = strlen(C->message_multipart);
		}
	}

	char* str = (char*) ev->ext.message.data;
	size_t len = strlen(str);
	if (C->message_ofs + len >= sizeof(C->message_multipart)){
		A12INT_DIRTRACE("dirsv:kind=error:multipart_message_overflow:source=%s", C->identity);
		return;
	}

	memcpy(
		&C->message_multipart[C->message_ofs],
		str,
		len
	);

	C->message_ofs += len;

/* too noisy to log everything normally */
#ifdef DEBUG
	A12INT_DIRTRACE("dirsv:kind=message:multipart=%d:broadcast=%s",
		(int) ev->ext.message.multipart, (char*) ev->ext.message.data);
#endif

/* queue more?*/
	if (ev->ext.message.multipart)
		return;

	C->message_multipart[C->message_ofs] = '\0';
	struct arcan_event outev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_MESSAGE,
	};

/* broadcast as one large chain so we don't risk any interleaving, this only
 * happens if there is no appl-runner paired into the worker (as it would
 * route through there) to absorb or rebroadcast the messages. */
	dirsrv_global_lock(__FILE__, __LINE__);
		if (C->in_admin){
			anet_directory_lua_admin_command(C, C->message_multipart);
		}
		else {
			struct dircl* cur = active_clients.root.next;
			while (cur){
				if (cur->in_appl == C->in_appl && cur != C){
					shmifsrv_enqueue_multipart_message(
						cur->C, &outev, C->message_multipart, C->message_ofs);
				}
				cur = cur->next;
			}
		}
	dirsrv_global_unlock(__FILE__, __LINE__);
}

static bool process_auth_request(struct dircl* C, struct arg_arr* entry)
{
/* just route authentication through the regular function, caching the reply */
	const char* pubk;

/* regardless of authentication reply, they only get one attempt at this */
	C->authenticated = true;
	if (!arg_lookup(entry, "a12", 0, NULL) || !arg_lookup(entry, "pubk", 0, &pubk))
		return false;

	uint8_t pubk_dec[32];
	if (!a12helper_fromb64((const uint8_t*) pubk, 32, pubk_dec))
		return false;

	memcpy(C->pubk, pubk_dec, 32);

	dirsrv_global_lock(__FILE__, __LINE__);
		struct a12_context_options* aopt = active_clients.opts->a12_cfg;

		struct a12_state* S = &lua_trace_state;
		struct pk_response rep = aopt->pk_lookup(S, pubk_dec, aopt->pk_lookup_tag);

/* notify or let .lua config have a say */
		if (!rep.authentic){
			rep = anet_directory_lua_register_unknown(C, rep, pubk);
			if (rep.authentic){
/* we get here if the keystore doesn't know the key, soft auth or trust-n-unknown
 * isn't set yet the config script still permits the key through. In that case we
 * still need to set the key to respond with (i.e. default). Differentiation opt.
 * is possible here, but of questionable utility. */
				char* tmp;
				uint16_t tmpport;

				uint8_t my_private_key[32];
				a12helper_keystore_hostkey(
					"default", 0, my_private_key, &tmp, &tmpport);
				a12_set_session(&rep, pubk_dec, my_private_key);
			}
		}
		else
			anet_directory_lua_register(C);
	dirsrv_global_unlock(__FILE__, __LINE__);

/* still bad, kill worker */
	if (!rep.authentic)
		return false;

	struct arcan_event ev = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_MESSAGE
	};

	unsigned char* b64 = a12helper_tob64(rep.key_pub, 32, &(size_t){0});
	snprintf((char*)&ev.tgt.message, COUNT_OF(ev.tgt.message), "a12:pub=%s", b64);
	free(b64);
	shmifsrv_enqueue_event(C->C, &ev, -1);
	b64 = a12helper_tob64(rep.key_session, 32, &(size_t){0});
	snprintf((char*)&ev.tgt.message, COUNT_OF(ev.tgt.message), "a12:ss=%s", b64);
	free(b64);
	shmifsrv_enqueue_event(C->C, &ev, -1);
	return true;
}

static void handle_monitor_command(struct dircl* C, struct arg_arr* entry)
{
	if (arg_lookup(entry, "break", 0, NULL)){
		dirsrv_global_lock(__FILE__, __LINE__);
			struct appl_meta* appl = locked_numid_appl(C->in_appl);
			if (appl){
				anet_directory_signal_runner(appl, SIGUSR1);
			}
		dirsrv_global_unlock(__FILE__, __LINE__);
	}
}

static void dircl_message(struct dircl* C, struct arcan_event ev)
{
/* reserved prefix? then treat as worker command - otherwise merge and
 * broadcast or forward into admin */
	if (strncmp((char*)ev.ext.message.data, "a12:", 4) != 0 || C->in_admin){
		msgqueue_worker(C, &ev);
		return;
	}

	struct arg_arr* entry = arg_unpack((char*)ev.ext.message.data);
	if (!entry){
		A12INT_DIRTRACE("dirsv:kind=worker:bad_msg:%s=", ev.ext.message.data);
		return;
	}

/* control signals that can't be handled by the VM process? */
	if (C->in_monitor){
		handle_monitor_command(C, entry);
		arg_cleanup(entry);
		return;
	}

/* don't do any processing before the worker has attempted authentication */
	if (!C->authenticated){
		if (!process_auth_request(C, entry))
			goto send_fail;
		return;
	}

	const char* msgarg;

/* this one comes from a DIRLIST being sent to the worker state machine. The
 * worker doesn't retain a synched list and may flip between dynamic
 * notification and not. This results in a message being created in a12.c with
 * "a12:dirlist" that the worker forwards verbatim, and here we are. */
	if (arg_lookup(entry, "dirlist", 0, NULL))
		dynlist_to_worker(C);

	else if (arg_lookup(entry, "diropen", 0, NULL))
		dynopen_to_worker(C, entry);

	else if (arg_lookup(entry, "applhost", 0, NULL))
		applhost_to_worker(C, entry);

/* just decode and update, send a bad key? well your uploads will fail. Multiple
 * clients are allowed to set the same key (differentiation for authentication
 * and discovery != data identity). */
	else if (arg_lookup(entry, "signkey", 0, &msgarg) && msgarg){
		a12helper_fromb64((uint8_t*) msgarg, 32, C->pubk_sign);
	}

/* missing - forward to Lua VM and appl-script if in ident */
	arg_cleanup(entry);
	return;

send_fail:
	shmifsrv_enqueue_event(C->C, &(struct arcan_event){
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_MESSAGE,
		.tgt.message = "a12:fail"
		}, -1
	);
	arg_cleanup(entry);
}

void handle_netstate(struct dircl* C, arcan_event ev)
{
	ev.ext.netstate.name[COUNT_OF(ev.ext.netstate.name)-1] = '\0';

/* update ip <-> port mapping */
	if (ev.ext.netstate.type == ROLE_PROBE){
		A12INT_DIRTRACE("dirsv:kind=worker:set_endpoint=%s", ev.ext.netstate.name);
		C->endpoint = ev;
		return;
	}

	if (ev.ext.netstate.type == ROLE_SOURCE || ev.ext.netstate.type == ROLE_DIR){
		A12INT_DIRTRACE("dirsv:kind=worker:register_source=%s:kind=%d",
			(char*)ev.ext.netstate.name, ev.ext.netstate.type);
				register_source(C, ev);
	}
/* set sink key */
	else if (ev.ext.netstate.type == ROLE_SINK){
		unsigned char* b64 = a12helper_tob64(
			(unsigned char*)ev.ext.netstate.name, 32, &(size_t){0});
			A12INT_DIRTRACE("dirsv:kind=worker:update_sink_pk=%s", b64);
		free(b64);
		memcpy(C->pubk, ev.ext.netstate.name, 32);
	}
	else
		A12INT_DIRTRACE("dirsv:kind=worker:unknown_netstate");
}

struct dircl* dirsrv_find_cl_ident(int appid, const char* name)
{
	dirsrv_global_lock(__FILE__, __LINE__);
		struct dircl* C = active_clients.root.next;
		while (C){
			if (C->in_appl == appid){
				if (strcmp(name, C->identity) == 0){
					break;
				}
			}
			C = C->next;
		}
	dirsrv_global_unlock(__FILE__, __LINE__);
	return C;
}

static void handle_ident(struct dircl* C, arcan_event ev)
{
	char* end;

/* message contains applid - the later is just used for mapping a client in
 * appl-ctrl and for logging, we ensure that there is no collision globally
 * through this pref_[random] setup.
 *
 * the reason for this is that we need some kind of printable identifier, and
 * the runner doesn't have access to the actual public key used to authenticate
 * and we don't have the H(salt | pubk) produced by the worker that the ctrl
 * can use for key-val store.
 *
 * this is mainly important for directed launch_target - the ctrl doesn't have
 * exec() like permissions so we need to do that and the route to the right
 * worker process. The option would be to route the launch_target shmifsrv
 * handle to the ctrl and then have it forward it to the worker, but that gets
 * more cumbersome if that actually goes through a linked directory.
 */
	size_t ind = strtoul((char*)ev.ext.message.data, &end, 10);
	char buf[sizeof("anon_XXXXXXXX")] = "anon_";

	if (*end == '\0' || (*(end+1)) == '\0'){
make_random:
		do {
			anet_directory_random_ident(&buf[5], 8);
			end = buf;
		} while (dirsrv_find_cl_ident(ind, buf));
	}
	else if (*end != ':'){
		A12INT_DIRTRACE("dirsv:kind=error:bad_join_id");
		return;
	}
	else if (*(++end)){
		size_t count = 0;
		char* work = strdup(end);

		while (dirsrv_find_cl_ident(ind, end)){
			count++;
			if (count == 99)
				goto make_random;
			snprintf(end, 16, "%.13s_%d", work, (int)count++);
		}

		free(work);
	}
	snprintf(C->identity, COUNT_OF(C->identity), "%s", end);

	struct appl_meta* cur;

	dirsrv_global_lock(__FILE__, __LINE__);
		cur = locked_numid_appl(ind);
		if (cur){
			C->in_appl = ind;

/* if there is no active runner for the appl, first launch one and then
 * send the primitives pairing the worker process with the script VM */
			if (cur->server_appl != SERVER_APPL_NONE){
				if (!cur->server_tag)
					anet_directory_lua_spawn_runner(
						cur, active_clients.opts->runner_process);

				anet_directory_lua_join(C, cur);

/* by joining the appl, masked sources might have appeared - check for
 * those */
				forward_appl_sources(C, ind);
			}
		}
		else
			C->in_appl = -1;
	dirsrv_global_unlock(__FILE__, __LINE__);
}

static void* dircl_process(void* P)
{
	struct dircl* C = P;

/* a 'fun' little side notice here is that there is a race in shmifsrv-
 * spawn child where the descriptor gets sent while the client is in a
 * forked state but not completed exec. */

	shmifsrv_monotonic_rebase();
	int pv = 25;
	bool dead = false, activated = false;

	while (!dead){
		struct pollfd pfd = {
			.fd = shmifsrv_client_handle(C->C, NULL),
			.events = POLLIN | POLLERR | POLLHUP
		};

		if (poll(&pfd, 1, pv) > 0){
			if (pfd.revents){
				if (pfd.revents != POLLIN){
					A12INT_DIRTRACE("dirsv:kind=worker:epipe");
					break;
				}
				pv = 25;
			}
		}

		int sv;
		if ((sv = shmifsrv_poll(C->C)) == CLIENT_DEAD){
			A12INT_DIRTRACE("dirsv:kind=worker:dead");
			dead = true;
			continue;
		}

/* send the directory index as a bchunkstate, this lets us avoid abusing the
 * MESSAGE event as well as re-using the same codepaths for dynamically
 * updating the index later. */
		if (!activated && shmifsrv_poll(C->C) == CLIENT_IDLE){
			A12INT_DIRTRACE("dirsv:kind=worker_join:activate");
			arcan_event ev = {
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_MESSAGE
			};

			if (active_clients.opts->a12_cfg->secret[0]){
				snprintf(
					(char*)ev.tgt.message, COUNT_OF(ev.tgt.message),
					"secret=%s", active_clients.opts->a12_cfg->secret
				);

/* apply the \t is illegal, escapes : rule */
				for (size_t i = 0; i < 32 && ev.tgt.message[i]; i++){
					if (ev.tgt.message[i] == ':')
						ev.tgt.message[i] = '\t';
				}

				shmifsrv_enqueue_event(C->C, &ev, -1);
			}

/* the applindex need to be set when the worker constructs the state machine,
 * while as the list of dynamic sources happens after it is up and running */
			dirlist_to_worker(C);
			ev.tgt.kind = TARGET_COMMAND_ACTIVATE;
			shmifsrv_enqueue_event(C->C, &ev, -1);
			activated = true;
		}

		struct arcan_event ev;
		bool flush = false;

		while (1 == shmifsrv_dequeue_events(C->C, &ev, 1)){
			flush = true;
/* register to join an appl */
			if (ev.ext.kind == EVENT_EXTERNAL_IDENT){
				A12INT_DIRTRACE("dirsv:kind=worker:cl_join=%s", (char*)ev.ext.message.data);
				handle_ident(C, ev);
			}
/* petName for a source/dir */
			else if (ev.ext.kind == EVENT_EXTERNAL_NETSTATE){
				handle_netstate(C, ev);
			}
/* right now we permit the worker to fetch / update their state store of any
 * appl as the format is id[.resource]. The other option is to use IDENT to
 * explicitly enter an appl signalling that participation in networked activity
 * is desired. */
			else if (ev.ext.kind == EVENT_EXTERNAL_BCHUNKSTATE){
				handle_bchunk_req(C,
					ev.ext.bchunk.ns, (char*) ev.ext.bchunk.extensions, ev.ext.bchunk.input);
			}

/* bounce-back ack streamstatus */
			else if (ev.ext.kind == EVENT_EXTERNAL_STREAMSTATUS){
				shmifsrv_enqueue_event(C->C, &ev, -1);
				if (C->pending_stream){
					C->pending_stream = false;
					handle_bchunk_completion(C, ev.ext.streamstat.completion >= 1.0);
				}
				else
					A12INT_DIRTRACE("dirsv:kind=worker_error:status_no_pending");
			}

/* this is cheating a bit, SHMIF splits TARGET and EXTERNAL for (srv->cl), (cl->srv)
 * but by replaying like this we use EXTERNAL as (cl->srv->cl) */

/* the generic message passing is first used for sending and authenticating the
 * keys on the initial connection. If the authentication goes through and IDENT
 * is used to 'join' an appl the MESSAGE facility should (TOFIX) become a broadcast
 * domain or wrapped through a Lua VM instance as the server end of the appl. */
			else if (ev.ext.kind == EVENT_EXTERNAL_MESSAGE){
				dircl_message(C, ev);
			}
		}

/* don't care about the data, only for multiplex wakeup */
		if (flush){
			char buf[256];
			read(pfd.fd, buf, 256);
		}

		int ticks = shmifsrv_monotonic_tick(NULL);
		while (!dead && ticks--){
			shmifsrv_tick(C->C);
		}
	}

	dirsrv_global_lock(__FILE__, __LINE__);
		if (C->tunnel){
			arcan_event ss = {
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_MESSAGE,
				.tgt.message = "a12:drop_tunnel=1"
			};
			shmifsrv_enqueue_event(C->tunnel->C, &ss, -1);

			C->tunnel = NULL;
		}

	A12INT_DIRTRACE_LOCKED(
		"srv:kind=worker:terminated:name=%s", C->petname.ext.netstate.name);
		C->prev->next = C->next;
		if (C->next)
			C->next->prev = C->prev;

/* broadcast the loss */
		struct arcan_event ev = C->petname;
		ev.ext.netstate.state = 0;

		if (ev.ext.netstate.name[0]){
			A12INT_DIRTRACE_LOCKED("srv:kind=worker:broadcast_loss");
			tag_outbound_name(&ev, C->pubk);
			struct dircl* cur = active_clients.root.next;
			while (cur && ev.ext.netstate.name[0]){
				assert(cur != C);
				shmifsrv_enqueue_event(cur->C, &ev, -1);
				cur = cur->next;
			}
		}

	if (C->lua_cb != LUA_NOREF){
		char lw[32];
		shmifsrv_last_words(C->C, lw, 32);
		anet_directory_lua_event(C, &(struct dirlua_event){
				.kind = DIRLUA_EVENT_LOST,
				.msg = lw
		});
	}

/* notify the outer VM so any logging / monitoring / admin channels are
 * getting unreferenced and released */
	anet_directory_lua_unregister(C);
	dirsrv_global_unlock(__FILE__, __LINE__);

	shmifsrv_free(C->C, true);
	memset(C, 0xff, sizeof(struct dircl));
	free(C);

	return NULL;
}

/*
 * the index only contain active appls, dynamic sources are sent separately
 * as netstate discover / lost events and just forwarded.
 */
static void rebuild_index()
{
	if (active_clients.dirlist)
		free(active_clients.dirlist);

	FILE* dirlist = open_memstream(
		&active_clients.dirlist, &active_clients.dirlist_sz);
	struct appl_meta* cur = &active_clients.opts->dir;
	while (cur){
		if (cur->appl.name[0]){
			fprintf(dirlist,
				"kind=appl:name=%s:id=%"PRIu16":size=%"PRIu64
				":categories=%"PRIu16":hash=%"PRIx8
				"%"PRIx8"%"PRIx8"%"PRIx8":timestamp=%"PRIu64":description=%s\n",
				cur->appl.name, cur->identifier, cur->buf_sz, cur->categories,
				cur->hash[0], cur->hash[1], cur->hash[2], cur->hash[3],
				cur->update_ts,
				cur->appl.short_descr
			);
		}
		cur = cur->next;
	}

	fclose(dirlist);
}

void anet_directory_shmifsrv_set(struct anet_dirsrv_opts* opts)
{
	static bool first = true;
	dirsrv_global_lock(__FILE__, __LINE__);
	active_clients.opts = opts;

	if (opts->dir.handle || opts->dir.buf){
		rebuild_index();

		if (!first){
			A12INT_DIRTRACE_LOCKED("list_updated");
			struct dircl* cur = &active_clients.root;
			while (cur){
				dirlist_to_worker(cur);
				cur = cur->next;
			}
		}

		first = false;
	}
	dirsrv_global_unlock(__FILE__, __LINE__);
}

/* This is in the parent process, it acts as a 1:1 thread/process which
 * pools and routes. The other end of this shmif connection is in the
 * normal net->listen thread */
struct dircl* anet_directory_shmifsrv_thread(
	struct shmifsrv_client* cl, struct a12_state* S, bool link)
{
	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
	pthread_attr_setstacksize(&pthattr, 1024 * 1024 * 4);

	struct dircl* newent = malloc(sizeof(struct dircl));
	*newent = (struct dircl){
		.C = cl,
		.in_appl = 0,
		.lua_cb = LUA_NOREF,
		.endpoint = {
			.category = EVENT_EXTERNAL,
			.ext.kind = EVENT_EXTERNAL_NETSTATE
		},
		.type = ROLE_SINK
	};

	const char* endpoint = a12_get_endpoint(S);
	if (endpoint){
		char buf[16];
		if (inet_pton(AF_INET, endpoint, buf)){
			newent->endpoint.ext.netstate.space = 3;
		}
		else if (inet_pton(AF_INET6, endpoint, buf)){
			newent->endpoint.ext.netstate.space = 4;
		}
		snprintf((char*)newent->endpoint.ext.netstate.name,
		COUNT_OF(newent->endpoint.ext.netstate.name), "%s", endpoint);
	}

	dirsrv_global_lock(__FILE__, __LINE__);
		struct dircl* cur = &active_clients.root;
		while (cur->next){
			cur = cur->next;
		}
		cur->next = newent;
		newent->prev = cur;
	dirsrv_global_unlock(__FILE__, __LINE__);

	newent->dir_link = link;
	pthread_create(&pth, &pthattr, dircl_process, newent);

	return newent;
}

static bool try_appl_controller(const char* d_name, int dfd)
{
	char* msg = NULL;

	if (
		0 >= dfd ||
		0 == asprintf(&msg, "%s/%s.lua", d_name, d_name)){
		return false;
	}

	int scriptfile = openat(dfd, msg, O_RDONLY);
	free(msg);

	if (-1 != scriptfile){
		close(scriptfile);
		return true;
	}

	return false;
}

void dirsrv_set_source_mask(
	uint8_t pubk[static 32], int applid, char identity[static 16],
	uint8_t dst_pubk[static 32])
{
	struct source_mask** cur = &active_clients.masks;
	while (*cur)
		cur = &(*cur)->next;

	*cur = malloc(sizeof(struct source_mask));
	struct source_mask* dst = *cur;

	memcpy(dst->identity, identity, 16);

	dst->applid = applid;
	dst->next = NULL;

	memcpy(dst->pubk, pubk, 32); /* is to match source */
	memcpy(dst->dstpubk, dst_pubk, 32); /* is to limit to pubk */
}

/* this will just keep / cache the built .FAPs in memory, the startup times
 * will still be long and there is no detection when / if to rebuild or when
 * the state has changed - a better server would use sqlite and some basic
 * signalling. */
void anet_directory_srv_scan(struct anet_dirsrv_opts* opts)
{
	dirsrv_global_lock(__FILE__, __LINE__);

	struct appl_meta* dst = &opts->dir;

/* closedir would drop the descriptor so copy */
	int fd = dup(opts->basedir);
	lseek(fd, 0, SEEK_SET);
	DIR* dir = fdopendir(fd);
	struct dirent* ent;

/* sweep each entry and check if it's a directory, fits the length restriction.
 * If there is a matching .fap extension that takes precedence. We require both
 * prepackaged and directory to be present for triaging purposes (and for .ctrl
 * form, to avoid having to re-expand) and not to break existing servers. */
	opts->dir_count = 0;
	while (dir && (ent = readdir(dir))){
		size_t nlen = strlen(ent->d_name);

		if (nlen >= 18 ||
			strcmp(ent->d_name, "..") == 0 || strcmp(ent->d_name, ".") == 0){
			continue;
		}

		struct stat sbuf;
		if (-1 == fstatat(fd, ent->d_name, &sbuf, 0))
			continue;

		if (S_ISDIR(sbuf.st_mode)){
			if (!(build_appl_pkg(ent->d_name, dst, fd, NULL)))
				continue;

			dst->identifier = 1 + opts->dir_count++;
			dst->server_appl = SERVER_APPL_NONE;

/* check if there is a corresponding server_appl/server_appl.lua and if so,
 * mark so that if a client joins we can spin up a worker process while there
 * are active clients. Try with temp folder first and fallback to basepath */
			char* srvappl;
			char* msg;

			if (try_appl_controller(ent->d_name, opts->appl_server_temp_dfd))
				dst->server_appl = SERVER_APPL_TEMP;

			else if (try_appl_controller(ent->d_name, opts->appl_server_dfd))
				dst->server_appl = SERVER_APPL_PRIMARY;

			dst = dst->next;
			continue;
		}

		if (!S_ISREG(sbuf.st_mode) ||
			nlen < 5 || strcmp(&ent->d_name[nlen - 4], ".fap") != 0)
			continue;

		int pfd = openat(fd, ent->d_name, O_RDONLY);
		if (-1 == pfd){
			fprintf(stderr, "couldn't scan %s\n", ent->d_name);
			continue;
		}

/* we need it in-memory for verify */
		char* buf;
		size_t buf_sz;
		FILE* fpek = file_to_membuf(fdopen(dup(pfd), "r"), &buf, &buf_sz);
		if (!fpek)
			continue;

		uint8_t nullsig[SIG_PUBK_SZ] = {0};
		const char* errmsg;
		char* name;

		if (!(name = verify_appl_pkg(buf, buf_sz, nullsig, dst->sig_pubk, &errmsg))){
			A12INT_DIRTRACE_LOCKED("scan_error:file=%s:message=%s", ent->d_name, errmsg);
			close(pfd);
			continue;
		}

/* dst already terminated, copy up until '.' */
		for (size_t i = 0;
			i < sizeof(dst->appl.name) - 1 && name[i] && name[i] != '.'; i++){
			dst->appl.name[i] = name[i];
		}

		dst->buf_sz = buf_sz;
		dst->buf = buf;
		dst->identifier = 1 + opts->dir_count++;

/* the hashing here is for the entire transfer in order to provide caching it
 * is not for the content itself - header and datablocks (can) have separate
 * signed hashes. */
		blake3_hasher hash;
		blake3_hasher_init(&hash);
		blake3_hasher_update(&hash, buf, buf_sz);
		blake3_hasher_finalize(&hash, (uint8_t*)dst->hash, 4);

		if (try_appl_controller(ent->d_name, opts->appl_server_temp_dfd))
			dst->server_appl = SERVER_APPL_TEMP;

		else if (try_appl_controller(ent->d_name, opts->appl_server_dfd))
			dst->server_appl = SERVER_APPL_PRIMARY;

		fclose(fpek);

		dst->next = malloc(sizeof(struct appl_meta));
		*(dst->next) = (struct appl_meta){0};
		dst = dst->next;
	}

	A12INT_DIRTRACE_LOCKED("scan_over:count=%zu", opts->dir_count);
	closedir(dir);
	dirsrv_global_unlock(__FILE__, __LINE__);
}
