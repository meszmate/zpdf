const color_mod = @import("../color/color.zig");
const Color = color_mod.Color;
const StandardFont = @import("../font/standard_fonts.zig").StandardFont;

/// Text alignment options.
pub const Alignment = enum {
    left,
    center,
    right,
    justify,
};

/// Describes the visual style of rendered text.
pub const TextStyle = struct {
    font: StandardFont = .helvetica,
    font_size: f32 = 12.0,
    color: Color = color_mod.rgb(0, 0, 0),
    /// Line height override. If null, defaults to font_size * 1.2.
    line_height: ?f32 = null,
    alignment: Alignment = .left,
    /// Maximum width for text wrapping. If null, text is not wrapped.
    max_width: ?f32 = null,

    /// Returns the effective line height (explicit or computed from font size).
    pub fn getLineHeight(self: TextStyle) f32 {
        return self.line_height orelse self.font_size * 1.2;
    }
};

const std = @import("std");

test "default style" {
    const style = TextStyle{};
    try std.testing.expectEqual(StandardFont.helvetica, style.font);
    try std.testing.expectApproxEqAbs(@as(f32, 12.0), style.font_size, 0.001);
    try std.testing.expectEqual(Alignment.left, style.alignment);
}

test "line height default" {
    const style = TextStyle{ .font_size = 10.0 };
    try std.testing.expectApproxEqAbs(@as(f32, 12.0), style.getLineHeight(), 0.001);
}

test "line height explicit" {
    const style = TextStyle{ .font_size = 10.0, .line_height = 15.0 };
    try std.testing.expectApproxEqAbs(@as(f32, 15.0), style.getLineHeight(), 0.001);
}
