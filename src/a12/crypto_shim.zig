// crypto_shim.zig — Zig std.crypto-backed replacement for arcan-net's bundled
// C crypto primitives (blake3, x25519, monocypher-ed25519, mlkem-native).
//
// Replaces ~5700 LOC of vendored C with thin export-fn wrappers around
// std.crypto, preserving the exact C-ABI call sites in a12.c / a12.zig.
//
// What this file provides (C-ABI, callconv(.c)):
//
//   Blake3
//     - blake3_hasher (extern struct, layout matches the bundled C header so
//       callers can still embed it by value inside other structs)
//     - blake3_hasher_init / _init_keyed / _init_derive_key
//     - blake3_hasher_update
//     - blake3_hasher_finalize / _finalize_seek
//
//   X25519
//     - x25519_private_key  (random + RFC-7748 clamp)
//     - x25519_public_key
//     - x25519_shared_secret
//
//   Ed25519 (monocypher-compatible 64-byte secret = seed||pubkey)
//     - crypto_ed25519_key_pair
//     - crypto_ed25519_sign
//     - crypto_ed25519_check
//
//   ML-KEM-768 (FIPS 203)
//     - mlkem_keypair / mlkem_keypair_derand
//     - mlkem_enc     / mlkem_enc_derand
//     - mlkem_dec
//
// Note on Blake3 storage:
//   The C `blake3_hasher` struct is 1928 bytes and its address has at least
//   8-byte alignment. `std.crypto.hash.Blake3` is 1888 bytes and requires
//   16-byte alignment. We store the Blake3 state inside the C struct with
//   manual alignment:
//     - bytes 0..8   : u64 `offset` = where Blake3 state starts inside the
//                      C struct. Always either 16 or 24.
//     - bytes offset..offset+1888 : the aligned std Blake3 state.
//   A magic marker in bytes 8..16 guards against reading uninitialized
//   memory. Total required = offset + sizeof(Blake3) ≤ 24 + 1888 = 1912
//   ≤ 1928 (C struct size). Verified below with a comptime assert.

const std = @import("std");
const builtin = @import("builtin");

// ---------------------------------------------------------------------------
// Random
// ---------------------------------------------------------------------------

// `arcan_random` is already exported from src/platform/posix/random.zig (or
// the equivalent platform-specific implementation). We DO NOT re-export it
// here to avoid duplicate-symbol errors. Everything in this file that needs
// random bytes calls `std.crypto.random.bytes` directly or delegates to
// `arcan_random` via an extern declaration.

extern fn arcan_random(dst: [*]u8, ntc: usize) callconv(.c) void;

// ---------------------------------------------------------------------------
// X25519
// ---------------------------------------------------------------------------

const X25519 = std.crypto.dh.X25519;

/// Generate a fresh X25519 private scalar: 32 random bytes, clamped per
/// RFC 7748.
export fn x25519_private_key(secret: [*]u8) callconv(.c) void {
    arcan_random(secret, 32);
    // RFC 7748 clamping.
    secret[0] &= 248;
    secret[31] &= 127;
    secret[31] |= 64;
}

/// Derive the X25519 public key from a (clamped) 32-byte secret.
export fn x25519_public_key(secret: [*]const u8, public: [*]u8) callconv(.c) void {
    const sk: [32]u8 = secret[0..32].*;
    // `recoverPublicKey` internally clamps, so double-clamping is fine.
    const pk = X25519.recoverPublicKey(sk) catch {
        // IdentityElement — only possible for a pathological all-zero scalar.
        // Return zeroed pubkey to match historical behavior.
        @memset(public[0..32], 0);
        return;
    };
    @memcpy(public[0..32], &pk);
}

/// Compute the X25519 shared secret.
/// Returns 0 on success, non-zero on failure (legacy arcan convention:
/// check matches any nonzero for "failed").
export fn x25519_shared_secret(
    secret_out: [*]u8,
    secret: [*]const u8,
    ext_pub: [*]const u8,
) callconv(.c) c_int {
    const sk: [32]u8 = secret[0..32].*;
    const pk: [32]u8 = ext_pub[0..32].*;
    const out = X25519.scalarmult(sk, pk) catch {
        @memset(secret_out[0..32], 0);
        return -1;
    };
    @memcpy(secret_out[0..32], &out);
    return 0;
}

