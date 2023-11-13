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
#include <stdatomic.h>

#include "../a12.h"
#include "../a12_int.h"
#include "../external/x25519.h"

#include "anet_helper.h"
#include "directory.h"
#include "a12_helper.h"

#include <sys/types.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <dirent.h>
#include <fcntl.h>
#include <poll.h>

struct appl_runner_state {
	struct ioloop_shared* ios;

	struct {
		int fd;
		FILE* fpek;
		bool active;
	} state;

	pid_t pid;

	FILE* pf_stdin;
	FILE* pf_stdout;

	int p_stdout;
	int p_stdin;
};

struct tunnel_state {
	struct a12_context_options opts;
	struct a12_dynreq req;
	struct arcan_shmif_cont* handover;
	int fd;
};

static void* tunnel_runner(void* t)
{
	struct tunnel_state* ts = t;
	char* err = NULL;
	struct a12_state* S = a12_client(&ts->opts);

	if (anet_authenticate(S, ts->fd, ts->fd, &err)){
		a12helper_a12srv_shmifcl(ts->handover, S, NULL, ts->fd, ts->fd);
	}
	else {
	}

	shutdown(ts->fd, SHUT_RDWR);
	close(ts->fd);
	free(err);
	free(ts);

	return NULL;
}

static void detach_tunnel_runner(
	int fd,
	struct a12_context_options* aopt,
	struct a12_dynreq* req,
	struct arcan_shmif_cont* handover)
{
	struct tunnel_state* ts = malloc(sizeof(struct tunnel_state));
	ts->opts = *aopt;
	ts->req = *req;
	ts->opts.pk_lookup_tag = &ts->req;
	ts->fd = fd;
	ts->handover = handover;

	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
	pthread_create(&pth, &pthattr, tunnel_runner, ts);
}

/*
 * The processing here is a bit problematic. One is that we still use a socket
 * pair rather than a shmif connection. If this connection is severed or the
 * a12 connection is disconnected we lack a channel for reconnect or redirect
 * outside of normal shmif transitions where we normally could just set an
 * altconn or force-reset.
 */
static struct {
	struct appl_runner_state active;
	_Atomic volatile int n_active;

} active_appls = {
	.active = {
	}
};

static struct pk_response key_auth_fixed(uint8_t pk[static 32], void* tag)
{
	struct a12_dynreq* key_auth_req = tag;

	struct pk_response auth = {};
	if (memcmp(key_auth_req->pubk, pk, 32) == 0){
		auth.authentic = true;
	}
	return auth;
}

/*
 * right now just initialise the outbound connection, in reality the req.mode
 * should be respected to swap over to the client processing
 */

/* setup the request:
 *    we might need to listen
 *    (ok) we might need to connect
 *    (ok) we might need to tunnel via the directory
 */
void dircl_source_handler(
	struct a12_state* S, struct a12_dynreq req, void* tag)
{
	struct ioloop_shared* I = tag;

/* security:
 *
 * disable the ephemeral exchange for now, this means the announced identity
 * when we connect to the directory server will be the one used for the x25519
 * exchange instead of a generated intermediate.
 *
 * on the other hand the exchange is still not externally visible, the shared
 * secret known by source, sink, dir is needed to observe the DH exchange, and
 * the Kpub- mapping is known by the directory regardless.
 *
 * we could treat the 'inner' exchange as 'ephemeral outer' though to establish
 * a transitively trusted pair, but it is rather fringe versus getting the other
 * bits working..
 */
	struct a12_context_options a12opts = {
		.local_role = ROLE_SINK,
		.pk_lookup = key_auth_fixed,
		.pk_lookup_tag = &req,
		.disable_ephemeral_k = true,
	};

	char port[sizeof("65535")];
	snprintf(port, sizeof(port), "%"PRIu16, req.port);
	snprintf(a12opts.secret, sizeof(a12opts.secret), "%s", req.authk);

	struct anet_options anet = {
		.retry_count = 10,
		.opts = &a12opts,
		.host = req.host,
		.port = port
	};

	if (req.proto == 4){
		int sv[2];
		if (0 != socketpair(AF_UNIX, SOCK_STREAM, 0, sv)){
			a12int_trace(A12_TRACE_DIRECTORY, "tunnel_socketpair_fail");
			return;
		}

		a12_set_tunnel_sink(S, 1, sv[0]);
		detach_tunnel_runner(sv[1], &a12opts, &req, I->handover);
		I->handover = NULL;
		return;
	}

