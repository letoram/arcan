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
#include <pthread.h>
#include <fcntl.h>

#include "../a12.h"
#include "../a12_int.h"
#include "anet_helper.h"
#include "a12_helper.h"
#include "directory.h"
#include "../../engine/arcan_mem.h"

#include <sys/types.h>
#include <sys/file.h>
#include <sys/wait.h>
#include "../external/fts.h"
#include "../external/x25519.h"
#include "monocypher-ed25519.h"

#include <dirent.h>
#include <fcntl.h>
#include <poll.h>

struct tunnel_meta {
	struct ioloop_shared* I;
	uint8_t tunid;
};
static struct a12_state trace_state = {.tracetag = "worker"};

#define TRACE(...) do { \
	if (!(a12_trace_targets & A12_TRACE_DIRECTORY))\
		break;\
	struct a12_state* S = &trace_state;\
		a12int_trace(A12_TRACE_DIRECTORY, __VA_ARGS__);\
	} while (0);

static void* tunnel_thread(void* tag)
{
	struct tunnel_meta* meta = tag;
	struct a12_state* S = meta->I->S;
	char* buf = malloc(8832);
	int fd;

	for(;;){
		bool tun_ok;
		pthread_mutex_lock(&meta->I->lock);
			fd = a12_tunnel_descriptor(S, meta->tunid, &tun_ok);
		pthread_mutex_unlock(&meta->I->lock);

		if (!tun_ok){
			break;
		}

		ssize_t nr = read(fd, buf, 8832);
		if (nr == 0 || (nr == -1 && (errno != EINTR && errno != EAGAIN)))
			break;

		else if (nr > 0){
			pthread_mutex_lock(&meta->I->lock);
				a12int_trace(A12_TRACE_DIRECTORY,
					"tunnel:%"PRIu8":source=%d:bytes=%zu", meta->tunid, fd, nr);
				a12_write_tunnel(S, meta->tunid, (unsigned char*) buf, nr);
			pthread_mutex_unlock(&meta->I->lock);
			write(meta->I->wakeup, &meta->tunid, 1);
		}
	}

	free(buf);
	pthread_mutex_lock(&meta->I->lock);
		a12_drop_tunnel(S, meta->tunid);
	pthread_mutex_unlock(&meta->I->lock);

	close(fd);
	free(meta);
	return NULL;
}

void anet_directory_tunnel_thread(struct ioloop_shared* S, uint8_t chid)
{
	pthread_t pth;
	pthread_attr_t pthattr;
	pthread_attr_init(&pthattr);
	pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
	struct tunnel_meta* M = malloc(sizeof(struct tunnel_meta));
	M->I = S;
	M->tunid = chid;
	pthread_create(&pth, &pthattr, tunnel_thread, M);
}

static struct ioloop_shared* current_loop;
struct ioloop_shared* anet_directory_ioloop_current()
{
	return current_loop;
}

