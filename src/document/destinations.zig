const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const Page = @import("page.zig").Page;
const Color = @import("../color/color.zig").Color;

/// Destination types as defined in the PDF specification (section 12.3.2).
pub const DestinationType = enum {
    xyz, // /XYZ left top zoom - go to specific position
    fit, // /Fit - fit page in window
    fit_h, // /FitH top - fit width
    fit_v, // /FitV left - fit height
    fit_r, // /FitR left bottom right top - fit rectangle
};

/// A named destination within the PDF document.
/// Named destinations allow clickable internal links (e.g. table of contents, cross-references).
pub const Destination = struct {
    name: []const u8,
    page_index: usize,
    dest_type: DestinationType = .xyz,
    left: ?f32 = null,
    top: ?f32 = null,
    zoom: ?f32 = null,
    bottom: ?f32 = null,
    right: ?f32 = null,
};

/// An internal link annotation that references a named destination.
pub const InternalLink = struct {
    /// Source rectangle on the page (clickable area): x1, y1, x2, y2.
    rect: [4]f32,
    /// Name of the destination to link to.
    dest_name: []const u8,
    /// Optional border width (0 = no border).
    border_width: f32 = 0,
    /// Optional highlight color when clicked.
    color: ?Color = null,
};

/// A single entry in a table of contents.
pub const TocEntry = struct {
    title: []const u8,
    page_index: usize,
    level: u8 = 0, // nesting level (0 = top)
};

/// Options for rendering a table of contents.
pub const TocOptions = struct {
    start_x: f32 = 72,
    start_y: f32 = 700,
    width: f32 = 468, // 612 - 72*2 for letter
    font_size: f32 = 12,
    line_height: f32 = 20,
    indent_per_level: f32 = 20,
    title_font: @import("../font/standard_fonts.zig").StandardFont = .helvetica,
    title_color: Color = .{ .named = .black },
    /// Height of the clickable link area.
    link_height: f32 = 14,
    /// Whether to draw dot leaders between title and page number.
    dot_leaders: bool = true,
    /// Destination name prefix (entries get names like "toc_0", "toc_1", etc.).
    dest_prefix: []const u8 = "toc_",
};

/// Render a table of contents on the given page with clickable internal links.
/// Returns the total height consumed by the TOC block.
/// This function also registers the destinations and internal links on the document.
pub fn renderToc(
    allocator: Allocator,
    page: *Page,
    entries: []const TocEntry,
    named_dests: *ArrayList(Destination),
    internal_links: *ArrayList(PageInternalLink),
    allocated_names: *ArrayList([]const u8),
    page_index: usize,
    options: TocOptions,
) !f32 {
    const writer = page.content.writer(page.allocator);

    var current_y = options.start_y;

    for (entries, 0..) |entry, i| {
        const indent = @as(f32, @floatFromInt(entry.level)) * options.indent_per_level;
        const text_x = options.start_x + indent;

        // Create destination name for target page
        var dest_name_buf: [128]u8 = undefined;
        const dest_name = std.fmt.bufPrint(&dest_name_buf, "{s}{d}", .{ options.dest_prefix, i }) catch "toc_0";

        // Duplicate the dest name into the allocator so it persists
        const dest_name_owned = try allocator.dupe(u8, dest_name);
        try allocated_names.append(allocator, dest_name_owned);

        // Register destination on target page (top of the page)
        try named_dests.append(allocator, .{
            .name = dest_name_owned,
            .page_index = entry.page_index,
            .dest_type = .fit,
        });

        // Draw text
        try writer.writeAll("q\n");

        // Set color
        const rgb_val = options.title_color.toRgb();
        try writer.print("{d:.4} {d:.4} {d:.4} rg\n", .{
            @as(f32, @floatFromInt(rgb_val.r)) / 255.0,
            @as(f32, @floatFromInt(rgb_val.g)) / 255.0,
            @as(f32, @floatFromInt(rgb_val.b)) / 255.0,
        });

        try writer.writeAll("BT\n");

        // Use the font resource name lookup
        const font_pdf_name = options.title_font.pdfName();
        const res_name = if (page.resources.fonts.get(font_pdf_name)) |fr|
            fr.name
        else
            "F1";

        try writer.print("/{s} {d:.2} Tf\n", .{ res_name, options.font_size });
        try writer.print("{d:.2} {d:.2} Td\n", .{ text_x, current_y });

        // Write escaped title text
        try writer.writeAll("(");
        for (entry.title) |ch| {
            switch (ch) {
                '(' => try writer.writeAll("\\("),
                ')' => try writer.writeAll("\\)"),
                '\\' => try writer.writeAll("\\\\"),
                else => try writer.print("{c}", .{ch}),
            }
        }
        try writer.writeAll(") Tj\n");

        // Draw page number on the right side
        var page_num_buf: [16]u8 = undefined;
        const page_num_str = std.fmt.bufPrint(&page_num_buf, "{d}", .{entry.page_index + 1}) catch "?";
        const page_num_width = @as(f32, @floatFromInt(page_num_str.len)) * options.font_size * 0.5;
        const page_num_x = options.start_x + options.width - page_num_width;

        try writer.print("{d:.2} {d:.2} Td\n", .{ page_num_x - text_x, @as(f32, 0) });
        try writer.writeAll("(");
        for (page_num_str) |ch| {
            try writer.print("{c}", .{ch});
        }
        try writer.writeAll(") Tj\n");

        try writer.writeAll("ET\n");

        // Draw dot leaders if enabled
        if (options.dot_leaders) {
            const title_est_width = @as(f32, @floatFromInt(entry.title.len)) * options.font_size * 0.5;
            const dots_start = text_x + title_est_width + 4;
            const dots_end = page_num_x - 4;
            if (dots_end > dots_start) {
                try writer.writeAll("BT\n");
                try writer.print("/{s} {d:.2} Tf\n", .{ res_name, options.font_size });
                try writer.print("{d:.2} {d:.2} Td\n", .{ dots_start, current_y });
                try writer.writeAll("(");
                var dx = dots_start;
                while (dx < dots_end) : (dx += options.font_size * 0.5) {
                    try writer.writeAll(".");
                }
                try writer.writeAll(") Tj\n");
                try writer.writeAll("ET\n");
            }
        }

        try writer.writeAll("Q\n");

        // Add internal link annotation for this TOC entry
        try internal_links.append(allocator, .{
            .page_index = page_index,
            .link = .{
                .rect = .{
                    text_x,
                    current_y - 2,
                    options.start_x + options.width,
                    current_y + options.link_height,
                },
                .dest_name = dest_name_owned,
                .border_width = 0,
            },
        });

        current_y -= options.line_height;
    }

    return options.start_y - current_y;
}

/// Internal link paired with its source page index (used by Document).
pub const PageInternalLink = struct {
    page_index: usize,
    link: InternalLink,
};
