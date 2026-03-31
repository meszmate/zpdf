const std = @import("std");
const Color = @import("../color/color.zig").Color;
const StandardFont = @import("../font/standard_fonts.zig").StandardFont;
const Page = @import("../document/page.zig").Page;
const TextAlignment = @import("../document/page.zig").TextAlignment;

/// Position of content within header/footer.
pub const HFPosition = enum {
    left,
    center,
    right,
};

/// A single content element in a header or footer.
pub const HFElement = struct {
    position: HFPosition,
    content: HFContent,
    font: StandardFont = .helvetica,
    font_size: f32 = 10,
    color: Color = .{ .named = .black },
};

/// Content that can appear in a header/footer.
pub const HFContent = union(enum) {
    /// Static text string
    text: []const u8,
    /// Page number (current page)
    page_number,
    /// Page count (total pages)
    page_count,
    /// "Page X of Y" format
    page_x_of_y,
    /// Custom format string with {page} and {total} placeholders
    formatted: []const u8,
};

/// Configuration for a header or footer.
pub const HeaderFooter = struct {
    elements: []const HFElement,
    /// Margin from top (header) or bottom (footer) of page in points
    margin: f32 = 36, // 0.5 inch
    /// Whether to draw a separator line
    separator_line: bool = false,
    /// Color of separator line
    separator_color: Color = .{ .named = .gray },
    /// Width of separator line
    separator_width: f32 = 0.5,
    /// Left margin for content
    left_margin: f32 = 50,
    /// Right margin for content
    right_margin: f32 = 50,
    /// Skip first page (useful for title pages)
    skip_first_page: bool = false,
};

/// Resolve an HFContent value into a text string for the given page/total.
/// Caller owns the returned memory when it is allocated (formatted case).
fn resolveContent(allocator: std.mem.Allocator, content: HFContent, page_num: u32, total_pages: u32) ![]const u8 {
    return switch (content) {
        .text => |t| t,
        .page_number => try std.fmt.allocPrint(allocator, "{d}", .{page_num}),
        .page_count => try std.fmt.allocPrint(allocator, "{d}", .{total_pages}),
        .page_x_of_y => try std.fmt.allocPrint(allocator, "Page {d} of {d}", .{ page_num, total_pages }),
        .formatted => |fmt_str| try replacePlaceholders(allocator, fmt_str, page_num, total_pages),
    };
}

/// Replace {page} and {total} placeholders in a format string.
fn replacePlaceholders(allocator: std.mem.Allocator, fmt_str: []const u8, page_num: u32, total_pages: u32) ![]const u8 {
    var result = std.ArrayListUnmanaged(u8){};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < fmt_str.len) {
        if (i + 6 <= fmt_str.len and std.mem.eql(u8, fmt_str[i .. i + 6], "{page}")) {
            try result.writer(allocator).print("{d}", .{page_num});
            i += 6;
        } else if (i + 7 <= fmt_str.len and std.mem.eql(u8, fmt_str[i .. i + 7], "{total}")) {
            try result.writer(allocator).print("{d}", .{total_pages});
            i += 7;
        } else {
            try result.append(allocator, fmt_str[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Returns true if the resolved string was heap-allocated and needs freeing.
fn contentNeedsFree(content: HFContent) bool {
    return switch (content) {
        .text => false,
        .page_number, .page_count, .page_x_of_y, .formatted => true,
    };
}

/// Apply headers and/or footers to all pages in the document.
/// This should be called after all pages have been created and before saving.
/// page_number_offset: starting page number (default 1)
pub fn applyHeadersFooters(
    pages: []const *Page,
    header: ?HeaderFooter,
    footer: ?HeaderFooter,
    page_number_offset: u32,
) !void {
    const total_pages: u32 = @intCast(pages.len);

    for (pages, 0..) |page, idx| {
        const page_num = page_number_offset + @as(u32, @intCast(idx));
        const is_first = idx == 0;

        if (header) |h| {
            if (!(h.skip_first_page and is_first)) {
                try applySection(page, h, page_num, total_pages, true);
            }
        }

        if (footer) |f| {
            if (!(f.skip_first_page and is_first)) {
                try applySection(page, f, page_num, total_pages, false);
            }
        }
    }
}

/// Apply a single header or footer section to a page.
fn applySection(
    page: *Page,
    section: HeaderFooter,
    page_num: u32,
    total_pages: u32,
    is_header: bool,
) !void {
    const y = if (is_header) page.height - section.margin else section.margin;

    // Draw separator line
    if (section.separator_line) {
        const line_y = if (is_header) y - section.margin / 4.0 else y + section.margin / 4.0;
        try page.drawLine(.{
            .x1 = section.left_margin,
            .y1 = line_y,
            .x2 = page.width - section.right_margin,
            .y2 = line_y,
            .color = section.separator_color,
            .line_width = section.separator_width,
        });
    }

    // Draw each element
    for (section.elements) |elem| {
        const resolved = try resolveContent(page.allocator, elem.content, page_num, total_pages);
        defer if (contentNeedsFree(elem.content)) page.allocator.free(resolved);

        const x = switch (elem.position) {
            .left => section.left_margin,
            .center => page.width / 2.0,
            .right => page.width - section.right_margin,
        };

        const alignment: TextAlignment = switch (elem.position) {
            .left => .left,
            .center => .center,
            .right => .right,
        };

        try page.drawText(resolved, .{
            .x = x,
            .y = y,
            .font = elem.font,
            .font_size = elem.font_size,
            .color = elem.color,
            .alignment = alignment,
        });
    }
}

test "replacePlaceholders" {
    const allocator = std.testing.allocator;
    const result = try replacePlaceholders(allocator, "Page {page} of {total}", 3, 10);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Page 3 of 10", result);
}

test "resolveContent static text" {
    const allocator = std.testing.allocator;
    const result = try resolveContent(allocator, .{ .text = "Hello" }, 1, 5);
    try std.testing.expectEqualStrings("Hello", result);
}

test "resolveContent page_number" {
    const allocator = std.testing.allocator;
    const result = try resolveContent(allocator, .page_number, 3, 10);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("3", result);
}

test "resolveContent page_x_of_y" {
    const allocator = std.testing.allocator;
    const result = try resolveContent(allocator, .page_x_of_y, 2, 8);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Page 2 of 8", result);
}
