const std = @import("std");
const Allocator = std.mem.Allocator;

/// Encodes data as hexadecimal pairs (PDF ASCIIHexDecode filter format).
///
/// Each byte is encoded as two uppercase hex characters followed by a `>`
/// end-of-data marker.
///
/// The caller owns the returned slice and must free it with the same allocator.
pub fn encode(allocator: Allocator, data: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, data.len * 2 + 1);
    errdefer allocator.free(result);

    for (data, 0..) |byte, i| {
        const hex = "0123456789ABCDEF";
        result[i * 2] = hex[byte >> 4];
        result[i * 2 + 1] = hex[byte & 0x0F];
    }

    result[data.len * 2] = '>'; // EOD marker

    return result;
}

/// Decodes hexadecimal-encoded data (PDF ASCIIHexDecode filter format).
///
/// Whitespace characters are ignored. Decoding stops at the `>` end-of-data
/// marker. If the final hex pair is incomplete (odd number of hex digits),
/// the missing digit is assumed to be `0`.
///
/// The caller owns the returned slice and must free it with the same allocator.
pub fn decode(allocator: Allocator, data: []const u8) ![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .{};
    errdefer result.deinit(allocator);

    var high_nibble: ?u4 = null;

    for (data) |c| {
        // EOD marker
        if (c == '>') break;

        // Skip whitespace
        switch (c) {
            ' ', '\t', '\n', '\r', 0x0C, 0x00 => continue,
            else => {},
        }

        const nibble = hexToNibble(c) orelse return error.InvalidHexCharacter;

        if (high_nibble) |high| {
            try result.append(allocator, @as(u8, high) << 4 | nibble);
            high_nibble = null;
        } else {
            high_nibble = nibble;
        }
    }

    // If there's an unpaired nibble, pad with 0
    if (high_nibble) |high| {
        try result.append(allocator, @as(u8, high) << 4);
    }

    return result.toOwnedSlice(allocator);
}

fn hexToNibble(c: u8) ?u4 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'A'...'F' => @intCast(c - 'A' + 10),
        'a'...'f' => @intCast(c - 'a' + 10),
        else => null,
    };
}

pub const Error = error{InvalidHexCharacter};

test "ascii hex encode" {
    const allocator = std.testing.allocator;

    const encoded = try encode(allocator, &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF });
    defer allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, "DEADBEEF>", encoded);
}

test "ascii hex decode" {
    const allocator = std.testing.allocator;

    const decoded = try decode(allocator, "DEADBEEF>");
    defer allocator.free(decoded);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF }, decoded);
}

test "ascii hex decode lowercase" {
    const allocator = std.testing.allocator;

    const decoded = try decode(allocator, "deadbeef>");
    defer allocator.free(decoded);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF }, decoded);
}

test "ascii hex decode with whitespace" {
    const allocator = std.testing.allocator;

    const decoded = try decode(allocator, "DE AD\nBE\tEF>");
    defer allocator.free(decoded);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF }, decoded);
}

test "ascii hex decode odd nibble" {
    const allocator = std.testing.allocator;

    // Odd number of hex digits: trailing nibble padded with 0
    const decoded = try decode(allocator, "ABC>");
    defer allocator.free(decoded);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xAB, 0xC0 }, decoded);
}

test "ascii hex round-trip" {
    const allocator = std.testing.allocator;
    const original = "Hello, PDF!";

    const encoded = try encode(allocator, original);
    defer allocator.free(encoded);

    const decoded = try decode(allocator, encoded);
    defer allocator.free(decoded);

    try std.testing.expectEqualSlices(u8, original, decoded);
}

test "ascii hex decode stops at eod" {
    const allocator = std.testing.allocator;

    // Data after > should be ignored
    const decoded = try decode(allocator, "4142>ignored");
    defer allocator.free(decoded);
    try std.testing.expectEqualSlices(u8, "AB", decoded);
}

test "ascii hex encode empty" {
    const allocator = std.testing.allocator;

    const encoded = try encode(allocator, "");
    defer allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, ">", encoded);
}

test "ascii hex decode empty" {
    const allocator = std.testing.allocator;

    const decoded = try decode(allocator, ">");
    defer allocator.free(decoded);
    try std.testing.expectEqual(@as(usize, 0), decoded.len);
}
