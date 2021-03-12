#ifndef HAVE_B64DEC
#define HAVE_B64DEC

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

uint8_t* from_base64(const uint8_t* instr, size_t *outlen){
	size_t inlen = strlen((char*)instr);

	if (inlen % 4 != 0 || inlen < 2)
		return NULL;

	*outlen = inlen / 4 * 3;
	if (instr[inlen - 1] == '=')
		(*outlen)--;

	if (instr[inlen - 2] == '=')
		(*outlen)--;

	(*outlen)++;
	uint8_t* outb = malloc(*outlen);

	if (!outb)
		return NULL;

	uint32_t val;
	size_t i, j;

	for (i = 0, j = 0; i < inlen; i+= 4) {
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

	outb[j++] = '\0';

	return outb;
}

#endif
