const std = @import("std");
const Allocator = std.mem.Allocator;

/// Code 39 character patterns.
/// Each character is encoded as 9 elements (bars and spaces), where
/// a wide element = 3 and a narrow element = 1.
/// Format: bar, space, bar, space, bar, space, bar, space, bar
const CharPattern = [9]u8;

const char_set = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. $/+%*";

const char_patterns = [44]CharPattern{
    .{ 1, 1, 1, 3, 3, 1, 3, 1, 1 }, // 0
    .{ 3, 1, 1, 1, 1, 3, 1, 1, 3 }, // 1
    .{ 1, 1, 3, 1, 1, 3, 1, 1, 3 }, // 2
    .{ 3, 1, 3, 1, 1, 3, 1, 1, 1 }, // 3
    .{ 1, 1, 1, 1, 3, 3, 1, 1, 3 }, // 4
    .{ 3, 1, 1, 1, 3, 3, 1, 1, 1 }, // 5
    .{ 1, 1, 3, 1, 3, 3, 1, 1, 1 }, // 6
    .{ 1, 1, 1, 1, 1, 3, 3, 1, 3 }, // 7
    .{ 3, 1, 1, 1, 1, 3, 3, 1, 1 }, // 8 (value=8, char='8')
    .{ 1, 1, 3, 1, 1, 3, 3, 1, 1 }, // 9
    .{ 3, 1, 1, 3, 1, 1, 1, 1, 3 }, // A
    .{ 1, 1, 3, 3, 1, 1, 1, 1, 3 }, // B
    .{ 3, 1, 3, 3, 1, 1, 1, 1, 1 }, // C
    .{ 1, 1, 1, 3, 3, 1, 1, 1, 3 }, // D
    .{ 3, 1, 1, 3, 3, 1, 1, 1, 1 }, // E
    .{ 1, 1, 3, 3, 3, 1, 1, 1, 1 }, // F
    .{ 1, 1, 1, 1, 1, 3, 1, 3, 3 }, // G (value=16)
    .{ 3, 1, 1, 1, 1, 1, 1, 3, 3 }, // H (value=17) - not used in indexing below
    .{ 1, 1, 3, 1, 1, 1, 1, 3, 3 }, // I
    .{ 1, 1, 1, 1, 3, 1, 1, 3, 3 }, // J
    .{ 3, 1, 1, 1, 1, 1, 3, 1, 3 }, // K (value=20)
    .{ 1, 1, 3, 1, 1, 1, 3, 1, 3 }, // L
    .{ 3, 1, 3, 1, 1, 1, 3, 1, 1 }, // M
    .{ 1, 1, 1, 1, 3, 1, 3, 1, 3 }, // N
    .{ 3, 1, 1, 1, 3, 1, 3, 1, 1 }, // O
    .{ 1, 1, 3, 1, 3, 1, 3, 1, 1 }, // P
    .{ 1, 1, 1, 1, 1, 1, 3, 3, 3 }, // Q
    .{ 3, 1, 1, 1, 1, 1, 3, 3, 1 }, // R
    .{ 1, 1, 3, 1, 1, 1, 3, 3, 1 }, // S
    .{ 1, 1, 1, 1, 3, 1, 3, 3, 1 }, // T
    .{ 3, 3, 1, 1, 1, 1, 1, 1, 3 }, // U (value=30)
    .{ 1, 3, 3, 1, 1, 1, 1, 1, 3 }, // V
    .{ 3, 3, 3, 1, 1, 1, 1, 1, 1 }, // W
    .{ 1, 3, 1, 1, 3, 1, 1, 1, 3 }, // X
    .{ 3, 3, 1, 1, 3, 1, 1, 1, 1 }, // Y
    .{ 1, 3, 3, 1, 3, 1, 1, 1, 1 }, // Z
    .{ 1, 3, 1, 1, 1, 1, 3, 1, 3 }, // -
    .{ 3, 3, 1, 1, 1, 1, 3, 1, 1 }, // .
    .{ 1, 3, 1, 1, 1, 1, 1, 3, 3 }, // (space) (value=38)
    .{ 1, 3, 1, 3, 1, 3, 1, 1, 1 }, // $ (value=39)
    .{ 1, 3, 1, 3, 1, 1, 1, 3, 1 }, // / (value=40)
    .{ 1, 3, 1, 1, 1, 3, 1, 3, 1 }, // + (value=41)
    .{ 1, 1, 1, 3, 1, 3, 1, 3, 1 }, // % (value=42)
    .{ 1, 3, 1, 1, 3, 1, 3, 1, 1 }, // * (start/stop) (value=43)
};

