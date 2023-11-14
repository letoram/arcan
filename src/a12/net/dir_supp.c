#include <arcan_shmif.h>
#include <arcan_shmif_server.h>

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
#include <fts.h>
#include <dirent.h>
#include <fcntl.h>
#include <poll.h>

void anet_directory_ioloop(struct ioloop_shared* I)
{
	int errmask = POLLERR | POLLHUP;
	struct pollfd fds[5] =
	{
		{.fd = I->userfd, .events = POLLIN | errmask},
		{.fd = I->fdin, .events = POLLIN | errmask},
		{.fd = -1, .events = POLLOUT | errmask},
		{.fd = -1, .events = POLLIN | errmask},
		{.fd = -1, .events = POLLIN | errmask},
	};

	uint8_t inbuf[9000];
	uint8_t* outbuf = NULL;
	uint64_t ts = 0;

	fcntl(I->fdin, F_SETFD, FD_CLOEXEC);
	fcntl(I->fdout, F_SETFD, FD_CLOEXEC);

	size_t outbuf_sz = a12_flush(I->S, &outbuf, A12_FLUSH_ALL);

	if (outbuf_sz)
		fds[2].fd = I->fdout;

/* regular simple processing loop, wait for DIRECTORY-LIST command */
	while (a12_ok(I->S) && -1 != poll(fds, 5, -1)){
		if ((fds[0].revents | fds[1].revents | fds[2].revents | fds[3].revents) & errmask){
			if ((fds[0].revents & errmask) && I->on_userfd){
				I->on_userfd(I, false);
			}
			if (I->shutdown)
				break;
		}

/* this might add or remove a shmif to our tracking set */
		if (fds[0].revents & POLLIN){
			I->on_userfd(I, true);
		}

		if (fds[4].revents){
			I->on_shmif(I);
		}

		if (fds[3].revents & POLLIN){
			uint8_t buf[8832];
			int fd = a12_tunnel_descriptor(I->S, 1);
			ssize_t sz = read(fd, buf, sizeof(buf));
			a12_write_tunnel(I->S, 1, buf, (size_t) sz);
		}

		if ((fds[2].revents & POLLOUT) && outbuf_sz){
			ssize_t nw = write(I->fdout, outbuf, outbuf_sz);
			if (nw > 0){
				outbuf += nw;
				outbuf_sz -= nw;
			}
		}

		if (fds[1].revents & POLLIN){
			ssize_t nr = recv(I->fdin, inbuf, 9000, 0);

			if (-1 == nr && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR){
				a12int_trace(A12_TRACE_DIRECTORY, "shutdown:reason=rw_error");
				break;
			}
			else if (0 == nr){
				a12int_trace(A12_TRACE_DIRECTORY, "shutdown:reason=closed");
				break;
			}
			a12_unpack(I->S, inbuf, nr, I, I->on_event);

/* check if there has been a change to the directory state after each unpack */
			uint64_t new_ts;
			if (I->on_directory){
				struct appl_meta* dir = a12int_get_directory(I->S, &new_ts);
				if (new_ts != ts){
					ts = new_ts;
					if (!I->on_directory(I, dir))
						break;
				}
			}
		}

		if (!outbuf_sz){
			outbuf_sz = a12_flush(I->S, &outbuf, A12_FLUSH_ALL);
			if (!outbuf_sz && I->shutdown)
				break;
		}

		fds[0].revents = fds[1].revents = fds[2].revents = fds[3].revents = 0;
		fds[4].revents = 0;
		fds[2].fd = outbuf_sz ? I->fdout : -1;
		fds[0].fd = I->userfd;
		fds[3].fd = a12_tunnel_descriptor(I->S, 1);
		fds[4].fd = I->shmif.addr ? I->shmif.epipe : -1;
	}
}