	struct anet_cl_connection con = anet_cl_setup(&anet);
	if (con.errmsg || !con.state){
		fprintf(stderr, "%s", con.errmsg ? con.errmsg : "broken connection state\n");
		return;
	}

	if (a12_remote_mode(con.state) != ROLE_SOURCE){
		fprintf(stderr, "remote endpoint is not a source\n");
		shutdown(con.fd, SHUT_RDWR);
		return;
	}

	a12helper_a12srv_shmifcl(I->handover, con.state, NULL, con.fd, con.fd);
	I->handover = NULL;

	shutdown(con.fd, SHUT_RDWR);
}

static void on_cl_event(
	struct arcan_shmif_cont* cont, int chid, struct arcan_event* ev, void* tag)
{
	struct ioloop_shared* I = tag;

/* main use would be the appl- runner forwarding messages that direction */
	a12int_trace(A12_TRACE_DIRECTORY, "event=%s", arcan_shmif_eventstr(ev, NULL, 0));
	if (ev->category == EVENT_EXTERNAL &&
		ev->ext.kind == EVENT_EXTERNAL_MESSAGE){
		arcan_shmif_enqueue(&I->shmif, ev);
		return;
	}

/* we do have an ongoing transfer (--push-appl) that we wait for an OK or cancel
 * before marking that we're ready to shutdown */
	if (I->cbt->in_transfer &&
		ev->category == EVENT_EXTERNAL &&
		ev->ext.kind == EVENT_EXTERNAL_STREAMSTATUS){
		if (ev->ext.streamstat.identifier == I->cbt->transfer_id){
			a12int_trace(A12_TRACE_DIRECTORY,
				"streamstatus:progress=%f:id=%f",
				ev->ext.streamstat.completion,
				(int)ev->ext.streamstat.identifier
			);
			if (ev->ext.streamstat.completion < 0 ||
				ev->ext.streamstat.completion >= 0.999){
				I->shutdown = true;
			}
		}
		else
			a12int_trace(A12_TRACE_DIRECTORY,
				"streamstatus:unknown=%d", (int)ev->ext.streamstat.identifier);
	}
}

static int cleancb(
	const char* path, const struct stat* s, int tfl, struct FTW* ftwbuf)
{
	if (remove(path))
		fprintf(stderr, "error during cleanup of %s\n", path);
	return 0;
}

static bool clean_appldir(const char* name, int basedir)
{
	if (-1 != basedir){
		fchdir(basedir);
	}

	char buf[strlen(name) + sizeof(".new")];
	if (atomic_load(&active_appls.n_active) > 0){
		snprintf(buf, sizeof(buf), "%s.new", name);
		nftw(buf, cleancb, 32, FTW_DEPTH | FTW_PHYS);
	}

/* more careful would get the current pressure through rlimits and sweep until
 * we know how many real slots are available and break at that, better option
 * still would be to just keep this in a memfs like setup and rebuild the
 * scratch dir entirely */
	return 0 == nftw(name, cleancb, 32, FTW_DEPTH | FTW_PHYS);
}

struct default_meta {
	const char* bin;
	char* key;
	char* val;
};

static void* alloc_cpath(struct a12_state* S, struct directory_meta* dir)
{
	const char* cpath = getenv("ARCAN_CONNPATH");
	struct default_meta* res = malloc(sizeof(struct default_meta));
	*res = (struct default_meta){.bin = "arcan"};

/* use regular arcan binary to act as display server */
	if (!cpath){
		return res;
	}

/* this repeats the lookup code found in arcan_shmif_control.c */
	size_t maxlen = sizeof((struct sockaddr_un){0}.sun_path);
	char cpath_full[maxlen];

	if ((cpath)[0] != '/'){
		char* basedir = getenv("XDG_RUNTIME_DIR");
		if (snprintf(cpath_full, maxlen, "%s/%s%s",
			basedir ? basedir : getenv("HOME"),
			basedir ? "" : ".", cpath) >= maxlen){
			free(res);
			fprintf(stderr,
				"Resolved path too long, cannot handover to arcan(_lwa)\n");
			return NULL;
		}
	}

	res->key = strdup("ARCAN_CONNPATH"),
	res->val = strdup(cpath_full);
	res->bin = "arcan_lwa";

	return res;
}

static pid_t exec_cpath(struct a12_state* S,
	struct directory_meta* dir, const char* name, void* tag, int* inf, int* outf)
{
	struct default_meta* ctx = tag;

