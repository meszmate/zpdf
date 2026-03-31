const std = @import("std");

/// RC4 stream cipher implementation.
/// Encrypts or decrypts `data` using `key`, writing the result to `output`.
/// Since RC4 is symmetric, encryption and decryption are the same operation.
/// The caller must ensure `output.len >= data.len`.
pub fn rc4(key: []const u8, data: []const u8, output: []u8) void {
    std.debug.assert(output.len >= data.len);
    std.debug.assert(key.len > 0);

    // KSA: Key Scheduling Algorithm
    var s: [256]u8 = undefined;
    for (0..256) |i| {
        s[i] = @intCast(i);
    }

    var j: u8 = 0;
    for (0..256) |i| {
        j = j +% s[i] +% key[i % key.len];
        std.mem.swap(u8, &s[i], &s[j]);
    }

    // PRGA: Pseudo-Random Generation Algorithm
    var si: u8 = 0;
    var sj: u8 = 0;
    for (data, 0..) |byte, idx| {
        si = si +% 1;
        sj = sj +% s[si];
        std.mem.swap(u8, &s[si], &s[sj]);
        const k = s[s[si] +% s[sj]];
        output[idx] = byte ^ k;
    }
}

// -- Tests --

test "rc4: encrypt and decrypt roundtrip" {
    const key = "SecretKey";
    const plaintext = "Hello, World!";
    var encrypted: [plaintext.len]u8 = undefined;
    var decrypted: [plaintext.len]u8 = undefined;

    rc4(key, plaintext, &encrypted);
    // Encrypted text should differ from plaintext
    try std.testing.expect(!std.mem.eql(u8, plaintext, &encrypted));

    rc4(key, &encrypted, &decrypted);
    try std.testing.expectEqualSlices(u8, plaintext, &decrypted);
}

test "rc4: empty data" {
    const key = "key";
    var output: [0]u8 = .{};
    rc4(key, &[_]u8{}, &output);
}

test "rc4: known test vector" {
    // RC4 test vector: Key = "Key", Plaintext = "Plaintext"
    const key = "Key";
    const plaintext = "Plaintext";
    var output: [plaintext.len]u8 = undefined;
    rc4(key, plaintext, &output);

    // RC4("Key", "Plaintext") = BBF316E8D940AF0AD3
    const expected = [_]u8{ 0xBB, 0xF3, 0x16, 0xE8, 0xD9, 0x40, 0xAF, 0x0A, 0xD3 };
    try std.testing.expectEqualSlices(u8, &expected, &output);
}
