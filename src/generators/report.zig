const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const Document = @import("../document/document.zig").Document;
const Page = @import("../document/page.zig").Page;
const PageSize = @import("../document/page_sizes.zig").PageSize;
const StandardFont = @import("../font/standard_fonts.zig").StandardFont;
const Color = @import("../color/color.zig").Color;
const text_layout = @import("../text/text_layout.zig");
const Margins = @import("../layout/page_template.zig").Margins;
const header_footer = @import("../layout/header_footer.zig");

/// A single section in the report with a title and body content.
pub const ReportSection = struct {
    title: []const u8,
    content: []const u8,
    level: u8, // 0-3 for nesting depth
};

/// Configuration options for the report builder.
pub const ReportOptions = struct {
    title: []const u8 = "Untitled Report",
    author: []const u8 = "",
    page_size: PageSize = .a4,
    margins: Margins = Margins.one_inch,
    body_font: StandardFont = .helvetica,
    body_font_size: f32 = 11,
    heading_font: StandardFont = .helvetica_bold,
    auto_number_sections: bool = true,
    include_toc: bool = false,
    header_text: ?[]const u8 = null,
    footer_text: ?[]const u8 = null,
    line_spacing: f32 = 1.4,
};

/// An item in the report: either a section, page break, or paragraph.
const ReportItem = union(enum) {
    section: ReportSection,
    page_break: void,
    paragraph: []const u8,
};

/// A table of contents entry recorded during generation.
const TocItem = struct {
    title: []const u8,
    level: u8,
    page_number: usize,
};