void anet_directory_ioloop(struct ioloop_shared* I)
{
	int errmask = POLLERR | POLLHUP;
	bool tun_ok = true;
	int sigpipe[2] = {-1, -1};
	pipe(sigpipe);
	current_loop = I;

	struct pollfd fds[] =
	{
		{.fd = I->userfd, .events = POLLIN | errmask},
		{.fd = I->fdin, .events = POLLIN | errmask},
		{.fd = -1, .events = POLLOUT | errmask},
		{.fd = sigpipe[0], .events = POLLIN | errmask},
		{.fd = -1, .events = POLLIN | errmask},
		{.fd = I->userfd2, .events = POLLIN | errmask},
	};

	I->wakeup = sigpipe[1];
	struct a12_state* S = I->S;

	uint8_t inbuf[9000];
	uint8_t* outbuf = NULL;
	uint64_t ts = 0;

	fcntl(I->fdin, F_SETFD, FD_CLOEXEC);
	fcntl(I->fdout, F_SETFD, FD_CLOEXEC);

	size_t outbuf_sz = a12_flush(I->S, &outbuf, A12_FLUSH_ALL);

	if (outbuf_sz)
		fds[2].fd = I->fdout;

/* regular simple processing loop, wait for DIRECTORY-LIST command */
	while (!I->shutdown && a12_ok(I->S) && -1 != poll(fds, COUNT_OF(fds), -1)){
		pthread_mutex_lock(&I->lock);

/* this might add or remove a shmif to our tracking set */
		if (fds[0].revents){
			I->on_userfd(I, !(fds[0].revents & errmask));
		}
		if (fds[5].revents & POLLIN){
			I->on_userfd2(I, !(fds[5].revents & errmask));
		}
		if (fds[4].revents){
			I->on_shmif(I, !(fds[4].revents & errmask));
		}

/* if we've received wakeup signals, just flush them, data is already queued
 * via a12_write_tunnel calls */
		if (fds[3].revents){
			uint8_t buf[1024];
			read(fds[3].fd, buf, 1024);
			a12int_trace(A12_TRACE_DIRECTORY, "tunnel_wake");
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

/* check if there has been a change to the directory state after each unpack,
 * while not an expensive operation it could still be tracked in a12_ and have
 * an accessor. */
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

/* finally make sure to flush out whatever the state machine has queued up */
		if (!outbuf_sz){
			outbuf_sz = a12_flush(I->S, &outbuf, A12_FLUSH_ALL);
			if (!outbuf_sz && I->shutdown)
				break;
		}

		fds[0].revents = fds[1].revents = fds[2].revents = fds[3].revents = 0;
		fds[4].revents = fds[5].revents = 0;

		fds[2].fd = outbuf_sz ? I->fdout : -1;
		fds[0].fd = I->userfd;
		fds[4].fd = I->shmif.addr ? I->shmif.epipe : -1;
		fds[5].fd = I->userfd2;

		pthread_mutex_unlock(&I->lock);
	}

	close(I->wakeup);
	close(fds[3].fd);
	current_loop = NULL;
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

char* verify_appl_pkg(
	char* buf, size_t buf_sz,
	uint8_t insig_pk[static SIG_PUBK_SZ], uint8_t outsig_pk[static SIG_PUBK_SZ],
	const char** errmsg)
{
	uint8_t nullsig[SIG_PUBK_SZ] = {0};

/* first line is packet header */
	size_t lineend = 0;
	for (; lineend < buf_sz; lineend++)
		if (buf[lineend] == '\n')
			break;

	if (buf[lineend] != '\n'){
		*errmsg = "bad/missing header";
		return NULL;
	}

/* shmif arg_unpack, it expects a terminated string so dig for that */
	buf[lineend] = '\0';
	struct arg_arr* args = arg_unpack(buf);
	buf[lineend] = '\n';
	if (!args){
		*errmsg = "malformed header";
		return NULL;
	}

/* provide the expected signing public key */

/* missing:
 * is a signing identity expected?
 *    1.
 *       check that the signed hash value matches the signature and the
 *       signature field exists.
 *
 *    2. recalculate hash and compare against signed hash.
 *       there should be a signature for the header itself, and a hash for
 *       the remaining package - both need to check out.
 *
 *    3.
 *       check if the updated package has a new base key (rotation push on
 *       suspected compromise).
 *
 *  open question, having a recovery key that isn't allowed to mutate? need
 *  better references on such schemes.
 */
	if (memcmp(insig_pk, nullsig, SIG_PUBK_SZ) != 0){
		*errmsg = "signature-handling missing";
		return NULL;
	}

	const char* outname = NULL;
	if (arg_lookup(args, "name", 0, &outname) && outname){
		if (!isalpha(outname[0])){
				*errmsg = "malformed appl-name";
				goto clean_end;
		}
		for (size_t i = 1; outname[i]; i++){
			if (!isalnum(outname[i]) && outname[i] != '_'){
				*errmsg = "malformed appl-name";
				goto clean_end;
			}
		}

		char* res = strdup(outname);
		arg_cleanup(args);
		*errmsg = "";
		return res;
	}

clean_end:
	arg_cleanup(args);
	return NULL;
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
		*msg = "broken manifest";
		return false;
	}

	mkdirat(cdir, basename, S_IRWXU);
	int bdir = openat(cdir, basename, O_DIRECTORY);
	if (-1 == bdir){
		*msg = "couldn't open basedir";
		return false;
	}

	int fd = openat(bdir, ".manifest", O_CREAT | O_TRUNC | O_RDWR, 0600);
	arg_cleanup(args);
	if (-1 == fd){
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
			*msg = "broken path entry in file header";
			break;
		}

		if (!arg_lookup(args, "name", 0, &name) || !name){
			*msg = "broken name entry in file header";
			break;
		}

		if (!arg_lookup(args, "size", 0, &size) || !size){
			*msg = "missing size in file header";
			break;
		}

		char* errp = NULL;
		size_t ntc = strtoul(size, &errp, 10);
		if (errp && *errp != '\0'){
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
			*msg = "couldn't allocate path";
			break;
		}

/* might want to check for duplicates here, fn shouldn't exist and if it does
 * it is a sign that there are collisions in the file itself. */
		int fd = openat(bdir, fn, O_CREAT | O_TRUNC | O_RDWR, S_IRUSR | S_IWUSR);
		if (-1 == fd){
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
			*msg = "truncated / corrupted package";
			break;
		}

		fclose(fout);
		in_file = false;
	}

	close(bdir);
	return feof(fin) && !in_file;
}

