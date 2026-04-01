const std = @import("std");

/// SHA-256 hash function per FIPS 180-4.
/// Produces a 256-bit (32-byte) message digest.
pub const Sha256 = struct {
    state: [8]u32,
    buffer: [64]u8,
    buffer_len: usize,
    total_len: u64,

    /// Initial hash values: first 32 bits of fractional parts of
    /// the square roots of the first 8 primes (2..19).
    const H0 = [8]u32{
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    };

    /// Round constants: first 32 bits of fractional parts of
    /// the cube roots of the first 64 primes (2..311).
    const K = [64]u32{
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    };

    pub fn init() Sha256 {
        return .{
            .state = H0,
            .buffer = undefined,
            .buffer_len = 0,
            .total_len = 0,
        };
    }

    pub fn update(self: *Sha256, data: []const u8) void {
        var input = data;
        self.total_len += input.len;

        // If we have buffered data, try to complete a block
        if (self.buffer_len > 0) {
            const needed = 64 - self.buffer_len;
            if (input.len >= needed) {
                @memcpy(self.buffer[self.buffer_len..64], input[0..needed]);
                self.processBlock(&self.buffer);
                input = input[needed..];
                self.buffer_len = 0;
            } else {
                @memcpy(self.buffer[self.buffer_len .. self.buffer_len + input.len], input);
                self.buffer_len += input.len;
                return;
            }
        }

        // Process complete blocks
        while (input.len >= 64) {
            self.processBlock(input[0..64]);
            input = input[64..];
        }

        // Buffer remaining bytes
        if (input.len > 0) {
            @memcpy(self.buffer[0..input.len], input);
            self.buffer_len = input.len;
        }
    }

    pub fn final(self: *Sha256) [32]u8 {
        // Padding: append 1 bit, then zeros, then 64-bit length
        const total_bits: u64 = self.total_len * 8;

        // Append the 0x80 byte
        self.buffer[self.buffer_len] = 0x80;
        self.buffer_len += 1;

        // If not enough room for length (need 8 bytes), pad and process
        if (self.buffer_len > 56) {
            @memset(self.buffer[self.buffer_len..64], 0);
            self.processBlock(&self.buffer);
            self.buffer_len = 0;
        }

        // Pad with zeros up to byte 56
        @memset(self.buffer[self.buffer_len..56], 0);

        // Append length in bits as big-endian u64
        self.buffer[56] = @truncate(total_bits >> 56);
        self.buffer[57] = @truncate(total_bits >> 48);
        self.buffer[58] = @truncate(total_bits >> 40);
        self.buffer[59] = @truncate(total_bits >> 32);
        self.buffer[60] = @truncate(total_bits >> 24);
        self.buffer[61] = @truncate(total_bits >> 16);
        self.buffer[62] = @truncate(total_bits >> 8);
        self.buffer[63] = @truncate(total_bits);

        self.processBlock(&self.buffer);

        // Produce output
        var result: [32]u8 = undefined;
        for (self.state, 0..) |s, i| {
            result[i * 4 + 0] = @truncate(s >> 24);
            result[i * 4 + 1] = @truncate(s >> 16);
            result[i * 4 + 2] = @truncate(s >> 8);
            result[i * 4 + 3] = @truncate(s);
        }
        return result;
    }

    /// Convenience: hash a single slice in one call.
    pub fn hash(data: []const u8) [32]u8 {
        var h = Sha256.init();
        h.update(data);
        return h.final();
    }

    fn processBlock(self: *Sha256, block: *const [64]u8) void {
        var w: [64]u32 = undefined;

        // Prepare message schedule
        for (0..16) |i| {
            w[i] = (@as(u32, block[i * 4]) << 24) |
                (@as(u32, block[i * 4 + 1]) << 16) |
                (@as(u32, block[i * 4 + 2]) << 8) |
                @as(u32, block[i * 4 + 3]);
        }
        for (16..64) |i| {
            const s0 = rightRotate(w[i - 15], 7) ^ rightRotate(w[i - 15], 18) ^ (w[i - 15] >> 3);
            const s1 = rightRotate(w[i - 2], 17) ^ rightRotate(w[i - 2], 19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16] +% s0 +% w[i - 7] +% s1;
        }

        // Initialize working variables
        var a = self.state[0];
        var b = self.state[1];
        var c = self.state[2];
        var d = self.state[3];
        var e = self.state[4];
        var f = self.state[5];
        var g = self.state[6];
        var h = self.state[7];

        // Compression
        for (0..64) |i| {
            const s1 = rightRotate(e, 6) ^ rightRotate(e, 11) ^ rightRotate(e, 25);
            const ch = (e & f) ^ (~e & g);
            const temp1 = h +% s1 +% ch +% K[i] +% w[i];
            const s0 = rightRotate(a, 2) ^ rightRotate(a, 13) ^ rightRotate(a, 22);
            const maj = (a & b) ^ (a & c) ^ (b & c);
            const temp2 = s0 +% maj;

            h = g;
            g = f;
            f = e;
            e = d +% temp1;
            d = c;
            c = b;
            b = a;
            a = temp1 +% temp2;
        }

        // Add to state
        self.state[0] +%= a;
        self.state[1] +%= b;
        self.state[2] +%= c;
        self.state[3] +%= d;
        self.state[4] +%= e;
        self.state[5] +%= f;
        self.state[6] +%= g;
        self.state[7] +%= h;
    }

    fn rightRotate(x: u32, comptime n: u5) u32 {
        return (x >> n) | (x << (@as(u5, 32 - @as(u6, n))));
    }
};

// -- Tests --

test "sha256: empty string" {
    const result = Sha256.hash("");
    const expected = [_]u8{
        0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14,
        0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f, 0xb9, 0x24,
        0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c,
        0xa4, 0x95, 0x99, 0x1b, 0x78, 0x52, 0xb8, 0x55,
    };
    try std.testing.expectEqualSlices(u8, &expected, &result);
}

test "sha256: abc" {
    const result = Sha256.hash("abc");
    const expected = [_]u8{
        0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
        0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
        0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
        0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad,
    };
    try std.testing.expectEqualSlices(u8, &expected, &result);
}

test "sha256: deterministic" {
    const a = Sha256.hash("test data");
    const b = Sha256.hash("test data");
    try std.testing.expectEqualSlices(u8, &a, &b);
}

test "sha256: incremental update" {
    var h = Sha256.init();
    h.update("ab");
    h.update("c");
    const incremental = h.final();
    const oneshot = Sha256.hash("abc");
    try std.testing.expectEqualSlices(u8, &oneshot, &incremental);
}

test "sha256: long message" {
    // SHA-256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
    const result = Sha256.hash("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq");
    const expected = [_]u8{
        0x24, 0x8d, 0x6a, 0x61, 0xd2, 0x06, 0x38, 0xb8,
        0xe5, 0xc0, 0x26, 0x93, 0x0c, 0x3e, 0x60, 0x39,
        0xa3, 0x3c, 0xe4, 0x59, 0x64, 0xff, 0x21, 0x67,
        0xf6, 0xec, 0xed, 0xd4, 0x19, 0xdb, 0x06, 0xc1,
    };
    try std.testing.expectEqualSlices(u8, &expected, &result);
}
