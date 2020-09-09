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
#include <fcntl.h>

#include "../a12.h"
#include "../a12_int.h"
#include "a12_helper.h"

struct key_ent;

struct key_ent {
	uint8_t key[32];
	char* host;
	size_t port;

	struct key_ent* next;
};

static struct {
	char* tag;
	size_t n_hosts;
	char* hosts;

	int dirfd_private;
	int dirfd_accepted;

	bool open;
	struct keystore_provider provider;
} keystore;

struct key_ent* alloc_key_ent(
	size_t host_lim, char key[static 32], struct key_ent* last_key)
{
	struct key_ent* res = malloc(sizeof(struct key_ent));
	if (!res)
		return NULL;

	*res = (struct key_ent){.host = NULL};
	memcpy(res->key, key, 32);

	if (last_key)
		last_key->next = res;

	return res;
}

static void load_accepted_keys(int dirfd)
{
	DIR* dir = fdopendir(dirfd);
	struct dirent* ent;
	struct known_key_ent* next_key = NULL;

	while ((ent = readdir(dir))){

		int fd = fopenat(dirfd, ent->d_name, O_RDONLY | O_CLOEXEC);
		if (-1 == fd)
			continue;

/* fate of fd is undefined in this case, better to leak */
		FILE* fpek = fdopen(fd, "r");
		if (!fpek)
			continue;

		if (!fgets(inbuf, 256, fpek)){
			fclose(fpek);
			continue;
		}

/* format is hostdescr <space> key, fgets might give EOL so strip that */
		size_t len = strlen(inbuf);
		char* cur = &inbuf[len];
		while (cur != inbuf){
		}

/* cpname b64enc */
		char inbuf[256];
		uint32_t outk[32];
		ssize_t nr = r

		char* work = inbuf;
		char* host = strsep(&work, " ");
		if (!host){
		}

		close(fd);
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
	struct stat dinf;
	mkdirat(keystore.provider.dirfd, "accepted", S_IRWXU);
	mkdirat(keystore.provider.dirfd, "hostkeys", S_IRWXU);

	int fl = O_DIRECTORY | O_RDONLY | O_CLOEXEC;
	if (-1 == (keystore.dirfd_accepted =
		openat(keystore.provider.dirfd, "accepted", fl))){
		return false;
	}

	if (-1 == (keystore.dirfd_private =
		openat(keystore.provider.dirfd, "hostkeys", fl))){
		close(keystore.provider.dirfd_accepted);
		return false;
	}

	load_accepted_keys();

	return true;
}

bool a12helper_keystore_accept(const char* pubk, const char* connp)
{
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

	int fin = openat(keystore.provider.directory.privfd, tagname, O_RDONLY);
	if (-1 == fin)
		return false;

	size_t len = 0;
	char* inbuf = malloc(1024);
	if (!inbuf)
		return false;

	FILE* fpek = fdopen(fin, "r");
	if (!fpek)
		return false;

	ssize_t nr;
	while ((nr = getline(&inbuf, &len, fpek)) != -1){
		if (!len)
			continue;
/* host,port key_b64 */
	}

	if (!host){
		*outhost = NULL;
		*outport = 0;
	}

	free(line);
	fclose(fpek);

	return true;
}

/* Append or crete a new tag with the specified host, this will also
 * create a new private key if needed. Returns the public key in outk */
bool a12helper_keystore_register(
	const char* tagname, const char* host, uint16_t port)
{
	if (!keystore.open)
		return false;

	return true;
}

bool a12helper_keystore_accepted(const char* pubk, const char* connp)
{
	return true;
}