/*
 * A big downside here is that due to traversal the appl might be different for
 * each build even if the contents hasn't actually changed. This is due to FTS
 * traversal. An option is to first FTS into a list, sort and then walk the
 * list based on that.
 */
bool build_appl_pkg(const char* name,
	struct appl_meta* dst, int cdir, const char* signtag)
{
	char* buf = NULL;
	size_t buf_sz = 0;
	FILE* fdata = NULL;

/*
 * construction happens in several steps:
 *
 *  read / unpack manifest, remove any entry for 'hash', 'ksig' and 'sig'.
 *  copy each file into data and continuously checksum.
 *  add checksum as 'hash' to manifest arg_arr.
 *  serialize 'hash' into buffer.
 *  calculate signature for hash buffer. [local authentication]
 *  copy keysig+signature+buffer+data into dst->buf, dst->sz. [local verification]
 *  calculate hash for dst->buf, dst->sz. [transfer]
 */

/*
 * A fair optimization here would leverage the merkle tree construction inside
 * blake3 to avoid calculating checksum twice (the btransfer itself needs a
 * checksum).
 */
	FTS* fts = NULL;

	int olddir = open(".", O_DIRECTORY);

	char* path[] = {".", NULL};
	fchdir(cdir);
	chdir(name);

	if (!(fdata = open_memstream(&buf, &buf_sz)))
		goto err;

	if (!(fts = afts_open(path, FTS_PHYSICAL, comp_alpha)))
		goto err;

	uint8_t pubk[32];
	uint8_t privk[64];
	if (signtag){
		if (!a12helper_keystore_get_sigkey(signtag, pubk, privk)){
			fprintf(stderr, "build_appl:couldn't open keystore-sign tag %s", signtag);
			goto err;
		}
	}

/* For extended permissions -- net,frameserver,... the .manifest file needs to
 * be present, follow the regular arg_arr pack/unpack format and specify which
 * ones it needs. */
	int fd = open(".manifest", O_RDONLY);
	struct arg_arr* header = NULL;

	if (-1 != fd){
		struct stat sb;
		if (-1 == fstat(fd, &sb)){
			fprintf(stderr, "build_appl:can't read .manifest\n");
			goto err;
		}
		char* buf = malloc(sb.st_size);
		FILE* fpek = fdopen(fd, "r");
		fread(buf, sb.st_size, 1, fpek);
		header = arg_unpack(buf);
		fclose(fpek);
		free(buf);
	}
	else {
		header = arg_unpack("version=1:permission=restricted\n");
	}

