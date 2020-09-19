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

	struct key_ent* next;
};

static struct {
	struct key_ent* hosts;

	int dirfd_private;
	int dirfd_accepted;

	bool open;
	struct keystore_provider provider;
} keystore;

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

uint8_t* to_b64(const uint8_t* data, size_t inl, size_t* outl)
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

static bool from_b64(const uint8_t* instr, size_t lim, uint8_t outb[static 32])
{
	size_t inlen = strlen((char*)instr);

	if (inlen % 4 != 0 || inlen < 2)
		return NULL;

	size_t len = inlen / 4 * 3;
	if (instr[inlen - 1] == '=')
		len--;

	if (instr[inlen - 2] == '=')
		len--;

	if (len != lim)
		return false;

	uint32_t val;
	for (int i = 0, j = 0; i < inlen && j < lim; i += 4, j += 3) {
		val  = (instr[i+0] == '=' ? 0 & (i+0) : b64dec_lut[instr[i+0]]) << 18;
		val += (instr[i+1] == '=' ? 0 & (i+1) : b64dec_lut[instr[i+1]]) << 12;
		val += (instr[i+2] == '=' ? 0 & (i+2) : b64dec_lut[instr[i+2]]) <<  6;
		val += (instr[i+3] == '=' ? 0 & (i+3) : b64dec_lut[instr[i+3]]) <<  0;

		outb[j  ] = (val >> 16) & 0xff;
		outb[j+1] = (val >>  8) & 0xff;
		outb[j+2] = (val >>  0) & 0xff;
	}

	return true;
}

struct key_ent* alloc_key_ent(uint8_t key[static 32])
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

/* decode keypart */
	return from_b64((uint8_t*) cur, 32, key);
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

	DIR* dir = fdopendir(keystore.dirfd_accepted);
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
/* fate of fd is undefined in this (rare, malloc-fail, weird-files in folder,
 * ...) case, better to leak */
		if (!fpek)
			continue;

		size_t len = 0;
		char* inbuf = NULL;

/* only one host per file, getline will alloc needed */
		while (getline(&inbuf, &len, fpek) != -1){
			char* hoststr;
			uint8_t key[32];

			if (!decode_hostline(inbuf, len, &hoststr, key)){
				fprintf(stderr, "keystore_naive(): failed to parse %s\n", ent->d_name);
				fclose(fpek);
				free(inbuf);
				continue;
			}

/* chain/attach as linked list, this will only contain the list of cps the key is valid for */
			*host = alloc_key_ent(key);
			if (*host){
				(*host)->host = hoststr;

				host = &(*host)->next;
			}

			break;
		}

		fclose(fpek);
	}

	closedir(dir);
}

bool a12helper_keystore_open(struct keystore_provider* p)
{
	if (!p || keystore.open)
		return false;

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

	int fl = O_PATH | O_RDONLY | O_CLOEXEC;
	if (-1 == (keystore.dirfd_accepted =
		openat(keystore.provider.directory.dirfd, "accepted", fl))){
		return false;
	}

	if (-1 == (keystore.dirfd_private =
		openat(keystore.provider.directory.dirfd, "hostkeys", fl))){
		close(keystore.dirfd_accepted);
		return false;
	}

	load_accepted_keys();

	return true;
}

bool a12helper_keystore_accept(const uint8_t pubk[static 32], const char* connp)
{
/* add wildcard if !connp, otherwise sanity check -
 * TODO: sweep kestore and check if it is missing */
	return true;
}

bool a12helper_keystore_release()
{
	if (!keystore.open)
		return false;

	close(keystore.provider.directory.dirfd);
	keystore.open = false;

	return true;
}

bool a12helper_keystore_hostkey(const char* tagname, size_t index,
	uint8_t privk[static 32], char** outhost, uint16_t* outport)
{
	if (!keystore.open || !tagname || !outhost || !outport)
		return false;

/* just (re-) open and scan to the line matching the desired index */
	int fin = openat(keystore.dirfd_private, tagname, O_RDONLY);
	if (-1 == fin)
		return false;

	FILE* fpek = fdopen(fin, "r");
	if (!fpek)
		return false;

	size_t len = 0;
	char* inbuf = NULL;
	bool res = false;

	ssize_t nr;
	while ((nr = getline(&inbuf, &len, fpek)) != -1){
		res = decode_hostline(inbuf, nr, outhost, privk);

/* unpack hostline at the right offset, that is simply split at outhost */
		if (!index){

/* IPv6 raw address complication here, treat as special case if the [..]:xxx form is used */
			break;
		}

		index--;
	}

	free(inbuf);
	fclose(fpek);

	return res;
}

/* Append or crete a new tag with the specified host, this will also create a key */
bool a12helper_keystore_register(
	const char* tagname, const char* host, uint16_t port)
{
	if (!keystore.open)
		return false;

	uint8_t privk[32];
	x25519_private_key(privk);

	int fout = openat(keystore.dirfd_private,
		tagname, O_WRONLY | O_CREAT | O_CLOEXEC, S_IRWXU);

	if (-1 == fout){
		fprintf(stderr, "couldn't open or create tag (%s) for private key\n", tagname);
		return false;
	}

	size_t key_b64sz = 0;
	uint8_t* b64 = to_b64(privk, 32, &key_b64sz);
	if (!b64){
		fprintf(stderr, "couldn't allocate intermediate buffer\n");
		close(fout);
		return false;
	}

	size_t out_sz = strlen(host) +
		sizeof(':') + sizeof("65536") + sizeof(' ') + key_b64sz + sizeof('\n');

	char buf[out_sz];
	snprintf(buf, sizeof(buf), "%s:%"PRIu16" %s\n", host, port, b64);

/* grab an exclusive lock, seek to the end of the keyfile, append the
 * record and try to error recover if we run out of space partway through */
	if (-1 == flock(fout, LOCK_EX)){
		fprintf(stderr, "couldn't lock keystore for writing\n");
		return false;
	}

 	off_t base_pos = lseek(fout, SEEK_END, 0);
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
bool a12helper_keystore_accepted(const uint8_t pubk[static 32], const char* connp)
{
	struct key_ent* ent = keystore.hosts;

	while (ent){
/* not this key? */
		if (memcmp(pubk, ent->key, 32) != 0){
			ent = ent->next;
			continue;
		}

/* valid for every connection point? */
		if (strcmp(ent->host, "*") == 0){
			return true;
		}

/* nope, and this is an unspecified connection point, so ignore */
		if (!connp){
			ent = ent->next;
			continue;
		}

/* then host- list is separated cp1,cp2,cp3,... so find needle in haystack */
		const char* needle = strstr(connp, ent->host);
		if (!needle){
			ent = ent->next;
			continue;
		}

/* that might be a partial match, i.e. key for connpath 'a' while not for 'ale'
 * so check that we are at a word boundary (at beginning, end or surrounded by , */
		if (
			(needle == ent->host) ||
			(needle[-1] == ',' && (needle[1] == '\0' || needle[1] == ','))
		){
			return true;
		}

		ent = ent->next;
	}

	return false;
}
