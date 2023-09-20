#include <arcan_shmif.h>
#include <arcan_shmif_server.h>

#include <ftw.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <stdlib.h>
#include <ctype.h>
#include <inttypes.h>
#include <stdint.h>
#include <signal.h>

#include "../a12.h"
#include "../a12_int.h"
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

struct dircl;

struct dircl {
	int in_appl;
	bool notify;
	int type;

	arcan_event petname;

	uint8_t pubk[32];
	bool authenticated;

	struct shmifsrv_client* C;
	struct dircl* next;
	struct dircl* prev;
};

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

/* Check for petname collision among existing instances, this is another of
 * those policy decisions that should be moved to a scripting layer. */
static bool gotname(struct dircl* source, struct arcan_event ev)
{
	struct dircl* C = active_clients.root.next;
	bool rv = false;

	pthread_mutex_lock(&active_clients.sync);
		while (C){
			if (C == source){
				C = C->next;
				continue;
			}

			if (strncasecmp(
					(char*)C->petname.ext.message.data,
					(char*)ev.ext.message.data,
					COUNT_OF(ev.ext.message.data)) == 0){
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

/*
 * split a worker provided resource identifier id[.resource] into its components
 * and return the matching appl_meta pairing with [id] (if any)
 */
enum {
	IDTYPE_APPL  = 0,
	IDTYPE_STATE = 1,
	IDTYPE_DEBUG = 2,
	IDTYPE_RAW   = 3
};

volatile struct appl_meta* identifier_to_appl(
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
			A12INT_DIRTRACE("dirsv:resolve_id:id=%s:applname=%s", id, cur->applname);
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

static void handle_bchunk_req(struct dircl* C, char* ext, bool input)
{
	int mtype;
	uint16_t mid = 0;
	char* outsep = NULL;

	volatile struct appl_meta* meta = identifier_to_appl(ext, &mtype, &mid, &outsep);

	if (!meta)
		goto fail;

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
			resfd = get_state_res(C, meta->applname, ".state", O_RDONLY, 0);
		break;
		case IDTYPE_DEBUG:
			goto fail;
		break;
/* request raw access to a file in the server-side (shared) applstore- path */
		case IDTYPE_RAW:{
			char* envbase = getenv("ARCAN_APPLSTOREPATH");
			if (envbase && isalnum(outsep[0])){
				pthread_mutex_lock(&active_clients.sync);
					char* name = strdup((char*)meta->applname);
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
	/* need to check if we have permission to swap out an appl, if so we also
	 * need to be notified when the actual binary transfer is over so that we can
	 * swap it out in the index (optionally on-disk) atomically and notify anyone
	 * listening that it has been updated. */
		case IDTYPE_APPL:
			goto fail;
		break;
		case IDTYPE_STATE:
			resfd = get_state_res(C, meta->applname, ".state", O_WRONLY, 0);
		break;
		case IDTYPE_DEBUG:
			resfd = get_state_res(C, meta->applname, ".debug", O_WRONLY, 0);
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
			.tgt.ioevs[1].iv = ressz
		};
		snprintf(ev.tgt.message, COUNT_OF(ev.tgt.message), "%"PRIu16, mid);

		shmifsrv_enqueue_event(C->C, &ev, resfd);
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
			.fd = shmifsrv_client_handle(C->C),
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
 *MESSAGE event as well as re-using the same codepaths for dynamically
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

			dirlist_to_worker(C);
			ev.tgt.kind = TARGET_COMMAND_ACTIVATE;
			shmifsrv_enqueue_event(C->C, &ev, -1);
			activated = true;
		}

		struct arcan_event ev;
		while (1 == shmifsrv_dequeue_events(C->C, &ev, 1)){
/* petName for a source or for joining an appl */
			if (ev.ext.kind == EVENT_EXTERNAL_IDENT){
				A12INT_DIRTRACE("dirsv:kind=worker:cl_join=%s", ev.ext.message);
			}

/* right now we permit the worker to fetch / update their state store of any
 * appl as the format is id[.resource]. The other option is to use IDENT to
 * explicitly enter an appl signalling that participation in networked activity
 * is desired. */
			else if (ev.ext.kind == EVENT_EXTERNAL_BCHUNKSTATE){
				handle_bchunk_req(C, (char*) ev.ext.bchunk.extensions, ev.ext.bchunk.input);
			}

/* registering as a source / directory? */
			else if (ev.ext.kind == EVENT_EXTERNAL_NETSTATE){
				if (ev.ext.netstate.state == 0){ /* lost */
				}
/* this is cheating a bit, SHMIF splits TARGET and EXTERNAL for (srv->cl), (cl->srv)
 * but by replaying like this we use EXTERNAL as (cl->srv->cl) */
			}

/* the generic message passing is first used for sending and authenticating the
 * keys on the initial connection. If the authentication goes through and IDENT
 * is used to 'join' an appl the MESSAGE facility should (TOFIX) become a broadcast
 * domain or wrapped through a Lua VM instance as the server end of the appl. */
			else if (ev.ext.kind == EVENT_EXTERNAL_MESSAGE){
				struct arg_arr* entry = arg_unpack((char*)ev.ext.message.data);
				if (!entry){
					A12INT_DIRTRACE("dirsv:kind=worker:bad_msg:%s=", ev.ext.message.data);
					continue;
				}

/* just route authentication through the regular function, caching the reply */
				const char* pubk;
				if (!C->authenticated){
					bool send_fail = false;
/* regardless of authentication reply, they only get one attempt at this */
					C->authenticated = true;

					if (!arg_lookup(entry, "a12", 0, NULL) || !arg_lookup(entry, "pubk", 0, &pubk)){
						send_fail = true;
					}
					else {
						uint8_t pubk_dec[32];
						if (!a12helper_fromb64((const uint8_t*) pubk, 32, pubk_dec)){
							send_fail = true;
						}
						else {
							pthread_mutex_lock(&active_clients.sync);
							struct pk_response rep = active_clients.opts->a12_cfg->pk_lookup(pubk_dec);
							pthread_mutex_unlock(&active_clients.sync);
							if (rep.authentic){
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
								memcpy(C->pubk, pubk_dec, 32);
							}
							else
								send_fail = true;
						}
					}

					if (send_fail){
						shmifsrv_enqueue_event(C->C, &(struct arcan_event){
							.category = EVENT_TARGET,
							.tgt.kind = TARGET_COMMAND_MESSAGE,
							.tgt.message = "a12:fail"
						}, -1);
					}
				}
				else {
	/* TOFIX: MESSAGE into broadcast or route through server-side APPL */
				}

				arg_cleanup(entry);
			}
		}

		int ticks = shmifsrv_monotonic_tick(NULL);
		while (!dead && ticks--){
			shmifsrv_tick(C->C);
		}
	}

	pthread_mutex_lock(&active_clients.sync);
	a12int_trace(
		A12_TRACE_DIRECTORY, "srv:kind=worker:terminated");
		C->prev->next = C->next;
		if (C->next)
			C->next->prev = C->prev;
	pthread_mutex_unlock(&active_clients.sync);

	shmifsrv_free(C->C, true);
	free(C);

	return NULL;
}

static void rebuild_index()
{
	if (active_clients.dirlist)
		free(active_clients.dirlist);

/* first appls */
	FILE* dirlist = open_memstream(
		&active_clients.dirlist, &active_clients.dirlist_sz);
	volatile struct appl_meta* cur = &active_clients.opts->dir;
	while (cur){
		if (cur->applname[0]){
			fprintf(dirlist,
				"kind=appl:name=%s:id=%"PRIu16":size=%"PRIu64
				":categories=%"PRIu16":hash=%"PRIx8
				"%"PRIx8"%"PRIx8"%"PRIx8":timestamp=%"PRIu64":description=%s\n",
				cur->applname, cur->identifier, cur->buf_sz, cur->categories,
				cur->hash[0], cur->hash[1], cur->hash[2], cur->hash[3],
				cur->update_ts,
				cur->short_descr
			);
		}
		cur = cur->next;
	}

/* then possible sources */
	struct dircl* cl = &active_clients.root;
	while (cl){
		if ((cl->type == ROLE_SOURCE || cl->type == ROLE_DIR) &&
				cl->petname.ext.message.data[0]){
			fprintf(dirlist, "kind=%s:name=%s\n",
				cl->type == ROLE_SOURCE ? "source" : "dir",
				cl->petname.ext.message.data);
		}
		cl = cl->next;
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

/* Note that DIRTRACE macro isn't used here as it locks the mutex.
 * Setting the directory again after the initial time (vs. individual
 * entry updates with broadcast) should be rare to never). */
		if (!first){
			a12int_trace(A12_TRACE_DIRECTORY, "list_updated");
			struct dircl* cur = &active_clients.root;
			while (cur){
				if (cur->notify)
					dirlist_to_worker(cur);
				cur = cur->next;
			}
		}
	}

	pthread_mutex_unlock(&active_clients.sync);
}

/* This is in the parent process, it acts as a 1:1 thread/process which
 * pools and routes. The other end of this shmif connection is in the
 * normal */
void anet_directory_shmifsrv_thread(struct shmifsrv_client* cl)
{
	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);

	struct dircl* newent = malloc(sizeof(struct dircl));
	*newent = (struct dircl){.C = cl};

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

static FILE* cmd_to_membuf(const char* cmd, char** out, size_t* out_sz)
{
	FILE* applin = popen(cmd, "r");
	if (!applin)
		return NULL;

	FILE* applbuf = open_memstream(out, out_sz);
	if (!applbuf){
		pclose(applin);
		return NULL;
	}

	char buf[4096];
	size_t nr;
	bool ok = true;

	while ((nr = fread(buf, 1, 4096, applin))){
		if (1 != fwrite(buf, nr, 1, applbuf)){
			ok = false;
			break;
		}
	}

	pclose(applin);
	if (!ok){
		fclose(applbuf);
		return NULL;
	}

/* actually keep both in order to allow appending elsewhere */
	fflush(applbuf);
	return applbuf;
}

/* This part is much more PoC - we'd need a nicer cache / store (sqlite?) so
 * that each time we start up, we don't have to rescan and the other end don't
 * have to redownload if nothing's changed. See the tar comments further below. */
static size_t scan_appdir(int fd, struct appl_meta* dst)
{
	int old = open(".", O_RDONLY, O_DIRECTORY);

	lseek(fd, 0, SEEK_SET);
	DIR* dir = fdopendir(fd);
	struct dirent* ent;
	size_t count = 0;

	while (dir && (ent = readdir(dir))){
		if (
			strlen(ent->d_name) >= 18 ||
			strcmp(ent->d_name, "..") == 0 || strcmp(ent->d_name, ".") == 0){
			continue;
		}
		fchdir(fd);

	/* just want directories */
		struct stat sbuf;
		if (-1 == stat(ent->d_name, &sbuf) || (sbuf.st_mode & S_IFMT) != S_IFDIR)
			continue;

		chdir(ent->d_name);

		struct appl_meta* new = malloc(sizeof(struct appl_meta));
		if (!new)
			break;

		*dst = (struct appl_meta){0};
		size_t buf_sz;

		/* This is a problematic format, both in terms of requiring an exec (though
		 * process not in a particularly vulnerable state) but the shenanigans
		 * needed to get determinism on top of that regarding permissions,
		 * m-/a-ctime. etc. is not particularly nice. We could re-use the walk
		 * function with our own and just pull in whitelisted extensions, sort and
		 * stream-index that - or go with with a Find / sort pre-pass, but tar flag
		 * portability is also a..
		 */
		dst->handle = cmd_to_membuf("tar cf - .", &dst->buf, &buf_sz);
		dst->buf_sz = buf_sz;
		fchdir(fd);

		if (!dst->handle){
			free(new);
			continue;
		}
		dst->identifier = count++;

		blake3_hasher temp;
		blake3_hasher_init(&temp);
		blake3_hasher_update(&temp, dst->buf, dst->buf_sz);
		blake3_hasher_finalize(&temp, dst->hash, 4);
		snprintf(dst->applname, 18, "%s", ent->d_name);
		a12int_trace(A12_TRACE_DIRECTORY, "scan_ok:added=%s", dst->applname);

		*new = (struct appl_meta){0};
		dst->next = new;
		dst = new;
	}

	a12int_trace(A12_TRACE_DIRECTORY, "scan_over:count=%zu", count);
	closedir(dir);

	if (-1 != old){
		fchdir(old);
		close(old);
	}

	return count;
}

/* this will just keep / cache the built .tars in memory, the startup times
 * will still be long and there is no detection when / if to rebuild or when
 * the state has changed - a better server would use sqlite and some basic
 * signalling. */
void anet_directory_srv_rescan(struct anet_dirsrv_opts* opts)
{
	opts->dir_count = scan_appdir(dup(opts->basedir), &opts->dir);
}
