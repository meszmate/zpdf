const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;

/// Code 128 character set B encoding patterns.
/// Each pattern is 6 elements representing bar/space widths.
const patterns = [107][6]u8{
    .{ 2, 1, 2, 2, 2, 2 }, // 0: space
    .{ 2, 2, 2, 1, 2, 2 }, // 1: !
    .{ 2, 2, 2, 2, 2, 1 }, // 2: "
    .{ 1, 2, 1, 2, 2, 3 }, // 3: #
    .{ 1, 2, 1, 3, 2, 2 }, // 4: $
    .{ 1, 3, 1, 2, 2, 2 }, // 5: %
    .{ 1, 2, 2, 2, 1, 3 }, // 6: &
    .{ 1, 2, 2, 3, 1, 2 }, // 7: '
    .{ 1, 3, 2, 2, 1, 2 }, // 8: (
    .{ 2, 2, 1, 2, 1, 3 }, // 9: )
    .{ 2, 2, 1, 3, 1, 2 }, // 10: *
    .{ 2, 3, 1, 2, 1, 2 }, // 11: +
    .{ 1, 1, 2, 2, 3, 2 }, // 12: ,
    .{ 1, 2, 2, 1, 3, 2 }, // 13: -
    .{ 1, 2, 2, 2, 3, 1 }, // 14: .
    .{ 1, 1, 3, 2, 2, 2 }, // 15: /
    .{ 1, 2, 3, 1, 2, 2 }, // 16: 0
    .{ 1, 2, 3, 2, 2, 1 }, // 17: 1
    .{ 2, 2, 3, 2, 1, 1 }, // 18: 2
    .{ 2, 2, 1, 1, 3, 2 }, // 19: 3
    .{ 2, 2, 1, 2, 3, 1 }, // 20: 4
    .{ 2, 1, 3, 2, 1, 2 }, // 21: 5
    .{ 2, 2, 3, 1, 1, 2 }, // 22: 6
    .{ 3, 1, 2, 1, 3, 1 }, // 23: 7
    .{ 3, 1, 1, 2, 2, 2 }, // 24: 8
    .{ 3, 2, 1, 1, 2, 2 }, // 25: 9
    .{ 3, 2, 1, 2, 2, 1 }, // 26: :
    .{ 3, 1, 2, 2, 1, 2 }, // 27: ;
    .{ 3, 2, 2, 1, 1, 2 }, // 28: <
    .{ 3, 2, 2, 2, 1, 1 }, // 29: =
    .{ 2, 1, 2, 1, 2, 3 }, // 30: >
    .{ 2, 1, 2, 3, 2, 1 }, // 31: ?
    .{ 2, 3, 2, 1, 2, 1 }, // 32: @
    .{ 1, 1, 1, 3, 2, 3 }, // 33: A
    .{ 1, 3, 1, 1, 2, 3 }, // 34: B
    .{ 1, 3, 1, 3, 2, 1 }, // 35: C
    .{ 1, 1, 2, 3, 2, 2 }, // 36: D
    .{ 1, 3, 2, 1, 2, 2 }, // 37: E
    .{ 1, 3, 2, 3, 2, 0 }, // 38: F
    .{ 2, 1, 1, 3, 1, 3 }, // 39: G
    .{ 2, 3, 1, 1, 1, 3 }, // 40: H
    .{ 2, 3, 1, 3, 1, 1 }, // 41: I
    .{ 1, 1, 2, 1, 3, 3 }, // 42: J
    .{ 1, 1, 2, 3, 3, 1 }, // 43: K
    .{ 1, 3, 2, 1, 3, 1 }, // 44: L
    .{ 1, 1, 3, 1, 2, 3 }, // 45: M
    .{ 1, 1, 3, 3, 2, 1 }, // 46: N
    .{ 1, 3, 3, 1, 2, 1 }, // 47: O
    .{ 3, 1, 3, 1, 2, 1 }, // 48: P
    .{ 2, 1, 1, 3, 3, 1 }, // 49: Q
    .{ 2, 3, 1, 1, 3, 1 }, // 50: R
    .{ 2, 1, 3, 1, 1, 3 }, // 51: S
    .{ 2, 1, 3, 3, 1, 1 }, // 52: T
    .{ 2, 1, 3, 1, 3, 1 }, // 53: U
    .{ 3, 1, 1, 1, 2, 3 }, // 54: V
    .{ 3, 1, 1, 3, 2, 1 }, // 55: W
    .{ 3, 3, 1, 1, 2, 1 }, // 56: X
    .{ 3, 1, 2, 1, 1, 3 }, // 57: Y
    .{ 3, 1, 2, 3, 1, 1 }, // 58: Z
    .{ 3, 3, 2, 1, 1, 1 }, // 59: [
    .{ 2, 1, 2, 1, 3, 2 }, // 60: backslash
    .{ 2, 1, 2, 2, 3, 1 }, // 61: ]
    .{ 2, 1, 2, 3, 1, 2 }, // 62: ^
    .{ 1, 4, 1, 1, 1, 3 }, // 63: _
    .{ 1, 1, 1, 2, 4, 2 }, // 64: `
    .{ 1, 2, 1, 1, 4, 2 }, // 65: a
    .{ 1, 2, 1, 2, 4, 1 }, // 66: b
    .{ 1, 1, 4, 2, 1, 2 }, // 67: c
    .{ 1, 2, 4, 1, 1, 2 }, // 68: d
    .{ 1, 2, 4, 2, 1, 1 }, // 69: e
    .{ 4, 1, 1, 2, 1, 2 }, // 70: f
    .{ 4, 2, 1, 1, 1, 2 }, // 71: g
    .{ 4, 2, 1, 2, 1, 1 }, // 72: h
    .{ 2, 1, 2, 1, 4, 1 }, // 73: i
    .{ 2, 1, 4, 1, 2, 1 }, // 74: j
    .{ 4, 1, 2, 1, 2, 1 }, // 75: k
    .{ 1, 1, 1, 1, 4, 3 }, // 76: l
    .{ 1, 1, 1, 3, 4, 1 }, // 77: m
    .{ 1, 3, 1, 1, 4, 1 }, // 78: n
    .{ 1, 1, 4, 1, 1, 3 }, // 79: o
    .{ 1, 1, 4, 3, 1, 1 }, // 80: p
    .{ 4, 1, 1, 1, 1, 3 }, // 81: q
    .{ 4, 1, 1, 3, 1, 1 }, // 82: r
    .{ 1, 1, 3, 1, 4, 1 }, // 83: s
    .{ 1, 1, 4, 1, 3, 1 }, // 84: t
    .{ 3, 1, 1, 1, 4, 1 }, // 85: u
    .{ 4, 1, 1, 1, 3, 1 }, // 86: v
    .{ 2, 1, 1, 4, 1, 2 }, // 87: w
    .{ 2, 1, 1, 2, 1, 4 }, // 88: x
    .{ 2, 1, 1, 2, 3, 2 }, // 89: y
    .{ 2, 3, 3, 1, 1, 1 }, // 90: z
    .{ 2, 1, 1, 1, 3, 3 }, // 91: {
    .{ 2, 1, 1, 3, 1, 3 }, // 92: |
    .{ 2, 1, 3, 1, 3, 1 }, // 93: }
    .{ 2, 1, 3, 3, 1, 1 }, // 94: ~
    .{ 3, 1, 1, 1, 3, 2 }, // 95: DEL
    .{ 3, 1, 1, 2, 3, 1 }, // 96: FNC3
    .{ 3, 2, 1, 1, 3, 1 }, // 97: FNC2
    .{ 3, 1, 4, 1, 1, 1 }, // 98: Shift
    .{ 3, 1, 1, 1, 1, 4 }, // 99: Code C
    .{ 3, 1, 1, 4, 1, 1 }, // 100: Code B
    .{ 4, 1, 1, 1, 1, 3 }, // 101: Code A
    .{ 4, 1, 1, 3, 1, 1 }, // 102: FNC1
    .{ 2, 1, 1, 4, 3, 1 }, // 103: Start A
    .{ 2, 1, 1, 1, 4, 3 }, // 104: Start B
    .{ 2, 1, 1, 3, 4, 1 }, // 105: Start C
    .{ 2, 3, 3, 1, 1, 1 }, // 106: Stop
};