	char buf[strlen(name) + sizeof("./")];
	snprintf(buf, sizeof(buf), "./%s", name);

	char logfd_str[16];
	int pstdin[2], pstdout[2];

	if (-1 == pipe(pstdin) || -1 == pipe(pstdout)){
		fprintf(stderr,
			"Couldn't setup control pipe in arcan handover\n");
		return 0;
	}

	snprintf(logfd_str, 16, "LOGFD:%d", pstdout[1]);

/*
 * The current default here is to collect crash- dumps or in-memory k/v store
 * synch and push them back to us, while taking controls from stdin.
 *
 * One thing that is important yet on the design- table is to allow the appl to
 * access a12- networked resources (or other protocols for that matter) and
 * have the request routed through the directory end and mapped to the
 * define_recordtarget, net_open, ... class of .lua functions.
 *
 * A use-case to 'test' against would be an appl that fetches a remote image
 * resource, takes a local webcam, overlays the remote image and streams the
 * result somewhere else - like a sink attached to the directory.
 */
	char* argv[] = {&buf[2],
		"-d", ":memory:",
		"-M", "-1",
		"-O", logfd_str,
		"-C",
		buf, NULL
	};

/* exec- over and monitor, keep connection alive */
	pid_t pid = fork();
	if (pid == 0){
/* remap control into STDIN */
		if (ctx->key)
			setenv(ctx->key, ctx->val, 1);

		fchdir(dir->clopt->basedir);

		setsid();
		setenv("XDG_RUNTIME_DIR", ".", 1);
		dup2(pstdin[0], STDIN_FILENO);
		close(pstdin[0]);
		close(pstdin[1]);
		close(pstdout[0]);

/*
 * keeping these open makes it easier to see when something goes wrong with _lwa
 *  close(STDERR_FILENO);
		close(STDOUT_FILENO);
		open("/dev/null", O_WRONLY);
		open("/dev/null", O_WRONLY);
*/
		execvp(ctx->bin, argv);
		exit(EXIT_FAILURE);
	}

	close(pstdin[0]);
	close(pstdout[1]);

	*inf = pstdin[1];
	*outf = pstdout[0];
	free(ctx->key);
	free(ctx->val);

	return pid;
}

static void runner_shmif(struct ioloop_shared* I)
{
	arcan_event ev;

	while (arcan_shmif_poll(&I->shmif, &ev) > 0){
		if (ev.category != EVENT_TARGET){
			continue;
		}

		if (ev.tgt.kind != TARGET_COMMAND_MESSAGE)
			continue;

/* we need to flip the 'direction' as the other end expect us to behave like a
 * shmif client, i.e. TARGET is from server to client, EXTERNAL is from client
 */
		struct arcan_event out = {
			.category = EVENT_EXTERNAL,
			.ext.message.multipart = ev.tgt.ioevs[0].iv
		};
		_Static_assert(sizeof(out.ext.message.data) ==
			sizeof(ev.tgt.message), "_event.h integrity");

		memcpy(out.ext.message.data, ev.tgt.message, sizeof(out.ext.message.data));

		a12_channel_enqueue(I->S, &out);
	}
}

static void setup_statefd(struct appl_runner_state* A)
{
	char filename[] = "statetemp-XXXXXX";
	A->state.fd = mkstemp(filename);

	if (-1 == A->state.fd){
		fprintf(stderr, "Couldn't create temp-store, state transfer disabled\n");
	}
	else
		unlink(filename);

	A->state.fpek = fdopen(A->state.fd, "w");
	A->state.active = true;
}

static void swap_appldir(const char* name, int basedir)
{
/* it is probably worth keeping track of the old here */
	size_t sz = strlen(name) + sizeof(".new");
	char buf[sz];
	snprintf(buf, sz, "%s.new", name);

	if (-1 != basedir){
		fchdir(basedir);
	}

	nftw(name, cleancb, 32, FTW_DEPTH | FTW_PHYS);
	renameat(basedir, buf, basedir, name);
}

/*
 * This will only trigger when there's data / shutdown from arcan. With the
 * current monitor mode setup that is only on script errors or legitimate
 * shutdowns, so safe to treat this as blocking.
 */
