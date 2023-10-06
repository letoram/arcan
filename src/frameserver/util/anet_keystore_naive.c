/* current:
 *  1. loading keys from accepted
 *  2. creating new key to private
 *  3. loading key from private
 *  4. accepting key into store
 */

#include <arcan_shmif.h>
#include <arcan_shmif_server.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <dirent.h>
#include <fcntl.h>
#include <ctype.h>
#include <inttypes.h>
#include <errno.h>

#include <sys/socket.h>
#include <sys/stat.h>
#include <netdb.h>

#include "a12.h"
#include "anet_helper.h"

#include "external/x25519.h"

#include "anet_helper.h"

struct key_ent;

struct key_ent {
	uint8_t key[32];
	char* host;
	size_t port;
	char* fn;

	struct key_ent* next;
};

static struct {
	struct key_ent* hosts;

	int dirfd_private;
	int dirfd_accepted;
	int dirfd_state;

	bool open;
	struct keystore_provider provider;
} keystore = {
	.dirfd_private = -1,
	.dirfd_accepted = -1,
	.dirfd_state = -1
};

static uint8_t b64dec_lut[256] = {
0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 62, 0, 0, 0,
63, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 0, 0, 0, 0, 0, 0, 0, 0, 1,
2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
22, 23, 24, 25, 0, 0, 0, 0, 0, 0, 26, 27, 28, 29, 30, 31, 32, 33, 34,
35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 0,
0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};

static uint8_t b64enc_lut[] =
	"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"
	"ghijklmnopqrstuvwxyz0123456789+/";

uint8_t* a12helper_tob64(const uint8_t* data, size_t inl, size_t* outl)
{
	size_t mlen = inl % 3;
	off_t ofs = 0;
	size_t pad = ((mlen & 1 ) << 1) + ((mlen & 2) >> 1);

	*outl = (inl * 4) / 3 + pad + 2;

	uint8_t* res = malloc(*outl);
	if (!res)
		return NULL;

	uint8_t* wrk = res;

	while (ofs < inl - mlen){
		uint32_t val = (data[0] << 16) + (data[1] << 8) + data[2];
		*wrk++ = b64enc_lut[(val >> 18) & 63];
		*wrk++ = b64enc_lut[(val >> 12) & 63];
		*wrk++ = b64enc_lut[(val >>  6) & 63];
		*wrk++ = b64enc_lut[(val >>  0) & 63];
		data += 3;
		ofs += 3;
	}

	if (pad == 2){
		*wrk++ = b64enc_lut[ (data[0]    ) >> 2 ];
		*wrk++ = b64enc_lut[ (data[0] & 3) << 4 ];
		*wrk++ = '=';
		*wrk++ = '=';
	}
	else if (pad == 1){
		*wrk++ = b64enc_lut[ data[0] >> 2 ];
		*wrk++ = b64enc_lut[ ((data[0] & 3) << 4) + (data[1] >> 4) ];
		*wrk++ = b64enc_lut[ (data[1] & 15) << 2 ];
		*wrk++ = '=';
	}

	*wrk = '\0';
	return res;
}

bool a12helper_fromb64(const uint8_t* instr, size_t lim, uint8_t outb[static 32])
{
	size_t inlen = strlen((char*)instr);

	if (inlen % 4 != 0 || inlen < 2)
		return NULL;

	size_t len = inlen / 4 * 3;
	if (instr[inlen - 1] == '=')
		len--;

	if (instr[inlen - 2] == '=')
		len--;

	if (len > lim)
		return false;

	uint32_t val;
	int i, j = 0;
	for (i = 0; i < inlen; i += 4){
		val  = (instr[i+0] == '=' ? 0 & (i+0) : b64dec_lut[instr[i+0]]) << 18;
		val += (instr[i+1] == '=' ? 0 & (i+1) : b64dec_lut[instr[i+1]]) << 12;
		val += (instr[i+2] == '=' ? 0 & (i+2) : b64dec_lut[instr[i+2]]) <<  6;
		val += (instr[i+3] == '=' ? 0 & (i+3) : b64dec_lut[instr[i+3]]) <<  0;

		if (j < len) outb[j++] = (val >> 16) & 0xff;
		if (j < len) outb[j++] = (val >>  8) & 0xff;
		if (j < len) outb[j++] = (val >>  0) & 0xff;
	}

	return j >= lim;
}

