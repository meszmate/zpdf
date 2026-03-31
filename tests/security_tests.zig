const std = @import("std");
const zpdf = @import("zpdf");
const testing = std.testing;

const rc4 = zpdf.security.rc4.rc4;
const md5 = zpdf.security.md5.md5;

test "RC4: encrypt and decrypt roundtrip" {
    const key = "SecretKey";
    const plaintext = "Hello, World!";
    var encrypted: [plaintext.len]u8 = undefined;
    var decrypted: [plaintext.len]u8 = undefined;

    rc4(key, plaintext, &encrypted);
    try testing.expect(!std.mem.eql(u8, plaintext, &encrypted));

    rc4(key, &encrypted, &decrypted);
    try testing.expectEqualSlices(u8, plaintext, &decrypted);
}

test "RC4: known test vector" {
    const key = "Key";
    const plaintext = "Plaintext";
    var output: [plaintext.len]u8 = undefined;
    rc4(key, plaintext, &output);

    const expected = [_]u8{ 0xBB, 0xF3, 0x16, 0xE8, 0xD9, 0x40, 0xAF, 0x0A, 0xD3 };
    try testing.expectEqualSlices(u8, &expected, &output);
}

test "RC4: empty data" {
    const key = "key";
    var output: [0]u8 = .{};
    rc4(key, &[_]u8{}, &output);
}

test "MD5: empty string" {
    const result = md5("");
    const expected = [_]u8{
        0xd4, 0x1d, 0x8c, 0xd9, 0x8f, 0x00, 0xb2, 0x04,
        0xe9, 0x80, 0x09, 0x98, 0xec, 0xf8, 0x42, 0x7e,
    };
    try testing.expectEqualSlices(u8, &expected, &result);
}

test "MD5: known value abc" {
    const result = md5("abc");
    const expected = [_]u8{
        0x90, 0x01, 0x50, 0x98, 0x3c, 0xd2, 0x4f, 0xb0,
        0xd6, 0x96, 0x3f, 0x7d, 0x28, 0xe1, 0x7f, 0x72,
    };
    try testing.expectEqualSlices(u8, &expected, &result);
}

test "MD5: deterministic" {
    const a = md5("test data");
    const b = md5("test data");
    try testing.expectEqualSlices(u8, &a, &b);
}
