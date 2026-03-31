const std = @import("std");
const color_mod = @import("color.zig");
const RgbColor = color_mod.RgbColor;
const CmykColor = color_mod.CmykColor;
const NamedColor = color_mod.NamedColor;

/// Convert RGB color values to CMYK.
pub fn rgbToCmyk(r: u8, g: u8, b: u8) CmykColor {
    const rf: f32 = @as(f32, @floatFromInt(r)) / 255.0;
    const gf: f32 = @as(f32, @floatFromInt(g)) / 255.0;
    const bf: f32 = @as(f32, @floatFromInt(b)) / 255.0;

    const k: f32 = 1.0 - @max(rf, @max(gf, bf));

    if (k >= 1.0) {
        return .{ .c = 0.0, .m = 0.0, .y = 0.0, .k = 1.0 };
    }

    const inv_k = 1.0 - k;
    return .{
        .c = (1.0 - rf - k) / inv_k,
        .m = (1.0 - gf - k) / inv_k,
        .y = (1.0 - bf - k) / inv_k,
        .k = k,
    };
}

/// Convert CMYK color values to RGB.
pub fn cmykToRgb(c: f32, m: f32, y: f32, k: f32) RgbColor {
    const r = (1.0 - c) * (1.0 - k);
    const g = (1.0 - m) * (1.0 - k);
    const b = (1.0 - y) * (1.0 - k);
    return .{
        .r = @intFromFloat(@round(r * 255.0)),
        .g = @intFromFloat(@round(g * 255.0)),
        .b = @intFromFloat(@round(b * 255.0)),
    };
}

/// Convert RGB color values to a grayscale value (0.0-1.0) using luminance weights.
pub fn rgbToGrayscale(r: u8, g: u8, b: u8) f32 {
    const rf: f32 = @as(f32, @floatFromInt(r)) / 255.0;
    const gf: f32 = @as(f32, @floatFromInt(g)) / 255.0;
    const bf: f32 = @as(f32, @floatFromInt(b)) / 255.0;
    // ITU-R BT.709 luminance coefficients
    return 0.2126 * rf + 0.7152 * gf + 0.0722 * bf;
}

/// Convert a named color to its RGB representation.
pub fn namedToRgb(named: NamedColor) RgbColor {
    return switch (named) {
        .black => .{ .r = 0, .g = 0, .b = 0 },
        .white => .{ .r = 255, .g = 255, .b = 255 },
        .red => .{ .r = 255, .g = 0, .b = 0 },
        .green => .{ .r = 0, .g = 128, .b = 0 },
        .blue => .{ .r = 0, .g = 0, .b = 255 },
        .yellow => .{ .r = 255, .g = 255, .b = 0 },
        .cyan => .{ .r = 0, .g = 255, .b = 255 },
        .magenta => .{ .r = 255, .g = 0, .b = 255 },
        .orange => .{ .r = 255, .g = 165, .b = 0 },
        .purple => .{ .r = 128, .g = 0, .b = 128 },
        .brown => .{ .r = 139, .g = 69, .b = 19 },
        .pink => .{ .r = 255, .g = 192, .b = 203 },
        .gray => .{ .r = 128, .g = 128, .b = 128 },
        .light_gray => .{ .r = 192, .g = 192, .b = 192 },
        .dark_gray => .{ .r = 64, .g = 64, .b = 64 },
        .navy => .{ .r = 0, .g = 0, .b = 128 },
        .teal => .{ .r = 0, .g = 128, .b = 128 },
        .maroon => .{ .r = 128, .g = 0, .b = 0 },
        .olive => .{ .r = 128, .g = 128, .b = 0 },
        .lime => .{ .r = 0, .g = 255, .b = 0 },
        .aqua => .{ .r = 0, .g = 255, .b = 255 },
        .coral => .{ .r = 255, .g = 127, .b = 80 },
        .salmon => .{ .r = 250, .g = 128, .b = 114 },
        .gold => .{ .r = 255, .g = 215, .b = 0 },
    };
}

// -- Tests --

test "rgbToCmyk black" {
    const cmyk = rgbToCmyk(0, 0, 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), cmyk.c, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), cmyk.m, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), cmyk.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), cmyk.k, 0.01);
}

test "rgbToCmyk white" {
    const cmyk = rgbToCmyk(255, 255, 255);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), cmyk.c, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), cmyk.m, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), cmyk.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), cmyk.k, 0.01);
}

test "rgbToCmyk red" {
    const cmyk = rgbToCmyk(255, 0, 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), cmyk.c, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), cmyk.m, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), cmyk.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), cmyk.k, 0.01);
}

test "cmykToRgb red" {
    const rgb = cmykToRgb(0.0, 1.0, 1.0, 0.0);
    try std.testing.expectEqual(@as(u8, 255), rgb.r);
    try std.testing.expectEqual(@as(u8, 0), rgb.g);
    try std.testing.expectEqual(@as(u8, 0), rgb.b);
}

test "cmykToRgb black" {
    const rgb = cmykToRgb(0.0, 0.0, 0.0, 1.0);
    try std.testing.expectEqual(@as(u8, 0), rgb.r);
    try std.testing.expectEqual(@as(u8, 0), rgb.g);
    try std.testing.expectEqual(@as(u8, 0), rgb.b);
}

test "rgbToGrayscale" {
    const g = rgbToGrayscale(128, 128, 128);
    try std.testing.expectApproxEqAbs(@as(f32, 0.502), g, 0.01);
}

test "rgbToGrayscale white" {
    const g = rgbToGrayscale(255, 255, 255);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), g, 0.01);
}

test "rgbToGrayscale black" {
    const g = rgbToGrayscale(0, 0, 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), g, 0.01);
}

test "namedToRgb red" {
    const rgb = namedToRgb(.red);
    try std.testing.expectEqual(@as(u8, 255), rgb.r);
    try std.testing.expectEqual(@as(u8, 0), rgb.g);
    try std.testing.expectEqual(@as(u8, 0), rgb.b);
}

test "namedToRgb black" {
    const rgb = namedToRgb(.black);
    try std.testing.expectEqual(@as(u8, 0), rgb.r);
    try std.testing.expectEqual(@as(u8, 0), rgb.g);
    try std.testing.expectEqual(@as(u8, 0), rgb.b);
}

test "roundtrip rgb->cmyk->rgb" {
    const original_r: u8 = 100;
    const original_g: u8 = 150;
    const original_b: u8 = 200;
    const cmyk = rgbToCmyk(original_r, original_g, original_b);
    const rgb = cmykToRgb(cmyk.c, cmyk.m, cmyk.y, cmyk.k);
    try std.testing.expectEqual(original_r, rgb.r);
    try std.testing.expectEqual(original_g, rgb.g);
    try std.testing.expectEqual(original_b, rgb.b);
}