struct key_ent* alloc_key_ent(const uint8_t key[static 32])
{
	struct key_ent* res = malloc(sizeof(struct key_ent));
	if (!res)
		return NULL;

	*res = (struct key_ent){.host = NULL};
	memcpy(res->key, key, 32);

	return res;
}

/* both accepted and hostkey use the same line format, hostfield
 * is interpreted differently so only the shared part is dealt with here */
static bool decode_hostline(char* buf,
	size_t endofs, char** outhost, uint8_t key[static 32])
{
/* trim host,port base64key<space>0..n -> host,port base64key */
	char* cur = &buf[endofs];
	while (cur != buf){
		if (!isspace(*cur))
			break;
		*cur-- = '\0';
	}

/* split on first whitespace */
	cur = buf;
	while (*cur && !isspace(*cur))
		cur++;

/* error conditions: at end of line or at beginning */
	if (!*cur || cur == buf)
		return false;

	*cur = '\0';
	cur++;

/* trim trailing whitespace */
	char* end = cur + strlen(cur) - 1;
	while (isspace(*end)){
		*end-- = '\0';
	}

	*outhost = buf;
/* decode keypart */
	return a12helper_fromb64((uint8_t*) cur, 32, key);
}

static void flush_accepted_keys()
{
	struct key_ent* cur = keystore.hosts;
	while (cur){
		struct key_ent* prev = cur;
		cur = cur->next;
		memset(prev, '\0', sizeof(struct key_ent));
		free(prev);
	}
	keystore.hosts = NULL;
}

static void load_accepted_keys()
{
	flush_accepted_keys();

	int tmpdfd = dup(keystore.dirfd_accepted);
	if (-1 == tmpdfd)
		return;

	DIR* dir = fdopendir(tmpdfd);
	struct dirent* ent;
	struct key_ent** host = &keystore.hosts;

/* all entries in directory is treated as possible keys, no single
 * authorized_keys, also means that we can have an inotify / watch on the
 * folder and immediately react on additions and revocations */
	while ((ent = readdir(dir))){
		int fd = openat(keystore.dirfd_accepted, ent->d_name, O_RDONLY | O_CLOEXEC);
		if (-1 == fd)
			continue;

		FILE* fpek = fdopen(fd, "r");
		if (!fpek)
			continue;

		size_t len = 0;
		char* inbuf = NULL;

/* only one host per file, getline will alloc needed */
		while (getline(&inbuf, &len, fpek) != -1){
			if (!len)
				continue;

			char* hoststr;
			uint8_t key[32];

			if (!decode_hostline(inbuf, len-1, &hoststr, key)){
				fprintf(stderr, "keystore_naive(): failed to parse %s\n", ent->d_name);
				free(inbuf);
				continue;
			}

/* chain/attach as linked list, this will only contain the list of cps the key is valid for */
			*host = alloc_key_ent(key);
			if (*host){
				(*host)->host = strdup(hoststr);
				(*host)->fn = strdup(ent->d_name);
				host = &(*host)->next;
			}

			break;
		}

		fclose(fpek);
	}

	rewinddir(dir);
	closedir(dir);
}

