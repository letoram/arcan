/* public domain, no copyright claimed. */

#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <arcan_math.h>
#include <arcan_general.h>

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

uint8_t* arcan_base64_decode(
	const uint8_t* instr, size_t *outlen, enum arcan_memhint hint){
	size_t inlen = strlen((char*)instr);

	if (inlen % 4 != 0 || inlen < 2)
		return NULL;

	*outlen = inlen / 4 * 3;
	if (instr[inlen - 1] == '=')
		(*outlen)--;

	if (instr[inlen - 2] == '=')
		(*outlen)--;

	uint8_t* outb = arcan_alloc_mem(*outlen,
		ARCAN_MEM_STRINGBUF, hint, ARCAN_MEMALIGN_NATURAL);

	if (!outb)
		return NULL;

	uint32_t val;
	for (int i = 0, j = 0; i < inlen; i+= 4) {
		val  = (instr[i+0] == '=' ? 0 & (i+0) : b64dec_lut[instr[i+0]]) << 18;
		val += (instr[i+1] == '=' ? 0 & (i+1) : b64dec_lut[instr[i+1]]) << 12;
		val += (instr[i+2] == '=' ? 0 & (i+2) : b64dec_lut[instr[i+2]]) <<  6;
		val += (instr[i+3] == '=' ? 0 & (i+3) : b64dec_lut[instr[i+3]]) <<  0;

		if (j < *outlen)
			outb[j++] = (val >> 16) & 0xff;

		if (j < *outlen)
			outb[j++] = (val >>  8) & 0xff;

		if (j < *outlen)
			outb[j++] = (val >>  0) & 0xff;
	}

	return outb;
}

uint8_t* arcan_base64_encode(
	const uint8_t* data, size_t inl, size_t* outl, enum arcan_memhint hint)
{
	size_t mlen = inl % 3;
	off_t ofs = 0;
	size_t pad = ((mlen & 1 ) << 1) + ((mlen & 2) >> 1);

	*outl = (inl * 4) / 3 + pad + 2;

	uint8_t* res = arcan_alloc_mem(*outl,
		ARCAN_MEM_STRINGBUF, hint, ARCAN_MEMALIGN_NATURAL);

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