static void process_thread(struct ioloop_shared* I, bool ok)
{
/* capture the state block, write into an unlinked tmp-file so the
 * file descriptor can be rewound and set as a bstream */
	struct appl_runner_state* A = I->tag;
	struct directory_meta* cbt = I->cbt;

	char buf[4096];

/* we have a queued state transfer (crash dump or key value), keep feeding
 * that until we get the #ENDKV - this is triggered by receiving finish or
 * finish_fail */
	if (A->state.active){
		while (fgets(buf, 4096, A->pf_stdout)){
			fputs(buf, A->state.fpek);
			if (strcmp(buf, "#ENDKV\n") == 0){
				A->state.active = false;
				fflush(A->state.fpek);
				fprintf(A->pf_stdin, "continue\n");
				break;
			}
		}
		return;
	}

/* we are trying to synch a reload, now's the time to remove the old appldir
 * and rename the .new into just basename. */
	if (ok){
		if (fgets(buf, 4096, A->pf_stdout)){
			if (strcmp(buf, "#LOCKED\n") == 0){
				swap_appldir(cbt->clopt->applname, cbt->clopt->basedir);

/*  the first 'continue here is to unlock the reload, i.e. we don't want to
 *  buffer more commands in the same atomic commit. this causes recovery into
 *  something that immediately switches into monitoring mode again in order
 *  to provide a window for re-injecting state.
 *
 *  since the process is still alive, the current state is still in :memory:
 *  sqlite though so no need unless we want an explicit revert. */
				fprintf(A->pf_stdin, "reload\n");
				fprintf(A->pf_stdin, "continue\n");

/* state is already in database so just continue again, here is where we
 * could do some other funky things, e.g. force a rollback to an externally
 * defined override state. */
				fprintf(A->pf_stdin, "continue\n");
			}
			else if (strcmp(buf, "#FINISH\n") == 0){
				fprintf(A->pf_stdin,
					cbt->clopt->block_state ? "continue\n" : "dumpkeys\n");
				return;
			}
			else if (strcmp(buf, "#FAIL\n") == 0){
				fprintf(A->pf_stdin,
					cbt->clopt->block_state ? "continue\n" : "dumpstate\n");
			}
			else if (strcmp(buf, "#BEGINKV\n") == 0){
				setup_statefd(A);
				fputs(buf, A->state.fpek);
				return process_thread(I, ok);
			}

/* client wants to join the applgroup through a net_open call and has set up a
 * connection point for us to access - this direction may seem a bit weird, but
 * since we are on equal privilege and arcan-core does not have a way of
 * hooking up a shmif_cont structure, only feeding it, this added the least
 * amount of complexity across the chain. */
			else if (strncmp(buf, "join ", 5) == 0){
				if (I->shmif.addr){
					arcan_shmif_drop(&I->shmif);
				}

				buf[strlen(buf)-1] = '\0';
				char cbuf[strlen(buf) + strlen(I->cbt->clopt->basedir_path) + 1];
				snprintf(cbuf, sizeof(cbuf), "%s/%s", I->cbt->clopt->basedir_path, &buf[5]);

/* strip \n and connect */
				int dfd;
				char* key = arcan_shmif_connect(cbuf, NULL, &dfd);
				a12int_trace(A12_TRACE_DIRECTORY,
					"appl_monitor:connect=%s:ok=%s", cbuf, key ? "true":"false");
				if (!key){
					return;
				}

				I->shmif = arcan_shmif_acquire(NULL, key, SEGID_MEDIA, 0);
				I->shmif.epipe = dfd;
				I->on_shmif = runner_shmif;

				if (!I->shmif.addr){
					a12int_trace(A12_TRACE_DIRECTORY, "appl_monitor:connect_fail");
					return;
				}

	/* join the message group for the running appl */
			  arcan_event ev = {
					.category = EVENT_EXTERNAL,
					.ext.kind = ARCAN_EVENT(IDENT)
				};

				size_t lim = sizeof(ev.ext.message.data)/sizeof(ev.ext.message.data[1]);
				if (cbt->clopt->ident[0]){
					snprintf(
						(char*)ev.ext.message.data, lim, "%d:%s",
						I->cbt->clopt->applid, cbt->clopt->ident
					);
				}
				else
					snprintf(
						(char*)ev.ext.message.data, lim, "%d", I->cbt->clopt->applid);
				a12_channel_enqueue(I->S, &ev);
				runner_shmif(I);
			}
		}

		return;
	}

	int pret;
	while ((waitpid(A->pid, &pret, -1))
		!= A->pid && (errno == EINTR || errno == EAGAIN)){}

/* exited successfully? then the state snapshot should only contain the K/V
 * dump. If empty - do nothing. If exit with error code, the state we read
 * should be debuginfo, forward accordingly. */
	if (!cbt->clopt->keep_appl)
		clean_appldir(cbt->clopt->applname, cbt->clopt->basedir);

	bool exec_res = false;
	if (WIFEXITED(pret) && !WEXITSTATUS(pret)){
		fprintf(stderr, "arcan(%s) exited successfully\n", cbt->clopt->applname);
		exec_res = true;
	}
/* exited with error code or sig(abrt,kill,...) */
	else if (
		(WIFEXITED(pret) && WEXITSTATUS(pret)) ||
		WIFSIGNALED(pret))
	{
		fprintf(stderr, "script/exection error, generating report\n");
	}
	else {
		fprintf(stderr, "arcan: unhandled application termination state\n");
	}

/* just request new dirlist and it should reload, if state or log are
 * blocked the fpek wouldn't have been created so it is safe to send */
	if (!A->state.fpek)
		goto out;

	long sz = ftell(A->state.fpek);
	char empty_ext[16] = {0};

	a12_enqueue_bstream(
		I->S,
		A->state.fd,
		exec_res ? A12_BTYPE_STATE : A12_BTYPE_CRASHDUMP,
		cbt->clopt->applid,
		false,
		sz,
		empty_ext
	);

	fclose(A->state.fpek);
	a12_shutdown_id(I->S, cbt->clopt->applid);

out:
	if (cbt->clopt->reload){
		a12int_request_dirlist(I->S, true);
	}
	else
		I->shutdown = A->state.fpek == NULL;

/* reset appl tracking state so reset will take the right path */
	if (A->pf_stdin){
		fclose(A->pf_stdin);
		A->pf_stdin = NULL;
		A->p_stdin = -1;
	}

	if (A->pf_stdout){
		fclose(A->pf_stdout);
		A->pf_stdout = NULL;
		A->p_stdout = -1;
	}

	A->pid = 0;
	I->on_event = NULL;
	I->userfd = -1;
	I->on_userfd = NULL;
	atomic_fetch_add(&active_appls.n_active, -1);
}

