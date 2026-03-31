const std = @import("std");
const conversion = @import("conversion.zig");

/// An RGB color with 8-bit per channel.
pub const RgbColor = struct {
    r: u8,
    g: u8,
    b: u8,
};

/// A CMYK color with floating-point components (0.0-1.0).
pub const CmykColor = struct {
    c: f32,
    m: f32,
    y: f32,
    k: f32,
};

/// A grayscale color with a single floating-point value (0.0 = black, 1.0 = white).
pub const GrayscaleColor = struct {
    value: f32,
};

/// Common named colors.
pub const NamedColor = enum {
    black,
    white,
    red,
    green,
    blue,
    yellow,
    cyan,
    magenta,
    orange,
    purple,
    brown,
    pink,
    gray,
    light_gray,
    dark_gray,
    navy,
    teal,
    maroon,
    olive,
    lime,
    aqua,
    coral,
    salmon,
    gold,
};

/// A color value that can be RGB, CMYK, grayscale, or a named color.
pub const Color = union(enum) {
    rgb: RgbColor,
    cmyk: CmykColor,
    grayscale: GrayscaleColor,
    named: NamedColor,

    /// Convert any color variant to its RGB representation.
    pub fn toRgb(self: Color) RgbColor {
        return switch (self) {
            .rgb => |c| c,
            .cmyk => |c| conversion.cmykToRgb(c.c, c.m, c.y, c.k),
            .grayscale => |c| blk: {
                const v: u8 = @intFromFloat(@round(c.value * 255.0));
                break :blk .{ .r = v, .g = v, .b = v };
            },
            .named => |c| conversion.namedToRgb(c),
        };
    }

    /// Write the PDF color-setting operator to the given writer.
    /// If `fill` is true, uses lowercase operators (rg/k/g) for fill color;
    /// otherwise uses uppercase operators (RG/K/G) for stroke color.
    pub fn writeColorOps(self: Color, writer: anytype, fill: bool) !void {
        switch (self) {
            .rgb => |c| {
                try std.fmt.format(writer, "{d:.4} {d:.4} {d:.4} {s}\n", .{
                    @as(f32, @floatFromInt(c.r)) / 255.0,
                    @as(f32, @floatFromInt(c.g)) / 255.0,
                    @as(f32, @floatFromInt(c.b)) / 255.0,
                    if (fill) "rg" else "RG",
                });
            },
            .cmyk => |c| {
                try std.fmt.format(writer, "{d:.4} {d:.4} {d:.4} {d:.4} {s}\n", .{
                    c.c,
                    c.m,
                    c.y,
                    c.k,
                    if (fill) "k" else "K",
                });
            },
            .grayscale => |c| {
                try std.fmt.format(writer, "{d:.4} {s}\n", .{
                    c.value,
                    if (fill) "g" else "G",
                });
            },
            .named => |n| {
                const c = conversion.namedToRgb(n);
                try std.fmt.format(writer, "{d:.4} {d:.4} {d:.4} {s}\n", .{
                    @as(f32, @floatFromInt(c.r)) / 255.0,
                    @as(f32, @floatFromInt(c.g)) / 255.0,
                    @as(f32, @floatFromInt(c.b)) / 255.0,
                    if (fill) "rg" else "RG",
                });
            },
        }
    }
};

/// Create an RGB color.
pub fn rgb(r: u8, g: u8, b: u8) Color {
    return .{ .rgb = .{ .r = r, .g = g, .b = b } };
}

/// Create a CMYK color. Components should be in range 0.0-1.0.
pub fn cmyk(c: f32, m: f32, y: f32, k: f32) Color {
    return .{ .cmyk = .{ .c = c, .m = m, .y = y, .k = k } };
}

/// Create a grayscale color. Value should be in range 0.0 (black) to 1.0 (white).
pub fn grayscale(value: f32) Color {
    return .{ .grayscale = .{ .value = value } };
}

/// Parse a hex color string in the form "#RRGGBB" or "RRGGBB".
pub fn hexColor(hex: []const u8) !Color {
    const start: usize = if (hex.len > 0 and hex[0] == '#') 1 else 0;
    const digits = hex[start..];

    if (digits.len != 6) {
        return error.InvalidHexColor;
    }

    const r = parseHexByte(digits[0], digits[1]) orelse return error.InvalidHexColor;
    const g = parseHexByte(digits[2], digits[3]) orelse return error.InvalidHexColor;
    const b = parseHexByte(digits[4], digits[5]) orelse return error.InvalidHexColor;

    return rgb(r, g, b);
}