bool a12helper_keystore_open(struct keystore_provider* p)
{
	if (!p)
		return false;

/* permit open on an already open keystore assuming it is the same provider */
	if (keystore.open){
		if (memcmp(p, &keystore.provider, sizeof(struct keystore_provider)) == 0)
			return true;

		return false;
	}

	keystore.provider = *p;
	if (keystore.provider.type != A12HELPER_PROVIDER_BASEDIR)
		return false;

	if (keystore.provider.directory.dirfd < STDERR_FILENO)
		return false;

/* ensure we have a dirfd to the set of private (host+privkey) and accepted
 * directories, would want an option to setup a notification thread that
 * watches these and reload on modifications, but that is only relevant when
 * running persistantly */
	mkdirat(keystore.provider.directory.dirfd, "accepted", S_IRWXU);
	mkdirat(keystore.provider.directory.dirfd, "hostkeys", S_IRWXU);
	mkdirat(keystore.provider.directory.dirfd, "state", S_IRWXU);

	int fl = O_DIRECTORY | O_CLOEXEC;
	if (-1 == (keystore.dirfd_accepted =
		openat(keystore.provider.directory.dirfd, "accepted", fl))){
		close(keystore.provider.directory.dirfd);
		keystore.provider.directory.dirfd = -1;
		return false;
	}

	if (-1 == (keystore.dirfd_private =
		openat(keystore.provider.directory.dirfd, "hostkeys", fl))){
		close(keystore.dirfd_accepted);
		keystore.dirfd_accepted = -1;
		close(keystore.provider.directory.dirfd);
		keystore.provider.directory.dirfd = -1;
		return false;
	}

	keystore.dirfd_state =
		openat(keystore.provider.directory.dirfd, "state", fl);

	load_accepted_keys();
	keystore.open = true;

	return true;
}

/* just used as a mkstmpat */
static void gen_fn(char* tmpfn, size_t len)
{
	arcan_random((uint8_t*)tmpfn, len);
	for (size_t i = 0; i < len; i++){
		tmpfn[i] = 'a' + ((uint8_t)tmpfn[i] % 21);
	}
}

bool a12helper_keystore_accept(const uint8_t pubk[static 32], const char* connp)
{
/* just random -> b64 until something sticks */
	char tmpfn[9] = {0};
	int fdout;
	if (!keystore.open)
		return false;

	do {
		gen_fn(tmpfn, 8);
		fdout = openat(keystore.dirfd_accepted,
			tmpfn, O_CREAT | O_EXCL | O_WRONLY, S_IRWXU);
	} while (fdout < 0);

	FILE* fpek = fdopen(fdout, "w");
	if (!fpek)
		return false;

	if (!connp)
		connp = "outbound";

/* get base64 of pubk, just write that + space + connp <lf> */
	size_t outl;
	uint8_t* buf = a12helper_tob64(pubk, 32, &outl);
	if (!buf){
		unlinkat(keystore.dirfd_accepted, tmpfn, 0);
		close(fdout);
		return false;
	}

	fprintf(fpek, "%s %s\n", connp, (char*) buf);
	fclose(fpek);
	free(buf);

/* add to the existing keystore */
	struct key_ent** host = &keystore.hosts;
	while (*host){
		host = &(*host)->next;
	}

	*host = alloc_key_ent(pubk);
	if (*host){
		(*host)->host = strdup(connp);
	}
	return true;
}

bool a12helper_keystore_release()
{
	if (!keystore.open)
		return false;

	close(keystore.provider.directory.dirfd);
	close(keystore.dirfd_accepted);
	close(keystore.dirfd_private);
	close(keystore.dirfd_state);

	keystore.provider.directory.dirfd = -1;
	keystore.dirfd_accepted = -1;
	keystore.dirfd_private = -1;
	keystore.dirfd_state = -1;
	keystore.open = false;

	return true;
}

static char* unpack_host(char* host,
	size_t defport, uint16_t* outport, const char** errfmt)
{
/* unpack hostline at the right offset, that is simply split at outhost */
	size_t len = strlen(host);
	if (!len){
		*errfmt = "empty host in keyfile [%s]:%zu\n";
		return NULL;
	}

	char* portch = strrchr(host, ':');
	if (!portch){
/* it's the 'n'th valid hostline we want, to be consistent we skip errors */
		*outport = defport;
		return host;
	}

/* just :port isn't permitted */
	if (portch == host){
		*errfmt = "malformed host in keyfile [%s:%zu]\n";
		return NULL;
	}

/* ipv6 text representation defined by telecom-'talents' so more parsing */
	if (portch[-1] != ']'){
		size_t port = strtoul(&portch[1], NULL, 10);
		*portch = '\0';

		if (!port || port > 65535){
			*errfmt = "invalid port for host in keyfile [%s:%zu]\n";
			return NULL;
		}

		*outport = port;
		return host;
	}

	if (host[0] != '['){
		*errfmt = "malformed IPv6 notation in keyfile [%s:%zu]\n";
		return NULL;
	}

/* [ipv6]:port */
	size_t port = strtoul(&portch[1], NULL, 10);
	portch[-1] = '\0';
	if (!port || port > 65535){
		*errfmt = "unvalid port for host in keyfile [%s:%zu]\n";
		return NULL;
	}
	*outport = port;

/* slide back so we don't risk UB from free on returned value */
	memmove(host, &host[1], strlen(host)+1);
	return host;
}