static void send_state(FILE* dst, FILE* src)
{
	if (!src)
		return;

	fseek(src, 0, SEEK_SET);

	char buf[4096];
	bool in_kv = false;

	while (fgets(buf, 4096, src)){
		if (in_kv){
			if (strcmp(buf, "#ENDKV\n") == 0){
				in_kv = false;
				continue;
			}
			fputs("loadkey ", dst);
			fputs(buf, dst);
		}
		else {
			if (strcmp(buf, "#BEGINKV\n") == 0){
				in_kv = true;
			}
			continue;
		}
	}
}

/*
 * This entire function is prototype- quality and mainly for figuring out the
 * interface / path between arcan (lwa), appl, arcan-net and a12.
 *
 * Its main purpose is to setup the env for arcan to either run the appl as a
 * normal display server, within an existing arcan one or from within another
 * desktop.
 *
 * It also launches / runs and blocks into a 'monitoring' mode used for setting
 * the initial state, capture crash dumps and snapshot / backup state.
 *
 * It is likely that the stdin/stdout pipe/monitor interface would be better
 * served by another shmif/shmif server connection, but right now it is just
 * plaintext.
 */
static bool handover_exec(struct appl_runner_state* A, FILE* sin)
{
	struct ioloop_shared* I = A->ios;
	struct directory_meta* dir = I->cbt;
	struct anet_dircl_opts* opts = dir->clopt;

	void* tag = opts->allocator(I->S, dir);
	if (!tag){
		I->shutdown = true;
		fprintf(stderr, "executor-alloc failed");
		fclose(sin);
		return false;
	}

/* ongoing refactor to break this out entirely */
	A->p_stdin = -1;
	A->p_stdout = -1;

	pid_t pid = opts->executor(
		I->S, dir, dir->clopt->applname, tag, &A->p_stdin, &A->p_stdout);
	if (pid <= 0){
		free(tag);
		fclose(sin);
		fprintf(stderr, "executor-failed");
		return false;
	}

	if (pid == -1){
		clean_appldir(dir->clopt->applname, dir->clopt->basedir);
		fprintf(stderr, "Couldn't spawn child process");
		return false;
	}

	A->pid = pid;
	A->pf_stdin = fdopen(A->p_stdin, "w");
	A->pf_stdout = fdopen(A->p_stdout, "r");
	setlinebuf(A->pf_stdin);
	setlinebuf(A->pf_stdout);

/* if we have state, now is a good time to do something with it, now the format
 * here isn't great - lf without escape is problematic as values with lf is
 * permitted so this needs to be modified a bit, but the _lwa to STATE_OUT
 * handler also calls for this so can wait until that is in place */
	send_state(A->pf_stdin, sin);
	fprintf(A->pf_stdin, "continue\n");

/* keep the state in block around for quick reload / resume, now hook
 * into the userfd part of the ioloop_state and do our processing there. */
	I->userfd = A->p_stdout;
	I->on_userfd = process_thread;
	I->tag = A;

	return true;
}

