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

	pid_t pid;

	FILE* pf_stdin;
	FILE* pf_stdout;

	int p_stdout;
	int p_stdin;
};

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
 *    we might need to tunnel via the directory
 */
static void on_source(struct a12_state* S, struct a12_dynreq req, void* tag)
{
/* security:
 * disable the ephemeral exchange for now, this means the announced identity
 * when we connect to the directory server will be the one used for the x25519
 * exchange instead of a generated intermediate.
 */
	struct a12_context_options a12opts = {
		.local_role = ROLE_SINK,
		.pk_lookup = key_auth_fixed,
		.pk_lookup_tag = &req,
		.disable_ephemeral_k = true,
/*	.force_ephemeral_k = true, */
	};

/* the other end will use the same pubkey twice (source always exposes itself
 * unless we simply skip the ephemeral round in the HELLO - something to do if
 * the other endpoint is trusted. */
	memcpy(&a12opts.expect_ephem_pubkey, req.pubk, 32);
	x25519_private_key(a12opts.priv_ephem_key);

	char port[sizeof("65535")];
	snprintf(port, sizeof(port), "%"PRIu16, req.port);

	struct anet_options anet = {
		.retry_count = 10,
		.opts = &a12opts,
		.host = req.host,
		.port = port
	};

	snprintf(a12opts.secret, sizeof(a12opts.secret), "%s", req.authk);
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

	a12helper_a12srv_shmifcl(NULL, con.state, NULL, con.fd, con.fd);
	shutdown(con.fd, SHUT_RDWR);
}

static void on_cl_event(
	struct arcan_shmif_cont* cont, int chid, struct arcan_event* ev, void* tag)
{
/* main use would be the appl- runner forwarding messages that direction */
	a12int_trace(A12_TRACE_DIRECTORY, "event=%s", arcan_shmif_eventstr(ev, NULL, 0));
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

static bool ensure_appldir(const char* name, int basedir)
{
/* this should also ensure that we have a correct statedir
 * and try to retrieve it if possible */
	if (-1 != basedir){
		fchdir(basedir);
	}

	char buf[strlen(name) + sizeof(".new")];
	if (atomic_load(&active_appls.n_active) > 0){
		snprintf(buf, sizeof(buf), "%s.new", name);
		name = buf;
	}

/* make sure we don't have a collision */
	clean_appldir(name, basedir);

	if (-1 == mkdir(name, S_IRWXU) || -1 == chdir(name)){
		fprintf(stderr, "Couldn't create [basedir]/%s\n", name);
		return false;
	}

	return true;
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

	if (!cpath)
		return NULL;

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

		setsid();
		setenv("XDG_RUNTIME_DIR", "./", 1);
		dup2(pstdin[0], STDIN_FILENO);
		close(pstdin[0]);
		close(pstdin[1]);
		close(pstdout[0]);
		close(STDERR_FILENO);
		close(STDOUT_FILENO);
		open("/dev/null", O_WRONLY);
		open("/dev/null", O_WRONLY);
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
	rename(buf, name);
}

/*
 * This will only trigger when there's data / shutdown from arcan. With the
 * current monitor mode setup that is only on script errors or legitimate
 * shutdowns, so safe to treat this as blocking.
 */
static void process_thread(struct ioloop_shared* I, bool ok)
{
	char buf[4096];

/* capture the state block, write into an unlinked tmp-file so the
 * file descriptor can be rewound and set as a bstream */
	struct appl_runner_state* A = I->tag;
	struct directory_meta* cbt = I->cbt;

/* we are trying to synch a reload, now's the time to remove the old appldir
 * and rename the .new into just basename. */
	if (ok){
		if (fgets(buf, 4096, A->pf_stdout)){
			if (strcmp(buf, "#LOCKED\n") == 0){
				swap_appldir(cbt->clopt->applname, cbt->clopt->basedir);

/*  the first 'continue here is to unlock the reload, i.e. we don't want to
 *  buffer more commands in the same atomic commit. this causes recovery into
 *  something that immediately switches into monitoring mode again in order
 *  to provide a window for re-injecting state */
				fprintf(A->pf_stdin, "reload\n");
				fprintf(A->pf_stdin, "continue\n");

/* state is already in database so just continue again, here is where we
 * could do some other funky things, e.g. force a rollback to an externally
 * defined override state. */
				fprintf(A->pf_stdin, "continue\n");
			}
		}

		return;
	}

	int pret = 0;
	char* out = NULL;
	char filename[] = "statetemp-XXXXXX";
	int state_fd = mkstemp(filename);
	size_t state_sz = 0;

	if (-1 == state_fd){
		fprintf(stderr, "Couldn't create temp-store, state transfer disabled\n");
	}
	else
		unlink(filename);

	while (!feof(A->pf_stdout)){
/* couldn't get more state, STDOUT is likely broken - process dead or dying */
		if (!fgets(buf, 4096, A->pf_stdout)){
			while ((waitpid(A->pid, &pret, 0)) != A->pid
				&& (errno == EINTR || errno == EAGAIN)){}
		}

/* try to cache it to our temporary state store */
		else if (-1 != state_fd){
			size_t ntw = strlen(buf);
			size_t pos = 0;

/* normal POSIX write shenanigans */
			while (ntw){
				ssize_t nw = write(state_fd, &buf[pos], ntw);
				if (-1 == nw){
					if (errno == EAGAIN || errno == EINTR)
						continue;

					fprintf(stderr, "Out of space caching state, transfer disabled\n");
					close(state_fd);
					state_fd = -1;
					break;
				}

				ntw -= nw;
				pos += nw;
				state_sz += nw;
			}
		}
	}

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

/* just request new dirlist and it should reload */
	if (-1 == state_fd || !state_sz){
		goto out;
	}

	char empty_ext[16] = {0};
	if (exec_res && !cbt->clopt->block_state){
		a12_enqueue_bstream(I->S, state_fd,
			A12_BTYPE_STATE, cbt->clopt->applid, false, state_sz, empty_ext);
	}
	else if (!exec_res && !cbt->clopt->block_log){
		fprintf(stderr, "sending crash report (%zu) bytes\n", state_sz);
		a12_enqueue_bstream(I->S, state_fd,
			A12_BTYPE_CRASHDUMP, cbt->clopt->applid, false, state_sz, empty_ext);
	}

out:
	if (-1 != state_fd)
		close(state_fd);

	if (cbt->clopt->reload){
		a12int_request_dirlist(I->S, true);
	}
	else
		I->shutdown = true;

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
		fprintf(stderr, "xfer completed on blob without an active state");
		I->shutdown = true;
		return;
	}

/* EOF the unpack action now */
	if (pclose(cbt->appl_out) != EXIT_SUCCESS){
		fprintf(stderr, "xfer download unpack failed");
		I->shutdown = true;
		return;
	}
	cbt->appl_out = NULL;
	cbt->appl_out_complete = false;

/* Setup so it is threadable, though unlikely that useful versus just having
 * userfd and multiplex appl-a12 that way. It would be for the case of running
 * multiple appls over the same channel so keep that door open. Right now we
 * work on the idea that if a new appl is received we should just force the
 * other end to reload. We do this by queueing the command, waking the watchdog
 * and waiting for it to reply to us via userfd */
	if (atomic_load(&active_appls.n_active) > 0){
		fprintf(active_appls.active.pf_stdin, "lock\n");
		kill(active_appls.active.pid, SIGUSR1);
		fprintf(stderr, "signalling=%d\n", active_appls.active.pid);
		return;
	}

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
		if (!ensure_appldir(cbt->clopt->applname, cbt->clopt->basedir)){
			fprintf(stderr, "Couldn't create temporary appl directory\n");
			return res;
		}