bool a12helper_keystore_hostkey(const char* tagname, size_t index,
	uint8_t privk[static 32], char** outhost, uint16_t* outport)
{
	if (!keystore.open || !tagname || !outhost || !outport)
		return false;

	*outhost = NULL;

/* just (re-) open and scan to the line matching the desired index */
	int fin = openat(keystore.dirfd_private, tagname, O_RDONLY | O_CLOEXEC);
	if (-1 == fin)
		return false;

	FILE* fpek = fdopen(fin, "r");
	if (!fpek)
		return false;

	bool res = false;

	ssize_t nr;
	size_t lineno = 0;
	size_t len = 0;
	char* inbuf = NULL;

	while ((nr = getline(&inbuf, &len, fpek)) != -1){
		char* host;
		lineno++;

		res = decode_hostline(inbuf, nr, &host, privk);
		if (!res){
			fprintf(stderr, "bad key entry in keyfile [%s]:%zu\n", tagname, lineno);
			continue;
		}

		const char* errmsg;
		if (!(*outhost = unpack_host(host, 6680, outport, &errmsg))){
			fprintf(stderr, errmsg, tagname, lineno);
			continue;
		}

		if (!index){
			res = true;
			break;
		}

		res = false;
		index--;
	}

	fclose(fpek);

	if (!res)
		free(*outhost);

	return res && index == 0;
}

/* Append or crete a new tag with the specified host, this will also create a key */
bool a12helper_keystore_register(
	const char* tagname, const char* host, uint16_t port, uint8_t pubk[static 32])
{
	if (!keystore.open)
		return false;

	uint8_t privk[32];
	x25519_private_key(privk);
	x25519_public_key(privk, pubk);

/* going posix instead of fdout because of locking */
	int fout = openat(keystore.dirfd_private,
		tagname, O_WRONLY | O_CREAT | O_CLOEXEC, S_IRWXU);

	if (-1 == fout){
		fprintf(stderr, "couldn't open or create tag (%s) for private key\n", tagname);
		return false;
	}

	size_t key_b64sz = 0;
	uint8_t* b64 = a12helper_tob64(privk, 32, &key_b64sz);
	if (!b64){
		fprintf(stderr, "couldn't allocate intermediate buffer\n");
		close(fout);
		return false;
	}

	size_t out_sz = strlen(host) +
		sizeof(':') + sizeof("65536") + sizeof(' ') + key_b64sz + sizeof('\n');

	char buf[out_sz];
	ssize_t res = snprintf(buf, sizeof(buf), "%s:%"PRIu16" %s\n", host, port, b64);
	free(b64);

	if (res < 0){
		fprintf(stderr, "failed to create buffer\n");
		close(fout);
		return false;
	}
	else out_sz = res;

/* grab an exclusive lock, seek to the end of the keyfile, append the
 * record and try to error recover if we run out of space partway through */
	if (-1 == flock(fout, LOCK_EX)){
		fprintf(stderr, "couldn't lock keystore for writing\n");
		close(fout);
		return false;
	}

	off_t base_pos = lseek(fout, 0, SEEK_END);
	ssize_t nw = 0;
	size_t out_pos = 0;

/* normally < pipe_buf for single atomic write, but idiotic hosts might
 * push that limit */
	while (out_pos != out_sz){
		while ( (nw = write(fout, &buf[out_pos], out_sz)) == -1 ){

/* and this can happen if we have a mount on nfs/fuse and the user gets bored */
			if (errno != EINTR && errno != EAGAIN){
				ftruncate(fout, base_pos);
				fprintf(stderr, "failed to write new key entry\n");
				goto out;
			}
		}
		out_pos += nw;
	}

out:
	flock(fout, LOCK_UN);
	close(fout);

	return true;
}