/// High-level report builder that auto-paginates and formats structured content.
pub const Report = struct {
    allocator: Allocator,
    options: ReportOptions,
    items: ArrayList(ReportItem),

    /// Creates a new report builder with the given options.
    pub fn init(allocator: Allocator, options: ReportOptions) Report {
        return .{
            .allocator = allocator,
            .options = options,
            .items = .{},
        };
    }

    /// Frees all resources held by this report builder.
    pub fn deinit(self: *Report) void {
        self.items.deinit(self.allocator);
    }

    /// Adds a section with a title, body content, and nesting level (0-3).
    pub fn addSection(self: *Report, title: []const u8, content: []const u8, level: u8) !void {
        try self.items.append(self.allocator, .{
            .section = .{
                .title = title,
                .content = content,
                .level = @min(level, 3),
            },
        });
    }

    /// Inserts an explicit page break at the current position.
    pub fn addPageBreak(self: *Report) !void {
        try self.items.append(self.allocator, .page_break);
    }

    /// Adds a body paragraph (no heading).
    pub fn addParagraph(self: *Report, text: []const u8) !void {
        try self.items.append(self.allocator, .{ .paragraph = text });
    }

    /// Generates the PDF document and returns the serialized bytes.
    /// Caller owns the returned slice.
    pub fn generate(self: *Report, allocator: Allocator) ![]u8 {
        var doc = Document.init(allocator);
        defer doc.deinit();

        doc.setTitle(self.options.title);
        if (self.options.author.len > 0) {
            doc.setAuthor(self.options.author);
        }

        const opts = self.options;
        const dims = opts.page_size.dimensions();
        const content_width = dims.width - opts.margins.left - opts.margins.right;
        const content_top = dims.height - opts.margins.top;
        const content_bottom = opts.margins.bottom;

        // Reserve space for header/footer
        const header_space: f32 = if (opts.header_text != null) 20 else 0;
        const footer_space: f32 = if (opts.footer_text != null) 20 else 0;
        const usable_top = content_top - header_space;
        const usable_bottom = content_bottom + footer_space;

        // Register fonts we'll need
        const body_handle = try doc.getStandardFont(opts.body_font);
        const heading_handle = try doc.getStandardFont(opts.heading_font);

        // Section counters for auto-numbering (max 4 levels)
        var section_counters = [4]u32{ 0, 0, 0, 0 };

        // Collect TOC entries during first pass
        var toc_items = ArrayList(TocItem){};
        defer toc_items.deinit(allocator);

        // Collect section numbering labels for TOC
        var toc_labels = ArrayList([]const u8){};
        defer {
            for (toc_labels.items) |label| allocator.free(label);
            toc_labels.deinit(allocator);
        }

        // === Main content generation ===
        var current_page = try doc.addPage(opts.page_size);
        _ = try current_page.addFont(body_handle.font.pdfName(), body_handle.ref);
        _ = try current_page.addFont(heading_handle.font.pdfName(), heading_handle.ref);
        var page_count: usize = 1;
        var cursor_y: f32 = usable_top;

        for (self.items.items) |item| {
            switch (item) {
                .page_break => {
                    current_page = try doc.addPage(opts.page_size);
                    _ = try current_page.addFont(body_handle.font.pdfName(), body_handle.ref);
                    _ = try current_page.addFont(heading_handle.font.pdfName(), heading_handle.ref);
                    page_count += 1;
                    cursor_y = usable_top;
                },
                .section => |sec| {
                    // Update section counters
                    section_counters[sec.level] += 1;
                    // Reset lower-level counters
                    for (sec.level + 1..4) |l| {
                        section_counters[l] = 0;
                    }

                    // Build section number string
                    var number_buf: [64]u8 = undefined;
                    var number_len: usize = 0;
                    if (opts.auto_number_sections) {
                        var fbs = std.io.fixedBufferStream(&number_buf);
                        const wr = fbs.writer();
                        for (0..sec.level + 1) |l| {
                            if (l > 0) wr.writeByte('.') catch break;
                            wr.print("{d}", .{section_counters[l]}) catch break;
                        }
                        number_len = fbs.pos;
                    }

                    const heading_size = headingFontSize(sec.level);
                    const heading_line_height = heading_size * opts.line_spacing;

                    // Check if heading fits; if not, new page
                    if (cursor_y - heading_line_height < usable_bottom) {
                        current_page = try doc.addPage(opts.page_size);
                        _ = try current_page.addFont(body_handle.font.pdfName(), body_handle.ref);
                        _ = try current_page.addFont(heading_handle.font.pdfName(), heading_handle.ref);
                        page_count += 1;
                        cursor_y = usable_top;
                    }

                    // Record TOC entry
                    if (opts.include_toc) {
                        try toc_items.append(allocator, .{
                            .title = sec.title,
                            .level = sec.level,
                            .page_number = page_count,
                        });
                        if (opts.auto_number_sections and number_len > 0) {
                            const label = try allocator.dupe(u8, number_buf[0..number_len]);
                            try toc_labels.append(allocator, label);
                        } else {
                            const label = try allocator.dupe(u8, "");
                            try toc_labels.append(allocator, label);
                        }
                    }

                    // Draw heading
                    var heading_text_buf: [256]u8 = undefined;
                    var heading_text: []const u8 = sec.title;
                    if (opts.auto_number_sections and number_len > 0) {
                        var hfbs = std.io.fixedBufferStream(&heading_text_buf);
                        hfbs.writer().writeAll(number_buf[0..number_len]) catch {};
                        hfbs.writer().writeAll(" ") catch {};
                        hfbs.writer().writeAll(sec.title) catch {};
                        heading_text = heading_text_buf[0..hfbs.pos];
                    }

                    // Add spacing before heading (except at top of page)
                    if (cursor_y < usable_top - 1) {
                        cursor_y -= heading_size * 0.5;
                    }

                    try current_page.drawText(heading_text, .{
                        .x = opts.margins.left,
                        .y = cursor_y,
                        .font = opts.heading_font,
                        .font_size = heading_size,
                    });
                    cursor_y -= heading_line_height;

                    // Draw body content with word wrapping
                    if (sec.content.len > 0) {
                        const state = try self.renderBodyText(
                            allocator,
                            sec.content,
                            &doc,
                            current_page,
                            cursor_y,
                            content_width,
                            usable_top,
                            usable_bottom,
                            page_count,
                            body_handle,
                            heading_handle,
                        );
                        current_page = state.page;
                        cursor_y = state.cursor_y;
                        page_count = state.page_count;
                    }

                    // Add some spacing after section
                    cursor_y -= opts.body_font_size * 0.5;
                },
                .paragraph => |text| {
                    if (text.len > 0) {
                        const state = try self.renderBodyText(
                            allocator,
                            text,
                            &doc,
                            current_page,
                            cursor_y,
                            content_width,
                            usable_top,
                            usable_bottom,
                            page_count,
                            body_handle,
                            heading_handle,
                        );
                        current_page = state.page;
                        cursor_y = state.cursor_y;
                        page_count = state.page_count;
                    }
                    cursor_y -= opts.body_font_size * 0.5;
                },
            }
        }

        // === Generate TOC on front pages if requested ===
        if (opts.include_toc and toc_items.items.len > 0) {
            // We need to prepend TOC pages. We'll insert them at the beginning.
            // First figure out how many TOC pages we need.
            const toc_line_height = opts.body_font_size * opts.line_spacing;
            const toc_title_height = 24.0 * opts.line_spacing;
            const avail_height = usable_top - usable_bottom;

            // Calculate number of TOC pages needed
            var toc_height: f32 = toc_title_height + 10; // TOC title + gap
            var toc_pages_needed: usize = 1;
            for (toc_items.items) |_| {
                toc_height += toc_line_height;
                if (toc_height > avail_height) {
                    toc_pages_needed += 1;
                    toc_height = toc_line_height;
                }
            }

            // Insert TOC pages at the beginning
            var toc_page_idx: usize = 0;
            var toc_page = try doc.insertPage(0, opts.page_size);
            _ = try toc_page.addFont(body_handle.font.pdfName(), body_handle.ref);
            _ = try toc_page.addFont(heading_handle.font.pdfName(), heading_handle.ref);
            var toc_y: f32 = usable_top;

            // Draw TOC title
            try toc_page.drawText("Table of Contents", .{
                .x = opts.margins.left,
                .y = toc_y,
                .font = opts.heading_font,
                .font_size = 24,
            });
            toc_y -= toc_title_height + 10;

            for (toc_items.items, 0..) |entry, idx| {
                if (toc_y - toc_line_height < usable_bottom) {
                    toc_page_idx += 1;
                    toc_page = try doc.insertPage(toc_page_idx, opts.page_size);
                    _ = try toc_page.addFont(body_handle.font.pdfName(), body_handle.ref);
                    _ = try toc_page.addFont(heading_handle.font.pdfName(), heading_handle.ref);
                    toc_y = usable_top;
                }

                // Indent based on level
                const indent = @as(f32, @floatFromInt(entry.level)) * 20.0;
                const x = opts.margins.left + indent;

                // Build TOC line: "number title ... page"
                var toc_line_buf: [320]u8 = undefined;
                var toc_fbs = std.io.fixedBufferStream(&toc_line_buf);
                const toc_wr = toc_fbs.writer();

                if (opts.auto_number_sections and idx < toc_labels.items.len and toc_labels.items[idx].len > 0) {
                    toc_wr.writeAll(toc_labels.items[idx]) catch {};
                    toc_wr.writeAll(" ") catch {};
                }
                toc_wr.writeAll(entry.title) catch {};

                // Actual page number accounting for TOC pages inserted
                const actual_page = entry.page_number + toc_pages_needed;
                var page_num_buf: [16]u8 = undefined;
                const page_num_str = std.fmt.bufPrint(&page_num_buf, "{d}", .{actual_page}) catch "?";

                // Add dot leader
                const title_width = opts.body_font.textWidth(toc_line_buf[0..toc_fbs.pos], opts.body_font_size);
                const num_width = opts.body_font.textWidth(page_num_str, opts.body_font_size);
                const dot_width = opts.body_font.textWidth(".", opts.body_font_size);
                const available_for_dots = content_width - indent - title_width - num_width - 10;
                if (available_for_dots > dot_width) {
                    toc_wr.writeAll(" ") catch {};
                    var dots_w: f32 = 0;
                    while (dots_w + dot_width < available_for_dots) {
                        toc_wr.writeAll(".") catch {};
                        dots_w += dot_width;
                    }
                    toc_wr.writeAll(" ") catch {};
                }
                toc_wr.writeAll(page_num_str) catch {};

                try toc_page.drawText(toc_line_buf[0..toc_fbs.pos], .{
                    .x = x,
                    .y = toc_y,
                    .font = opts.body_font,
                    .font_size = opts.body_font_size,
                });
                toc_y -= toc_line_height;
            }

            // Update total page count
            page_count += toc_pages_needed;
        }

        // === Apply headers and footers ===
        const total_pages = doc.getPageCount();
        for (0..total_pages) |i| {
            const page = doc.getPage(i).?;
            const page_num = i + 1;

            if (opts.header_text) |ht| {
                try page.drawText(ht, .{
                    .x = opts.margins.left,
                    .y = dims.height - opts.margins.top + 10,
                    .font = opts.body_font,
                    .font_size = 9,
                    .color = .{ .named = .gray },
                });
                // Draw separator line
                try page.drawLine(.{
                    .x1 = opts.margins.left,
                    .y1 = dims.height - opts.margins.top + 5,
                    .x2 = dims.width - opts.margins.right,
                    .y2 = dims.height - opts.margins.top + 5,
                    .color = .{ .named = .light_gray },
                    .line_width = 0.5,
                });
            }

            if (opts.footer_text) |ft| {
                // Build footer with page number
                var footer_buf: [256]u8 = undefined;
                var footer_fbs = std.io.fixedBufferStream(&footer_buf);
                const fwr = footer_fbs.writer();
                // Replace {page} and {total} placeholders
                var fi: usize = 0;
                while (fi < ft.len) {
                    if (fi + 6 <= ft.len and std.mem.eql(u8, ft[fi .. fi + 6], "{page}")) {
                        fwr.print("{d}", .{page_num}) catch {};
                        fi += 6;
                    } else if (fi + 7 <= ft.len and std.mem.eql(u8, ft[fi .. fi + 7], "{total}")) {
                        fwr.print("{d}", .{total_pages}) catch {};
                        fi += 7;
                    } else {
                        fwr.writeByte(ft[fi]) catch {};
                        fi += 1;
                    }
                }

                // Draw separator line
                try page.drawLine(.{
                    .x1 = opts.margins.left,
                    .y1 = opts.margins.bottom - 5,
                    .x2 = dims.width - opts.margins.right,
                    .y2 = opts.margins.bottom - 5,
                    .color = .{ .named = .light_gray },
                    .line_width = 0.5,
                });

                // Center the footer text
                const footer_text = footer_buf[0..footer_fbs.pos];
                const footer_width = opts.body_font.textWidth(footer_text, 9);
                const footer_x = opts.margins.left + (content_width - footer_width) / 2.0;

                try page.drawText(footer_text, .{
                    .x = footer_x,
                    .y = opts.margins.bottom - 15,
                    .font = opts.body_font,
                    .font_size = 9,
                    .color = .{ .named = .gray },
                });
            }
        }

        return doc.save(allocator);
    }

    /// Renders body text with word wrapping and auto-pagination.
    /// Returns updated page state.
    fn renderBodyText(
        self: *const Report,
        allocator: Allocator,
        text: []const u8,
        doc: *Document,
        initial_page: *Page,
        initial_y: f32,
        content_width: f32,
        usable_top: f32,
        usable_bottom: f32,
        initial_page_count: usize,
        body_handle: anytype,
        heading_handle: anytype,
    ) !struct { page: *Page, cursor_y: f32, page_count: usize } {
        const opts = self.options;
        const line_height = opts.body_font_size * opts.line_spacing;

        const lines = try text_layout.layoutText(
            allocator,
            text,
            opts.body_font,
            opts.body_font_size,
            content_width,
        );
        defer text_layout.freeTextLines(allocator, lines);

        var current_page = initial_page;
        var cursor_y = initial_y;
        var pc = initial_page_count;

        for (lines) |line| {
            if (cursor_y - line_height < usable_bottom) {
                current_page = try doc.addPage(opts.page_size);
                _ = try current_page.addFont(body_handle.font.pdfName(), body_handle.ref);
                _ = try current_page.addFont(heading_handle.font.pdfName(), heading_handle.ref);
                pc += 1;
                cursor_y = usable_top;
            }

            if (line.text.len > 0) {
                try current_page.drawText(line.text, .{
                    .x = opts.margins.left,
                    .y = cursor_y,
                    .font = opts.body_font,
                    .font_size = opts.body_font_size,
                });
            }
            cursor_y -= line_height;
        }

        return .{ .page = current_page, .cursor_y = cursor_y, .page_count = pc };
    }

    /// Returns the font size for a heading at the given nesting level.
    fn headingFontSize(level: u8) f32 {
        return switch (level) {
            0 => 18.0,
            1 => 15.0,
            2 => 13.0,
            else => 12.0,
        };
    }
};

