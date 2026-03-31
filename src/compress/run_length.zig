const std = @import("std");
const Allocator = std.mem.Allocator;

/// Encodes data using the PDF RunLengthDecode format.
///
/// The PDF RLE format uses a length byte followed by data:
/// - 0..127: copy the next N+1 bytes literally
/// - 129..255: repeat the next byte 257-N times
/// - 128: end-of-data (EOD) marker
///
/// The encoder uses a simple greedy approach: it identifies runs of identical
/// bytes and literal sequences, choosing the most compact representation.
///
/// The caller owns the returned slice and must free it with the same allocator.
pub fn encode(allocator: Allocator, data: []const u8) ![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .{};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < data.len) {
        // Count consecutive identical bytes
        var run_len: usize = 1;
        while (i + run_len < data.len and
            data[i + run_len] == data[i] and
            run_len < 128) : (run_len += 1)
        {}

        if (run_len >= 2) {
            // Encode as a run: length byte = 257 - run_len
            try result.append(allocator, @intCast(257 - run_len));
            try result.append(allocator, data[i]);
            i += run_len;
        } else {
            // Collect literal bytes (non-repeating or single bytes)
            const lit_start = i;
            var lit_len: usize = 0;

            while (i + lit_len < data.len and lit_len < 128) {
                // Check if a run starts here (at least 2 identical bytes)
                if (i + lit_len + 1 < data.len and
                    data[i + lit_len] == data[i + lit_len + 1])
                {
                    // A run of 2+ identical bytes starts; stop the literal sequence
                    break;
                }
                lit_len += 1;
            }

            // If we found no literals (shouldn't happen given run_len < 2
            // above, but guard against edge case), emit at least one
            if (lit_len == 0) {
                lit_len = 1;
            }

            // Encode as literal: length byte = lit_len - 1
            try result.append(allocator, @intCast(lit_len - 1));
            try result.appendSlice(allocator, data[lit_start .. lit_start + lit_len]);
            i += lit_len;
        }
    }

    // Append EOD marker
    try result.append(allocator, 128);

    return result.toOwnedSlice(allocator);
}

/// Decodes data encoded with the PDF RunLengthDecode format.
///
/// The PDF RLE format uses a length byte followed by data:
/// - 0..127: copy the next N+1 bytes literally
/// - 129..255: repeat the next byte 257-N times
/// - 128: end-of-data (EOD) marker
///
/// The caller owns the returned slice and must free it with the same allocator.
pub fn decode(allocator: Allocator, data: []const u8) ![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .{};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < data.len) {
        const length_byte = data[i];
        i += 1;

        if (length_byte == 128) {
            // EOD marker
            break;
        } else if (length_byte <= 127) {
            // Literal run: copy next length_byte+1 bytes
            const count: usize = @as(usize, length_byte) + 1;
            if (i + count > data.len) return error.InvalidRunLength;
            try result.appendSlice(allocator, data[i .. i + count]);
            i += count;
        } else {
            // Repeated run: repeat next byte (257-length_byte) times
            if (i >= data.len) return error.InvalidRunLength;
            const count: usize = 257 - @as(usize, length_byte);
            const byte = data[i];
            i += 1;
            try result.appendNTimes(allocator, byte, count);
        }
    }

    return result.toOwnedSlice(allocator);
}

pub const Error = error{InvalidRunLength};

test "run length encode literal" {
    const allocator = std.testing.allocator;

    const encoded = try encode(allocator, "ABCDE");
    defer allocator.free(encoded);

    // Should be: 4 (5 literals - 1), A, B, C, D, E, 128 (EOD)
    try std.testing.expectEqualSlices(u8, &[_]u8{ 4, 'A', 'B', 'C', 'D', 'E', 128 }, encoded);
}

test "run length encode repeated" {
    const allocator = std.testing.allocator;

    const encoded = try encode(allocator, "AAAA");
    defer allocator.free(encoded);

    // Should be: 253 (257-4), A, 128 (EOD)
    try std.testing.expectEqualSlices(u8, &[_]u8{ 253, 'A', 128 }, encoded);
}

test "run length decode literal" {
    const allocator = std.testing.allocator;

    // 4 = copy next 5 bytes, then EOD
    const decoded = try decode(allocator, &[_]u8{ 4, 'H', 'e', 'l', 'l', 'o', 128 });
    defer allocator.free(decoded);
    try std.testing.expectEqualSlices(u8, "Hello", decoded);
}

test "run length decode repeated" {
    const allocator = std.testing.allocator;

    // 253 = repeat next byte 257-253=4 times, then EOD
    const decoded = try decode(allocator, &[_]u8{ 253, 'X', 128 });
    defer allocator.free(decoded);
    try std.testing.expectEqualSlices(u8, "XXXX", decoded);
}

test "run length round-trip" {
    const allocator = std.testing.allocator;
    const original = "AAABBBCCDDDDDDDDEFFGH";

    const encoded = try encode(allocator, original);
    defer allocator.free(encoded);

    const decoded = try decode(allocator, encoded);
    defer allocator.free(decoded);

    try std.testing.expectEqualSlices(u8, original, decoded);
}

test "run length round-trip empty" {
    const allocator = std.testing.allocator;

    const encoded = try encode(allocator, "");
    defer allocator.free(encoded);

    try std.testing.expectEqualSlices(u8, &[_]u8{128}, encoded);

    const decoded = try decode(allocator, encoded);
    defer allocator.free(decoded);

    try std.testing.expectEqual(@as(usize, 0), decoded.len);
}

test "run length round-trip single byte" {
    const allocator = std.testing.allocator;
    const original = "X";

    const encoded = try encode(allocator, original);
    defer allocator.free(encoded);

    const decoded = try decode(allocator, encoded);
    defer allocator.free(decoded);

    try std.testing.expectEqualSlices(u8, original, decoded);
}

test "run length long run" {
    const allocator = std.testing.allocator;

    // 128 identical bytes (max single run)
    var original: [128]u8 = undefined;
    @memset(&original, 'Z');

    const encoded = try encode(allocator, &original);
    defer allocator.free(encoded);

    const decoded = try decode(allocator, encoded);
    defer allocator.free(decoded);

    try std.testing.expectEqualSlices(u8, &original, decoded);
}

test "run length mixed content" {
    const allocator = std.testing.allocator;
    const original = [_]u8{ 1, 2, 3, 3, 3, 3, 3, 4, 5, 5, 6 };

    const encoded = try encode(allocator, &original);
    defer allocator.free(encoded);

    const decoded = try decode(allocator, encoded);
    defer allocator.free(decoded);

    try std.testing.expectEqualSlices(u8, &original, decoded);
}
