const std = @import("std");
const Md5 = std.crypto.hash.Md5;

/// Compute the MD5 digest of the given data, returning a 16-byte hash.
pub fn md5(data: []const u8) [16]u8 {
    var hash: [16]u8 = undefined;
    Md5.hash(data, &hash, .{});
    return hash;
}

// -- Tests --

test "md5: empty string" {
    const result = md5("");
    const expected = [_]u8{
        0xd4, 0x1d, 0x8c, 0xd9, 0x8f, 0x00, 0xb2, 0x04,
        0xe9, 0x80, 0x09, 0x98, 0xec, 0xf8, 0x42, 0x7e,
    };
    try std.testing.expectEqualSlices(u8, &expected, &result);
}

test "md5: abc" {
    const result = md5("abc");
    const expected = [_]u8{
        0x90, 0x01, 0x50, 0x98, 0x3c, 0xd2, 0x4f, 0xb0,
        0xd6, 0x96, 0x3f, 0x7d, 0x28, 0xe1, 0x7f, 0x72,
    };
    try std.testing.expectEqualSlices(u8, &expected, &result);
}

test "md5: deterministic" {
    const a = md5("test data");
    const b = md5("test data");
    try std.testing.expectEqualSlices(u8, &a, &b);
}
