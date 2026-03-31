const std = @import("std");
const Color = @import("../color/color.zig").Color;
const StandardFont = @import("../font/standard_fonts.zig").StandardFont;
const Page = @import("../document/page.zig").Page;

/// A span of text with uniform styling.
pub const TextSpan = struct {
    text: []const u8,
    font: StandardFont = .helvetica,
    font_size: f32 = 12,
    color: Color = .{ .named = .black },
    /// Superscript offset (positive = up)
    rise: f32 = 0,
    /// Character spacing in points
    char_spacing: f32 = 0,
    /// Word spacing in points
    word_spacing: f32 = 0,
    /// Underline this span
    underline: bool = false,
    /// Strikethrough this span
    strikethrough: bool = false,
};

/// Alignment for the rich text block.
pub const RichTextAlignment = enum {
    left,
    center,
    right,
    justify,
};

/// Options for a rich text block.
pub const RichTextOptions = struct {
    x: f32,
    y: f32,
    max_width: f32,
    line_height_factor: f32 = 1.2,
    alignment: RichTextAlignment = .left,
    /// First line indent in points
    first_line_indent: f32 = 0,
};

/// A laid-out piece of a span on a single line.
const LayoutFragment = struct {
    span_index: usize,
    text: []const u8,
    width: f32,
    font: StandardFont,
    font_size: f32,
    color: Color,
    rise: f32,
    char_spacing: f32,
    word_spacing: f32,
    underline: bool,
    strikethrough: bool,
};

/// A single laid-out line of rich text.
const LayoutLine = struct {
    fragments: []LayoutFragment,
    width: f32,
    max_font_size: f32,
    y: f32,
};

/// A word carrying its source span styling.
const Word = struct {
    text: []const u8,
    width: f32,
    span_index: usize,
    font: StandardFont,
    font_size: f32,
    color: Color,
    rise: f32,
    char_spacing: f32,
    word_spacing: f32,
    underline: bool,
    strikethrough: bool,
    trailing_space_width: f32,
};