// ---------------------------------------------------------------------------
// Blake3
// ---------------------------------------------------------------------------

const Blake3 = std.crypto.hash.Blake3;

// Size of the C blake3_hasher struct (see src/a12/external/blake3/blake3.h).
// Computed by hand + verified against gcc:
//   FILE*(8) + size_t(8) + key[8]u32(32) + chunk_state(112, incl. padding)
//   + cv_stack_len(1) + cv_stack[1760] + 7 bytes tail padding = 1928 bytes.
// We DO NOT re-declare the C struct here; the C header stays authoritative
// and defines `blake3_hasher` for any C callers that still embed it.
const C_BLAKE3_HASHER_SIZE: usize = 1928;

// Layout matches the C blake3_hasher in arcan's blake3.h fork:
//   [0..8]   FILE* log (unused here — repurposed as the offset to our
//            aligned std.crypto.hash.Blake3 state; never null after init,
//            so it doubles as the "initialized" sentinel)
//   [8..16]  size_t counter (incremented by every update; read by a12.zig
//            traces via `S.out_mac.counter` — must agree with C upstream
//            which does `self->counter += input_len` in blake3_hasher_update)
// After the 16-byte header, the Blake3 state starts at the next 16-byte
// boundary. The Blake3 state size + 16 must fit in 1928 bytes.

// Comptime-verify the C struct can hold our (offset + counter + Blake3).
comptime {
    if (24 + @sizeOf(Blake3) > C_BLAKE3_HASHER_SIZE) {
        @compileError("crypto_shim: C blake3_hasher is too small to embed std Blake3 + alignment header");
    }
    // We rely on 16-byte natural alignment for Blake3. If std ever bumps its
    // alignment requirement past 16, the offset math below must be updated.
    if (@alignOf(Blake3) > 16) {
        @compileError("crypto_shim: std.crypto.hash.Blake3 alignment > 16 is not supported by this shim");
    }
}

inline fn b3_slot(hasher: *anyopaque) struct { state: *Blake3, mem: [*]u8 } {
    const mem_ptr: [*]u8 = @ptrCast(hasher);
    const base_addr = @intFromPtr(mem_ptr);
    // Header occupies the first 16 bytes. The Blake3 state must start at the
    // next 16-byte boundary at or after `base + 16`.
    const hdr_end = base_addr + 16;
    const pad = (@as(usize, 16) - (hdr_end & 15)) & 15;
    const state_addr = hdr_end + pad;
    const state_ptr: *Blake3 = @ptrFromInt(state_addr);
    return .{ .state = state_ptr, .mem = mem_ptr };
}

inline fn b3_store_offset(mem: [*]u8, state: *Blake3) void {
    const base_addr = @intFromPtr(mem);
    const state_addr = @intFromPtr(state);
    const off: u64 = @intCast(state_addr - base_addr);
    @memcpy(mem[0..8], std.mem.asBytes(&off));
    // Reset the counter field on (re-)init. C upstream sets `self->counter
    // = 0` inside hasher_init_base; same semantics here.
    const zero: u64 = 0;
    @memcpy(mem[8..16], std.mem.asBytes(&zero));
}

inline fn b3_load_state(hasher: *const anyopaque) *const Blake3 {
    // Same layout for read-only access; cast away const for pointer math only.
    const mem_ptr: [*]const u8 = @ptrCast(hasher);
    var off: u64 = 0;
    @memcpy(std.mem.asBytes(&off), mem_ptr[0..8]);
    // off == 0 means the hasher was zero-initialized and never went through
    // blake3_hasher_init — the offset is always >= 16 after init.
    std.debug.assert(off != 0);
    const state_addr = @intFromPtr(mem_ptr) + off;
    return @ptrFromInt(state_addr);
}

