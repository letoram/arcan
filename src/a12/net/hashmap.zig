// Pure-Zig port of sheredom/hashmap.h. Exports the hashmap_* C ABI consumed
// by session.zig via the extern decls in anet_types.zig. Replaces
// src/a12/net/hashmap_impl.c so the arcan-net build graph contains no
// first-party C sources.
//
// Algorithm identical to hashmap.h: open-addressed table with a fixed
// 8-slot linear-probe window, CRC32-style table hash + Jenkins/Murmur3
// mix, double-on-full rehash. struct layouts below must match hashmap.h
// byte-for-byte (see anet_types.zig:struct_hashmap_s).

const libc = @import("posix");

pub const hashmap_element_s = extern struct {
    key: ?*const anyopaque = null,
    key_len: u32 = 0,
    in_use: c_int = 0,
    data: ?*anyopaque = null,
};

pub const hashmap_hasher_t = ?*const fn (seed: u32, key: ?*const anyopaque, key_len: u32) callconv(.c) u32;
pub const hashmap_comparer_t = ?*const fn (a: ?*const anyopaque, a_len: u32, b: ?*const anyopaque, b_len: u32) callconv(.c) c_int;

pub const hashmap_s = extern struct {
    log2_capacity: u32 = 0,
    size: u32 = 0,
    hasher: hashmap_hasher_t = null,
    comparer: hashmap_comparer_t = null,
    data: ?[*]hashmap_element_s = null,
};

pub const hashmap_create_options_s = extern struct {
    hasher: hashmap_hasher_t = null,
    comparer: hashmap_comparer_t = null,
    initial_capacity: u32 = 0,
    _: u32 = 0,
};

const LINEAR_PROBE_LENGTH: u32 = 8;
const U32_MAX: u32 = 0xFFFF_FFFF;

