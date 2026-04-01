const std = @import("std");
const Page = @import("../document/page.zig").Page;
const Color = @import("../color/color.zig").Color;
const StandardFont = @import("../font/standard_fonts.zig").StandardFont;

pub const ListStyle = enum {
    bullet, // bullet character
    dash, // -
    disc, // filled circle
    circle, // stroked circle
    square, // filled square
    numbered, // 1. 2. 3.
    lettered, // a. b. c.
    lettered_upper, // A. B. C.
    roman, // i. ii. iii.
    roman_upper, // I. II. III.
};

pub const ListItem = struct {
    text: []const u8,
    children: ?[]const ListItem = null, // nested sub-list
    child_style: ?ListStyle = null, // override style for children
};

pub const ListOptions = struct {
    x: f32,
    y: f32,
    max_width: f32,
    font: StandardFont = .helvetica,
    font_size: f32 = 12,
    color: Color = .{ .named = .black },
    line_height: f32 = 16,
    style: ListStyle = .bullet,
    indent: f32 = 20, // indent per nesting level
    marker_gap: f32 = 8, // gap between marker and text
    item_spacing: f32 = 4, // extra spacing between items
};

/// Render a list on a page. Returns total height consumed.
pub fn drawList(page: *Page, items: []const ListItem, options: ListOptions) !f32 {
    return drawListInternal(page, items, options, 0, 1);
}

fn drawListInternal(
    page: *Page,
    items: []const ListItem,
    options: ListOptions,
    level: u32,
    start_number: u32,
) !f32 {
    var cur_y = options.y;
    const level_indent = options.indent * @as(f32, @floatFromInt(level));
    const marker_x = options.x + level_indent;

    for (items, 0..) |item, idx| {
        const item_number = start_number + @as(u32, @intCast(idx));

        // Calculate marker width for this style
        const marker_width = markerWidth(options.style, item_number, options.font, options.font_size);

        // Text starts after marker + gap
        const text_x = marker_x + marker_width + options.marker_gap;
        const available_width = options.max_width - level_indent - marker_width - options.marker_gap;

        // Draw the marker
        try drawMarker(page, options.style, item_number, marker_x, cur_y, options.font, options.font_size, options.color);

        // Draw text with word wrapping
        const text_height = try drawWrappedText(page, item.text, text_x, cur_y, available_width, options.font, options.font_size, options.color, options.line_height);

        cur_y -= text_height;

        // Render children if present
        if (item.children) |children| {
            if (children.len > 0) {
                const child_style = item.child_style orelse defaultChildStyle(options.style);
                var child_opts = options;
                child_opts.y = cur_y;
                child_opts.style = child_style;
                const child_height = try drawListInternal(page, children, child_opts, level + 1, 1);
                cur_y -= child_height;
            }
        }

        // Add item spacing (except after last item)
        if (idx < items.len - 1) {
            cur_y -= options.item_spacing;
        }
    }

    return options.y - cur_y;
}

fn defaultChildStyle(parent_style: ListStyle) ListStyle {
    return switch (parent_style) {
        .bullet => .dash,
        .dash => .bullet,
        .disc => .circle,
        .circle => .disc,
        .square => .dash,
        .numbered => .lettered,
        .lettered => .numbered,
        .lettered_upper => .numbered,
        .roman => .lettered,
        .roman_upper => .lettered_upper,
    };
}

fn markerWidth(style: ListStyle, number: u32, font: StandardFont, font_size: f32) f32 {
    return switch (style) {
        .bullet, .dash => font.textWidth("-", font_size),
        .disc, .circle => font_size * 0.35,
        .square => font_size * 0.35,
        .numbered => blk: {
            var buf: [16]u8 = undefined;
            const marker_text = formatNumber(number, &buf);
            break :blk font.textWidth(marker_text, font_size);
        },
        .lettered => blk: {
            var buf: [8]u8 = undefined;
            const marker_text = formatLetter(number, &buf, false);
            break :blk font.textWidth(marker_text, font_size);
        },
        .lettered_upper => blk: {
            var buf: [8]u8 = undefined;
            const marker_text = formatLetter(number, &buf, true);
            break :blk font.textWidth(marker_text, font_size);
        },
        .roman => blk: {
            var buf: [32]u8 = undefined;
            const marker_text = formatRoman(number, &buf, false);
            break :blk font.textWidth(marker_text, font_size);
        },
        .roman_upper => blk: {
            var buf: [32]u8 = undefined;
            const marker_text = formatRoman(number, &buf, true);
            break :blk font.textWidth(marker_text, font_size);
        },
    };
}