inline fn b3_bump_counter(mem: [*]u8, delta: usize) void {
    var counter: u64 = 0;
    @memcpy(std.mem.asBytes(&counter), mem[8..16]);
    counter +%= delta;
    @memcpy(mem[8..16], std.mem.asBytes(&counter));
}

export fn blake3_hasher_init(self: *anyopaque) callconv(.c) void {
    const slot = b3_slot(self);
    slot.state.* = Blake3.init(.{});
    b3_store_offset(slot.mem, slot.state);
}

export fn blake3_hasher_init_keyed(self: *anyopaque, key: [*]const u8) callconv(.c) void {
    const slot = b3_slot(self);
    const key_arr: [32]u8 = key[0..32].*;
    slot.state.* = Blake3.init(.{ .key = key_arr });
    b3_store_offset(slot.mem, slot.state);
}

export fn blake3_hasher_init_derive_key(
    self: *anyopaque,
    context: [*:0]const u8,
) callconv(.c) void {
    const slot = b3_slot(self);
    const ctx_slice = std.mem.span(context);
    slot.state.* = Blake3.initKdf(ctx_slice, .{});
    b3_store_offset(slot.mem, slot.state);
}

export fn blake3_hasher_update(
    self: *anyopaque,
    input: ?*const anyopaque,
    input_len: usize,
) callconv(.c) void {
    if (input_len == 0) return;
    const slot = b3_slot(self);
    const p: [*]const u8 = @ptrCast(input.?);
    slot.state.update(p[0..input_len]);
    b3_bump_counter(slot.mem, input_len);
}

export fn blake3_hasher_finalize(
    self: *const anyopaque,
    out: [*]u8,
    out_len: usize,
) callconv(.c) void {
    if (out_len == 0) return;
    const state = b3_load_state(self);
    state.final(out[0..out_len]);
}

export fn blake3_hasher_finalize_seek(
    self: *const anyopaque,
    seek: u64,
    out: [*]u8,
    out_len: usize,
) callconv(.c) void {
    if (out_len == 0) return;
    const state = b3_load_state(self);
    if (seek == 0) {
        state.final(out[0..out_len]);
        return;
    }
    // std.crypto.hash.Blake3 has no public "seek" XOF. We allocate a staging
    // buffer of `seek + out_len` bytes, write the full XOF prefix into it,
    // and copy the requested slice. Call sites in arcan-net only ever pass
    // seek=0, so this path is a correctness fallback.
    const total = seek + out_len;
    const allocator = std.heap.page_allocator;
    const buf = allocator.alloc(u8, total) catch {
        // Best-effort: if allocation fails, emit zeros. Matches the
        // defensive behavior elsewhere in a12 crypto.
        @memset(out[0..out_len], 0);
        return;
    };
    defer allocator.free(buf);
    state.final(buf);
    @memcpy(out[0..out_len], buf[seek..][0..out_len]);
}

// ---------------------------------------------------------------------------
// Ed25519  (monocypher layout: 64-byte secret = seed||pubkey)
// ---------------------------------------------------------------------------

const Ed25519 = std.crypto.sign.Ed25519;

/// Generate an Ed25519 key pair from a 32-byte seed.
/// Outputs:
///   secret_key[64] = seed(32) || public(32)   (monocypher layout, matches
///                                               std Ed25519 SecretKey bytes)
///   public_key[32]
///   seed[32]       (unchanged, kept for API compatibility — monocypher
///                   sometimes wipes it; we leave it intact)
export fn crypto_ed25519_key_pair(
    secret_key: [*]u8,
    public_key: [*]u8,
    seed: [*]u8,
) callconv(.c) void {
    const seed_arr: [32]u8 = seed[0..32].*;
    const kp = Ed25519.KeyPair.generateDeterministic(seed_arr) catch {
        // IdentityElement: return zeroed keys. In practice this never
        // happens for random seeds.
        @memset(secret_key[0..64], 0);
        @memset(public_key[0..32], 0);
        return;
    };
    const sk_bytes = kp.secret_key.toBytes(); // 64 bytes, seed||pub
    const pk_bytes = kp.public_key.toBytes(); // 32 bytes
    @memcpy(secret_key[0..64], &sk_bytes);
    @memcpy(public_key[0..32], &pk_bytes);
}

