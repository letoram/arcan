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

extern bool g_shutdown;

static struct a12_bhandler_res srv_bevent(
	struct a12_state* S, struct a12_bhandler_meta M, void* tag);

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
 * have to redownload if nothing's changed. */
static size_t scan_appdir(int fd, struct appl_meta* dst)
{
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

		*new = (struct appl_meta){0};
		dst->next = new;
		dst = new;
	}

	closedir(dir);
	return count;
}

static void on_srv_event(
	struct arcan_shmif_cont* cont, int chid, struct arcan_event* ev, void* tag)
{
	struct directory_meta* cbt = tag;

/* the only concerns here are BCHUNK matching our directory IDs */
	if (ev->ext.kind == EVENT_EXTERNAL_BCHUNKSTATE){
/* sweep the directory, and when found: */
		if (!isdigit(ev->ext.bchunk.extensions[0])){
			a12int_trace(A12_TRACE_DIRECTORY, "event=bchunkstate:error=invalid_id");
			return;
		}

		uint16_t extid = (uint16_t)
			strtoul((char*)ev->ext.bchunk.extensions, NULL, 10);

		struct appl_meta* meta = cbt->dir;
		while (meta){
			if (extid == meta->identifier){
/* we have the applname, and the Kpub of the other end -
 * use that to determine if we have any state block to send first */
				int fd = a12_access_state(cbt->S, meta->applname, "r", 0);
				if (-1 != fd){
					a12int_trace(A12_TRACE_DIRECTORY,
						"event=bchunkstate:send_state=%s", meta->applname);
					a12_enqueue_bstream(
						cbt->S, fd, A12_BTYPE_STATE, meta->identifier, false, 0);
					close(fd);
				}

				a12int_trace(A12_TRACE_DIRECTORY,
					"event=bchunkstate:send=%s", meta->applname);
				a12_enqueue_blob(cbt->S, meta->buf, meta->buf_sz, meta->identifier);
				return;
			}
			meta = meta->next;
		}
		a12int_trace(A12_TRACE_DIRECTORY,
			"event=bchunkstate:error=no_match:id=%"PRIu16, extid);
	}
	else
		a12int_trace(A12_TRACE_DIRECTORY,
			"event=%s", arcan_shmif_eventstr(ev, NULL, 0));
}

/* this will just keep / cache the built .tars in memory, the startup times
 * will still be long and there is no detection when / if to rebuild or when
 * the state has changed - a better server would use sqlite and some basic
 * signalling. */
void anet_directory_srv_rescan(struct anet_dirsrv_opts* opts)
{
	opts->dir_count = scan_appdir(dup(opts->basedir), &opts->dir);
}

void anet_directory_srv(
	struct a12_state* S, struct anet_dirsrv_opts opts, int fdin, int fdout)
{
	struct directory_meta cbt = {
		.dir = &opts.dir,
		.S = S
	};

	if (!opts.dir_count){
		a12int_trace(A12_TRACE_DIRECTORY, "shutdown:reason=no_valid_appls");
		return;
	}

	a12int_set_directory(S, &opts.dir);
	a12_set_bhandler(S, srv_bevent, &cbt);
	anet_directory_ioloop(S, &cbt, fdin, fdout, -1, on_srv_event, NULL, NULL);
}

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

static struct appl_meta* find_identifier(struct appl_meta* base, unsigned id)
{
	while (base){
		if (base->identifier == id)
			return base;
		base = base->next;
	}
	return NULL;
}

static struct a12_bhandler_res srv_bevent(
	struct a12_state* S, struct a12_bhandler_meta M, void* tag)
{
	struct a12_bhandler_res res = {
		.fd = -1,
		.flag = A12_BHANDLER_DONTWANT
	};

	struct directory_meta* cbt = tag;
	struct appl_meta* meta = find_identifier(cbt->dir, M.identifier);
	if (!meta)
		return res;

/* this is not robust or complete - the previous a12_access_state for the ID
 * should really only be swapped when we have a complete transfer - one option
 * is to first store under a temporary id, then on completion access and copy */
	switch (M.state){
	case A12_BHANDLER_COMPLETED:
		a12int_trace(
			A12_TRACE_DIRECTORY, "kind=status:completed:identifier=%"PRIu16, M.identifier);
	break;
	case A12_BHANDLER_CANCELLED:
/* 1. truncate the existing state store for the slot */
	break;
	case A12_BHANDLER_INITIALIZE:
/* 1. check that the identifier is valid. */
/* 2. reserve the state slot - add suffix if it is debug */
/* 3. setup the result structure. */
		if (M.type == A12_BTYPE_STATE){
			res.fd = a12_access_state(S, meta->applname, "w+", M.known_size);
			ftruncate(res.fd, 0);
		}
		else if (M.type == A12_BTYPE_CRASHDUMP){
			char name[sizeof(meta->applname) + sizeof(".dump")];
			snprintf(name, sizeof(name), "%s.dump", meta->applname);
			res.fd = a12_access_state(S, name, "w+", M.known_size);
		}
	break;
	}

	if (-1 != res.fd)
		res.flag = A12_BHANDLER_NEWFD;
	return res;
}