fn drawMarker(
    page: *Page,
    style: ListStyle,
    number: u32,
    x: f32,
    y: f32,
    font: StandardFont,
    font_size: f32,
    text_color: Color,
) !void {
    switch (style) {
        .bullet => {
            // Use a simple bullet character rendered as a small filled circle
            const r = font_size * 0.12;
            const cx = x + r;
            const cy = y + font_size * 0.3;
            try drawFilledCircle(page, cx, cy, r, text_color);
        },
        .dash => {
            try page.drawText("-", .{
                .x = x,
                .y = y,
                .font = font,
                .font_size = font_size,
                .color = text_color,
            });
        },
        .disc => {
            const r = font_size * 0.15;
            const cx = x + r;
            const cy = y + font_size * 0.3;
            try drawFilledCircle(page, cx, cy, r, text_color);
        },
        .circle => {
            const r = font_size * 0.15;
            const cx = x + r;
            const cy = y + font_size * 0.3;
            try drawStrokedCircle(page, cx, cy, r, text_color);
        },
        .square => {
            const side = font_size * 0.28;
            const sx = x;
            const sy = y + font_size * 0.15;
            try drawFilledRect(page, sx, sy, side, side, text_color);
        },
        .numbered => {
            var buf: [16]u8 = undefined;
            const marker_text = formatNumber(number, &buf);
            try page.drawText(marker_text, .{
                .x = x,
                .y = y,
                .font = font,
                .font_size = font_size,
                .color = text_color,
            });
        },
        .lettered => {
            var buf: [8]u8 = undefined;
            const marker_text = formatLetter(number, &buf, false);
            try page.drawText(marker_text, .{
                .x = x,
                .y = y,
                .font = font,
                .font_size = font_size,
                .color = text_color,
            });
        },
        .lettered_upper => {
            var buf: [8]u8 = undefined;
            const marker_text = formatLetter(number, &buf, true);
            try page.drawText(marker_text, .{
                .x = x,
                .y = y,
                .font = font,
                .font_size = font_size,
                .color = text_color,
            });
        },
        .roman => {
            var buf: [32]u8 = undefined;
            const marker_text = formatRoman(number, &buf, false);
            try page.drawText(marker_text, .{
                .x = x,
                .y = y,
                .font = font,
                .font_size = font_size,
                .color = text_color,
            });
        },
        .roman_upper => {
            var buf: [32]u8 = undefined;
            const marker_text = formatRoman(number, &buf, true);
            try page.drawText(marker_text, .{
                .x = x,
                .y = y,
                .font = font,
                .font_size = font_size,
                .color = text_color,
            });
        },
    }
}

pub fn formatNumber(n: u32, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "{d}.", .{n}) catch "?.";
}

pub fn formatLetter(n: u32, buf: []u8, upper: bool) []const u8 {
    if (n == 0 or n > 26) return "?.";
    const base: u8 = if (upper) 'A' else 'a';
    const ch = base + @as(u8, @intCast(n - 1));
    buf[0] = ch;
    buf[1] = '.';
    return buf[0..2];
}

pub fn formatRoman(n: u32, buf: []u8, upper: bool) []const u8 {
    if (n == 0 or n > 3999) return "?.";

    const values = [_]u32{ 1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1 };
    const lower_syms = [_][]const u8{ "m", "cm", "d", "cd", "c", "xc", "l", "xl", "x", "ix", "v", "iv", "i" };
    const upper_syms = [_][]const u8{ "M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I" };

    const syms = if (upper) &upper_syms else &lower_syms;

    var remaining = n;
    var pos: usize = 0;

    for (values, 0..) |val, sym_idx| {
        while (remaining >= val) {
            const sym = syms[sym_idx];
            for (sym) |ch| {
                if (pos >= buf.len) return buf[0..pos];
                buf[pos] = ch;
                pos += 1;
            }
            remaining -= val;
        }
    }

    // Append '.'
    if (pos < buf.len) {
        buf[pos] = '.';
        pos += 1;
    }

    return buf[0..pos];
}