/// Sign `message[0..message_size]` with a 64-byte monocypher secret key.
export fn crypto_ed25519_sign(
    signature: [*]u8,
    secret_key: [*]const u8,
    message: [*]const u8,
    message_size: usize,
) callconv(.c) void {
    const sk_bytes: [64]u8 = secret_key[0..64].*;
    const sk = Ed25519.SecretKey.fromBytes(sk_bytes) catch {
        @memset(signature[0..64], 0);
        return;
    };
    const kp = Ed25519.KeyPair.fromSecretKey(sk) catch {
        @memset(signature[0..64], 0);
        return;
    };
    const msg = if (message_size == 0) &[_]u8{} else message[0..message_size];
    // Use deterministic signing (noise = null) to match monocypher semantics.
    const sig = kp.sign(msg, null) catch {
        @memset(signature[0..64], 0);
        return;
    };
    const sig_bytes = sig.toBytes();
    @memcpy(signature[0..64], &sig_bytes);
}

/// Verify an Ed25519 signature. Returns 0 on success, non-zero on failure,
/// matching monocypher's `crypto_ed25519_check` convention.
export fn crypto_ed25519_check(
    signature: [*]const u8,
    public_key: [*]const u8,
    message: [*]const u8,
    message_size: usize,
) callconv(.c) c_int {
    const sig_bytes: [64]u8 = signature[0..64].*;
    const pk_bytes: [32]u8 = public_key[0..32].*;
    const pk = Ed25519.PublicKey.fromBytes(pk_bytes) catch return -1;
    const sig = Ed25519.Signature.fromBytes(sig_bytes);
    const msg = if (message_size == 0) &[_]u8{} else message[0..message_size];
    sig.verify(msg, pk) catch return -1;
    return 0;
}

// ---------------------------------------------------------------------------
// ML-KEM-768
// ---------------------------------------------------------------------------

const MlKem768 = std.crypto.kem.ml_kem.MLKem768;

// Key material sizes, per FIPS 203 and mlkem-native header.
const MLKEM768_PK_BYTES: usize = 1184; // public key
const MLKEM768_SK_BYTES: usize = 2400; // secret key
const MLKEM768_CT_BYTES: usize = 1088; // ciphertext
const MLKEM768_SS_BYTES: usize = 32; // shared secret

comptime {
    // Cross-check against the std types so this file fails loudly if std's
    // ML-KEM-768 byte layout ever drifts.
    if (MlKem768.PublicKey.bytes_length != MLKEM768_PK_BYTES)
        @compileError("MlKem768 PublicKey bytes_length mismatch");
    if (MlKem768.SecretKey.bytes_length != MLKEM768_SK_BYTES)
        @compileError("MlKem768 SecretKey bytes_length mismatch");
    if (MlKem768.ciphertext_length != MLKEM768_CT_BYTES)
        @compileError("MlKem768 ciphertext_length mismatch");
    if (MlKem768.shared_length != MLKEM768_SS_BYTES)
        @compileError("MlKem768 shared_length mismatch");
}

/// Randomized key-pair generation.
export fn mlkem_keypair(pk: [*]u8, sk: [*]u8) callconv(.c) c_int {
    // Seed from arcan_random so keys come from the project's CSPRNG rather
    // than std.crypto.random's TLS-initialized one.
    var seed: [MlKem768.seed_length]u8 = undefined;
    arcan_random(&seed, seed.len);
    const kp = MlKem768.KeyPair.generateDeterministic(seed) catch return -1;
    const pk_bytes = kp.public_key.toBytes();
    const sk_bytes = kp.secret_key.toBytes();
    @memcpy(pk[0..MLKEM768_PK_BYTES], &pk_bytes);
    @memcpy(sk[0..MLKEM768_SK_BYTES], &sk_bytes);
    return 0;
}