	if (!header){
		fprintf(stderr, "build_appl:malformed .manifest\n");
		goto err;
	}

/* we are recalculating these and prepending later */
	arg_remove(header, "sign");
	arg_remove(header, "ksig");
	arg_remove(header, "hash");

/* walk and get list of files, lexicographic sort, filter out links,
 * cycles, dot files */
	for (FTSENT* cur = afts_read(fts); cur; cur = afts_read(fts)){
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
			fprintf(stderr,
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
		fprintf(fdata,
				"path=%s:name=%s:size=%zu\n",
				strcmp(cur->fts_path, ".") == 0 ? "" :
				&cur->fts_path[2],
				cur->fts_name, fbuf_sz
		);

		cur->fts_path[cur->fts_pathlen - cur->fts_namelen - 1] = '/';
		fflush(fdata);
		fwrite(fbuf, fbuf_sz, 1, fdata);
		free(fbuf);
	}

	afts_close(fts);
	fclose(fdata);

/* calculate hash over all the data */
	uint8_t hash_data[16];
	blake3_hasher hash;
	blake3_hasher_init(&hash);
	blake3_hasher_update(&hash, buf, buf_sz);
	blake3_hasher_finalize(&hash, hash_data, 16);

/* convert that to b64 and add to header */
	unsigned char* pub_b64 = a12helper_tob64(hash_data, 16, &(size_t){0});
	arg_add(NULL, &header, "hash", (char*) pub_b64, false);
	free(pub_b64);

	char* out_header = arg_serialize(header);
	FILE* fpkg = open_memstream(&dst->buf, &dst->buf_sz);

/* if we are set to sign, first hash the serialized header (which includes
 * datablock hash), create the hash, convert pubk and signature and add to a
 * prepend buffer */
	if (signtag){
		blake3_hasher_init(&hash);
		blake3_hasher_update(&hash, out_header, strlen(out_header));
		blake3_hasher_finalize(&hash, hash_data, 16);
		uint8_t sign[64];
		crypto_ed25519_sign(sign, privk, hash_data, 16);
		unsigned char* pubk_b64 = a12helper_tob64(pubk, 32, &(size_t){0});
		unsigned char* sign_b64 = a12helper_tob64(sign, 64, &(size_t){0});
		fprintf(fpkg, "ksig=%s:sign=%s:%s\n", pubk_b64, sign_b64, out_header);
		free(pubk_b64);
		free(sign_b64);
	}
	else
		fprintf(fpkg, "%s\n", out_header);

	free(out_header);
	arg_cleanup(header);

	fwrite(buf, buf_sz, 1, fpkg);
	fflush(fpkg);
	fclose(fpkg);

/* now calculate hash for the entire blob and add to the appl_meta, collisions
 * are fine / it is short just as a quick 'skip download' as the rest are in
 * packet header that should be verified and extracted quickly. */
	blake3_hasher_init(&hash);
	blake3_hasher_update(&hash, dst->buf, dst->buf_sz);
	blake3_hasher_finalize(&hash, (uint8_t*)dst->hash, 4);

	snprintf(dst->appl.name, COUNT_OF(dst->appl.name), "%s", name);

/* keep an empty entry at the end to terminate the list */
	dst->next = malloc(sizeof(struct appl_meta));
	*(dst->next) = (struct appl_meta){0};

	fchdir(olddir);
	close(olddir);
	return true;

err:
	if (fdata)
		fclose(fdata);
	if (fts)
		afts_close(fts);
	free(dst->buf);
	dst->buf = NULL;
	fchdir(olddir);
	close(olddir);
	return false;
}

void anet_directory_random_ident(char* dst, size_t nb)
{
	uint8_t rnd[nb];
	arcan_random(rnd, nb);
	for (size_t i = 0; i < nb; i++){
		dst[i] = 'a' + (rnd[i] % 26);
	}
}

bool anet_directory_merge_multipart(
	struct arcan_event* ev, struct arg_arr** outarg, char** outbuf, int* err)
{
	static _Thread_local size_t multipart_sz;
	static _Thread_local size_t multipart_cnt;
	static _Thread_local char* multipart_buf;

/* free TLS */
	if (!ev){
		if (multipart_sz){
			multipart_sz = 0;
			multipart_cnt = 0;
			free(multipart_buf);
			multipart_buf = NULL;
		}
		return true;
	}

