/*
 * Using Chacha20 as streamcipher, keyed per thread and getting
 * seed from OS specific methods and a fallback to /dev/urandom
 * similar to arc4random and friends, of course, but given that
 */

#include "chacha20.c"
#include <stdio.h>
#include <errno.h>

static _Thread_local struct chacha20_ctx streamcipher;

/* just lifted from the getrandom manpage, on others
 * (osx, fbsd, openbsd) we assume that we have this one */
#ifdef __LINUX
#include <unistd.h>
#include <sys/syscall.h>
static int getentropy(void* buf, size_t buflen)
{
	int ret;
	if (buflen > 256)
		goto failure;


	ret = syscall(SYS_getrandom, buf, buflen, 0);
	if (ret < 0)
		return ret;
	if (ret == buflen)
		return 0;

failure:
	errno = EIO;
	return -1;
}
#else
#include <sys/random.h>
#endif

static void seed_csprng()
{
	uint8_t seed[16];
	uint8_t nonce[8] = {9};

/* fallback, /dev/urandom - hopefully it will never be used as it would need to
 * be taken into account when it comes to chroot/jail/privsep */
	if (getentropy(seed, 16) != 0){
		FILE* fpek = fopen("/dev/urandom", "r");
		if (!fpek || 1 != fread(seed, 16, 1, fpek))
			arcan_fatal("couldn't seed CSPRNG, system not in a safe state\n");
		fclose(fpek);
	}

	chacha20_setup(&streamcipher, seed, 16, nonce, 0);
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
		chacha20_block(&streamcipher, ibuf);
		memcpy(dst, ibuf, malign);
		ofs += malign;
		ntc -= malign;
	}

/* as we're only using the keystream as a csprng, any leftover bytes
 * in each block can be ignored */
	while (ntc >= 64){
		chacha20_block(&streamcipher, (uint32_t*)&dst[ofs]);
		ofs += 64;
		ntc -= 64;
	}

	if (!ntc)
		return;

/* and slow-copy the remaining bytes */
	chacha20_block(&streamcipher, ibuf);
	memcpy(&dst[ofs], ibuf, ntc);
}