/// Render rich text spans into a page's content stream.
/// Returns the total height consumed by the text block.
pub fn drawRichText(
    page: *Page,
    spans: []const TextSpan,
    options: RichTextOptions,
) !f32 {
    const allocator = page.allocator;

    // 1. Break spans into words
    var words = std.ArrayListUnmanaged(Word){};
    defer words.deinit(allocator);

    for (spans, 0..) |span, si| {
        if (span.text.len == 0) continue;

        var start: usize = 0;
        var i: usize = 0;
        while (i < span.text.len) {
            if (span.text[i] == ' ') {
                if (i > start) {
                    const word_text = span.text[start..i];
                    const space_w = span.font.textWidth(" ", span.font_size);
                    try words.append(allocator, .{
                        .text = word_text,
                        .width = span.font.textWidth(word_text, span.font_size),
                        .span_index = si,
                        .font = span.font,
                        .font_size = span.font_size,
                        .color = span.color,
                        .rise = span.rise,
                        .char_spacing = span.char_spacing,
                        .word_spacing = span.word_spacing,
                        .underline = span.underline,
                        .strikethrough = span.strikethrough,
                        .trailing_space_width = space_w,
                    });
                }
                start = i + 1;
            }
            i += 1;
        }
        // Last word in span (no trailing space)
        if (start < span.text.len) {
            const word_text = span.text[start..];
            try words.append(allocator, .{
                .text = word_text,
                .width = span.font.textWidth(word_text, span.font_size),
                .span_index = si,
                .font = span.font,
                .font_size = span.font_size,
                .color = span.color,
                .rise = span.rise,
                .char_spacing = span.char_spacing,
                .word_spacing = span.word_spacing,
                .underline = span.underline,
                .strikethrough = span.strikethrough,
                .trailing_space_width = 0,
            });
        }
    }

    if (words.items.len == 0) return 0;

    // 2. Layout words into lines
    var lines = std.ArrayListUnmanaged(LayoutLine){};
    defer {
        for (lines.items) |line| {
            allocator.free(line.fragments);
        }
        lines.deinit(allocator);
    }

    var line_fragments = std.ArrayListUnmanaged(LayoutFragment){};
    defer line_fragments.deinit(allocator);

    var line_width: f32 = 0;
    var max_fs: f32 = 0;
    var is_first_line = true;

    for (words.items, 0..) |word, wi| {
        const indent: f32 = if (is_first_line) options.first_line_indent else 0;
        const available = options.max_width - indent;

        // Width needed: word width + space (if not first word on line)
        const space_before: f32 = if (line_fragments.items.len > 0) word.trailing_space_width else 0;
        const needed = line_width + space_before + word.width;

        if (line_fragments.items.len > 0 and needed > available) {
            // Finalize current line
            const frags = try allocator.dupe(LayoutFragment, line_fragments.items);
            try lines.append(allocator, .{
                .fragments = frags,
                .width = line_width,
                .max_font_size = max_fs,
                .y = 0, // computed later
            });
            line_fragments.clearRetainingCapacity();
            line_width = 0;
            max_fs = 0;
            is_first_line = false;
        }

        // Add space fragment before word if not first on line
        if (line_fragments.items.len > 0) {
            // Add the space width to the previous fragment's effective width
            line_width += word.trailing_space_width;
        }

        try line_fragments.append(allocator, .{
            .span_index = word.span_index,
            .text = word.text,
            .width = word.width,
            .font = word.font,
            .font_size = word.font_size,
            .color = word.color,
            .rise = word.rise,
            .char_spacing = word.char_spacing,
            .word_spacing = word.word_spacing,
            .underline = word.underline,
            .strikethrough = word.strikethrough,
        });
        line_width += word.width;
        if (word.font_size > max_fs) max_fs = word.font_size;

        _ = wi;
    }

    // Final line
    if (line_fragments.items.len > 0) {
        const frags = try allocator.dupe(LayoutFragment, line_fragments.items);
        try lines.append(allocator, .{
            .fragments = frags,
            .width = line_width,
            .max_font_size = max_fs,
            .y = 0,
        });
    }

    // 3. Compute Y positions (top to bottom, PDF coordinates go up)
    var cur_y = options.y;
    for (lines.items) |*line| {
        line.y = cur_y;
        cur_y -= line.max_font_size * options.line_height_factor;
    }

    const total_height = options.y - cur_y;

    // 4. Render each line
    const writer = page.content.writer(page.allocator);

    for (lines.items, 0..) |line, line_idx| {
        const indent: f32 = if (line_idx == 0) options.first_line_indent else 0;
        const available = options.max_width - indent;
        const base_x = options.x + indent;

        // Calculate starting X based on alignment
        var x_offset: f32 = 0;
        var justify_extra_space: f32 = 0;
        const gap_count = if (line.fragments.len > 1) line.fragments.len - 1 else 0;

        switch (options.alignment) {
            .left => {},
            .center => {
                x_offset = (available - line.width) / 2.0;
            },
            .right => {
                x_offset = available - line.width;
            },
            .justify => {
                // Don't justify the last line
                if (line_idx < lines.items.len - 1 and gap_count > 0) {
                    justify_extra_space = (available - line.width) / @as(f32, @floatFromInt(gap_count));
                }
            },
        }

        // Begin text object
        try writer.writeAll("BT\n");

        var cur_x = base_x + x_offset;

        for (line.fragments, 0..) |frag, fi| {
            // Look up font resource name
            const font_pdf_name = frag.font.pdfName();
            const res_name = if (page.resources.fonts.get(font_pdf_name)) |fr|
                fr.name
            else
                "F1";

            // Set font
            try writer.print("/{s} {d:.2} Tf\n", .{ res_name, frag.font_size });

            // Set color
            try frag.color.writeColorOps(writer, true);

            // Set text rise
            if (frag.rise != 0) {
                try writer.print("{d:.2} Ts\n", .{frag.rise});
            } else {
                try writer.writeAll("0 Ts\n");
            }

            // Set char spacing
            if (frag.char_spacing != 0) {
                try writer.print("{d:.2} Tc\n", .{frag.char_spacing});
            }

            // Set word spacing
            if (frag.word_spacing != 0) {
                try writer.print("{d:.2} Tw\n", .{frag.word_spacing});
            }

            // Position
            try writer.print("{d:.2} {d:.2} Td\n", .{ cur_x, line.y });

            // Draw text
            try writer.writeAll("(");
            for (frag.text) |ch| {
                switch (ch) {
                    '(' => try writer.writeAll("\\("),
                    ')' => try writer.writeAll("\\)"),
                    '\\' => try writer.writeAll("\\\\"),
                    else => try writer.print("{c}", .{ch}),
                }
            }
            try writer.writeAll(") Tj\n");

            // Advance X position
            const advance = frag.width + if (fi < line.fragments.len - 1)
                (frag.font.textWidth(" ", frag.font_size) + justify_extra_space)
            else
                @as(f32, 0);
            cur_x += advance;
        }

        try writer.writeAll("ET\n");

        // 5. Draw underlines and strikethroughs outside text object
        cur_x = base_x + x_offset;
        for (line.fragments, 0..) |frag, fi| {
            if (frag.underline) {
                const descent = @as(f32, @floatFromInt(frag.font.descender())) * frag.font_size / 1000.0;
                const ul_y = line.y + descent;
                try drawDecorationLine(writer, cur_x, ul_y, frag.width, frag.color, frag.font_size * 0.05);
            }

            if (frag.strikethrough) {
                const st_y = line.y + frag.font_size * 0.3;
                try drawDecorationLine(writer, cur_x, st_y, frag.width, frag.color, frag.font_size * 0.05);
            }

            const advance = frag.width + if (fi < line.fragments.len - 1)
                (frag.font.textWidth(" ", frag.font_size) + justify_extra_space)
            else
                @as(f32, 0);
            cur_x += advance;
        }
    }

    return total_height;
}

fn drawDecorationLine(writer: anytype, x: f32, y: f32, width: f32, c: Color, line_width: f32) !void {
    try writer.writeAll("q\n");
    try c.writeColorOps(writer, false);
    try writer.print("{d:.2} w\n", .{line_width});
    try writer.print("{d:.2} {d:.2} m\n", .{ x, y });
    try writer.print("{d:.2} {d:.2} l\n", .{ x + width, y });
    try writer.writeAll("S\n");
    try writer.writeAll("Q\n");
}
