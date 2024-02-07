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

#include "../a12.h"
#include "../a12_int.h"
#include "a12_helper.h"
#include "anet_helper.h"
#include "directory.h"

#include <sys/types.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <dirent.h>
#include <fcntl.h>
#include <poll.h>

#include <stdatomic.h>
#include <pthread.h>

extern bool g_shutdown;

static struct {
	pthread_mutex_t sync;
	struct dircl root;
	volatile struct anet_dirsrv_opts* opts;
	char* dirlist;
	size_t dirlist_sz;
} active_clients = {
	.sync = PTHREAD_MUTEX_INITIALIZER
};

#define A12INT_DIRTRACE(...) do { \
	if (!(a12_trace_targets & A12_TRACE_DIRECTORY))\
		break;\
	pthread_mutex_lock(&active_clients.sync);\
		a12int_trace(A12_TRACE_DIRECTORY, __VA_ARGS__);\
	pthread_mutex_unlock(&active_clients.sync);\
	} while (0);

static void rebuild_index();

/* Check for petname collision among existing instances, this is another of
 * those policy decisions that should be moved to a scripting layer to also
 * apply geographically appropriate blocklists for the inevitable censors */
static bool gotname(struct dircl* source, struct arcan_event ev)
{
	bool rv = false;

	pthread_mutex_lock(&active_clients.sync);
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
	pthread_mutex_unlock(&active_clients.sync);

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
			A12INT_DIRTRACE("dirsv:kind=tmpfile:error=%d", errno);
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
			.tgt.message = ".index"
		}, fd);

	close(fd);
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

	pthread_mutex_lock(&active_clients.sync);
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

/* for now blindly accept tunneling if requested and permitted */
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
	pthread_mutex_unlock(&active_clients.sync);
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

static void dynlist_to_worker(struct dircl* C)
{
	pthread_mutex_lock(&active_clients.sync);
	struct dircl* cur = active_clients.root.next;
	while (cur){
		if (cur == C || !cur->C || !cur->petname.ext.netstate.name[0]){
			cur = cur->next;
			continue;
		}

/* and the dynamic sources separately */
		arcan_event ev = cur->petname;
		size_t nl = strlen(ev.ext.netstate.name);
		ev.ext.netstate.name[nl] = ':';
		memcpy(&ev.ext.netstate.name[nl+1], cur->pubk, 32);
		shmifsrv_enqueue_event(C->C, &ev, -1);

		cur = cur->next;
	}
	pthread_mutex_unlock(&active_clients.sync);
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
	IDTYPE_ACTRL = 4
};

/*
 * assumes we have appl_meta lookup set locked and kept for the lifespan
 * of the returned value as the set/identifiers can mutate otherwise.
 */
static struct appl_meta* locked_numid_appl(uint16_t id)
{
	volatile struct appl_meta* cur = &active_clients.opts->dir;

	while (cur){
		if (cur->identifier == id){
			return (struct appl_meta*) cur;
		}
		cur = cur->next;
	}

	return NULL;
}

static volatile struct appl_meta* identifier_to_appl(
	char* id, int* mtype, uint16_t* mid, char** outsep)
{
	*mtype = 0;

	char* sep = strrchr(id, '.');

/* are we looking for a subresource? */
	if (sep){
		*sep = '\0';
		sep++;
		if (strcmp(sep, "state") == 0)
			*mtype = IDTYPE_STATE;
		else if (strcmp(sep, "debug") == 0)
			*mtype = IDTYPE_DEBUG;
		else if (strcmp(sep, "appl") == 0)
			*mtype = IDTYPE_APPL;
		else if (strcmp(sep, "ctrl") == 0)
			*mtype = IDTYPE_ACTRL;
		else if (strlen(sep) > 0){
			*mtype = IDTYPE_RAW;
			*outsep = sep;
		}
	}

	char* err = NULL;
	*mid = strtoul(id, &err, 10);
	if (!err || *err != '\0'){
		A12INT_DIRTRACE("dirsv:kind=einval:id=%s", id);
		return NULL;
	}

	pthread_mutex_lock(&active_clients.sync);
	volatile struct appl_meta* cur = &active_clients.opts->dir;

	while (cur){
		if (cur->identifier == *mid){
			pthread_mutex_unlock(&active_clients.sync);
			A12INT_DIRTRACE("dirsv:resolve_id:id=%s:applname=%s", id, cur->appl.name);
			return cur;
		}
		cur = cur->next;
	}

	pthread_mutex_unlock(&active_clients.sync);
	A12INT_DIRTRACE("dirsv:kind=missing_id:id=%s", id);
	return NULL;
}

