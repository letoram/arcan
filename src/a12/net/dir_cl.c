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

static void on_cl_event(
	struct arcan_shmif_cont* cont, int chid, struct arcan_event* ev, void* tag)
{
/* the only concerns here are BCHUNK matching our directory IDs,
 * with the BCHUNK_IN, spin up a new fork + tar from stdin to temp applfolder
 * and exec into arcan_lwa */
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

/*
 * This entire function is protoype- quality and mainly for figuring out the
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
static bool handover_exec(struct a12_state* S, const char* name,
	FILE* state_in, struct directory_meta* dir, int* state, size_t* state_sz)
{
	struct anet_dircl_opts* opts = dir->clopt;

	void* tag = opts->allocator(S, dir);
	if (!tag){
		*state = -1;
		return false;
	}

/* ongoing refactor to break this out entirely */
	int inf = -1;
	int outf = -1;
	*state_sz = 0;

	pid_t pid = opts->executor(S, dir, name, tag, &inf, &outf);
	if (pid <= 0){
		free(tag);
		fprintf(stderr, "executor-failed");
		*state = -1;
		return false;
	}

	if (pid == -1){
		clean_appldir(name, opts->basedir);
		fprintf(stderr, "Couldn't spawn child process");
		*state = -1;
		return false;
	}

	FILE* pfin = fdopen(inf, "w");
	FILE* pfout = fdopen(outf, "r");
	setlinebuf(pfin);
	setlinebuf(pfout);

/* if we have state, now is a good time to do something with it, now the format
 * here isn't great - lf without escape is problematic as values with lf is
 * permitted so this needs to be modified a bit, but the _lwa to STATE_OUT
 * handler also calls for this so can wait until that is in place */
	if (state_in){
		char buf[4096];
		bool in_kv = false;

		while (fgets(buf, 4096, state_in)){
			if (in_kv){
				if (strcmp(buf, "#ENDKV\n") == 0){
					in_kv = false;
					continue;
				}
				fputs("loadkey ", pfin);
				fputs(buf, pfin);
			}
			else {
				if (strcmp(buf, "#BEGINKV\n") == 0){
					in_kv = true;
				}
				continue;
			}
		}
	}
	fprintf(pfin, "continue\n");

/* capture the state block, write into an unlinked tmp-file so the
 * file descriptor can be rewound and set as a bstream */
	int pret = 0;
	char* out = NULL;
	char filename[] = "statetemp-XXXXXX";
	int state_fd = mkstemp(filename);
	if (-1 == state_fd){
		fprintf(stderr, "Couldn't create temp-store, state transfer disabled\n");
	}
	else
		unlink(filename);

	while (!feof(pfout)){
		char buf[4096];

/* couldn't get more state, STDOUT is likely broken - process dead or dying */
		if (!fgets(buf, 4096, pfout)){
			while ((waitpid(pid, &pret, 0)) != pid
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
					*state_sz = 0;
					break;
				}

				ntw -= nw;
				pos += nw;
				*state_sz += nw;
			}
		}
	}

/* exited successfully? then the state snapshot should only contain the K/V
 * dump, and if empty - nothing to do */
	if (!opts->keep_appl)
		clean_appldir(name, opts->basedir);
	*state = state_fd;

	if (WIFEXITED(pret) && !WEXITSTATUS(pret)){
		return true;
	}
/* exited with error code or sig(abrt,kill,...) */
	if (
		(WIFEXITED(pret) && WEXITSTATUS(pret)) ||
		WIFSIGNALED(pret))
	{
		;
	}
	else {
		fprintf(stderr, "unhandled application termination state\n");
	}

	return false;
}

static void mark_xfer_complete(
	struct a12_state* S, struct a12_bhandler_meta M, struct directory_meta* cbt)
{
/* state transfer will be initiated before appl transfer (if one is present),
 * but might complete afterwards - defer the actual execution until BOTH have
 * been completed */
	if (M.type == A12_BTYPE_STATE){
		cbt->state_in_complete = true;
		if (cbt->appl_out_complete)
			goto run;
		return;
	}
	else if (M.type != A12_BTYPE_BLOB)
		return;

/* signs of foul-play */
	if (!cbt->appl_out){
		fprintf(stderr, "xfer completed on blob without an active state");
		g_shutdown = true;
		return;
	}

