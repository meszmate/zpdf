const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StandardFont = @import("../font/standard_fonts.zig").StandardFont;

/// A single laid-out line of text with its measured width.
pub const TextLine = struct {
    /// The text content of this line (a slice into the original string).
    text: []const u8,
    /// The measured width of this line in PDF points.
    width: f32,
    /// Byte offset of the start of this line in the original text.
    start: usize,
    /// Byte offset of the end of this line in the original text (exclusive).
    end: usize,
};

/// Lays out text into lines, splitting on whitespace and wrapping at max_width.
/// Handles embedded newlines as forced line breaks.
/// Caller owns the returned slice and must free it with the same allocator.
pub fn layoutText(
    allocator: Allocator,
    text: []const u8,
    font: StandardFont,
    font_size: f32,
    max_width: ?f32,
) ![]TextLine {
    var lines: ArrayList(TextLine) = .{};
    errdefer lines.deinit(allocator);

    if (text.len == 0) {
        return lines.toOwnedSlice(allocator);
    }

    // Split on newlines first, then wrap each paragraph.
    var para_start: usize = 0;
    while (para_start <= text.len) {
        // Find the end of this paragraph (next newline or end of text).
        var para_end = para_start;
        while (para_end < text.len and text[para_end] != '\n') {
            para_end += 1;
        }

        const paragraph = text[para_start..para_end];

        if (paragraph.len == 0) {
            // Empty paragraph (consecutive newline or trailing newline).
            try lines.append(allocator, .{
                .text = paragraph,
                .width = 0,
                .start = para_start,
                .end = para_end,
            });
        } else {
            // Wrap this paragraph.
            try wrapParagraph(allocator, &lines, paragraph, para_start, font, font_size, max_width);
        }

        para_start = para_end + 1;
    }

    return lines.toOwnedSlice(allocator);
}

/// Wraps a single paragraph (no embedded newlines) into lines.
fn wrapParagraph(
    allocator: Allocator,
    lines: *ArrayList(TextLine),
    paragraph: []const u8,
    base_offset: usize,
    font: StandardFont,
    font_size: f32,
    max_width: ?f32,
) !void {
    const space_width = font.textWidth(" ", font_size);
    const limit = max_width orelse std.math.floatMax(f32);

    var line_start: usize = 0;
    var line_width: f32 = 0;
    var word_start: usize = 0;
    var i: usize = 0;

    // Skip leading spaces.
    while (i < paragraph.len and paragraph[i] == ' ') {
        i += 1;
    }
    line_start = i;
    word_start = i;

    while (i <= paragraph.len) {
        // Find word boundaries.
        if (i == paragraph.len or paragraph[i] == ' ') {
            if (word_start < i) {
                const word = paragraph[word_start..i];
                const word_width = font.textWidth(word, font_size);

                if (line_width > 0 and line_width + space_width + word_width > limit) {
                    // Wrap: emit current line, start new one with this word.
                    var trimmed_end = word_start;
                    while (trimmed_end > line_start and paragraph[trimmed_end - 1] == ' ') {
                        trimmed_end -= 1;
                    }
                    const line_text = paragraph[line_start..trimmed_end];
                    const measured = font.textWidth(line_text, font_size);
                    try lines.append(allocator, .{
                        .text = line_text,
                        .width = measured,
                        .start = base_offset + line_start,
                        .end = base_offset + trimmed_end,
                    });
                    line_start = word_start;
                    line_width = word_width;
                } else {
                    if (line_width > 0) {
                        line_width += space_width;
                    }
                    line_width += word_width;
                }
            }
            // At end of paragraph, break out of the loop.
            if (i == paragraph.len) break;
            // Skip spaces.
            while (i < paragraph.len and paragraph[i] == ' ') {
                i += 1;
            }
            word_start = i;
        } else {
            i += 1;
        }
    }

    // Emit the last line.
    var trimmed_end = paragraph.len;
    while (trimmed_end > line_start and paragraph[trimmed_end - 1] == ' ') {
        trimmed_end -= 1;
    }
    if (trimmed_end > line_start or lines.items.len == 0) {
        const line_text = paragraph[line_start..trimmed_end];
        const measured = font.textWidth(line_text, font_size);
        try lines.append(allocator, .{
            .text = line_text,
            .width = measured,
            .start = base_offset + line_start,
            .end = base_offset + trimmed_end,
        });
    }
}

/// Calculates the total height needed to render the given lines.
pub fn measureTextHeight(lines: []const TextLine, font_size: f32, line_height: f32) f32 {
    if (lines.len == 0) return 0;
    _ = font_size;
    return @as(f32, @floatFromInt(lines.len)) * line_height;
}

// -- Tests --

test "layout single line no wrap" {
    const lines = try layoutText(std.testing.allocator, "Hello World", .helvetica, 12.0, null);
    defer std.testing.allocator.free(lines);

    try std.testing.expectEqual(@as(usize, 1), lines.len);
    try std.testing.expectEqualStrings("Hello World", lines[0].text);
}

test "layout empty text" {
    const lines = try layoutText(std.testing.allocator, "", .helvetica, 12.0, null);
    defer std.testing.allocator.free(lines);
    try std.testing.expectEqual(@as(usize, 0), lines.len);
}

test "layout with newlines" {
    const lines = try layoutText(std.testing.allocator, "Line 1\nLine 2\nLine 3", .helvetica, 12.0, null);
    defer std.testing.allocator.free(lines);

    try std.testing.expectEqual(@as(usize, 3), lines.len);
    try std.testing.expectEqualStrings("Line 1", lines[0].text);
    try std.testing.expectEqualStrings("Line 2", lines[1].text);
    try std.testing.expectEqualStrings("Line 3", lines[2].text);
}

test "layout with wrapping" {
    // "Hello" in Helvetica at 12pt = (722+556+222+222+556)/1000*12 = ~27.3pt
    // "World" = (944+556+333+222+500)/1000*12 = ~30.7pt
    // space = 278/1000*12 = ~3.3pt
    // Total ~61.3pt. With max_width=50, should wrap.
    const lines = try layoutText(std.testing.allocator, "Hello World", .helvetica, 12.0, 50.0);
    defer std.testing.allocator.free(lines);

    try std.testing.expectEqual(@as(usize, 2), lines.len);
    try std.testing.expectEqualStrings("Hello", lines[0].text);
    try std.testing.expectEqualStrings("World", lines[1].text);
}

test "measure text height" {
    const dummy = [_]TextLine{
        .{ .text = "a", .width = 10, .start = 0, .end = 1 },
        .{ .text = "b", .width = 10, .start = 2, .end = 3 },
        .{ .text = "c", .width = 10, .start = 4, .end = 5 },
    };
    const height = measureTextHeight(&dummy, 12.0, 14.4);
    try std.testing.expectApproxEqAbs(@as(f32, 43.2), height, 0.1);
}