static int get_state_res(
	struct dircl* C, volatile char* appl, const char* name, int fl, int mode)
{
	char fnbuf[64];
	int resfd = -1;
	pthread_mutex_lock(&active_clients.sync);
		snprintf(fnbuf, 64, "%s", appl);
		resfd =
			a12helper_keystore_statestore(C->pubk,fnbuf, 0, fl & O_RDONLY ? "r" : "w+");
	pthread_mutex_unlock(&active_clients.sync);
	return resfd;
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

static void register_source(struct dircl* C, struct arcan_event ev)
{
	const char* allow = active_clients.opts->allow_src;

	if (ev.ext.netstate.type == ROLE_DIR)
		allow = active_clients.opts->allow_dir;

/* first defer the action to the script, if it does not consume it, use the
 * default behaviour of first checking permission then broadcast to all
 * listening clients */
	pthread_mutex_lock(&active_clients.sync);
		int rv = anet_directory_lua_filter_source(C, &ev);
	pthread_mutex_unlock(&active_clients.sync);

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

/* and no duplicates, if there is a config script it gets to manage collisions
 * so this is only a fallback if it didn't or doesn't care */
	if (gotname(C, ev)){
		A12INT_DIRTRACE(
			"dirsv:kind=warning_register:collision=%s", ev.ext.registr.title);
/* generate new name */
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

/* notify everyone interested about the change, the local state machine
 * will determine whether to forward or not */
	pthread_mutex_lock(&active_clients.sync);
		struct dircl* cur = active_clients.root.next;
		while (cur){
			if (cur != C && cur->C && !(cur->type || cur->type == ROLE_SINK)){
				shmifsrv_enqueue_event(cur->C, &ev, -1);
			}
			cur = cur->next;
		}
	pthread_mutex_unlock(&active_clients.sync);
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

	pthread_mutex_lock(&active_clients.sync);
		volatile struct appl_meta* cur = &active_clients.opts->dir;
		while (cur){
			if (cur->identifier != C->pending_id){
				cur = cur->next;
				continue;
			}
			ok = true;
			break;
		}

	if (!ok){
		A12INT_DIRTRACE("dirsv:bchunk_state:complete_unknown");
		pthread_mutex_unlock(&active_clients.sync);
		goto out;
	}

/* when adding proper formats, here is a place for type-validation scanning /
 * attestation / signing (external / popen and sandboxed ofc.) */
		lseek(C->pending_fd, 0, SEEK_SET);
		FILE* fpek = fdopen(C->pending_fd, "r");
		if (!fpek)
			goto out;

		char* dst;
		size_t dst_sz;
		FILE* handle = file_to_membuf(fpek, &dst, &dst_sz);

/* time to replace the backing slot, rebuild index and notify listeners */
		if (handle){
			cur->buf_sz = dst_sz;
			cur->buf = dst;
			cur->handle = handle;

			blake3_hasher hash;
			blake3_hasher_init(&hash);
			blake3_hasher_update(&hash, dst, dst_sz);
			blake3_hasher_finalize(&hash, (uint8_t*)cur->hash, 4);

/* need to unlock as shmifsrv set will lock again, it will take care of
 * rebuilding the index and notifying listeners though - identity action
 * so volatile is no concern */
			pthread_mutex_unlock(&active_clients.sync);
			A12INT_DIRTRACE("dirsv:bchunk_state:appl_update=%d", cur->identifier);
			anet_directory_shmifsrv_set(
				(struct anet_dirsrv_opts*) active_clients.opts);
		}
		else
			pthread_mutex_unlock(&active_clients.sync);

	fclose(fpek);
	return;

out:
	close(C->pending_fd);
	C->pending_fd = -1;
}

/*
 * not part of the default developer permissions yet
 */
static volatile struct appl_meta* allocate_new_appl(char* ext, uint16_t* mid)
{
	return NULL;
}

/* We have an incoming BCHUNKSTATE for a worker. We need to parse and unpack the
 * format used to squeeze the request into the event type, then check permissions
 * for retrieval or creation. */
static void handle_bchunk_req(struct dircl* C, char* ext, bool input)
{
	int mtype = 0;
	uint16_t mid = 0;
	char* outsep = NULL;
	bool closefd = true;

	volatile struct appl_meta* meta = identifier_to_appl(ext, &mtype, &mid, &outsep);

/* Special case, for (new) appl-upload we need permission and register an
 * identifier for the new appl. */
	if (!meta){
		if (mtype == IDTYPE_APPL && !input){
			if (a12helper_keystore_accepted(C->pubk, active_clients.opts->allow_appl)){
				A12INT_DIRTRACE("dirsv:accepted_new=%s", ext);
				meta = allocate_new_appl(ext, &mid);
			}
			else
				A12INT_DIRTRACE("dirsv:rejected_new=%s:permission", ext);
		}

		if (!meta)
			goto fail;
	}

	int resfd = -1;
	size_t ressz = 0;

	if (input){
		switch (mtype){
		case IDTYPE_APPL:
			pthread_mutex_lock(&active_clients.sync);
				resfd = buf_memfd(meta->buf, meta->buf_sz);
				ressz = meta->buf_sz;
			pthread_mutex_unlock(&active_clients.sync);
		break;
		case IDTYPE_STATE:
			resfd = get_state_res(C, meta->appl.name, ".state", O_RDONLY, 0);
		break;
		case IDTYPE_DEBUG:
			goto fail;
		break;
/* request raw access to a file in the server-side (shared) applstore- path */
		case IDTYPE_RAW:{
			char* envbase = getenv("ARCAN_APPLSTOREPATH");
			if (envbase && isalnum(outsep[0])){
				pthread_mutex_lock(&active_clients.sync);
					char* name = strdup((char*)meta->appl.name);
				pthread_mutex_unlock(&active_clients.sync);
				char* full = NULL;
				if (0 < asprintf(&full, "%s/%s/%s", envbase, name, outsep)){
					resfd = open(full, O_RDONLY);
					free(full);
				}
				free(name);
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
			if (a12helper_keystore_accepted(C->pubk, active_clients.opts->allow_appl)){
				A12INT_DIRTRACE("accept_update=%d", (int) mid);
				resfd = buf_memfd(NULL, 0);
				if (-1 != resfd){
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
		case IDTYPE_ACTRL:
			goto fail;
		break;
		case IDTYPE_STATE:
			resfd = get_state_res(C, meta->appl.name, ".state", O_WRONLY, 0);
		break;
		case IDTYPE_DEBUG:
			resfd = get_state_res(C, meta->appl.name, ".debug", O_WRONLY, 0);
		break;
/* need to check if we have permissions to a. make an upload, b. overwrite an
 * existing file (which unfortunately also means tracking ownership - we can do
 * this with a pubk tag at the beginning as a header, then return the
 * descriptor positioned post-header offset */
		case IDTYPE_RAW:
			goto fail;
		break;
		}
	}

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
		shmifsrv_enqueue_event(C->C, &ev, resfd);
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
	if (C->in_appl < 0)
		return;

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
 * happens if there is no appl-runner set to absorb or rebroadcast the
 * messages. */
	pthread_mutex_lock(&active_clients.sync);
	struct dircl* cur = active_clients.root.next;
	while (cur){
		if (cur->in_appl == C->in_appl && cur != C){
			shmifsrv_enqueue_multipart_message(
				cur->C, &outev, C->message_multipart, C->message_ofs);
		}
		cur = cur->next;
	}
	pthread_mutex_unlock(&active_clients.sync);

/* reset the queue buffer */
	snprintf(C->message_multipart, 16, "from=%s:", C->identity);
	C->message_ofs = strlen(C->message_multipart);
}

static void dircl_message(struct dircl* C, struct arcan_event ev)
{
/* reserved prefix? then treat as worker command */
	if (strncmp((char*)ev.ext.message.data, "a12:", 4) != 0){
		msgqueue_worker(C, &ev);
		return;
	}

	struct arg_arr* entry = arg_unpack((char*)ev.ext.message.data);
	if (!entry){
		A12INT_DIRTRACE("dirsv:kind=worker:bad_msg:%s=", ev.ext.message.data);
		return;
	}

/* just route authentication through the regular function, caching the reply */
	const char* pubk;
	if (!C->authenticated){
/* regardless of authentication reply, they only get one attempt at this */
		C->authenticated = true;
		if (!arg_lookup(entry, "a12", 0, NULL) || !arg_lookup(entry, "pubk", 0, &pubk))
			goto send_fail;

		uint8_t pubk_dec[32];
		if (!a12helper_fromb64((const uint8_t*) pubk, 32, pubk_dec))
			goto send_fail;

		memcpy(C->pubk, pubk_dec, 32);

		pthread_mutex_lock(&active_clients.sync);
			struct a12_context_options* aopt = active_clients.opts->a12_cfg;
			struct pk_response rep = aopt->pk_lookup(pubk_dec, aopt->pk_lookup_tag);

/* notify or let .lua config have a say */
			if (!rep.authentic)
				rep = anet_directory_lua_register_unknown(C, rep);
			else
				anet_directory_lua_register(C);
		pthread_mutex_unlock(&active_clients.sync);

/* still ad, kill worker */
		if (!rep.authentic)
			goto send_fail;

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
		return;
	}

/* this one comes from a DIRLIST being sent to the worker state machine. The
 * worker doesn't retain a synched list and may flip between dynamic
 * notification and not. This results in a message being created in a12.c with
 * "a12:dirlist" that the worker forwards verbatim, and here we are. */
	if (arg_lookup(entry, "dirlist", 0, NULL))
		dynlist_to_worker(C);

	else if (arg_lookup(entry, "diropen", 0, NULL))
		dynopen_to_worker(C, entry);

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

static bool got_collision(int appid, char* name)
{
	bool res = false;
	pthread_mutex_lock(&active_clients.sync);
		struct dircl* C = active_clients.root.next;
		while (C){
			if (C->in_appl == appid){
				if (strcmp(name, C->identity) == 0){
					res = true;
					break;
				}
			}
			C = C->next;
		}
	pthread_mutex_unlock(&active_clients.sync);
	return res;
}

static void handle_ident(struct dircl* C, arcan_event ev)
{
	char* end;

/* applind:uid - need to handle identifier collision and somehow notify the
 * worker that we ack:ed the join but also that its actual identity flipped. We
 * might also need to do this if moderation says anything. The easiest way
 * around it would be a 'you are now' xyz. otoh - the presentation name should
 * be implemented in some other way. The problem doesn't manifest in the first
 * order as you don't need to 'see' your own identity, but if someone tries to
 * reply to you or you reply to the colliding identity the problem will
 * manifest. */
	size_t ind = strtoul((char*)ev.ext.message.data, &end, 10);

	char buf[10] = "anon_";
	if (*end == '\0' || (*(end+1)) == '\0'){
make_random:
		do {
			uint8_t rnd[4];
			arcan_random(rnd, 4);
			for (size_t i = 0; i < 4; i++){
				buf[i+5] = 'a' + (rnd[i] % 26);
			}
			end = buf;
		} while (got_collision(ind, buf));
	}
	else if (*end != ':'){
		A12INT_DIRTRACE("dirsv:kind=error:bad_join_id");
		return;
	}
	else if (*(++end)){
		size_t count = 0;
		char* work = strdup(end);

		while (got_collision(ind, end)){
			count++;
			if (count == 99)
				goto make_random;
			snprintf(end, 16, "%.13s_%d", work, (int)count++);
		}

		free(work);
	}

	struct appl_meta* cur;

	pthread_mutex_lock(&active_clients.sync);
	cur = locked_numid_appl(ind);
	if (cur){
		C->in_appl = ind;
		if (cur->server_appl){
			anet_directory_lua_join(C, cur);
		}
	}
	else
		C->in_appl = -1;

	pthread_mutex_unlock(&active_clients.sync);
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
		while (1 == shmifsrv_dequeue_events(C->C, &ev, 1)){
/* petName for a source/dir or for joining an appl */
			if (ev.ext.kind == EVENT_EXTERNAL_IDENT){
				A12INT_DIRTRACE("dirsv:kind=worker:cl_join=%s", (char*)ev.ext.message.data);
				handle_ident(C, ev);
			}
			else if (ev.ext.kind == EVENT_EXTERNAL_NETSTATE){
				handle_netstate(C, ev);
			}
/* right now we permit the worker to fetch / update their state store of any
 * appl as the format is id[.resource]. The other option is to use IDENT to
 * explicitly enter an appl signalling that participation in networked activity
 * is desired. */
			else if (ev.ext.kind == EVENT_EXTERNAL_BCHUNKSTATE){
				handle_bchunk_req(C, (char*) ev.ext.bchunk.extensions, ev.ext.bchunk.input);
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

		int ticks = shmifsrv_monotonic_tick(NULL);
		while (!dead && ticks--){
			shmifsrv_tick(C->C);
		}
	}

	pthread_mutex_lock(&active_clients.sync);

		if (C->tunnel){
			arcan_event ss = {
				.category = EVENT_TARGET,
				.tgt.kind = TARGET_COMMAND_MESSAGE,
				.tgt.message = "a12:drop_tunnel=1"
			};
			shmifsrv_enqueue_event(C->tunnel->C, &ss, -1);

			C->tunnel = NULL;
		}

	a12int_trace(A12_TRACE_DIRECTORY,
		"srv:kind=worker:terminated:name=%s", C->petname.ext.netstate.name);
		C->prev->next = C->next;
		if (C->next)
			C->next->prev = C->prev;

	/* broadcast the loss */
		struct arcan_event ev = C->petname;
		ev.ext.netstate.state = 0;

		if (ev.ext.netstate.name[0]){
			a12int_trace(A12_TRACE_DIRECTORY, "srv:kind=worker:broadcast_loss");
			tag_outbound_name(&ev, C->pubk);
			struct dircl* cur = active_clients.root.next;
			while (cur && ev.ext.netstate.name[0]){
				assert(cur != C);
				shmifsrv_enqueue_event(cur->C, &ev, -1);
				cur = cur->next;
			}
		}
	pthread_mutex_unlock(&active_clients.sync);

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
	volatile struct appl_meta* cur = &active_clients.opts->dir;
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
	pthread_mutex_lock(&active_clients.sync);
	active_clients.opts = opts;

	if (opts->dir.handle || opts->dir.buf){
		rebuild_index();

/* Note that DIRTRACE macro isn't used here as it locks the mutex. Setting the
 * directory again after the initial time (vs. individual entry updates with
 * broadcast) should be rare to never). An optimization here is to only send
 * a new dirlist to clients that have explicitly asked for notification. That
 * information is hidden in the a12_state in the dirsrv_worker. */
		if (!first){
			a12int_trace(A12_TRACE_DIRECTORY, "list_updated");
			struct dircl* cur = &active_clients.root;
			while (cur){
				dirlist_to_worker(cur);
				cur = cur->next;
			}
		}

		first = false;
	}

	pthread_mutex_unlock(&active_clients.sync);
}

/* This is in the parent process, it acts as a 1:1 thread/process which
 * pools and routes. The other end of this shmif connection is in the
 * normal net->listen thread */
void anet_directory_shmifsrv_thread(
	struct shmifsrv_client* cl, struct a12_state* S)
{
	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);

	struct dircl* newent = malloc(sizeof(struct dircl));
	*newent = (struct dircl){
		.C = cl,
		.in_appl = -1,
		.endpoint = {
			.category = EVENT_EXTERNAL,
			.ext.kind = EVENT_EXTERNAL_NETSTATE
		}
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

	pthread_mutex_lock(&active_clients.sync);
		struct dircl* cur = &active_clients.root;
		while (cur->next){
			cur = cur->next;
		}
		cur->next = newent;
		newent->prev = cur;
	pthread_mutex_unlock(&active_clients.sync);
	pthread_create(&pth, &pthattr, dircl_process, newent);
}

/* this will just keep / cache the built .FAPs in memory, the startup times
 * will still be long and there is no detection when / if to rebuild or when
 * the state has changed - a better server would use sqlite and some basic
 * signalling. */
void anet_directory_srv_rescan(struct anet_dirsrv_opts* opts)
{
	pthread_mutex_lock(&active_clients.sync);
	if (!opts->flag_rescan){
		pthread_mutex_unlock(&active_clients.sync);
		return;
	}

	opts->flag_rescan = false;

	int old = open(".", O_RDONLY, O_DIRECTORY);
	struct appl_meta* dst = &opts->dir;

/* closedir would drop the descriptor so copy */
	int fd = dup(opts->basedir);
	lseek(fd, 0, SEEK_SET);
	DIR* dir = fdopendir(fd);
	struct dirent* ent;

/* sweep each entry and check if it's a directory */
	opts->dir_count = 0;
	while (dir && (ent = readdir(dir))){
		if (
			strlen(ent->d_name) >= 18 ||
			strcmp(ent->d_name, "..") == 0 || strcmp(ent->d_name, ".") == 0){
			continue;
		}

/* this doesn't really happen more than once and when we need a full rescan the
 * real database solution would be in place so identifiers mutating isn't much
 * of a concern right now. */
		if (build_appl_pkg(ent->d_name, dst, fd)){
			dst->identifier = opts->dir_count++;
			dst->server_appl = false;

/* check if there is a corresponding server_appl/server_appl.lua and if so,
 * mark so that if a client joins we can spin up a worker process while there
 * are active clients. */
			char* srvappl;
			char* msg;
			if (
				opts->appl_server_dfd > 0 &&
				0 < asprintf(&msg, "%s/%s.lua", ent->d_name, ent->d_name)){

				int scriptfile = openat(opts->appl_server_dfd, msg, O_RDONLY);
				if (-1 != scriptfile){
					dst->server_appl = true;
					close(scriptfile);
				}
				free(msg);
			}

			dst = dst->next;
		}
	}

	a12int_trace(A12_TRACE_DIRECTORY, "scan_over:count=%zu", opts->dir_count);
	closedir(dir);

	if (-1 != old){
		fchdir(old);
		close(old);
	}

	pthread_mutex_unlock(&active_clients.sync);
}
