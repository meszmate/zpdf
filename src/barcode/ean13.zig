const std = @import("std");
const Allocator = std.mem.Allocator;

/// EAN-13 encoding patterns.
/// L-codes (odd parity), G-codes (even parity), R-codes.
/// Each digit pattern is 7 modules wide (1 = bar, 0 = space).
pub const l_patterns = [10][7]u8{
    .{ 0, 0, 0, 1, 1, 0, 1 }, // 0
    .{ 0, 0, 1, 1, 0, 0, 1 }, // 1
    .{ 0, 0, 1, 0, 0, 1, 1 }, // 2
    .{ 0, 1, 1, 1, 1, 0, 1 }, // 3
    .{ 0, 1, 0, 0, 0, 1, 1 }, // 4
    .{ 0, 1, 1, 0, 0, 0, 1 }, // 5
    .{ 0, 1, 0, 1, 1, 1, 1 }, // 6
    .{ 0, 1, 1, 1, 0, 1, 1 }, // 7
    .{ 0, 1, 1, 0, 1, 1, 1 }, // 8
    .{ 0, 0, 0, 1, 0, 1, 1 }, // 9
};

const g_patterns = [10][7]u8{
    .{ 0, 1, 0, 0, 1, 1, 1 }, // 0
    .{ 0, 1, 1, 0, 0, 1, 1 }, // 1
    .{ 0, 0, 1, 1, 0, 1, 1 }, // 2
    .{ 0, 1, 0, 0, 0, 0, 1 }, // 3
    .{ 0, 0, 1, 1, 1, 0, 1 }, // 4
    .{ 0, 1, 1, 1, 0, 0, 1 }, // 5
    .{ 0, 0, 0, 0, 1, 0, 1 }, // 6
    .{ 0, 0, 1, 0, 0, 0, 1 }, // 7
    .{ 0, 0, 0, 1, 0, 0, 1 }, // 8
    .{ 0, 0, 1, 0, 1, 1, 1 }, // 9
};

pub const r_patterns = [10][7]u8{
    .{ 1, 1, 1, 0, 0, 1, 0 }, // 0
    .{ 1, 1, 0, 0, 1, 1, 0 }, // 1
    .{ 1, 1, 0, 1, 1, 0, 0 }, // 2
    .{ 1, 0, 0, 0, 0, 1, 0 }, // 3
    .{ 1, 0, 1, 1, 1, 0, 0 }, // 4
    .{ 1, 0, 0, 1, 1, 1, 0 }, // 5
    .{ 1, 0, 1, 0, 0, 0, 0 }, // 6
    .{ 1, 0, 0, 0, 1, 0, 0 }, // 7
    .{ 1, 0, 0, 1, 0, 0, 0 }, // 8
    .{ 1, 1, 1, 0, 1, 0, 0 }, // 9
};

/// First digit encoding: determines which of L/G pattern is used for digits 2-7.
/// 0 = L pattern, 1 = G pattern.
const first_digit_encoding = [10][6]u8{
    .{ 0, 0, 0, 0, 0, 0 }, // 0: LLLLLL
    .{ 0, 0, 1, 0, 1, 1 }, // 1: LLGLGG
    .{ 0, 0, 1, 1, 0, 1 }, // 2: LLGGLG
    .{ 0, 0, 1, 1, 1, 0 }, // 3: LLGGGL
    .{ 0, 1, 0, 0, 1, 1 }, // 4: LGLLGG
    .{ 0, 1, 1, 0, 0, 1 }, // 5: LGGLLG
    .{ 0, 1, 1, 1, 0, 0 }, // 6: LGGGLL
    .{ 0, 1, 0, 1, 0, 1 }, // 7: LGLGLG
    .{ 0, 1, 0, 1, 1, 0 }, // 8: LGLGGL
    .{ 0, 1, 1, 0, 1, 0 }, // 9: LGGLGL
};

/// Calculate the EAN-13 check digit for a 12-digit input.
pub fn calculateCheckDigit(digits: []const u8) u8 {
    var sum: u32 = 0;
    for (digits, 0..) |d, i| {
        const val: u32 = if (d >= '0' and d <= '9') d - '0' else d;
        if (i % 2 == 0) {
            sum += val;
        } else {
            sum += val * 3;
        }
    }
    const remainder = sum % 10;
    return if (remainder == 0) 0 else @intCast(10 - remainder);
}

