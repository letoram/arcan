// Pure Zig port of posix/random.c
// Thread-local ChaCha8 CSPRNG seeded from OS entropy (getrandom).
// Replaces the C chacha.c implementation with std.crypto.stream.chacha.

const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);

extern fn arcan_fatal(msg: [*c]const u8, ...) callconv(.c) void;

const ChaCha8IETF = std.crypto.stream.chacha.ChaCha8IETF;

/// Thread-local CSPRNG state: a ChaCha8 cipher seeded lazily from OS entropy.
const CsprngState = struct {
    ready: bool = false,
    /// Buffered keystream for partial-block requests.
    buf: [64]u8 = undefined,
    buf_pos: usize = 64, // start exhausted so first call generates a block
    /// ChaCha8 counter-mode state: key + nonce + block counter.
    key: [32]u8 = undefined,
    nonce: [12]u8 = undefined,
    counter: u32 = 0,

    fn seed(self: *CsprngState) void {
        var seed_buf: [32]u8 = undefined;
        if (is_freestanding) {
            // On freestanding, zero-seed (no OS entropy available)
            @memset(&seed_buf, 0);
        } else {
            seed_from_os(&seed_buf);
        }

        self.key = seed_buf;
        self.nonce = .{ 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
        self.counter = 0;
        self.buf_pos = 64; // mark buffer as exhausted
        self.ready = true;
    }

    /// Generate one 64-byte keystream block into `out`.
    fn generateBlock(self: *CsprngState, out: *[64]u8) void {
        // ChaCha8IETF.xor produces keystream when XOR'd with zeros
        const zeros: [64]u8 = .{0} ** 64;
        ChaCha8IETF.xor(out, &zeros, self.counter, self.key, self.nonce);
        self.counter +%= 1;
    }

    /// Fill `dst` with random bytes from the keystream.
    fn fill(self: *CsprngState, dst: []u8) void {
        var remaining = dst;

        // First, drain any leftover bytes from the internal buffer
        if (self.buf_pos < 64) {
            const avail = 64 - self.buf_pos;
            const take = @min(avail, remaining.len);
            @memcpy(remaining[0..take], self.buf[self.buf_pos..][0..take]);
            self.buf_pos += take;
            remaining = remaining[take..];
        }

        // Generate full 64-byte blocks directly into the output
        while (remaining.len >= 64) {
            self.generateBlock(remaining[0..64]);
            remaining = remaining[64..];
        }

        // Handle the tail: generate a block, copy what we need, buffer the rest
        if (remaining.len > 0) {
            self.generateBlock(&self.buf);
            @memcpy(remaining, self.buf[0..remaining.len]);
            self.buf_pos = remaining.len;
        }
    }
};

fn seed_from_os(seed_buf: *[32]u8) void {
    // Try OS CSPRNG (getrandom syscall on Linux)
    std.posix.getrandom(seed_buf) catch {
        // Fallback: /dev/urandom
        const f = std.fs.openFileAbsolute("/dev/urandom", .{}) catch {
            arcan_fatal("couldn't seed CSPRNG, system not in a safe state\n");
            unreachable;
        };
        defer f.close();
        const nread = f.read(seed_buf) catch {
            arcan_fatal("couldn't seed CSPRNG, system not in a safe state\n");
            unreachable;
        };
        if (nread != seed_buf.len) {
            arcan_fatal("couldn't seed CSPRNG, system not in a safe state\n");
            unreachable;
        }
    };
}

threadlocal var state: CsprngState = .{};

export fn arcan_random(dst: [*]u8, ntc: usize) callconv(.c) void {
    if (!state.ready) state.seed();
    state.fill(dst[0..ntc]);
}
