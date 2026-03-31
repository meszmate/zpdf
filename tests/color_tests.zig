const std = @import("std");
const zpdf = @import("zpdf");
const testing = std.testing;

const color = zpdf.color;
const conversion = zpdf.color_conversion;

test "rgb constructor" {
    const c = color.rgb(255, 128, 0);
    try testing.expectEqual(@as(u8, 255), c.rgb.r);
    try testing.expectEqual(@as(u8, 128), c.rgb.g);
    try testing.expectEqual(@as(u8, 0), c.rgb.b);
}

test "cmyk constructor" {
    const c = color.cmyk(0.5, 0.25, 0.0, 0.1);
    try testing.expectApproxEqAbs(@as(f32, 0.5), c.cmyk.c, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.25), c.cmyk.m, 0.001);
}

test "grayscale constructor" {
    const c = color.grayscale(0.5);
    try testing.expectApproxEqAbs(@as(f32, 0.5), c.grayscale.value, 0.001);
}

test "hexColor parsing" {
    const c1 = try color.hexColor("#FF8000");
    try testing.expectEqual(@as(u8, 255), c1.rgb.r);
    try testing.expectEqual(@as(u8, 128), c1.rgb.g);
    try testing.expectEqual(@as(u8, 0), c1.rgb.b);

    const c2 = try color.hexColor("00FF00");
    try testing.expectEqual(@as(u8, 255), c2.rgb.g);

    try testing.expectError(error.InvalidHexColor, color.hexColor("FFF"));
}

test "color conversion rgb to cmyk roundtrip" {
    const cmyk_val = conversion.rgbToCmyk(100, 150, 200);
    const rgb_back = conversion.cmykToRgb(cmyk_val.c, cmyk_val.m, cmyk_val.y, cmyk_val.k);
    try testing.expectEqual(@as(u8, 100), rgb_back.r);
    try testing.expectEqual(@as(u8, 150), rgb_back.g);
    try testing.expectEqual(@as(u8, 200), rgb_back.b);
}

test "toRgb from named color" {
    const c = color.Color{ .named = .red };
    const r = c.toRgb();
    try testing.expectEqual(@as(u8, 255), r.r);
    try testing.expectEqual(@as(u8, 0), r.g);
    try testing.expectEqual(@as(u8, 0), r.b);
}

test "toRgb from grayscale white" {
    const c = color.grayscale(1.0);
    const r = c.toRgb();
    try testing.expectEqual(@as(u8, 255), r.r);
    try testing.expectEqual(@as(u8, 255), r.g);
    try testing.expectEqual(@as(u8, 255), r.b);
}