/// Encode a 12 or 13 digit string into EAN-13 module pattern.
/// Returns an array where 1 = bar and 0 = space.
pub fn encode(allocator: Allocator, value: []const u8) ![]u8 {
    if (value.len < 12) return error.InvalidLength;

    // Extract digits
    var digits: [13]u8 = undefined;
    for (0..12) |i| {
        if (value[i] < '0' or value[i] > '9') return error.InvalidCharacter;
        digits[i] = value[i] - '0';
    }

    // Calculate or verify check digit
    if (value.len >= 13) {
        digits[12] = value[12] - '0';
    } else {
        digits[12] = calculateCheckDigit(value[0..12]);
    }

    var result: std.ArrayListUnmanaged(u8) = .{};
    errdefer result.deinit(allocator);

    // Start guard: 101
    try result.appendSlice(allocator, &[_]u8{ 1, 0, 1 });

    // Left half (digits 2-7, using L/G patterns based on first digit)
    const encoding = first_digit_encoding[digits[0]];
    for (0..6) |i| {
        const d = digits[i + 1];
        if (encoding[i] == 0) {
            try result.appendSlice(allocator, &l_patterns[d]);
        } else {
            try result.appendSlice(allocator, &g_patterns[d]);
        }
    }

    // Center guard: 01010
    try result.appendSlice(allocator, &[_]u8{ 0, 1, 0, 1, 0 });

    // Right half (digits 8-13, using R patterns)
    for (0..6) |i| {
        const d = digits[i + 7];
        try result.appendSlice(allocator, &r_patterns[d]);
    }

    // End guard: 101
    try result.appendSlice(allocator, &[_]u8{ 1, 0, 1 });

    return result.toOwnedSlice(allocator);
}

/// Render an EAN-13 barcode as PDF content stream operators.
pub fn render(allocator: Allocator, value: []const u8, x: f32, y: f32, width: f32, height: f32) ![]u8 {
    const modules = try encode(allocator, value);
    defer allocator.free(modules);

    const module_width = width / @as(f32, @floatFromInt(modules.len));

    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try writer.writeAll("q\n");

    // Group consecutive bars into rectangles for efficiency
    var i: usize = 0;
    while (i < modules.len) {
        if (modules[i] == 1) {
            // Find the run of consecutive 1s
            var run_len: usize = 1;
            while (i + run_len < modules.len and modules[i + run_len] == 1) {
                run_len += 1;
            }
            const bar_x = x + @as(f32, @floatFromInt(i)) * module_width;
            const bar_w = @as(f32, @floatFromInt(run_len)) * module_width;
            try writer.print("{d:.4} {d:.4} {d:.4} {d:.4} re f\n", .{ bar_x, y, bar_w, height });
            i += run_len;
        } else {
            i += 1;
        }
    }

    try writer.writeAll("Q\n");

    return buf.toOwnedSlice(allocator);
}

// -- Tests --

test "ean13: check digit calculation" {
    // EAN-13 for "590123412345" should have check digit 7
    const check = calculateCheckDigit("590123412345");
    try std.testing.expectEqual(@as(u8, 7), check);
}

test "ean13: check digit for zeros" {
    const check = calculateCheckDigit("000000000000");
    try std.testing.expectEqual(@as(u8, 0), check);
}

test "ean13: encode produces correct length" {
    const allocator = std.testing.allocator;
    const result = try encode(allocator, "5901234123457");
    defer allocator.free(result);
    // EAN-13 total: 3 + 6*7 + 5 + 6*7 + 3 = 95 modules
    try std.testing.expectEqual(@as(usize, 95), result.len);
}

test "ean13: encode starts with start guard" {
    const allocator = std.testing.allocator;
    const result = try encode(allocator, "5901234123457");
    defer allocator.free(result);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 1, 0, 1 }, result[0..3]);
}

test "ean13: encode ends with end guard" {
    const allocator = std.testing.allocator;
    const result = try encode(allocator, "5901234123457");
    defer allocator.free(result);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 1, 0, 1 }, result[92..95]);
}

test "ean13: render produces PDF operators" {
    const allocator = std.testing.allocator;
    const result = try render(allocator, "5901234123457", 10, 20, 200, 80);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "q\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Q\n") != null);
}

test "ean13: short input rejected" {
    const allocator = std.testing.allocator;
    const result = encode(allocator, "123");
    try std.testing.expectError(error.InvalidLength, result);
}
