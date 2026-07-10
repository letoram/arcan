// Zig port of posix/base64.c
// Base64 encode/decode using arcan_alloc_mem for allocation.

const ARCAN_MEM_STRINGBUF: c_uint = 5;
const ARCAN_MEM_BZERO: c_uint = 1;
const ARCAN_MEMALIGN_NATURAL: c_uint = 0;

extern fn arcan_alloc_mem(sz: usize, memtype: c_uint, hint: c_uint, alignment: c_uint) ?[*]u8;

const b64dec_lut = [256]u8{
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
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
};

const b64enc_lut = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

export fn arcan_base64_decode(
    instr: [*]const u8,
    outlen: *usize,
    hint: c_uint,
) ?[*]u8 {
    var inlen: usize = 0;
    while (instr[inlen] != 0) : (inlen += 1) {}

    if (inlen % 4 != 0 or inlen < 2)
        return null;

    outlen.* = inlen / 4 * 3;
    if (instr[inlen - 1] == '=')
        outlen.* -= 1;
    if (instr[inlen - 2] == '=')
        outlen.* -= 1;

    const outb = arcan_alloc_mem(outlen.*, ARCAN_MEM_STRINGBUF, hint, ARCAN_MEMALIGN_NATURAL) orelse return null;

    var j: usize = 0;
    var i: usize = 0;
    while (i < inlen) : (i += 4) {
        var val: u32 = 0;
        val |= @as(u32, if (instr[i + 0] == '=') 0 else b64dec_lut[instr[i + 0]]) << 18;
        val |= @as(u32, if (instr[i + 1] == '=') 0 else b64dec_lut[instr[i + 1]]) << 12;
        val |= @as(u32, if (instr[i + 2] == '=') 0 else b64dec_lut[instr[i + 2]]) << 6;
        val |= @as(u32, if (instr[i + 3] == '=') 0 else b64dec_lut[instr[i + 3]]) << 0;

        if (j < outlen.*) {
            outb[j] = @truncate(val >> 16);
            j += 1;
        }
        if (j < outlen.*) {
            outb[j] = @truncate(val >> 8);
            j += 1;
        }
        if (j < outlen.*) {
            outb[j] = @truncate(val);
            j += 1;
        }
    }

    return outb;
}

export fn arcan_base64_encode(
    data: [*]const u8,
    inl: usize,
    outl: *usize,
    hint: c_uint,
) ?[*]u8 {
    const mlen = inl % 3;
    const pad: usize = ((mlen & 1) << 1) + ((mlen & 2) >> 1);

    outl.* = (inl * 4) / 3 + pad + 2;

    const res = arcan_alloc_mem(outl.*, ARCAN_MEM_STRINGBUF, hint, ARCAN_MEMALIGN_NATURAL) orelse return null;

    var wrk: usize = 0;
    var ofs: usize = 0;
    var src: usize = 0;
    while (ofs < inl - mlen) : (ofs += 3) {
        const val: u32 = (@as(u32, data[src]) << 16) + (@as(u32, data[src + 1]) << 8) + @as(u32, data[src + 2]);
        res[wrk] = b64enc_lut[(val >> 18) & 63];
        wrk += 1;
        res[wrk] = b64enc_lut[(val >> 12) & 63];
        wrk += 1;
        res[wrk] = b64enc_lut[(val >> 6) & 63];
        wrk += 1;
        res[wrk] = b64enc_lut[(val >> 0) & 63];
        wrk += 1;
        src += 3;
    }

    if (pad == 2) {
        res[wrk] = b64enc_lut[data[src] >> 2];
        wrk += 1;
        res[wrk] = b64enc_lut[(data[src] & 3) << 4];
        wrk += 1;
        res[wrk] = '=';
        wrk += 1;
        res[wrk] = '=';
        wrk += 1;
    } else if (pad == 1) {
        res[wrk] = b64enc_lut[data[src] >> 2];
        wrk += 1;
        res[wrk] = b64enc_lut[((data[src] & 3) << 4) + (data[src + 1] >> 4)];
        wrk += 1;
        res[wrk] = b64enc_lut[(data[src + 1] & 15) << 2];
        wrk += 1;
        res[wrk] = '=';
        wrk += 1;
    }

    res[wrk] = 0;
    return res;
}