	char* src;
	bool multipart;
	size_t cap;

/* pick source arguments based on category as the fields are different */
	if (ev->category == EVENT_EXTERNAL){
		multipart = ev->ext.message.multipart;
		src = (char*) ev->ext.message.data;
		cap = COUNT_OF(ev->ext.message.data);
	}
	else if (ev->category == EVENT_TARGET){
		src = ev->tgt.message;
		multipart = ev->tgt.ioevs[0].iv;
		cap = COUNT_OF(ev->tgt.message);
	}
	else {
		*err = MULTIPART_BAD_EVENT;
		return false;
	}

/* short path, single-message */
	if (!multipart && !multipart_sz){
		if (outarg){
			*outarg = arg_unpack(src);
			if (!*outarg){
				multipart_cnt = 0;
				*err = MULTIPART_BAD_FMT;
				return false;
			}
		}
		else
			*outbuf = strdup(src);

		multipart_cnt = 0;
		return true;
	}

/* grow or alloc?, srv is invalid unless it ends at an aligned UTF-8 sequence
 * and is \0 terminated. arg_unpack handles UTF-8 validation. */
	size_t len = strnlen(src, cap);

	if (len == cap){
		multipart_cnt = 0;
		*err = MULTIPART_BAD_MSG;
		return false;
	}

	if (len + multipart_cnt >= multipart_sz){
		char* buf = malloc(multipart_sz + 4096);
		if (!buf){
			*err = MULTIPART_OOM;
			return false;
		}

		if (multipart_sz){
			memcpy(buf, multipart_buf, multipart_cnt);
			free(multipart_buf);
		}

		multipart_buf = buf;
		multipart_sz += 4096;
	}

	memcpy(&multipart_buf[multipart_cnt], src, len);
	multipart_cnt += len;
	multipart_buf[multipart_cnt] = '\0';

/* buffer more? */
	if (multipart){
		*err = 0;
		return false;
	}

	*outarg = arg_unpack((const char*) multipart_buf);
	multipart_cnt = 0;

	if (!*outarg){
		*err = MULTIPART_BAD_FMT;
		return false;
	}

	*err = 0;
	return true;
}

bool dir_block_synch_request(
	struct arcan_shmif_cont* C,
	struct arcan_event ev, struct evqueue_entry* reply,
	int cat_ok, int kind_ok, int cat_fail, int kind_fail)
{
	*reply = (struct evqueue_entry){0};

	if (ev.ext.kind)
		arcan_shmif_enqueue(C, &ev);

	while (arcan_shmif_wait(C, &ev)){

/* exploit the fact that kind is at the same offset regardless of union */
		if (
			(cat_ok == ev.category && ev.tgt.kind == kind_ok) ||
			(cat_fail == ev.category && ev.tgt.kind == kind_fail)){
			reply->ev = ev;
			reply->next = NULL;
			return true;
		}

/* need to dup to queue descriptor-events as they are closed() on next call
 * into arcan_shmif_xxx. This assumes we can't get queued enough fdevents that
 * we would saturate our fd allocation */
		if (arcan_shmif_descrevent(&ev)){
			ev.tgt.ioevs[0].iv = arcan_shmif_dupfd(ev.tgt.ioevs[0].iv, -1, true);
		}

		reply->ev = ev;
		reply->next = malloc(sizeof(struct evqueue_entry));
		*(reply->next) = (struct evqueue_entry){0};
		reply = reply->next;
	}

	return false;
}

bool dir_request_resource(
	struct arcan_shmif_cont* C, size_t ns, const char* id, int mode,
	struct evqueue_entry* pending)
{
	struct arcan_event ev = (struct arcan_event){
		.ext.kind = EVENT_EXTERNAL_BCHUNKSTATE,
		.ext.bchunk = {
			.input = mode == BREQ_LOAD,
			.ns = ns
		}
	};

