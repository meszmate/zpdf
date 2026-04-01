const std = @import("std");
const Allocator = std.mem.Allocator;
const ean13 = @import("ean13.zig");

/// Calculate the UPC-A check digit for an 11-digit input.
pub fn calculateCheckDigit(digits: []const u8) u8 {
    // UPC-A check digit uses the same algorithm as EAN-13
    // but on 11 digits. We prepend a "0" to make it 12 digits
    // and use the EAN-13 algorithm.
    var buf: [12]u8 = undefined;
    buf[0] = '0';
    for (digits, 0..) |d, i| {
        buf[i + 1] = d;
    }
    return ean13.calculateCheckDigit(&buf);
}

/// Encode a UPC-A barcode by delegating to EAN-13 with a leading "0".
/// Accepts 11 digits (data only) or 12 digits (data + check digit).
/// Returns an array where 1 = bar and 0 = space (95 modules).
pub fn encode(allocator: Allocator, value: []const u8) ![]u8 {
    if (value.len != 11 and value.len != 12) return error.InvalidLength;

    for (value) |c| {
        if (c < '0' or c > '9') return error.InvalidCharacter;
    }

    // Build a 13-digit EAN-13 string: "0" + UPC-A digits
    var ean13_buf: [13]u8 = undefined;
    ean13_buf[0] = '0';

    if (value.len == 11) {
        @memcpy(ean13_buf[1..12], value[0..11]);
        ean13_buf[12] = calculateCheckDigit(value[0..11]) + '0';
    } else {
        @memcpy(ean13_buf[1..13], value[0..12]);
    }

    return ean13.encode(allocator, &ean13_buf);
}

/// Render a UPC-A barcode as PDF content stream operators.
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

test "upca: check digit calculation" {
    // UPC-A for "03600029145" should have check digit 2
    const check = calculateCheckDigit("03600029145");
    try std.testing.expectEqual(@as(u8, 2), check);
}

test "upca: encode produces 95 modules" {
    const allocator = std.testing.allocator;
    const result = try encode(allocator, "03600029145");
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 95), result.len);
}

test "upca: encode with check digit" {
    const allocator = std.testing.allocator;
    const result = try encode(allocator, "036000291452");
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 95), result.len);
}

test "upca: render produces PDF operators" {
    const allocator = std.testing.allocator;
    const result = try render(allocator, "036000291452", 10, 20, 200, 80);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "q\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Q\n") != null);
}

test "upca: invalid length rejected" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidLength, encode(allocator, "123"));
}

test "upca: invalid characters rejected" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidCharacter, encode(allocator, "0360002914A"));
}