fn drawWrappedText(
    page: *Page,
    text: []const u8,
    x: f32,
    y: f32,
    max_width: f32,
    font: StandardFont,
    font_size: f32,
    text_color: Color,
    line_height: f32,
) !f32 {
    if (text.len == 0) return line_height;
    if (max_width <= 0) return line_height;

    var cur_y = y;
    var line_start: usize = 0;

    while (line_start < text.len) {
        // Find how much text fits on this line
        var line_end = text.len;
        var last_space: ?usize = null;

        for (line_start..text.len) |i| {
            if (text[i] == ' ') last_space = i;
            const segment = text[line_start .. i + 1];
            const w = font.textWidth(segment, font_size);
            if (w > max_width) {
                if (last_space) |sp| {
                    if (sp > line_start) {
                        line_end = sp;
                        break;
                    }
                }
                // No space found, break at current position if not first char
                if (i > line_start) {
                    line_end = i;
                    break;
                }
            }
        }

        const line = text[line_start..line_end];
        try page.drawText(line, .{
            .x = x,
            .y = cur_y,
            .font = font,
            .font_size = font_size,
            .color = text_color,
        });

        // Move to next line
        if (line_end < text.len) {
            cur_y -= line_height;
            // Skip space at break point
            line_start = if (line_end < text.len and text[line_end] == ' ') line_end + 1 else line_end;
        } else {
            break;
        }
    }

    // Total height is at least one line
    return (y - cur_y) + line_height;
}

fn drawFilledCircle(page: *Page, cx: f32, cy: f32, r: f32, fill_color: Color) !void {
    try page.drawCircle(.{
        .cx = cx,
        .cy = cy,
        .r = r,
        .color = fill_color,
    });
}

fn drawStrokedCircle(page: *Page, cx: f32, cy: f32, r: f32, stroke_color: Color) !void {
    try page.drawCircle(.{
        .cx = cx,
        .cy = cy,
        .r = r,
        .border_color = stroke_color,
        .border_width = 0.5,
    });
}

fn drawFilledRect(page: *Page, x: f32, y: f32, w: f32, h: f32, fill_color: Color) !void {
    try page.drawRect(.{
        .x = x,
        .y = y,
        .width = w,
        .height = h,
        .color = fill_color,
    });
}

// ── Tests ──────────────────────────────────────────────────────────

test "formatRoman basic" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("i.", formatRoman(1, &buf, false));
    try std.testing.expectEqualStrings("iv.", formatRoman(4, &buf, false));
    try std.testing.expectEqualStrings("ix.", formatRoman(9, &buf, false));
    try std.testing.expectEqualStrings("xiv.", formatRoman(14, &buf, false));
    try std.testing.expectEqualStrings("xlii.", formatRoman(42, &buf, false));
}

test "formatRoman upper" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("I.", formatRoman(1, &buf, true));
    try std.testing.expectEqualStrings("IV.", formatRoman(4, &buf, true));
    try std.testing.expectEqualStrings("XIV.", formatRoman(14, &buf, true));
    try std.testing.expectEqualStrings("MCMXCIX.", formatRoman(1999, &buf, true));
}

test "formatLetter" {
    var buf: [8]u8 = undefined;
    try std.testing.expectEqualStrings("a.", formatLetter(1, &buf, false));
    try std.testing.expectEqualStrings("c.", formatLetter(3, &buf, false));
    try std.testing.expectEqualStrings("z.", formatLetter(26, &buf, false));
    try std.testing.expectEqualStrings("A.", formatLetter(1, &buf, true));
    try std.testing.expectEqualStrings("Z.", formatLetter(26, &buf, true));
}

test "formatNumber" {
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("1.", formatNumber(1, &buf));
    try std.testing.expectEqualStrings("10.", formatNumber(10, &buf));
    try std.testing.expectEqualStrings("100.", formatNumber(100, &buf));
}
