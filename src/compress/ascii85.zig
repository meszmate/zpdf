const std = @import("std");
const Allocator = std.mem.Allocator;

/// Encodes data using ASCII Base85 encoding as used in PDF streams.
///
/// Output is wrapped with `<~` prefix and `~>` suffix.
/// Groups of 4 zero bytes are encoded as `z`. Remaining bytes (1-3) at the
/// end are encoded with remaining+1 characters.
///
/// The caller owns the returned slice and must free it with the same allocator.
pub fn encode(allocator: Allocator, data: []const u8) ![]u8 {
    // Worst case: each 4 bytes -> 5 chars, plus <~ and ~> delimiters
    const max_len = 2 + (data.len / 4) * 5 + (if (data.len % 4 != 0) data.len % 4 + 1 else 0) + 2;
    var result: std.ArrayListUnmanaged(u8) = .{};
    errdefer result.deinit(allocator);
    try result.ensureTotalCapacity(allocator, max_len);

    try result.appendSlice(allocator, "<~");

    var i: usize = 0;
    while (i + 4 <= data.len) : (i += 4) {
        const val = std.mem.readInt(u32, data[i..][0..4], .big);

        if (val == 0) {
            try result.append(allocator, 'z');
        } else {
            var group: [5]u8 = undefined;
            var v = val;
            var j: usize = 5;
            while (j > 0) {
                j -= 1;
                group[j] = @intCast(v % 85 + 33);
                v /= 85;
            }
            try result.appendSlice(allocator, &group);
        }
    }

    // Handle remaining bytes (1-3)
    const remaining = data.len - i;
    if (remaining > 0) {
        // Pad with zeros to form a full 4-byte group
        var padded: [4]u8 = .{ 0, 0, 0, 0 };
        @memcpy(padded[0..remaining], data[i..]);

        const val = std.mem.readInt(u32, &padded, .big);

        var group: [5]u8 = undefined;
        var v = val;
        var j: usize = 5;
        while (j > 0) {
            j -= 1;
            group[j] = @intCast(v % 85 + 33);
            v /= 85;
        }

        // Output only remaining+1 characters
        try result.appendSlice(allocator, group[0 .. remaining + 1]);
    }

    try result.appendSlice(allocator, "~>");

    return result.toOwnedSlice(allocator);
}

/// Decodes ASCII Base85 encoded data as used in PDF streams.
///
/// Input may optionally include the `<~` prefix and `~>` suffix.
/// Whitespace is ignored. The `z` shorthand for four zero bytes is supported.
///
/// The caller owns the returned slice and must free it with the same allocator.
pub fn decode(allocator: Allocator, data: []const u8) ![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .{};
    errdefer result.deinit(allocator);

    // Strip <~ prefix and ~> suffix if present
    var input = data;
    if (input.len >= 2 and input[0] == '<' and input[1] == '~') {
        input = input[2..];
    }
    if (input.len >= 2 and input[input.len - 2] == '~' and input[input.len - 1] == '>') {
        input = input[0 .. input.len - 2];
    }

    // Collect non-whitespace characters
    var chars: std.ArrayListUnmanaged(u8) = .{};
    defer chars.deinit(allocator);

    for (input) |c| {
        switch (c) {
            ' ', '\t', '\n', '\r', 0x0C => continue, // skip whitespace
            else => try chars.append(allocator, c),
        }
    }

    var i: usize = 0;
    while (i < chars.items.len) {
        if (chars.items[i] == 'z') {
            try result.appendSlice(allocator, &.{ 0, 0, 0, 0 });
            i += 1;
            continue;
        }

        // Collect up to 5 characters for this group
        const remaining = chars.items.len - i;
        const group_len = @min(remaining, 5);

        if (group_len < 2) {
            return error.InvalidAscii85;
        }

        // Pad partial groups with 'u' (the highest valid char, value 84)
        var group: [5]u8 = .{ 'u', 'u', 'u', 'u', 'u' };
        @memcpy(group[0..group_len], chars.items[i .. i + group_len]);

        // Decode the 5 base-85 digits into a 4-byte value
        var val: u32 = 0;
        for (group) |c| {
            if (c < 33 or c > 117) {
                return error.InvalidAscii85;
            }
            val = val *% 85 +% (c - 33);
        }

        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, val, .big);

        // For partial groups, output only group_len-1 bytes
        const out_len: usize = if (group_len == 5) 4 else group_len - 1;
        try result.appendSlice(allocator, bytes[0..out_len]);

        i += group_len;
    }

    return result.toOwnedSlice(allocator);
}

pub const Error = error{InvalidAscii85};

test "ascii85 encode basic" {
    const allocator = std.testing.allocator;

    const encoded = try encode(allocator, "Man ");
    defer allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, "<~9jqo^~>", encoded);
}

test "ascii85 encode zero group" {
    const allocator = std.testing.allocator;

    const encoded = try encode(allocator, &[_]u8{ 0, 0, 0, 0 });
    defer allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, "<~z~>", encoded);
}

test "ascii85 decode basic" {
    const allocator = std.testing.allocator;

    const decoded = try decode(allocator, "<~9jqo^~>");
    defer allocator.free(decoded);
    try std.testing.expectEqualSlices(u8, "Man ", decoded);
}

test "ascii85 decode zero group" {
    const allocator = std.testing.allocator;

    const decoded = try decode(allocator, "<~z~>");
    defer allocator.free(decoded);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0, 0, 0, 0 }, decoded);
}

test "ascii85 round-trip" {
    const allocator = std.testing.allocator;
    const original = "Hello, World! This is a test of ASCII85 encoding in PDF.";

    const encoded = try encode(allocator, original);
    defer allocator.free(encoded);

    const decoded = try decode(allocator, encoded);
    defer allocator.free(decoded);

    try std.testing.expectEqualSlices(u8, original, decoded);
}

test "ascii85 round-trip partial group" {
    const allocator = std.testing.allocator;

    // Test with lengths that are not multiples of 4
    const test_cases = [_][]const u8{ "A", "AB", "ABC", "ABCD", "ABCDE" };

    for (test_cases) |original| {
        const encoded = try encode(allocator, original);
        defer allocator.free(encoded);

        const decoded = try decode(allocator, encoded);
        defer allocator.free(decoded);

        try std.testing.expectEqualSlices(u8, original, decoded);
    }
}

test "ascii85 decode with whitespace" {
    const allocator = std.testing.allocator;

    const decoded = try decode(allocator, "<~ 9jqo^ ~>");
    defer allocator.free(decoded);
    try std.testing.expectEqualSlices(u8, "Man ", decoded);
}

test "ascii85 encode empty" {
    const allocator = std.testing.allocator;

    const encoded = try encode(allocator, "");
    defer allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, "<~~>", encoded);
}

test "ascii85 decode empty" {
    const allocator = std.testing.allocator;

    const decoded = try decode(allocator, "<~~>");
    defer allocator.free(decoded);
    try std.testing.expectEqual(@as(usize, 0), decoded.len);
}