// Polynomial 0x11EDC6F41 — matches SSE 4.2 _mm_crc32_* so hashes are stable
// across the x86-SSE, ARM-CRC, and table paths in the original C.
const crc32_tab = [_]u32{
    0x00000000, 0xF26B8303, 0xE13B70F7, 0x1350F3F4, 0xC79A971F, 0x35F1141C, 0x26A1E7E8, 0xD4CA64EB,
    0x8AD958CF, 0x78B2DBCC, 0x6BE22838, 0x9989AB3B, 0x4D43CFD0, 0xBF284CD3, 0xAC78BF27, 0x5E133C24,
    0x105EC76F, 0xE235446C, 0xF165B798, 0x030E349B, 0xD7C45070, 0x25AFD373, 0x36FF2087, 0xC494A384,
    0x9A879FA0, 0x68EC1CA3, 0x7BBCEF57, 0x89D76C54, 0x5D1D08BF, 0xAF768BBC, 0xBC267848, 0x4E4DFB4B,
    0x20BD8EDE, 0xD2D60DDD, 0xC186FE29, 0x33ED7D2A, 0xE72719C1, 0x154C9AC2, 0x061C6936, 0xF477EA35,
    0xAA64D611, 0x580F5512, 0x4B5FA6E6, 0xB93425E5, 0x6DFE410E, 0x9F95C20D, 0x8CC531F9, 0x7EAEB2FA,
    0x30E349B1, 0xC288CAB2, 0xD1D83946, 0x23B3BA45, 0xF779DEAE, 0x05125DAD, 0x1642AE59, 0xE4292D5A,
    0xBA3A117E, 0x4851927D, 0x5B016189, 0xA96AE28A, 0x7DA08661, 0x8FCB0562, 0x9C9BF696, 0x6EF07595,
    0x417B1DBC, 0xB3109EBF, 0xA0406D4B, 0x522BEE48, 0x86E18AA3, 0x748A09A0, 0x67DAFA54, 0x95B17957,
    0xCBA24573, 0x39C9C670, 0x2A993584, 0xD8F2B687, 0x0C38D26C, 0xFE53516F, 0xED03A29B, 0x1F682198,
    0x5125DAD3, 0xA34E59D0, 0xB01EAA24, 0x42752927, 0x96BF4DCC, 0x64D4CECF, 0x77843D3B, 0x85EFBE38,
    0xDBFC821C, 0x2997011F, 0x3AC7F2EB, 0xC8AC71E8, 0x1C661503, 0xEE0D9600, 0xFD5D65F4, 0x0F36E6F7,
    0x61C69362, 0x93AD1061, 0x80FDE395, 0x72966096, 0xA65C047D, 0x5437877E, 0x4767748A, 0xB50CF789,
    0xEB1FCBAD, 0x197448AE, 0x0A24BB5A, 0xF84F3859, 0x2C855CB2, 0xDEEEDFB1, 0xCDBE2C45, 0x3FD5AF46,
    0x7198540D, 0x83F3D70E, 0x90A324FA, 0x62C8A7F9, 0xB602C312, 0x44694011, 0x5739B3E5, 0xA55230E6,
    0xFB410CC2, 0x092A8FC1, 0x1A7A7C35, 0xE811FF36, 0x3CDB9BDD, 0xCEB018DE, 0xDDE0EB2A, 0x2F8B6829,
    0x82F63B78, 0x709DB87B, 0x63CD4B8F, 0x91A6C88C, 0x456CAC67, 0xB7072F64, 0xA457DC90, 0x563C5F93,
    0x082F63B7, 0xFA44E0B4, 0xE9141340, 0x1B7F9043, 0xCFB5F4A8, 0x3DDE77AB, 0x2E8E845F, 0xDCE5075C,
    0x92A8FC17, 0x60C37F14, 0x73938CE0, 0x81F80FE3, 0x55326B08, 0xA759E80B, 0xB4091BFF, 0x466298FC,
    0x1871A4D8, 0xEA1A27DB, 0xF94AD42F, 0x0B21572C, 0xDFEB33C7, 0x2D80B0C4, 0x3ED04330, 0xCCBBC033,
    0xA24BB5A6, 0x502036A5, 0x4370C551, 0xB11B4652, 0x65D122B9, 0x97BAA1BA, 0x84EA524E, 0x7681D14D,
    0x2892ED69, 0xDAF96E6A, 0xC9A99D9E, 0x3BC21E9D, 0xEF087A76, 0x1D63F975, 0x0E330A81, 0xFC588982,
    0xB21572C9, 0x407EF1CA, 0x532E023E, 0xA145813D, 0x758FE5D6, 0x87E466D5, 0x94B49521, 0x66DF1622,
    0x38CC2A06, 0xCAA7A905, 0xD9F75AF1, 0x2B9CD9F2, 0xFF56BD19, 0x0D3D3E1A, 0x1E6DCDEE, 0xEC064EED,
    0xC38D26C4, 0x31E6A5C7, 0x22B65633, 0xD0DDD530, 0x0417B1DB, 0xF67C32D8, 0xE52CC12C, 0x1747422F,
    0x49547E0B, 0xBB3FFD08, 0xA86F0EFC, 0x5A048DFF, 0x8ECEE914, 0x7CA56A17, 0x6FF599E3, 0x9D9E1AE0,
    0xD3D3E1AB, 0x21B862A8, 0x32E8915C, 0xC083125F, 0x144976B4, 0xE622F5B7, 0xF5720643, 0x07198540,
    0x590AB964, 0xAB613A67, 0xB831C993, 0x4A5A4A90, 0x9E902E7B, 0x6CFBAD78, 0x7FAB5E8C, 0x8DC0DD8F,
    0xE330A81A, 0x115B2B19, 0x020BD8ED, 0xF0605BEE, 0x24AA3F05, 0xD6C1BC06, 0xC5914FF2, 0x37FACCF1,
    0x69E9F0D5, 0x9B8273D6, 0x88D28022, 0x7AB90321, 0xAE7367CA, 0x5C18E4C9, 0x4F48173D, 0xBD23943E,
    0xF36E6F75, 0x0105EC76, 0x12551F82, 0xE03E9C81, 0x34F4F86A, 0xC69F7B69, 0xD5CF889D, 0x27A40B9E,
    0x79B737BA, 0x8BDCB4B9, 0x988C474D, 0x6AE7C44E, 0xBE2DA0A5, 0x4C4623A6, 0x5F16D052, 0xAD7D5351,
};

fn crc32_hasher(seed: u32, key: ?*const anyopaque, key_len: u32) callconv(.c) u32 {
    var crc: u32 = seed;
    if (key) |k| {
        const s: [*]const u8 = @ptrCast(k);
        var i: u32 = 0;
        while (i < key_len) : (i += 1) {
            const byte: u32 = s[i];
            crc = crc32_tab[(crc ^ byte) & 0xFF] ^ (crc >> 8);
        }
    }
    // Murmur3-style mix
    crc ^= key_len;
    crc ^= crc >> 16;
    crc *%= 0x85ebca6b;
    crc ^= crc >> 13;
    crc *%= 0xc2b2ae35;
    crc ^= crc >> 16;
    return crc;
}

