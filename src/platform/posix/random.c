/*
 * Using Chacha as streamcipher, keyed per thread and getting
 * seed from OS specific methods and a fallback to /dev/urandom
 * similar to arc4random and friends, of course, but given that
 */

#include "chacha.c"
#include <stdio.h>
#include <errno.h>
#include <sys/param.h>

void arcan_fatal(const char* msg, ...);

static _Thread_local struct chacha_ctx streamcipher;

/* just lifted from the getrandom manpage, on others
 * (osx, fbsd, openbsd) we assume that we have this one */
#if defined(__LINUX) || defined(__DragonFly__)

/* normally defined in unistd.h, but that one also pulls in
 * getentropy of its own, though not always available..., */
long syscall(long number, ...);
#include <sys/syscall.h>
static int seedrnd(void* buf, size_t buflen)
{
	int ret;
	if (buflen > 256)
		goto failure;

#ifndef SYS_getrandom
#else
	ret = syscall(SYS_getrandom, buf, buflen, 0);
	if (ret < 0)
		return ret;
	if (ret == buflen)
		return 0;
#endif

failure:
	errno = EIO;
	return -1;
}
#elif defined(__FreeBSD__) && __FreeBSD__ < 12
#include <sys/sysctl.h>
extern int __sysctl(int*, u_int, void*, size_t*, void*, size_t);
static int seedrnd(void* buf, size_t buflen)
{
	int mib[2] = {CTL_KERN, KERN_ARND};
	size_t size = buflen, len;
	uint8_t* db = (uint8_t*) buf;

	while(size){
		len = size;
		if (__sysctl(mib, 2, db, &len, NULL, 0) == -1){
			goto out;
		}
		db += len;
		size -= len;
	}

out:
	if (size != 0){
		errno = EIO;
		return -1;
	}
	return 0;
}

#elif defined(__FreeBSD__) || defined(__OpenBSD__)
#include <unistd.h>
#define seedrnd getentropy
#else
#include <sys/random.h>
#define seedrnd getentropy
#endif

static void seed_csprng()
{
	uint8_t seed[16];
	uint8_t nonce[8] = {9};

/* fallback, /dev/urandom - hopefully it will never be used as it would need to
 * be taken into account when it comes to chroot/jail/privsep */
	if (seedrnd(seed, 16) != 0){
		FILE* fpek = fopen("/dev/urandom", "r");
		if (!fpek || 1 != fread(seed, 16, 1, fpek))
			arcan_fatal("couldn't seed CSPRNG, system not in a safe state\n");
		fclose(fpek);
	}

	chacha_setup(&streamcipher, seed, 16, nonce, 0, 8);
}

void arcan_random(uint8_t* dst, size_t ntc)
{
	if (!streamcipher.ready)
		seed_csprng();

/* slow-copy until we're aligned */
	uint32_t ibuf[16];
	size_t ofs = 0;
	size_t malign = (uintptr_t) dst % sizeof(uint32_t*);
	if (malign && ntc >= 64){
		chacha_block(&streamcipher, ibuf);
		memcpy(dst, ibuf, malign);
		ofs += malign;
		ntc -= malign;
	}

/* as we're only using the keystream as a csprng, any leftover bytes
 * in each block can be ignored */
	while (ntc >= 64){
		chacha_block(&streamcipher, (uint32_t*)&dst[ofs]);
		ofs += 64;
		ntc -= 64;
	}

	if (!ntc)
		return;

/* and slow-copy the remaining bytes */
	chacha_block(&streamcipher, ibuf);
	memcpy(&dst[ofs], ibuf, ntc);
}