	int kind =
		mode == BREQ_STORE ?
			TARGET_COMMAND_BCHUNK_OUT : TARGET_COMMAND_BCHUNK_IN;

	snprintf(
		(char*)ev.ext.bchunk.extensions, COUNT_OF(ev.ext.bchunk.extensions), "%s", id);

	TRACE(
		"request_parent:ns=%zu:kind=%d:%s", ns, kind, ev.ext.bchunk.extensions);

	return
		dir_block_synch_request(
			C, ev, pending,
			EVENT_TARGET, kind,
			EVENT_TARGET, TARGET_COMMAND_REQFAIL);
}

struct appl_meta* dir_unpack_index(int fd)
{
	TRACE("new_index");
	FILE* fpek = fdopen(fd, "r");
	if (!fpek){
		TRACE("error=einval_fd");
		return NULL;
	}

	struct appl_meta* first = NULL;
	struct appl_meta** cur = &first;

	while (!feof(fpek)){
		char line[256];
		size_t n = 0;

/* the .index is trusted, but to ease troubleshooting there is some light basic
 * validation to help if the format is updated / extended */
		char* res = fgets(line, sizeof(line), fpek);
		if (!res)
			continue;

		n++;
		struct arg_arr* entry = arg_unpack(line);
		if (!entry){
			TRACE("error=malformed_entry:index=%zu", n);
			continue;
		}

		const char* kind;
		if (!arg_lookup(entry, "kind", 0, &kind) || !kind){
			TRACE("error=malformed_entry:index=%zu", n);
			arg_cleanup(entry);
			continue;
		}

/* We re-use the same a12int_ interface for the directory entries for marking a
 * source or directory entry, just with a different type identifier so that the
 * implementation knows to package the update correctly. Actual integrity of the
 * directory is guaranteed by the parent process. Avoiding collisions and so on
 * is done in the parent, as is enforcing permissions. */
		const char* name = NULL;
		arg_lookup(entry, "name", 0, &name);

		*cur = malloc(sizeof(struct appl_meta));
		**cur = (struct appl_meta){0};
		snprintf((*cur)->appl.name, 18, "%s", name);

		const char* tmp;
		if (arg_lookup(entry, "categories", 0, &tmp) && tmp)
			(*cur)->categories = (uint16_t) strtoul(tmp, NULL, 10);

		if (arg_lookup(entry, "size", 0, &tmp) && tmp)
			(*cur)->buf_sz = (uint32_t) strtoul(tmp, NULL, 10);

		if (arg_lookup(entry, "id", 0, &tmp) && tmp)
			(*cur)->identifier = (uint16_t) strtoul(tmp, NULL, 10);

		if (arg_lookup(entry, "hash", 0, &tmp) && tmp){
			union {
				uint32_t val;
				uint8_t u8[4];
			} dst;

			dst.val = strtoul(tmp, NULL, 16);
			memcpy((*cur)->hash, dst.u8, 4);
		}

		if (arg_lookup(entry, "timestamp", 0, &tmp) && tmp){
			(*cur)->update_ts = (uint64_t) strtoull(tmp, NULL, 10);
		}

		cur = &(*cur)->next;
		arg_cleanup(entry);
	}