void* appl_runner(void* tag)
{
	struct appl_runner_state* S = tag;
	struct directory_meta* cbt = S->ios->cbt;

	FILE* state_in = NULL;
	if (-1 != cbt->state_in){
		lseek(cbt->state_in, 0, SEEK_SET);
		state_in = fdopen(cbt->state_in, "r");
		cbt->state_in = -1;
		cbt->state_in_complete = false;
	}

	swap_appldir(cbt->clopt->applname, cbt->clopt->basedir);

/* appl_runner hooks into ios->userfd and attaches the event handler
 * which translates commands and eventually serializes / forwards state */
	handover_exec(S, state_in);
	return NULL;
}

static void mark_xfer_complete(struct ioloop_shared* I, struct a12_bhandler_meta M)
{
	struct directory_meta* cbt = I->cbt;
/* state transfer will be initiated before appl transfer (if one is present),
 * but might complete afterwards - defer the actual execution until BOTH have
 * been completed */
	if (M.type == A12_BTYPE_STATE){
		cbt->state_in_complete = true;
	}
	else if (M.type == A12_BTYPE_BLOB){
		cbt->appl_out_complete = true;
	}

/* still need to wait for the state block to finish */
	if (cbt->state_in != -1 && !cbt->state_in_complete){
		return;
	}

	if (!cbt->appl_out_complete)
		return;

/* signs of foul-play - we recieved completion notices without init.. */
	if (!cbt->appl_out){
		fprintf(stderr, "xfer completed on blob without an active state\n");
		I->shutdown = true;
		return;
	}

/* extract into 'newname' first, then we swap it before launch */
	char newname[strlen(cbt->clopt->applname) + sizeof(".new")];
	snprintf(newname, sizeof(newname), "%s.new", cbt->clopt->applname);
	const char* msg;
	if (!extract_appl_pkg(cbt->appl_out, cbt->clopt->basedir, newname, &msg)){
		fprintf(stderr, "unpack appl failed: %s\n", msg);
		I->shutdown = true;
		return;
	}

	cbt->appl_out = NULL;
	cbt->appl_out_complete = false;

/* if there is already an appl running we wnat to swap it out, in order to do
 * that we want to make sure there are no file-system races. this is done by
 * sending a lock command, waiting for that to be acknowledged when in the
 * handler rename. */
	if (atomic_load(&active_appls.n_active) > 0){
		fprintf(active_appls.active.pf_stdin, "lock\n");
		kill(active_appls.active.pid, SIGUSR1);
		fprintf(stderr, "signalling=%d\n", active_appls.active.pid);
		return;
	}

/* Setup so it is threadable, though unlikely that useful versus just having
 * userfd and multiplex appl-a12 that way. It would be for the case of running
 * multiple appls over the same channel so keep that door open. Right now we
 * work on the idea that if a new appl is received we should just force the
 * other end to reload. We do this by queueing the command, waking the watchdog
 * and waiting for it to reply to us via userfd */

	atomic_fetch_add(&active_appls.n_active, 1);
	active_appls.active.ios = I;

/*pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
	pthread_create(&pth, &pthattr, appl_runner, &active_appls.active);
*/
	appl_runner(&active_appls.active);
}