fn memcmp_comparer(a: ?*const anyopaque, a_len: u32, b: ?*const anyopaque, b_len: u32) callconv(.c) c_int {
    if (a_len != b_len) return 0;
    const ap: [*]const u8 = @ptrCast(a orelse return 0);
    const bp: [*]const u8 = @ptrCast(b orelse return 0);
    var i: u32 = 0;
    while (i < a_len) : (i += 1) if (ap[i] != bp[i]) return 0;
    return 1;
}

inline fn capacityOf(m: *const hashmap_s) u32 {
    return @as(u32, 1) << @intCast(m.log2_capacity);
}

fn hashHelperInt(m: *const hashmap_s, k: ?*const anyopaque, l: u32) u32 {
    const h = m.hasher.?(U32_MAX, k, l);
    // log2_capacity is in [1, 31] after create_ex; shift therefore fits u5.
    const shift: u5 = @intCast(32 - m.log2_capacity);
    return (h *% 2654435769) >> shift;
}

fn hashHelper(m: *const hashmap_s, key: ?*const anyopaque, len: u32, out_index: *u32) bool {
    if (m.size == capacityOf(m)) return false;
    const data = m.data orelse return false;
    const curr = hashHelperInt(m, key, len);
    var first_free: u32 = U32_MAX;
    var i: u32 = 0;
    while (i < LINEAR_PROBE_LENGTH) : (i += 1) {
        const idx = curr + i;
        const slot = &data[idx];
        if (slot.in_use == 0) {
            if (first_free == U32_MAX or idx < first_free) first_free = idx;
        } else if (m.comparer.?(slot.key, slot.key_len, key, len) != 0) {
            out_index.* = idx;
            return true;
        }
    }
    if (first_free == U32_MAX) return false;
    out_index.* = first_free;
    return true;
}

fn rehashIterator(new_hash: ?*anyopaque, e: *hashmap_element_s) callconv(.c) c_int {
    const nh: *hashmap_s = @ptrCast(@alignCast(new_hash.?));
    const r = hashmap_put(nh, e.key, e.key_len, e.data);
    if (r > 0) return 1;
    return -1; // iterate_pairs removes the item
}

fn rehashHelper(m: *hashmap_s) c_int {
    var opts = hashmap_create_options_s{};
    opts.initial_capacity = capacityOf(m) *% 2;
    opts.hasher = m.hasher;
    if (opts.initial_capacity == 0) return 1;

    var new_m: hashmap_s = .{};
    const flag = hashmap_create_ex(opts, &new_m);
    if (flag != 0) return flag;

    const iter_flag = hashmap_iterate_pairs(m, rehashIterator, @ptrCast(&new_m));
    if (iter_flag != 0) return iter_flag;

    hashmap_destroy(m);
    m.* = new_m;
    return 0;
}

// ─── Exported C ABI ─────────────────────────────────────────────────────────

pub export fn hashmap_create(initial_capacity: u32, out_hashmap: *hashmap_s) callconv(.c) c_int {
    var opts = hashmap_create_options_s{};
    opts.initial_capacity = initial_capacity;
    return hashmap_create_ex(opts, out_hashmap);
}

pub export fn hashmap_create_ex(options: hashmap_create_options_s, out_hashmap: *hashmap_s) callconv(.c) c_int {
    var opts = options;
    if (opts.initial_capacity < 2) {
        opts.initial_capacity = 2;
    } else if ((opts.initial_capacity & (opts.initial_capacity -% 1)) != 0) {
        // Round up to the next power of two: 1 << (32 - clz(x))
        const clz_u32: u32 = @clz(opts.initial_capacity);
        opts.initial_capacity = @as(u32, 1) << @intCast(32 - clz_u32);
    }
    if (opts.hasher == null) opts.hasher = &crc32_hasher;
    if (opts.comparer == null) opts.comparer = &memcmp_comparer;

    const total: usize = @as(usize, opts.initial_capacity) + LINEAR_PROBE_LENGTH;
    const mem = libc.calloc(total, @sizeOf(hashmap_element_s)) orelse return 1;
    out_hashmap.data = @ptrCast(@alignCast(mem));

    const clz_u32: u32 = @clz(opts.initial_capacity);
    out_hashmap.log2_capacity = 31 - clz_u32;
    out_hashmap.size = 0;
    out_hashmap.hasher = opts.hasher;
    out_hashmap.comparer = opts.comparer;
    return 0;
}

