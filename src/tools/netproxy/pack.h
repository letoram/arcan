static void unpack_u64(uint64_t* dst, uint8_t* inbuf)
{
	*dst =
		((uint64_t)inbuf[0] <<  0) |
		((uint64_t)inbuf[1] <<  8) |
		((uint64_t)inbuf[2] << 16) |
		((uint64_t)inbuf[3] << 24) |
		((uint64_t)inbuf[4] << 32) |
		((uint64_t)inbuf[5] << 40) |
		((uint64_t)inbuf[6] << 48) |
		((uint64_t)inbuf[7] << 56);
}

static void unpack_u32(uint32_t* dst, uint8_t* inbuf)
{
	*dst =
		((uint64_t)inbuf[0] <<  0) |
		((uint64_t)inbuf[1] <<  8) |
		((uint64_t)inbuf[2] << 16) |
		((uint64_t)inbuf[3] << 24);
}

static void unpack_u16(uint16_t* dst, uint8_t* inbuf)
{
	*dst =
		((uint64_t)inbuf[0] <<  0) |
		((uint64_t)inbuf[1] <<  8);
}

static void pack_u64(uint64_t src, uint8_t* outb)
{
	outb[0] = (uint8_t)(src >> 0);
	outb[1] = (uint8_t)(src >> 8);
	outb[2] = (uint8_t)(src >> 16);
	outb[3] = (uint8_t)(src >> 24);
	outb[4] = (uint8_t)(src >> 32);
	outb[5] = (uint8_t)(src >> 40);
	outb[6] = (uint8_t)(src >> 48);
	outb[7] = (uint8_t)(src >> 56);
}

static void pack_u32(uint32_t src, uint8_t* outb)
{
	outb[0] = (uint8_t)(src >> 0);
	outb[1] = (uint8_t)(src >> 8);
	outb[2] = (uint8_t)(src >> 16);
	outb[3] = (uint8_t)(src >> 24);
}

static void pack_u16(uint16_t src, uint8_t* outb)
{
	outb[0] = (uint16_t)(src >> 0);
	outb[1] = (uint16_t)(src >> 8);
}