		cbt->appl_out = popen("tar xfm -", "w");
		res.fd = fileno(cbt->appl_out);
		res.flag = A12_BHANDLER_NEWFD;

/* these should really just enforce basedir and never use relative, it is
 * just some initial hack thing that survived. */
		if (-1 != cbt->clopt->basedir)
			fchdir(cbt->clopt->basedir);
		else
			chdir("..");
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
	if (cbt->clopt->applname[0] != '*' ||
		strcmp(&I->cbt->clopt->applname[1], petname) != 0)
		return;

	size_t outl;
	unsigned char* req = a12helper_tob64(pubk, 32, &outl);
	a12int_trace(A12_TRACE_DIRECTORY, "request:petname=%s:pubk=%s", petname, req);
	free(req);
	a12_request_dynamic_resource(S, pubk, on_source, I);
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

		a12_enqueue_blob(I->S,
			cbt->clopt->outapp.buf,
			cbt->clopt->outapp.buf_sz,
			cbt->clopt->outapp.identifier,
			A12_BTYPE_APPL,
			cbt->clopt->outapp.appl.name
		);

		I->shutdown = true;
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

	if (cbt->clopt->applname[0] && cbt->clopt->applname[0] != '*'){
		fprintf(stderr, "appl:%s not found\n", cbt->clopt->applname);
		return false;
	}

	if (cbt->clopt->die_on_list)
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

	S->on_discover = cl_got_dyn;
	S->discover_tag = &ioloop;

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
		a12_request_dynamic_resource(S, nk, opts.dir_source, opts.dir_source_tag);
	}
	else
		a12int_request_dirlist(S, !opts.die_on_list);

	anet_directory_ioloop(&ioloop);
}