// -- Tests --

test "report init and deinit" {
    var report = Report.init(std.testing.allocator, .{});
    defer report.deinit();
    try std.testing.expectEqual(@as(usize, 0), report.items.items.len);
}

test "report add section" {
    var report = Report.init(std.testing.allocator, .{});
    defer report.deinit();

    try report.addSection("Introduction", "Hello world.", 0);
    try std.testing.expectEqual(@as(usize, 1), report.items.items.len);
}

test "report add paragraph and page break" {
    var report = Report.init(std.testing.allocator, .{});
    defer report.deinit();

    try report.addParagraph("Some text.");
    try report.addPageBreak();
    try report.addParagraph("More text.");
    try std.testing.expectEqual(@as(usize, 3), report.items.items.len);
}

test "report generate produces valid PDF bytes" {
    var report = Report.init(std.testing.allocator, .{
        .title = "Test Report",
        .author = "Test",
        .auto_number_sections = true,
        .include_toc = false,
    });
    defer report.deinit();

    try report.addSection("Chapter 1", "This is the first chapter.", 0);
    try report.addSection("Section 1.1", "A subsection.", 1);
    try report.addParagraph("A standalone paragraph.");
    try report.addPageBreak();
    try report.addSection("Chapter 2", "The second chapter.", 0);

    const bytes = try report.generate(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    // Valid PDF starts with %PDF-
    try std.testing.expect(bytes.len > 100);
    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-"));
}

test "report generate with toc" {
    var report = Report.init(std.testing.allocator, .{
        .title = "TOC Report",
        .include_toc = true,
        .auto_number_sections = true,
    });
    defer report.deinit();

    try report.addSection("First", "Content one.", 0);
    try report.addSection("Second", "Content two.", 0);

    const bytes = try report.generate(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    try std.testing.expect(bytes.len > 100);
    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-"));
}

test "report generate with headers and footers" {
    var report = Report.init(std.testing.allocator, .{
        .title = "HF Report",
        .header_text = "My Report",
        .footer_text = "Page {page} of {total}",
    });
    defer report.deinit();

    try report.addSection("Intro", "Some body text here.", 0);

    const bytes = try report.generate(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    try std.testing.expect(bytes.len > 100);
    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-"));
}

test "report heading font sizes" {
    try std.testing.expectApproxEqAbs(@as(f32, 18.0), Report.headingFontSize(0), 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 15.0), Report.headingFontSize(1), 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 13.0), Report.headingFontSize(2), 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 12.0), Report.headingFontSize(3), 0.01);
}

test "report level clamped to 3" {
    var report = Report.init(std.testing.allocator, .{});
    defer report.deinit();

    try report.addSection("Deep", "Content.", 10);
    const sec = report.items.items[0].section;
    try std.testing.expectEqual(@as(u8, 3), sec.level);
}

test "report auto pagination with long content" {
    var report = Report.init(std.testing.allocator, .{
        .title = "Long Report",
        .auto_number_sections = false,
    });
    defer report.deinit();

    // Add enough content to trigger multiple pages
    const long_text = "This is a line of text that should be repeated many times to fill up the page and trigger auto-pagination. " ** 20;
    try report.addSection("Long Section", long_text, 0);

    const bytes = try report.generate(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    try std.testing.expect(bytes.len > 100);
    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-"));
}