	fclose(fpek);
	return first;
}

#ifdef HAVE_DIRSRV
bool anet_directory_dirsrv_exec_source(
		struct dircl* dst,
		uint16_t applid, const char* ident,
		char* exec, struct arcan_strarr* argv, struct arcan_strarr* envv)
{
/* generate a temporary keypair for the new source to connect and register it
 * with source permissions only. Easier than modifying dir_srv.c auth for this
 * special case, we just grant it into the keystore. */
	uint8_t private[32], public[32];
	x25519_private_key(private);
	x25519_public_key(private, public);
	size_t priv_outl, pub_outl;
	a12helper_keystore_accept_ephemeral(public, "_local", ident);
	char emptyid[16] = {0};

/* generate a random name if no identity was supplied, this is mainly useful
 * for targeted launch */
	char tmpnam[8];
	if (!ident){
		anet_directory_random_ident(tmpnam, 7);
		tmpnam[7] = '\0';
		ident = tmpnam;
	}

	dirsrv_global_lock(__FILE__, __LINE__);
	if (dst){
		dirsrv_set_source_mask(public, applid, emptyid, dst->pubk);
	}
	else{
		uint8_t emptyk[32] = {0};
		dirsrv_set_source_mask(public, applid, emptyid, emptyk);
	}

	dirsrv_global_unlock(__FILE__, __LINE__);

/*
 * then build the keypair that we'll use over the tunnel
 */
	uint8_t srvprivk[32], srvpubk[32];
	char* tmp;
	uint16_t tmpport;
	a12helper_keystore_hostkey("default", 0, srvprivk, &tmp, &tmpport);
	x25519_public_key(srvprivk, srvpubk);

	unsigned char* priv_b64 = a12helper_tob64(private, 32, &priv_outl);
	unsigned char* pub_b64 = a12helper_tob64(srvpubk, 32, &pub_outl);

/*
 * now the exec parameters for arcan-net itself, the argv and envv we get
 * as arguments are for the actual application, not the network connection
 * so we append those at the end.
 *
 * For the time being, add verbose logging.
 */
	char* outargv[argv->count + 13];
	char* outident = strdup(ident);

	memset(outargv, '\0', sizeof(outargv));
	size_t ind = 0;
	outargv[ind++] = dirsrv_static_opts()->path_self;
	outargv[ind++] = "-d";
	outargv[ind++] = "8191";
	outargv[ind++] = "--stderr-log";
	outargv[ind++] = "--force-kpub";
	outargv[ind++] = (char*) pub_b64;
	outargv[ind++] = "--ident";
	outargv[ind++] = outident;
	outargv[ind++] = "localhost";
/* should also grab port from CFG */
	outargv[ind++] = "--";
	outargv[ind++] = exec;

/* note that the self arg in argv is skipped, as -- for arcan-net would have
 * the same effect. */
	for (size_t i = 1; i < argv->count; i++)
		outargv[ind++] = argv->data[i];

	char* outenv[envv->count + 2];
	memset(outenv, '\0', sizeof(outenv));
	char envinf[sizeof("A12_USEPRIV=") + priv_outl];
	snprintf(envinf, sizeof(envinf), "A12_USEPRIV=%s", priv_b64);

	for (size_t i = 0; i < envv->count; i++)
		outenv[i] = envv->data[i];
	outenv[envv->count] = envinf;

	char* msg = NULL;
	if (0 >= asprintf(&msg, "launch_%s.log", ident)){
		msg = NULL;
	}

/* finally execute the process in question */
	pid_t pid = fork();
	if (pid == 0){
		if ((fork() != 0))
			_exit(EXIT_SUCCESS);

		close(STDIN_FILENO);
		close(STDOUT_FILENO);
		close(STDERR_FILENO);

		sigaction(SIGINT, &(struct sigaction){}, NULL);

		open("/dev/null", O_RDWR); /* stdin */
		open("/dev/null", O_RDWR); /* stdout */
		if (-1 == openat(
			dirsrv_static_opts()->dirsrv.appl_logdfd, msg, O_RDWR | O_CREAT, 0700)){
			open("/dev/null", O_RDWR); /* stderr */
		}

		setsid();
		execve(dirsrv_static_opts()->path_self, outargv, outenv);
		_exit(EXIT_FAILURE);
	}

/* SIGCHLD is just dropped by default */
	free(msg);
	free(outident);

	return true;
}
#endif