/// Stop pattern (7 elements including the final termination bar).
const stop_pattern = [_]u8{ 2, 3, 3, 1, 1, 1, 2 };

const start_b: u8 = 104;

/// Encode a string value into Code 128 bar widths (Code Set B).
pub fn encode(allocator: Allocator, value: []const u8) ![]u8 {
    var result: ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    // Start Code B
    try result.appendSlice(allocator, &patterns[start_b]);

    // Calculate checksum
    var checksum: u32 = start_b;

    for (value, 0..) |ch, i| {
        const code_value: u8 = if (ch >= 32 and ch <= 126) ch - 32 else 0;
        try result.appendSlice(allocator, &patterns[code_value]);
        checksum += @as(u32, code_value) * @as(u32, @intCast(i + 1));
    }

    // Checksum character
    const check_char = @as(u8, @intCast(checksum % 103));
    try result.appendSlice(allocator, &patterns[check_char]);

    // Stop pattern
    try result.appendSlice(allocator, &stop_pattern);

    return result.toOwnedSlice(allocator);
}

/// Render a Code 128 barcode as PDF content stream operators (filled rectangles).
pub fn render(allocator: Allocator, value: []const u8, x: f32, y: f32, width: f32, height: f32) ![]u8 {
    const bar_widths = try encode(allocator, value);
    defer allocator.free(bar_widths);

    var total_modules: u32 = 0;
    for (bar_widths) |w| {
        total_modules += w;
    }

    const module_width = if (total_modules > 0) width / @as(f32, @floatFromInt(total_modules)) else 0;

    var buf: ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try writer.writeAll("q\n");

    var cur_x = x;
    for (bar_widths, 0..) |w, i| {
        const bar_w = @as(f32, @floatFromInt(w)) * module_width;
        if (i % 2 == 0) {
            try writer.print("{d:.4} {d:.4} {d:.4} {d:.4} re f\n", .{ cur_x, y, bar_w, height });
        }
        cur_x += bar_w;
    }

    try writer.writeAll("Q\n");

    return buf.toOwnedSlice(allocator);
}

// -- Tests --

test "code128: encode produces output" {
    const allocator = std.testing.allocator;
    const result = try encode(allocator, "Hello");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "code128: encode starts with Start B pattern" {
    const allocator = std.testing.allocator;
    const result = try encode(allocator, "A");
    defer allocator.free(result);
    try std.testing.expectEqualSlices(u8, &patterns[start_b], result[0..6]);
}

test "code128: encode ends with stop pattern" {
    const allocator = std.testing.allocator;
    const result = try encode(allocator, "A");
    defer allocator.free(result);
    try std.testing.expectEqualSlices(u8, &stop_pattern, result[result.len - 7 ..]);
}

test "code128: render produces PDF operators" {
    const allocator = std.testing.allocator;
    const result = try render(allocator, "123", 10, 20, 200, 50);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "q\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "re f\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Q\n") != null);
}