pub export fn hashmap_put(
    hashmap: *hashmap_s,
    key: ?*const anyopaque,
    len: u32,
    value: ?*anyopaque,
) callconv(.c) c_int {
    if (key == null or len == 0) return 1;
    var index: u32 = 0;
    while (!hashHelper(hashmap, key, len, &index)) {
        if (rehashHelper(hashmap) != 0) return 1;
    }
    const data = hashmap.data orelse return 1;
    const slot = &data[index];
    slot.data = value;
    slot.key = key;
    slot.key_len = len;
    if (slot.in_use == 0) {
        slot.in_use = 1;
        hashmap.size += 1;
    }
    return 0;
}

pub export fn hashmap_get(
    hashmap: *const hashmap_s,
    key: ?*const anyopaque,
    len: u32,
) callconv(.c) ?*anyopaque {
    if (key == null or len == 0) return null;
    const data = hashmap.data orelse return null;
    const curr = hashHelperInt(hashmap, key, len);
    var i: u32 = 0;
    while (i < LINEAR_PROBE_LENGTH) : (i += 1) {
        const slot = &data[curr + i];
        if (slot.in_use != 0 and hashmap.comparer.?(slot.key, slot.key_len, key, len) != 0) {
            return slot.data;
        }
    }
    return null;
}

pub export fn hashmap_remove(
    hashmap: *hashmap_s,
    key: ?*const anyopaque,
    len: u32,
) callconv(.c) c_int {
    if (key == null or len == 0) return 1;
    const data = hashmap.data orelse return 1;
    const curr = hashHelperInt(hashmap, key, len);
    var i: u32 = 0;
    while (i < LINEAR_PROBE_LENGTH) : (i += 1) {
        const slot = &data[curr + i];
        if (slot.in_use != 0 and hashmap.comparer.?(slot.key, slot.key_len, key, len) != 0) {
            slot.* = .{};
            hashmap.size -= 1;
            return 0;
        }
    }
    return 1;
}

pub export fn hashmap_remove_and_return_key(
    hashmap: *hashmap_s,
    key: ?*const anyopaque,
    len: u32,
) callconv(.c) ?*const anyopaque {
    if (key == null or len == 0) return null;
    const data = hashmap.data orelse return null;
    const curr = hashHelperInt(hashmap, key, len);
    var i: u32 = 0;
    while (i < LINEAR_PROBE_LENGTH) : (i += 1) {
        const slot = &data[curr + i];
        if (slot.in_use != 0 and hashmap.comparer.?(slot.key, slot.key_len, key, len) != 0) {
            const stored = slot.key;
            slot.* = .{};
            hashmap.size -= 1;
            return stored;
        }
    }
    return null;
}

pub export fn hashmap_iterate(
    hashmap: *const hashmap_s,
    iterator: ?*const fn (ctx: ?*anyopaque, value: ?*anyopaque) callconv(.c) c_int,
    context: ?*anyopaque,
) callconv(.c) c_int {
    const data = hashmap.data orelse return 0;
    const f = iterator orelse return 0;
    const total = capacityOf(hashmap) + LINEAR_PROBE_LENGTH;
    var i: u32 = 0;
    while (i < total) : (i += 1) {
        if (data[i].in_use != 0) {
            if (f(context, data[i].data) == 0) return 1;
        }
    }
    return 0;
}

pub export fn hashmap_iterate_pairs(
    hashmap: *hashmap_s,
    iterator: ?*const fn (ctx: ?*anyopaque, e: *hashmap_element_s) callconv(.c) c_int,
    context: ?*anyopaque,
) callconv(.c) c_int {
    const data = hashmap.data orelse return 0;
    const f = iterator orelse return 0;
    const total = capacityOf(hashmap) + LINEAR_PROBE_LENGTH;
    var i: u32 = 0;
    while (i < total) : (i += 1) {
        const slot = &data[i];
        if (slot.in_use == 0) continue;
        const r = f(context, slot);
        switch (r) {
            -1 => {
                slot.* = .{};
                hashmap.size -= 1;
            },
            0 => {},
            else => return 1,
        }
    }
    return 0;
}

pub export fn hashmap_destroy(hashmap: *hashmap_s) callconv(.c) void {
    if (hashmap.data) |d| libc.free(@ptrCast(d));
    hashmap.* = .{};
}

pub export fn hashmap_num_entries(hashmap: *const hashmap_s) callconv(.c) u32 {
    return hashmap.size;
}

pub export fn hashmap_capacity(hashmap: *const hashmap_s) callconv(.c) u32 {
    return capacityOf(hashmap);
}
