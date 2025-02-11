/*
 * Using Chacha as streamcipher, keyed per thread and getting
 * seed from OS specific methods and a fallback to /dev/urandom
 * similar to arc4random and friends, of course, but given that
 */

#include "../posix/chacha.c"
#include <stdio.h>
#include <errno.h>

#include <windows.h>

void arcan_fatal(const char* msg, ...);

static _Thread_local struct chacha_ctx streamcipher;

int seedrnd(void* buf, size_t buflen)
{
    if (buflen > 256) return -1;

    HCRYPTPROV prov;

    if (!CryptAcquireContextA(
	    &prov,
	    NULL,
	    NULL,
	    PROV_RSA_FULL,
	    CRYPT_VERIFYCONTEXT
    ))
	    return -1;

	BOOL success = CryptGenRandom(prov, buflen, buf);

	CryptReleaseContext(prov, 0);

	return success ? 0 : -1;
}

static void seed_csprng()
{
	uint8_t seed[16];
	uint8_t nonce[8] = {9};

/* fallback, /dev/urandom - hopefully it will never be used as it would need to
 * be taken into account when it comes to chroot/jail/privsep */
	if (seedrnd(seed, 16) != 0){
		arcan_fatal("couldn't seed CSPRNG, system not in a safe state\n");
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