struct a12_bhandler_res anet_directory_cl_bhandler(
	struct a12_state* S, struct a12_bhandler_meta M, void* tag)
{
	struct ioloop_shared* I = tag;
	struct directory_meta* cbt = I->cbt;
	struct a12_bhandler_res res = {
		.fd = -1,
		.flag = A12_BHANDLER_DONTWANT
	};

/*
 * three key paths:
 *  1. downloading / running an appl
 *  2. auto-updating an appl
 *  3. synchronising a state blob change
 */
	switch (M.state){
	case A12_BHANDLER_COMPLETED:
		mark_xfer_complete(I, M);
	break;
	case A12_BHANDLER_INITIALIZE:{
/* if we get a state blob before the binary blob, it should be kept until the
 * binary blob is completed and injected as part of the monitoring setup -
 * wrap this around a FILE* abstraction */
		if (M.type == A12_BTYPE_STATE){
			if (-1 != cbt->state_in){
				fprintf(stderr, "Server sent multiple state blocks, ignoring\n");
				return res;
			}

/* create a tempfile / unlink it */
			char filename[] = "statetemp-XXXXXX";
			if (-1 == (cbt->state_in = mkstemp(filename))){
				fprintf(stderr, "Couldn't allocate temp-store, ignoring state\n");
				return res;
			}

			cbt->state_in_complete = true;
			res.fd = cbt->state_in;
			res.flag = A12_BHANDLER_NEWFD;
			unlink(filename);
			return res;
		}

	/* This can also happen if there was a new appl announced while we were busy
	 * unpacking the previous one, the dirstate event triggers the bin request
	 * triggers new initialize. Options are to cancel the current form, ignore
	 * the update or defer the request for a new one. The current implementation
	 * is to defer and happens in dir-state. */
		if (cbt->appl_out){
			fprintf(stderr, "Appl transfer initiated while one was pending\n");
			return res;
		}

	/* We already have an appl running, this can be two things - one we have a
	 * resource intended for the appl itself. While still unhandled that is easy,
	 * setup a new descriptor link, BCHUNK_IN/OUT it into the shmif connection
	 * marked streaming and we are good to go.
	 *
	 * In the case of an appl we should verify that we wanted hot reloading,
	 * ensure_appldir into new and set atomic-swap on completion. */
		if (-1 == cbt->clopt->basedir){
			snprintf(cbt->clopt->basedir_path, PATH_MAX, "%s", "/tmp/appltemp-XXXXXX");
			if (!mkdtemp(cbt->clopt->basedir_path)){
				fprintf(stderr, "Couldn't build a temporary storage base\n");
				return res;
			}
			cbt->clopt->basedir = open(cbt->clopt->basedir_path, O_DIRECTORY);
		}

		char filename[] = "appltemp-XXXXXX";
		int appl_fd = mkstemp(filename);
		if (-1 == appl_fd){
			fprintf(stderr, "Couldn't create temporary appl- unpack store\n");
			return res;
		}
		unlink(filename);

		cbt->appl_out = fdopen(appl_fd, "rw");
		res.flag = A12_BHANDLER_NEWFD;
		res.fd = appl_fd;
	}
	break;

/* set to fail for now? this is most likely to happen if write to the backing
 * FD fails (though the server is free to cancel for other reasons) */
	case A12_BHANDLER_CANCELLED:
		if (M.type == A12_BTYPE_STATE){
			fprintf(stderr, "appl state transfer cancelled\n");
			close(cbt->state_in);
			cbt->state_in = -1;
			cbt->state_in_complete = false;
		}
		else if (M.type == A12_BTYPE_BLOB){
			fprintf(stderr, "appl download cancelled\n");
			if (cbt->appl_out){
				cbt->appl_out = NULL;
				cbt->appl_out_complete = false;
			}
			clean_appldir(cbt->clopt->applname, cbt->clopt->basedir);
		}
		else
			;
	break;
	}

	return res;
}

static void cl_got_dyn(struct a12_state* S, int type,
		const char* petname, bool found, uint8_t pubk[static 32], void* tag)
{
	struct ioloop_shared* I = tag;
	struct directory_meta* cbt = I->cbt;
	printf("source-%s=<%s\n", found ? "found" : "lost", petname);

/* some kind of symbol, < as source, > as sink, / as directory */

	if (cbt->clopt->applname[0] != '<' ||
		strcmp(&I->cbt->clopt->applname[1], petname) != 0)
		return;

	size_t outl;
	unsigned char* req = a12helper_tob64(pubk, 32, &outl);
	a12int_trace(A12_TRACE_DIRECTORY, "request:petname=%s:pubk=%s", petname, req);
	free(req);
	a12_request_dynamic_resource(S,
		pubk, cbt->clopt->request_tunnel, dircl_source_handler, I);
}