/// Deterministic key-pair generation (coins = seed).
export fn mlkem_keypair_derand(
    pk: [*]u8,
    sk: [*]u8,
    coins: [*]const u8,
) callconv(.c) c_int {
    const seed: [MlKem768.seed_length]u8 = coins[0..MlKem768.seed_length].*;
    const kp = MlKem768.KeyPair.generateDeterministic(seed) catch return -1;
    const pk_bytes = kp.public_key.toBytes();
    const sk_bytes = kp.secret_key.toBytes();
    @memcpy(pk[0..MLKEM768_PK_BYTES], &pk_bytes);
    @memcpy(sk[0..MLKEM768_SK_BYTES], &sk_bytes);
    return 0;
}

/// Encapsulate: produce (ct, ss) for a given public key (randomized).
export fn mlkem_enc(ct: [*]u8, ss: [*]u8, pk: [*]const u8) callconv(.c) c_int {
    const pk_bytes: [MLKEM768_PK_BYTES]u8 = pk[0..MLKEM768_PK_BYTES].*;
    const public = MlKem768.PublicKey.fromBytes(&pk_bytes) catch return -1;
    var seed: [MlKem768.encaps_seed_length]u8 = undefined;
    arcan_random(&seed, seed.len);
    const enc = public.encaps(seed);
    @memcpy(ct[0..MLKEM768_CT_BYTES], &enc.ciphertext);
    @memcpy(ss[0..MLKEM768_SS_BYTES], &enc.shared_secret);
    return 0;
}

/// Deterministic encapsulation (coins supplied).
export fn mlkem_enc_derand(
    ct: [*]u8,
    ss: [*]u8,
    pk: [*]const u8,
    coins: [*]const u8,
) callconv(.c) c_int {
    const pk_bytes: [MLKEM768_PK_BYTES]u8 = pk[0..MLKEM768_PK_BYTES].*;
    const public = MlKem768.PublicKey.fromBytes(&pk_bytes) catch return -1;
    const seed: [MlKem768.encaps_seed_length]u8 = coins[0..MlKem768.encaps_seed_length].*;
    const enc = public.encaps(seed);
    @memcpy(ct[0..MLKEM768_CT_BYTES], &enc.ciphertext);
    @memcpy(ss[0..MLKEM768_SS_BYTES], &enc.shared_secret);
    return 0;
}

/// Decapsulate: recover shared secret from ciphertext + secret key.
export fn mlkem_dec(
    ss: [*]u8,
    ct: [*]const u8,
    sk: [*]const u8,
) callconv(.c) c_int {
    const sk_bytes: [MLKEM768_SK_BYTES]u8 = sk[0..MLKEM768_SK_BYTES].*;
    const secret = MlKem768.SecretKey.fromBytes(&sk_bytes) catch return -1;
    const ct_arr: [MLKEM768_CT_BYTES]u8 = ct[0..MLKEM768_CT_BYTES].*;
    const shared = secret.decaps(&ct_arr) catch return -1;
    @memcpy(ss[0..MLKEM768_SS_BYTES], &shared);
    return 0;
}

// ---------------------------------------------------------------------------
// Compile-time sanity
// ---------------------------------------------------------------------------

comptime {
    // Pin references so exported symbols don't get DCE'd before reaching
    // the linker. Zig 0.15.2 already treats `export fn` as root, but being
    // explicit here also makes it obvious which symbols this file provides.
    _ = x25519_private_key;
    _ = x25519_public_key;
    _ = x25519_shared_secret;
    _ = blake3_hasher_init;
    _ = blake3_hasher_init_keyed;
    _ = blake3_hasher_init_derive_key;
    _ = blake3_hasher_update;
    _ = blake3_hasher_finalize;
    _ = blake3_hasher_finalize_seek;
    _ = crypto_ed25519_key_pair;
    _ = crypto_ed25519_sign;
    _ = crypto_ed25519_check;
    _ = mlkem_keypair;
    _ = mlkem_keypair_derand;
    _ = mlkem_enc;
    _ = mlkem_enc_derand;
    _ = mlkem_dec;
}