fn hexDigitToValue(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return null;
}

fn parseHexByte(hi: u8, lo: u8) ?u8 {
    const h = hexDigitToValue(hi) orelse return null;
    const l = hexDigitToValue(lo) orelse return null;
    return h * 16 + l;
}

// -- Tests --

test "rgb constructor" {
    const c = rgb(255, 128, 0);
    try std.testing.expectEqual(@as(u8, 255), c.rgb.r);
    try std.testing.expectEqual(@as(u8, 128), c.rgb.g);
    try std.testing.expectEqual(@as(u8, 0), c.rgb.b);
}

test "cmyk constructor" {
    const c = cmyk(0.5, 0.25, 0.0, 0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), c.cmyk.c, 0.001);
}

test "grayscale constructor" {
    const c = grayscale(0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), c.grayscale.value, 0.001);
}

test "hexColor with hash" {
    const c = try hexColor("#FF8000");
    try std.testing.expectEqual(@as(u8, 255), c.rgb.r);
    try std.testing.expectEqual(@as(u8, 128), c.rgb.g);
    try std.testing.expectEqual(@as(u8, 0), c.rgb.b);
}

test "hexColor without hash" {
    const c = try hexColor("00FF00");
    try std.testing.expectEqual(@as(u8, 0), c.rgb.r);
    try std.testing.expectEqual(@as(u8, 255), c.rgb.g);
    try std.testing.expectEqual(@as(u8, 0), c.rgb.b);
}

test "hexColor lowercase" {
    const c = try hexColor("#ff8000");
    try std.testing.expectEqual(@as(u8, 255), c.rgb.r);
    try std.testing.expectEqual(@as(u8, 128), c.rgb.g);
    try std.testing.expectEqual(@as(u8, 0), c.rgb.b);
}

test "hexColor invalid length" {
    try std.testing.expectError(error.InvalidHexColor, hexColor("FFF"));
}

test "hexColor invalid chars" {
    try std.testing.expectError(error.InvalidHexColor, hexColor("ZZZZZZ"));
}

test "toRgb named" {
    const c = Color{ .named = .red };
    const r = c.toRgb();
    try std.testing.expectEqual(@as(u8, 255), r.r);
    try std.testing.expectEqual(@as(u8, 0), r.g);
    try std.testing.expectEqual(@as(u8, 0), r.b);
}

test "toRgb grayscale" {
    const c = grayscale(1.0);
    const r = c.toRgb();
    try std.testing.expectEqual(@as(u8, 255), r.r);
    try std.testing.expectEqual(@as(u8, 255), r.g);
    try std.testing.expectEqual(@as(u8, 255), r.b);
}

test "toRgb cmyk" {
    const c = cmyk(0.0, 1.0, 1.0, 0.0);
    const r = c.toRgb();
    try std.testing.expectEqual(@as(u8, 255), r.r);
    try std.testing.expectEqual(@as(u8, 0), r.g);
    try std.testing.expectEqual(@as(u8, 0), r.b);
}

test "writeColorOps fill rgb" {
    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const c = rgb(128, 0, 255);
    try c.writeColorOps(stream.writer(), true);
    const written = stream.getWritten();
    try std.testing.expect(std.mem.endsWith(u8, written, "rg\n"));
}

test "writeColorOps stroke grayscale" {
    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const c = grayscale(0.5);
    try c.writeColorOps(stream.writer(), false);
    const written = stream.getWritten();
    try std.testing.expect(std.mem.endsWith(u8, written, "G\n"));
}

test "writeColorOps fill cmyk" {
    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const c = cmyk(1.0, 0.0, 0.0, 0.0);
    try c.writeColorOps(stream.writer(), true);
    const written = stream.getWritten();
    try std.testing.expect(std.mem.endsWith(u8, written, "k\n"));
}

test "writeColorOps stroke named" {
    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const c = Color{ .named = .blue };
    try c.writeColorOps(stream.writer(), false);
    const written = stream.getWritten();
    try std.testing.expect(std.mem.endsWith(u8, written, "RG\n"));
}