static bool cl_got_dir(struct ioloop_shared* I, struct appl_meta* dir)
{
	struct directory_meta* cbt = I->cbt;

	if (cbt->clopt->outapp.buf){
		struct appl_meta* C = dir;
		cbt->clopt->outapp.identifier = 65535;
		bool found = false;

		while (C){
			if (strcmp(C->appl.name, cbt->clopt->outapp.appl.name) == 0){
				found = true;
				cbt->clopt->outapp.appl.name[0] = '\0';
				a12int_trace(A12_TRACE_DIRECTORY,
					"push-match:name=%s:identifier=%d",
					C->appl.name, (int) C->identifier
				);
				cbt->clopt->outapp.identifier = C->identifier;
				break;
			}
			C = C->next;
		}

/* no explicit identifier to throw it in, try to create a new (which may need
 * different permissions hence why the initial search) */
		if (!found){
			a12int_trace(A12_TRACE_DIRECTORY,
				"push-no-match:name=%s", cbt->clopt->outapp.appl.name);
		}

		cbt->transfer_id = cbt->clopt->outapp.identifier;
		cbt->in_transfer = true;

		a12_enqueue_blob(I->S,
			cbt->clopt->outapp.buf,
			cbt->clopt->outapp.buf_sz,
			cbt->clopt->outapp.identifier,
			A12_BTYPE_APPL,
			cbt->clopt->outapp.appl.name
		);

		return true;
	}

	while (dir){
/* use identifier to request binary */
		if (cbt->clopt->applname[0]){
			if (strcasecmp(dir->appl.name, cbt->clopt->applname) == 0){
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
					(char*)ev.ext.bchunk.extensions, 6, "%"PRIu16, dir->identifier);
				a12_channel_enqueue(I->S, &ev);

/* and register our store+launch handler */
				cbt->clopt->applid = dir->identifier;
				a12_set_bhandler(I->S, anet_directory_cl_bhandler, I);
				return true;
			}
		}
		printf("ts=%"PRIu64":name=%s\n", dir->update_ts, dir->appl.name);
		dir = dir->next;
	}

	if (cbt->clopt->applname[0] && cbt->clopt->applname[0] != '<'){
		fprintf(stderr, "appl:%s not found\n", cbt->clopt->applname);
		return false;
	}

	if (cbt->clopt->die_on_list && cbt->clopt->applname[0] != '<')
		return false;

	return true;
}

void anet_directory_cl(
	struct a12_state* S, struct anet_dircl_opts opts, int fdin, int fdout)
{
	struct directory_meta cbt = {
		.S = S,
		.clopt = &opts,
		.state_in = -1
	};

	if (!opts.allocator || !opts.executor){
		opts.allocator = alloc_cpath;
		opts.executor = exec_cpath;
	}

	sigaction(SIGPIPE,&(struct sigaction){.sa_handler = SIG_IGN}, 0);

	struct ioloop_shared ioloop = {
		.S = S,
		.fdin = fdin,
		.fdout = fdout,
		.userfd = -1,
		.on_event = on_cl_event,
		.on_directory = cl_got_dir,
		.lock = PTHREAD_MUTEX_INITIALIZER,
		.cbt = &cbt,
	};

	a12_set_destination_raw(S,
		0, (struct a12_unpack_cfg){
			.on_discover = cl_got_dyn,
			.on_discover_tag = &ioloop,
		}, sizeof(struct a12_unpack_cfg)
	);

/* send REGISTER event with our ident, this is a convenience thing right now,
 * it might be slightly cleaner having an actual directory command for the
 * thing rather than (ab)using REGISTER here and IDENT for appl-messaging. */
	if (opts.dir_source){
		uint8_t nk[32] = {0};
		struct arcan_event ev = {
			.ext.kind = ARCAN_EVENT(REGISTER),
			.category = EVENT_EXTERNAL,
			.ext.registr = {}
		};
		snprintf(
			(char*)ev.ext.registr.title, 64, "%s", opts.ident);
		a12_channel_enqueue(S, &ev);
		a12_request_dynamic_resource(S, nk, false, opts.dir_source, opts.dir_source_tag);
	}
	else
		a12int_request_dirlist(S, !opts.die_on_list || opts.applname[0]);

	anet_directory_ioloop(&ioloop);

/* if we went for setting up the basedir we clean it as well */
	if (opts.basedir_path[0]){
		rmdir(opts.basedir_path);
		close(opts.basedir);
		opts.basedir = -1;
		opts.basedir_path[0] = '\0';
	}
}
