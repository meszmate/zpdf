const std = @import("std");
const Allocator = std.mem.Allocator;
const ean13 = @import("ean13.zig");

/// L and R patterns are the same as EAN-13.
const l_patterns = ean13.l_patterns;
const r_patterns = ean13.r_patterns;

/// Calculate the EAN-8 check digit for a 7-digit input.
pub fn calculateCheckDigit(digits: []const u8) u8 {
    // EAN-8 check digit: weights alternate 3, 1, 3, 1, 3, 1, 3
    // (positions are 1-indexed; odd positions get weight 3, even get weight 1)
    // This is equivalent to: for a 7-digit input, weight pattern is 3,1,3,1,3,1,3
    var sum: u32 = 0;
    for (digits, 0..) |d, i| {
        const val: u32 = if (d >= '0' and d <= '9') d - '0' else d;
        if (i % 2 == 0) {
            sum += val * 3;
        } else {
            sum += val;
        }
    }
    const remainder = sum % 10;
    return if (remainder == 0) 0 else @intCast(10 - remainder);
}

/// Encode an EAN-8 barcode.
/// Accepts 7 digits (data only) or 8 digits (data + check digit).
/// Returns an array where 1 = bar and 0 = space (67 modules).
/// Structure: 3 guard + 4*7 left (L encoding) + 5 center + 4*7 right (R encoding) + 3 guard = 67
pub fn encode(allocator: Allocator, value: []const u8) ![]u8 {
    if (value.len != 7 and value.len != 8) return error.InvalidLength;

    var digits: [8]u8 = undefined;
    for (0..7) |i| {
        if (value[i] < '0' or value[i] > '9') return error.InvalidCharacter;
        digits[i] = value[i] - '0';
    }

    if (value.len == 8) {
        if (value[7] < '0' or value[7] > '9') return error.InvalidCharacter;
        digits[7] = value[7] - '0';
    } else {
        digits[7] = calculateCheckDigit(value[0..7]);
    }

    var result: std.ArrayListUnmanaged(u8) = .{};
    errdefer result.deinit(allocator);

    // Start guard: 101
    try result.appendSlice(allocator, &[_]u8{ 1, 0, 1 });

    // Left half: 4 digits, all L encoding
    for (0..4) |i| {
        try result.appendSlice(allocator, &l_patterns[digits[i]]);
    }

    // Center guard: 01010
    try result.appendSlice(allocator, &[_]u8{ 0, 1, 0, 1, 0 });

    // Right half: 4 digits, all R encoding
    for (0..4) |i| {
        try result.appendSlice(allocator, &r_patterns[digits[i + 4]]);
    }

    // End guard: 101
    try result.appendSlice(allocator, &[_]u8{ 1, 0, 1 });

    return result.toOwnedSlice(allocator);
}

/// Render an EAN-8 barcode as PDF content stream operators.
pub fn render(allocator: Allocator, value: []const u8, x: f32, y: f32, width: f32, height: f32) ![]u8 {
    const modules = try encode(allocator, value);
    defer allocator.free(modules);

    const module_width = width / @as(f32, @floatFromInt(modules.len));

    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try writer.writeAll("q\n");

    var i: usize = 0;
    while (i < modules.len) {
        if (modules[i] == 1) {
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

test "ean8: check digit calculation" {
    // EAN-8 for "9638507" should have check digit 4
    const check = calculateCheckDigit("9638507");
    try std.testing.expectEqual(@as(u8, 4), check);
}

test "ean8: check digit for 1234567" {
    // Weights: 3,1,3,1,3,1,3 => 1*3+2*1+3*3+4*1+5*3+6*1+7*3 = 3+2+9+4+15+6+21 = 60
    // 60 % 10 = 0, check = 0
    const check = calculateCheckDigit("1234567");
    try std.testing.expectEqual(@as(u8, 0), check);
}

test "ean8: encode produces 67 modules" {
    const allocator = std.testing.allocator;
    const result = try encode(allocator, "9638507");
    defer allocator.free(result);
    // EAN-8 total: 3 + 4*7 + 5 + 4*7 + 3 = 67 modules
    try std.testing.expectEqual(@as(usize, 67), result.len);
}

test "ean8: encode with check digit" {
    const allocator = std.testing.allocator;
    const result = try encode(allocator, "96385074");
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 67), result.len);
}

test "ean8: encode starts with start guard" {
    const allocator = std.testing.allocator;
    const result = try encode(allocator, "96385074");
    defer allocator.free(result);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 1, 0, 1 }, result[0..3]);
}

test "ean8: encode ends with end guard" {
    const allocator = std.testing.allocator;
    const result = try encode(allocator, "96385074");
    defer allocator.free(result);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 1, 0, 1 }, result[64..67]);
}

test "ean8: render produces PDF operators" {
    const allocator = std.testing.allocator;
    const result = try render(allocator, "96385074", 10, 20, 200, 80);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "q\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Q\n") != null);
}

test "ean8: invalid length rejected" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidLength, encode(allocator, "123"));
}

test "ean8: invalid characters rejected" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidCharacter, encode(allocator, "963850A"));
}