const start_stop_idx: usize = 43; // '*' character

/// Look up the pattern index for a given character.
fn charIndex(ch: u8) ?usize {
    for (char_set, 0..) |c, i| {
        if (c == ch) return i;
    }
    return null;
}

/// Encode a string value into Code 39 bar widths.
/// The value should contain only valid Code 39 characters (0-9, A-Z, -, ., space, $, /, +, %).
/// Start/stop characters (*) are added automatically.
pub fn encode(allocator: Allocator, value: []const u8) ![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .{};
    errdefer result.deinit(allocator);

    // Start character
    try result.appendSlice(allocator, &char_patterns[start_stop_idx]);
    try result.append(allocator, 1); // Inter-character gap (narrow space)

    for (value) |ch| {
        const upper = if (ch >= 'a' and ch <= 'z') ch - 32 else ch;
        const idx = charIndex(upper) orelse continue;
        try result.appendSlice(allocator, &char_patterns[idx]);
        try result.append(allocator, 1); // Inter-character gap
    }

    // Stop character
    try result.appendSlice(allocator, &char_patterns[start_stop_idx]);

    return result.toOwnedSlice(allocator);
}

/// Render a Code 39 barcode as PDF content stream operators (filled rectangles).
pub fn render(allocator: Allocator, value: []const u8, x: f32, y: f32, width: f32, height: f32) ![]u8 {
    const bar_widths = try encode(allocator, value);
    defer allocator.free(bar_widths);

    var total_modules: u32 = 0;
    for (bar_widths) |w| {
        total_modules += w;
    }

    const module_width = if (total_modules > 0) width / @as(f32, @floatFromInt(total_modules)) else 0;

    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try writer.writeAll("q\n");

    var cur_x = x;
    for (bar_widths, 0..) |w, i| {
        const bar_w = @as(f32, @floatFromInt(w)) * module_width;
        if (i % 2 == 0) {
            // Even indices are bars
            try writer.print("{d:.4} {d:.4} {d:.4} {d:.4} re f\n", .{ cur_x, y, bar_w, height });
        }
        cur_x += bar_w;
    }

    try writer.writeAll("Q\n");

    return buf.toOwnedSlice(allocator);
}

// -- Tests --

test "code39: encode produces output" {
    const allocator = std.testing.allocator;
    const result = try encode(allocator, "HELLO");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "code39: encode wraps with start/stop" {
    const allocator = std.testing.allocator;
    const result = try encode(allocator, "A");
    defer allocator.free(result);
    // Should start with start pattern
    try std.testing.expectEqualSlices(u8, &char_patterns[start_stop_idx], result[0..9]);
}

test "code39: render produces PDF operators" {
    const allocator = std.testing.allocator;
    const result = try render(allocator, "123", 0, 0, 200, 50);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "q\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Q\n") != null);
}

test "code39: lowercase converted to uppercase" {
    const allocator = std.testing.allocator;
    const lower = try encode(allocator, "abc");
    defer allocator.free(lower);
    const upper = try encode(allocator, "ABC");
    defer allocator.free(upper);
    try std.testing.expectEqualSlices(u8, upper, lower);
}
