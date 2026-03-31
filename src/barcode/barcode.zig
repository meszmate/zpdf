const std = @import("std");
const Allocator = std.mem.Allocator;
const code128 = @import("code128.zig");
const code39 = @import("code39.zig");
const ean13 = @import("ean13.zig");
const qr_code = @import("qr/qr_code.zig");

/// Supported barcode types.
pub const BarcodeType = enum {
    code128,
    code39,
    ean13,
    qr,
};

/// Options for drawing a barcode.
pub const BarcodeOptions = struct {
    barcode_type: BarcodeType,
    value: []const u8,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    qr_error_level: qr_code.ErrorLevel = .medium,
};

/// Draw a barcode of the specified type and return PDF content stream operators.
/// Caller owns the returned memory.
pub fn drawBarcode(allocator: Allocator, options: BarcodeOptions) ![]u8 {
    return switch (options.barcode_type) {
        .code128 => try code128.render(allocator, options.value, options.x, options.y, options.width, options.height),
        .code39 => try code39.render(allocator, options.value, options.x, options.y, options.width, options.height),
        .ean13 => try ean13.render(allocator, options.value, options.x, options.y, options.width, options.height),
        .qr => {
            var qr = try qr_code.QrCode.generate(allocator, options.value, options.qr_error_level);
            defer qr.deinit();
            // For QR codes, use the smaller of width/height as the size
            const size = @min(options.width, options.height);
            return try qr.render(allocator, options.x, options.y, size);
        },
    };
}

// -- Tests --

test "barcode: draw code128" {
    const allocator = std.testing.allocator;
    const result = try drawBarcode(allocator, .{
        .barcode_type = .code128,
        .value = "ABC123",
        .x = 10,
        .y = 20,
        .width = 200,
        .height = 50,
    });
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "barcode: draw code39" {
    const allocator = std.testing.allocator;
    const result = try drawBarcode(allocator, .{
        .barcode_type = .code39,
        .value = "HELLO",
        .x = 0,
        .y = 0,
        .width = 300,
        .height = 60,
    });
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "barcode: draw ean13" {
    const allocator = std.testing.allocator;
    const result = try drawBarcode(allocator, .{
        .barcode_type = .ean13,
        .value = "5901234123457",
        .x = 10,
        .y = 10,
        .width = 200,
        .height = 80,
    });
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "barcode: draw qr" {
    const allocator = std.testing.allocator;
    const result = try drawBarcode(allocator, .{
        .barcode_type = .qr,
        .value = "Hello",
        .x = 10,
        .y = 10,
        .width = 100,
        .height = 100,
        .qr_error_level = .low,
    });
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}