	cbt->appl_out_complete = true;

/* still need to wait for the state block to finish */
	if (cbt->state_in != -1 && !cbt->state_in_complete){
		return;
	}

/*
 * run the appl, collect state into *state_out and if need be, synch it onwards
 * - the a12 implementation will take care of the actual transfer and
 *   cancellation should the other end not care for our state synch
 *
 * this is a placeholder setup, the better approach is to keep track of the
 * child we are running while still processing other a12 events - to open up
 * for multiplexing any resources the child might want dynamically, as well
 * as handle 'push' updates to the appl itself and just 'force' through the
 * monitor interface.
 */
run:
	pclose(cbt->appl_out);
	cbt->appl_out = NULL;
	cbt->appl_out_complete = false;

/* rewind the state block and pass it (if present) to the execution setup */
	FILE* state_in = NULL;
	if (-1 != cbt->state_in){
		lseek(cbt->state_in, 0, SEEK_SET);
		state_in = fdopen(cbt->state_in, "r");
		cbt->state_in = -1;
		cbt->state_in_complete = false;
	}

	int state_out = -1;
	size_t state_sz = 0;

	bool exec_res = handover_exec(S,
		cbt->clopt->applname, state_in, cbt, &state_out, &state_sz);

	if (state_in)
		fclose(state_in);

/* execution completed - this is where we could/should actually continue and
 * switch to an ioloop that check the child process for completion or for appl
 * 'push' updates */
	if (-1 == state_out)
		return;

/* if permitted and we got state or crashdump, synch it back */
	if (state_sz){
			if (exec_res && !cbt->clopt->block_state){
				a12_enqueue_bstream(S,
					state_out, A12_BTYPE_STATE, M.identifier, false, state_sz);
				close(state_out);
				state_out = -1;
			}
			else if (!exec_res && !cbt->clopt->block_log){
				a12_enqueue_bstream(S,
					state_out, A12_BTYPE_CRASHDUMP, M.identifier, false, state_sz);
				close(state_out);
				state_out = -1;
			}
		}

/* never got adopted */
	if (-1 != state_out)
		close(state_out);

/* backwards way to do it and should be reconsidered when we do processing
 * while arcan_lwa / arcan is still running, but for now this will cause a
 * new dirlist, a new match and a new request -> running */
	if (cbt->clopt->reload){
		a12int_request_dirlist(S, false);
	}
	else
		g_shutdown = true;
}

struct a12_bhandler_res anet_directory_cl_bhandler(
	struct a12_state* S, struct a12_bhandler_meta M, void* tag)
{
	struct directory_meta* cbt = tag;
	struct a12_bhandler_res res = {
		.fd = -1,
		.flag = A12_BHANDLER_DONTWANT
	};

	switch (M.state){
	case A12_BHANDLER_COMPLETED:
		mark_xfer_complete(S, M, tag);
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

		if (cbt->appl_out){
			fprintf(stderr, "Appl transfer initiated while one was pending\n");
			return res;
		}

/* could also use -C */
		if (!ensure_appldir(cbt->clopt->applname, cbt->clopt->basedir)){
			fprintf(stderr, "Couldn't create temporary appl directory\n");
			return res;
		}

/* for restoring the DB, can simply popen to arcan_db with the piped mode
 * (arcan_db add_appl_kv basename key value) and send a SIGUSR2 to the process
 * to indicate that the state has been updated. */
		cbt->appl_out = popen("tar xfm -", "w");
		res.fd = fileno(cbt->appl_out);
		res.flag = A12_BHANDLER_NEWFD;

		if (-1 != cbt->clopt->basedir)
			fchdir(cbt->clopt->basedir);
		else
			chdir("..");
	}
	break;

/* set to fail for now? this is most likely to happen if write to the backing
 * FD fails (though the server is free to cancel for other reasons) */
	case A12_BHANDLER_CANCELLED:
		fprintf(stderr, "appl download cancelled\n");
		if (M.type == A12_BTYPE_STATE){
			close(cbt->state_in);
			cbt->state_in = -1;
			cbt->state_in_complete = false;
		}
		else if (M.type == A12_BTYPE_BLOB){
			if (cbt->appl_out){
				pclose(cbt->appl_out);
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

static bool cl_got_dir(struct a12_state* S, struct appl_meta* M, void* tag)
{
	struct directory_meta* cbt = tag;

	while (M){
/* use identifier to request binary */
		if (cbt->clopt->applname[0]){
			if (strcasecmp(M->applname, cbt->clopt->applname) == 0){
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

/* and register our store+launch handler */
				a12_set_bhandler(S, anet_directory_cl_bhandler, tag);
				return true;
			}
		}
		else
			printf("name=%s\n", M->applname);

		M = M->next;
	}

	if (cbt->clopt->applname[0]){
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

	if (opts.source_argv){
		return;
	}

/* always request dirlist so we can resolve applname against the server-local
 * ID as that might change */
	a12int_request_dirlist(S, false);
	anet_directory_ioloop(S, &cbt, fdin, fdout, -1, on_cl_event, cl_got_dir, NULL);
}
