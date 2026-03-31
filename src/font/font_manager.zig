const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const standard_fonts = @import("standard_fonts.zig");
const StandardFont = standard_fonts.StandardFont;

/// A reference to an indirect PDF object identified by object number and generation number.
/// Mirrors the Ref type from core/types.zig for self-contained usage.
pub const Ref = struct {
    obj_num: u32,
    gen_num: u16,

    pub fn eql(self: Ref, other: Ref) bool {
        return self.obj_num == other.obj_num and self.gen_num == other.gen_num;
    }
};

/// An embedded (non-standard) font with raw font data.
pub const EmbeddedFont = struct {
    name: []const u8,
    data: []const u8,
};

/// The type of font: either one of the 14 standard PDF fonts or an embedded font.
pub const FontType = union(enum) {
    standard: StandardFont,
    embedded: EmbeddedFont,
};

/// A handle to a registered font, combining a PDF object reference with font type information.
pub const FontHandle = struct {
    ref: ?Ref,
    font: FontType,
};

/// Manages font registration and provides text measurement utilities.
pub const FontManager = struct {
    allocator: Allocator,
    fonts: ArrayList(FontHandle),

    /// Initialize a new FontManager.
    pub fn init(allocator: Allocator) FontManager {
        return .{
            .allocator = allocator,
            .fonts = .{},
        };
    }

    /// Release all resources held by the FontManager.
    pub fn deinit(self: *FontManager) void {
        self.fonts.deinit(self.allocator);
    }

    /// Register a standard PDF font and return a handle to it.
    /// The handle initially has no PDF object reference (ref is null);
    /// the writer assigns one when the font is added to the PDF.
    pub fn addStandardFont(self: *FontManager, font: StandardFont) !FontHandle {
        const handle = FontHandle{
            .ref = null,
            .font = .{ .standard = font },
        };
        try self.fonts.append(self.allocator, handle);
        return handle;
    }

    /// Get the width of a single character in font units (out of 1000).
    pub fn getCharWidth(handle: FontHandle, char: u8) u16 {
        return switch (handle.font) {
            .standard => |sf| sf.charWidth(char),
            .embedded => 500, // default width for embedded fonts without metrics
        };
    }

    /// Calculate the width of a text string in points at a given font size.
    pub fn getTextWidth(handle: FontHandle, text: []const u8, font_size: f32) f32 {
        return switch (handle.font) {
            .standard => |sf| sf.textWidth(text, font_size),
            .embedded => blk: {
                const total: u32 = @as(u32, 500) * @as(u32, @intCast(text.len));
                break :blk @as(f32, @floatFromInt(total)) * font_size / 1000.0;
            },
        };
    }
};

// -- Tests --

test "FontManager init and deinit" {
    var fm = FontManager.init(std.testing.allocator);
    defer fm.deinit();
    try std.testing.expectEqual(@as(usize, 0), fm.fonts.items.len);
}

test "addStandardFont" {
    var fm = FontManager.init(std.testing.allocator);
    defer fm.deinit();

    const handle = try fm.addStandardFont(.helvetica);
    try std.testing.expect(handle.ref == null);
    try std.testing.expectEqual(@as(usize, 1), fm.fonts.items.len);
}

test "getCharWidth standard" {
    const handle = FontHandle{
        .ref = null,
        .font = .{ .standard = .helvetica },
    };
    try std.testing.expectEqual(@as(u16, 667), FontManager.getCharWidth(handle, 'A'));
}

test "getTextWidth standard" {
    const handle = FontHandle{
        .ref = null,
        .font = .{ .standard = .helvetica },
    };
    const w = FontManager.getTextWidth(handle, "Hello", 12.0);
    try std.testing.expectApproxEqAbs(@as(f32, 27.336), w, 0.01);
}

test "getCharWidth embedded" {
    const handle = FontHandle{
        .ref = null,
        .font = .{ .embedded = .{ .name = "CustomFont", .data = "" } },
    };
    try std.testing.expectEqual(@as(u16, 500), FontManager.getCharWidth(handle, 'A'));
}