bool a12helper_keystore_tags(bool (*cb)(const char*, void*), void* tag)
{
	if (!cb)
		return false;

	lseek(keystore.dirfd_private, 0, SEEK_SET);
	int tmpdfd = dup(keystore.dirfd_private);
	if (-1 == tmpdfd)
		return false;

	DIR* dir = fdopendir(tmpdfd);
	if (!dir){
		if (-1 != tmpdfd)
			close(tmpdfd);

		cb(NULL, tag);
		return false;
	}

	struct dirent* dent;

/* 'all applications are supposed to handle dt_unknown' but stat:ing and
 * checking if it is a regular file and then opening thereafter is also meh -
 * other keystores won't have this problem anyhow so just ignore.The default
 * key is ignored as that one points to localhost */
	while ((dent = readdir(dir))){
		if (dent->d_type == DT_REG && strcmp(dent->d_name, "default") != 0){
			if (!cb(dent->d_name, tag))
				break;
		}
	}

	cb(NULL, tag);

	closedir(dir);
	return true;
}

int a12helper_keystore_statestore(
	const uint8_t pubk[static 32], const char* name, size_t sz, const char* mode)
{
	if (keystore.dirfd_state == -1)
		return -1;

	struct key_ent* ent = keystore.hosts;
	while (ent && memcmp(pubk, ent->key, 32) != 0)
		ent = ent->next;

	if (!ent)
		return -1;

/* need to save / store the cap somewhere, match the directory name to the
 * same random name that was given to the key earlier */
	mkdirat(keystore.dirfd_state, ent->fn, S_IRWXU);
	int dir = openat(keystore.dirfd_state, ent->fn, O_DIRECTORY | O_CLOEXEC);
	if (dir == -1)
		return -1;

/* sz is not enforced yet, just read a .cap file? */
	if (strcmp(mode, "w+") == 0){
		return openat(dir, name, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR);
	}
	else
		return openat(dir, name, O_RDONLY | O_CLOEXEC);
}

/*
 * this can be timed for a side-channel leak of:
 *
 *  - whether a key is known accepted or not
 *  - the number of accepted connection points for a key
 *  - the number of accepted keys
 *
 * mitigate by call first for '*' connp, then the specific one (if desired)
 * mitigate by also asking for a few random keys
 */
const char*
	a12helper_keystore_accepted(const uint8_t pubk[static 32], const char* connp)
{
	struct key_ent* ent = keystore.hosts;
	if (!connp)
		return NULL;

	size_t nlen = strlen(connp);
	if (!nlen)
		return NULL;

	while (ent){
/* not this key? */
		if (memcmp(pubk, ent->key, 32) != 0){
			ent = ent->next;
			continue;
		}

/* valid for every connection point? */
		if (strcmp(ent->host, "*") == 0 || strcmp(connp, "*") == 0){
			return ent->host;
		}

/* then host- list is separated cp1,cp2,cp3,... so find needle in haystack */
		const char* needle = strstr(ent->host, connp);
		if (!needle){
			ent = ent->next;
			continue;
		}

/* that might be a partial match, i.e. key for connpath 'a' while not for 'ale'
 * so check that we are at a word boundary (at beginning, end or surrounded by , */
		if (
			(
			 (needle == ent->host || needle[-1] == ',') && /* start on boundary */
			 (needle[nlen] == '\0' || needle[nlen] == ',') /* end on boundary */
			)){
			return ent->host;
		}

/* continue as the pubk may exist multiple times */
		ent = ent->next;
	}

	return NULL;
}

int a12helper_keystore_dirfd(const char** err)
{
	char* basedir = getenv("ARCAN_STATEPATH");

	if (!basedir){
		*err = "Missing keystore (set ARCAN_STATEPATH)";
		return -1;
	}

	int dir = open(basedir, O_DIRECTORY | O_CLOEXEC);
	if (-1 == dir){
		*err = "Error opening basedir, check permissions and type";
		return -1;
	}

	int keydir = openat(dir, "a12", O_DIRECTORY | O_CLOEXEC);
	if (-1 == keydir){
		mkdirat(dir, "a12", S_IRWXU);
		keydir = openat(dir, "a12", O_DIRECTORY | O_CLOEXEC);
	}

	return keydir;
}