FILE* file_to_membuf(FILE* applin, char** out, size_t* out_sz)
{
	if (!applin)
		return NULL;

	FILE* applbuf = open_memstream(out, out_sz);
	if (!applbuf){
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

	if (!ok){
		fclose(applbuf);
		return NULL;
	}

/* actually keep both in order to allow appending elsewhere */
	fflush(applbuf);
	return applbuf;
}

static int comp_alpha(const FTSENT** a, const FTSENT** b)
{
	return strcmp((*a)->fts_name, (*b)->fts_name);
}

static bool ensure_path(int cdir, const char* path)
{
	char* wrk = strdup(path);
	char* tmp = wrk;
	bool finished = false;
	struct stat s;

	while(1){
		tmp += strspn(tmp, "/");
		tmp += strcspn(tmp, "/");

		if (!*tmp)
			finished = true;
		*tmp = '\0';

		mkdirat(cdir, wrk, S_IRWXU);

		if (finished)
			break;

		*tmp = '/';
	}

	free(wrk);
	return finished;
}

bool extract_appl_pkg(FILE* fin, int cdir, const char* basename, const char** msg)
{
	bool in_file = false;
	fseek(fin, 0, SEEK_SET);

/* permission header, inject as > .manifest. the main point with this file is
 * to communicate frameserver needs; terminal? decode against devices? encode?
 * net? all of these have different security parameters in the context of lwa
 * versus other ones. */
	char line[1024];
	char* lastpath = NULL;
	if (!fgets(line, 1024, fin)){
		return false;
	}
	struct arg_arr* args = arg_unpack(line);
	if (!args){
		a12int_trace(A12_TRACE_DIRECTORY, "malformed_appl_fmt:missing=manifest");
		*msg = "broken manifest";
		return false;
	}

	mkdirat(cdir, basename, S_IRWXU);
	int bdir = openat(cdir, basename, O_DIRECTORY);
	if (-1 == bdir){
		a12int_trace(A12_TRACE_DIRECTORY, "permission=open_basedir");
		*msg = "couldn't open basedir";
		return false;
	}

	int fd = openat(bdir, ".manifest", O_CREAT | O_TRUNC | O_RDWR, 0600);
	arg_cleanup(args);
	if (-1 == fd){
		a12int_trace(A12_TRACE_ALLOC, "failed_open_manifest");
		*msg = "couldn't create .manifest";
		return false;
	}
	FILE* fout = fdopen(fd, "w");
	fputs(line, fout);
	fclose(fout);

	while(!feof(fin)){
		if (!fgets(line, 1024, fin)){
			break;
		}

		size_t len = strlen(line);
		if (!len){
			a12int_trace(A12_TRACE_DIRECTORY, "malformed_appl:invalid=entry");
			*msg = "invalid file entry header";
			break;
		}

		line[len-1] = '\0';
		struct arg_arr* args = arg_unpack(line);
		if (!args){
			break;
		}

/* need path, name and size */
		const char* path;
		const char* name;
		const char* size;
		in_file = true;

		if (!arg_lookup(args, "path", 0, &path) || !path){
			a12int_trace(A12_TRACE_DIRECTORY, "malformed_appl_fmt:missing=path");
			*msg = "broken path entry in file header";
			break;
		}

		if (!arg_lookup(args, "name", 0, &name) || !name){
			a12int_trace(A12_TRACE_DIRECTORY, "malformed_appl_fmt:missing=name");
			*msg = "broken name entry in file header";
			break;
		}

		if (!arg_lookup(args, "size", 0, &size) || !size){
			a12int_trace(A12_TRACE_DIRECTORY, "malformed_appl_fmt:missing=size");
			*msg = "missing size in file header";
			break;
		}

		char* errp = NULL;
		size_t ntc = strtoul(size, &errp, 10);
		if (errp && *errp != '\0'){
			a12int_trace(A12_TRACE_DIRECTORY, "malformed_appl_fmt:invalid=size");
			*msg = "invalid size entry in file header";
			break;
		}

		size_t plen = strlen(path);
/* file comes sorted on path and name, only mkdir chain on new */
		if ((!lastpath || strcmp(path, lastpath)) != 0 && plen > 0){
			free(lastpath);
			lastpath = strdup(path);
			ensure_path(bdir, path);
		}

/* the other option to extracting like this is parsing into an index of offsets
 * and using that with resource resolving calls inside of arcan. the
 * precondition to this is the server-side 'shared resource' loading which
 * ensures that we have virtualisation of all key api calls. */
		char* fn;
		if (!plen)
			fn = strdup(name);
		else if (-1 == asprintf(&fn, "%s/%s", path, name)){
			fn = NULL;
		}

		if (!fn){
			a12int_trace(A12_TRACE_ALLOC, "failed_asprintf_path");
			*msg = "couldn't allocate path";
			break;
		}

/* might want to check for duplicates here, fn shouldn't exist and if it does
 * it is a sign that there are collisions in the file itself. */
		int fd = openat(bdir, fn, O_CREAT | O_TRUNC | O_RDWR, S_IRUSR | S_IWUSR);
		if (-1 == fd){
			a12int_trace(A12_TRACE_ALLOC, "failed_open_creat=%s", fn);
			*msg = "couldn't create file";
			break;
		}
		free(fn);
		fout = fdopen(fd, "w");

		while (ntc){
			char buf[4096];
			size_t nr = fread(buf, 1, 4096 > ntc ? ntc : 4096, fin);
			if (!nr){
				break;
			}
			fwrite(buf, 1, nr, fout);
			ntc -= nr;
		}

		if (ntc){
			a12int_trace(A12_TRACE_DIRECTORY,
				"malformed_appl:invalid=size:name=%s", fn);
			*msg = "truncated / corrupted package";
			break;
		}

		fclose(fout);
		in_file = false;
	}

	close(bdir);
	return feof(fin) && !in_file;
}

bool build_appl_pkg(const char* name, struct appl_meta* dst, int cdir)
{
	FILE* fpek = NULL;
	FTS* fts = NULL;

	int olddir = open(".", O_DIRECTORY);

	char* path[] = {".", NULL};
	fchdir(cdir);
	chdir(name);

	size_t buf_sz;
	if (!(fpek = open_memstream(&dst->buf, &buf_sz)))
		goto err;

	if (!(fts = fts_open(path, FTS_PHYSICAL, comp_alpha)))
		goto err;

/* for extended permissions -- net,frameserver,... the .manifest file needs to
 * be present, follow the regular arg_arr pack/unpack format and specify which
 * ones it needs. */
	FILE* header = fopen(".manifest", "r");
	if (header){
		char buf[256];
		if (!fgets(buf, 256, header)){
			a12int_trace(A12_TRACE_DIRECTORY, "build_appl:error=cant_read_manifest");
			fclose(header);
			goto err;
		}

		struct arg_arr* args = arg_unpack(buf);
		if (!args){
			a12int_trace(A12_TRACE_DIRECTORY, "build_appl:error=cant_parse_manifest");
			fclose(header);
			goto err;
		}

		fprintf(fpek, "version=1:permission=restricted\n");

		arg_cleanup(args);
		fclose(header);
	}
	else
		fprintf(fpek, "version=1:permission=restricted\n");

/* walk and get list of files, lexicographic sort, filter out links,
 * cycles, dot files */
	for (FTSENT* cur = fts_read(fts); cur; cur = fts_read(fts)){
/* possibly allow-list files here, at least make sure it's valid UTF8 as well
 * as not any reserved (/, ., :, \t, \n) symbols */
		if (cur->fts_name[0] == '.'){
			continue;
		}

		if (cur->fts_info != FTS_F){
			continue;
		}

		FILE* fin = fopen(cur->fts_name, "r");
		if (!fin){
			a12int_trace(A12_TRACE_DIRECTORY,
				"build_app:error=cant_open:name=%s:path=%s", cur->fts_name, cur->fts_path);
			goto err;
		}

	/* read all of fin into a memory buffer then */
		char* fbuf;
		size_t fbuf_sz;
		FILE* fbuf_f = file_to_membuf(fin, &fbuf, &fbuf_sz);
		if (!fbuf_f){
			fclose(fin);
			goto err;
		}
		fclose(fin);
		fclose(fbuf_f);
		cur->fts_path[cur->fts_pathlen - cur->fts_namelen - 1] = '\0';
		fprintf(fpek,
				"path=%s:name=%s:size=%zu\n",
				strcmp(cur->fts_path, ".") == 0 ? "" :
				&cur->fts_path[2],
				cur->fts_name, fbuf_sz
		);
		cur->fts_path[cur->fts_pathlen - cur->fts_namelen - 1] = '/';
		fflush(fpek);
		fwrite(fbuf, fbuf_sz, 1, fpek);
		free(fbuf);
	}

	fts_close(fts);
	fclose(fpek);

	dst->buf_sz = buf_sz;
	blake3_hasher hash;
	blake3_hasher_init(&hash);
	blake3_hasher_update(&hash, dst->buf, dst->buf_sz);
	blake3_hasher_finalize(&hash, (uint8_t*)dst->hash, 4);

	snprintf(dst->appl.name, COUNT_OF(dst->appl.name), "%s", name);

	dst->next = malloc(sizeof(struct appl_meta));
	*(dst->next) = (struct appl_meta){0};

	fchdir(olddir);
	close(olddir);
	return true;

err:
	if (fpek)
		fclose(fpek);
	if (fts)
		fts_close(fts);
	free(dst->buf);
	dst->buf = NULL;
	fchdir(olddir);
	close(olddir);
	return false;
}
