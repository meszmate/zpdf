const std = @import("std");
const zpdf = @import("zpdf");
const testing = std.testing;

const TextStyle = zpdf.text.text_style.TextStyle;
const Alignment = zpdf.text.text_style.Alignment;
const layoutText = zpdf.text.text_layout.layoutText;
const measureTextHeight = zpdf.text.text_layout.measureTextHeight;
const renderText = zpdf.text.text_renderer.renderText;
const color = zpdf.color;

test "TextStyle defaults" {
    const style = TextStyle{};
    try testing.expectApproxEqAbs(@as(f32, 12.0), style.font_size, 0.001);
    try testing.expectEqual(Alignment.left, style.alignment);
    try testing.expectApproxEqAbs(@as(f32, 14.4), style.getLineHeight(), 0.001);
}

test "TextStyle explicit line height" {
    const style = TextStyle{ .font_size = 10.0, .line_height = 15.0 };
    try testing.expectApproxEqAbs(@as(f32, 15.0), style.getLineHeight(), 0.001);
}

test "layoutText single line no wrap" {
    const lines = try layoutText(testing.allocator, "Hello World", .helvetica, 12.0, null);
    defer testing.allocator.free(lines);
    try testing.expectEqual(@as(usize, 1), lines.len);
    try testing.expectEqualStrings("Hello World", lines[0].text);
}

test "layoutText wrapping" {
    const lines = try layoutText(testing.allocator, "Hello World", .helvetica, 12.0, 50.0);
    defer testing.allocator.free(lines);
    try testing.expectEqual(@as(usize, 2), lines.len);
    try testing.expectEqualStrings("Hello", lines[0].text);
    try testing.expectEqualStrings("World", lines[1].text);
}

test "layoutText empty text" {
    const lines = try layoutText(testing.allocator, "", .helvetica, 12.0, null);
    defer testing.allocator.free(lines);
    try testing.expectEqual(@as(usize, 0), lines.len);
}

test "renderText produces BT/ET block" {
    const result = try renderText(testing.allocator, "Hello", .{
        .x = 72,
        .y = 720,
        .font_name = "Helvetica",
        .font_size = 12,
        .color = color.rgb(0, 0, 0),
    });
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "BT\n") != null);
    try testing.expect(std.mem.indexOf(u8, result, "/Helvetica") != null);
    try testing.expect(std.mem.indexOf(u8, result, "(Hello) Tj\n") != null);
    try testing.expect(std.mem.indexOf(u8, result, "ET\n") != null);
}

test "renderText empty returns empty" {
    const result = try renderText(testing.allocator, "", .{
        .x = 72,
        .y = 720,
        .font_name = "Helvetica",
        .font_size = 12,
        .color = color.rgb(0, 0, 0),
    });
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(usize, 0), result.len);
}
