const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const color_mod = @import("../color/color.zig");
const Color = color_mod.Color;
const Alignment = @import("text_style.zig").Alignment;
const layout = @import("text_layout.zig");
const TextLine = layout.TextLine;
const StandardFont = @import("../font/standard_fonts.zig").StandardFont;

/// Options for rendering text into PDF content stream operators.
pub const TextDrawOptions = struct {
    x: f32,
    y: f32,
    font_name: []const u8,
    font_size: f32,
    color: Color,
    alignment: Alignment = .left,
    max_width: ?f32 = null,
    line_height: ?f32 = null,
};

/// Renders text into PDF content stream operators (BT/ET block).
/// Handles multi-line text with wrapping and alignment.
/// Caller owns the returned memory.
pub fn renderText(allocator: Allocator, text: []const u8, options: TextDrawOptions) ![]u8 {
    var buf: ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);

    const writer = buf.writer(allocator);
    const effective_line_height = options.line_height orelse options.font_size * 1.2;

    // Layout text into lines.
    const lines = try layout.layoutText(allocator, text, .helvetica, options.font_size, options.max_width);
    defer allocator.free(lines);

    if (lines.len == 0) {
        return buf.toOwnedSlice(allocator);
    }

    // Set fill color for text.
    try options.color.writeColorOps(writer, true);

    // Begin text object.
    try writer.print("BT\n", .{});

    // Set font and size.
    try writer.print("/{s} {d:.4} Tf\n", .{ options.font_name, options.font_size });

    for (lines, 0..) |line, i| {
        if (line.text.len == 0) continue;

        // Calculate x position based on alignment.
        var x = options.x;
        if (options.max_width) |max_w| {
            switch (options.alignment) {
                .left => {},
                .center => {
                    x = options.x + (max_w - line.width) / 2.0;
                },
                .right => {
                    x = options.x + max_w - line.width;
                },
                .justify => {
                    // Justify is left-aligned for the last line.
                },
            }
        }

        // Calculate y position (PDF y-axis goes up; successive lines move down).
        const y = options.y - @as(f32, @floatFromInt(i)) * effective_line_height;

        // Position the text cursor.
        try writer.print("{d:.4} {d:.4} Td\n", .{ x, y });

        // Write the text string, escaping special PDF characters.
        try writer.print("(", .{});
        for (line.text) |ch| {
            switch (ch) {
                '(' => try writer.print("\\(", .{}),
                ')' => try writer.print("\\)", .{}),
                '\\' => try writer.print("\\\\", .{}),
                else => try writer.print("{c}", .{ch}),
            }
        }
        try writer.print(") Tj\n", .{});
    }

    // End text object.
    try writer.print("ET\n", .{});

    return buf.toOwnedSlice(allocator);
}

/// Escapes special characters for PDF text strings.
fn escapePdfString(allocator: Allocator, text: []const u8) ![]u8 {
    var result: ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    for (text) |ch| {
        switch (ch) {
            '(' => try result.appendSlice(allocator, "\\("),
            ')' => try result.appendSlice(allocator, "\\)"),
            '\\' => try result.appendSlice(allocator, "\\\\"),
            else => try result.append(allocator, ch),
        }
    }

    return result.toOwnedSlice(allocator);
}

// -- Tests --

test "render simple text" {
    const result = try renderText(std.testing.allocator, "Hello", .{
        .x = 72,
        .y = 720,
        .font_name = "Helvetica",
        .font_size = 12,
        .color = color_mod.rgb(0, 0, 0),
    });
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "BT\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "/Helvetica") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "(Hello) Tj\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "ET\n") != null);
}

test "render text with special characters" {
    const result = try renderText(std.testing.allocator, "Hello (World)", .{
        .x = 72,
        .y = 720,
        .font_name = "Helvetica",
        .font_size = 12,
        .color = color_mod.rgb(0, 0, 0),
    });
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "\\(") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\\)") != null);
}

test "render empty text" {
    const result = try renderText(std.testing.allocator, "", .{
        .x = 72,
        .y = 720,
        .font_name = "Helvetica",
        .font_size = 12,
        .color = color_mod.rgb(0, 0, 0),
    });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "escape pdf string" {
    const result = try escapePdfString(std.testing.allocator, "test (parens) and \\backslash");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "\\(") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\\)") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\\\\") != null);
}
