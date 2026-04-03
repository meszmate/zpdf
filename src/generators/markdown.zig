const std = @import("std");
const Allocator = std.mem.Allocator;
const color_mod = @import("../color/color.zig");
const Color = color_mod.Color;
const StandardFont = @import("../font/standard_fonts.zig").StandardFont;
const Document = @import("../document/document.zig").Document;
const Page = @import("../document/page.zig").Page;
const PageSize = @import("../document/page_sizes.zig").PageSize;
const rich_text = @import("../text/rich_text.zig");
const TextSpan = rich_text.TextSpan;
const RichTextOptions = rich_text.RichTextOptions;
const lists_mod = @import("../layout/lists.zig");

/// Options controlling the appearance of the generated PDF.
pub const MarkdownOptions = struct {
    page_size: PageSize = .a4,
    margin_top: f32 = 72,
    margin_bottom: f32 = 72,
    margin_left: f32 = 72,
    margin_right: f32 = 72,

    // Fonts
    body_font: StandardFont = .helvetica,
    bold_font: StandardFont = .helvetica_bold,
    italic_font: StandardFont = .helvetica_oblique,
    bold_italic_font: StandardFont = .helvetica_bold_oblique,
    code_font: StandardFont = .courier,
    code_bold_font: StandardFont = .courier_bold,
    heading_font: StandardFont = .helvetica_bold,

    // Sizes
    body_size: f32 = 11,
    h1_size: f32 = 24,
    h2_size: f32 = 20,
    h3_size: f32 = 16,
    h4_size: f32 = 13,
    code_size: f32 = 9.5,

    // Colors
    text_color: Color = .{ .named = .black },
    heading_color: Color = color_mod.rgb(30, 30, 30),
    link_color: Color = color_mod.rgb(0, 0, 238),
    code_color: Color = color_mod.rgb(50, 50, 50),
    code_bg_color: Color = color_mod.rgb(240, 240, 240),
    blockquote_color: Color = color_mod.rgb(100, 100, 100),
    blockquote_border_color: Color = color_mod.rgb(180, 180, 180),
    rule_color: Color = color_mod.rgb(200, 200, 200),

    // Spacing
    paragraph_spacing: f32 = 8,
    heading_spacing_before: f32 = 16,
    heading_spacing_after: f32 = 6,
    line_height_factor: f32 = 1.4,
    code_block_padding: f32 = 8,
    blockquote_indent: f32 = 20,
    blockquote_border_width: f32 = 3,
    list_indent: f32 = 20,
};

/// Inline style for a segment of text within a line.
const InlineStyle = struct {
    bold: bool = false,
    italic: bool = false,
    code: bool = false,
    link_url: ?[]const u8 = null,
};

/// A parsed inline segment of text with associated style.
const InlineSegment = struct {
    text: []const u8,
    style: InlineStyle,
};

/// Types of parsed block elements.
const BlockType = enum {
    heading,
    paragraph,
    code_block,
    unordered_list,
    ordered_list,
    blockquote,
    horizontal_rule,
    blank,
};

/// A parsed block of markdown content.
const Block = struct {
    block_type: BlockType,
    /// Heading level (1-4), only used for headings
    heading_level: u8 = 0,
    /// Raw lines of text for this block
    lines: std.ArrayListUnmanaged([]const u8) = .{},

    fn deinit(self: *Block, allocator: Allocator) void {
        self.lines.deinit(allocator);
    }
};

/// Converts Markdown text to PDF bytes.
pub const MarkdownRenderer = struct {
    allocator: Allocator,
    options: MarkdownOptions,

    /// Create a new MarkdownRenderer with the given options.
    pub fn init(allocator: Allocator, options: MarkdownOptions) MarkdownRenderer {
        return .{
            .allocator = allocator,
            .options = options,
        };
    }

    /// Render markdown text into PDF bytes. Caller owns the returned slice.
    pub fn render(self: *MarkdownRenderer, markdown_text: []const u8) ![]u8 {
        const opts = self.options;
        const allocator = self.allocator;

        var doc = Document.init(allocator);
        defer doc.deinit();

        doc.setTitle("Markdown Document");
        doc.setCreator("zpdf Markdown Renderer");

        // Register all fonts we might use
        const fonts_to_register = [_]StandardFont{
            opts.body_font,
            opts.bold_font,
            opts.italic_font,
            opts.bold_italic_font,
            opts.code_font,
            opts.code_bold_font,
            opts.heading_font,
        };

        var font_handles: [7]@import("../document/document.zig").FontHandle = undefined;
        for (fonts_to_register, 0..) |f, i| {
            font_handles[i] = try doc.getStandardFont(f);
        }

        // Parse markdown into blocks
        var blocks = try parseBlocks(allocator, markdown_text);
        defer {
            for (blocks.items) |*b| b.deinit(allocator);
            blocks.deinit(allocator);
        }

        // Layout: render blocks onto pages
        const dims = opts.page_size.dimensions();
        const content_width = dims.width - opts.margin_left - opts.margin_right;
        const page_top = dims.height - opts.margin_top;
        const page_bottom = opts.margin_bottom;

        var current_page = try addNewPage(&doc, opts, &font_handles);
        var y: f32 = page_top;

        for (blocks.items) |*block| {
            switch (block.block_type) {
                .blank => {
                    y -= opts.paragraph_spacing;
                    if (y < page_bottom) {
                        current_page = try addNewPage(&doc, opts, &font_handles);
                        y = page_top;
                    }
                },
                .heading => {
                    const font_size = switch (block.heading_level) {
                        1 => opts.h1_size,
                        2 => opts.h2_size,
                        3 => opts.h3_size,
                        else => opts.h4_size,
                    };
                    y -= opts.heading_spacing_before;
                    if (y - font_size < page_bottom) {
                        current_page = try addNewPage(&doc, opts, &font_handles);
                        y = page_top;
                    }

                    const line_text = if (block.lines.items.len > 0) block.lines.items[0] else "";
                    var spans_list = std.ArrayListUnmanaged(TextSpan){};
                    defer spans_list.deinit(allocator);

                    try parseInlineSpans(allocator, line_text, opts, font_size, true, &spans_list);

                    if (spans_list.items.len == 0) {
                        try spans_list.append(allocator, .{
                            .text = line_text,
                            .font = opts.heading_font,
                            .font_size = font_size,
                            .color = opts.heading_color,
                        });
                    }

                    const height = try current_page.drawRichText(spans_list.items, .{
                        .x = opts.margin_left,
                        .y = y,
                        .max_width = content_width,
                        .line_height_factor = opts.line_height_factor,
                    });
                    y -= height + opts.heading_spacing_after;
                },
                .paragraph => {
                    // Join all lines into one paragraph text
                    var para_text = std.ArrayListUnmanaged(u8){};
                    defer para_text.deinit(allocator);
                    for (block.lines.items, 0..) |line, i| {
                        if (i > 0) try para_text.append(allocator, ' ');
                        try para_text.appendSlice(allocator, line);
                    }

                    var spans_list = std.ArrayListUnmanaged(TextSpan){};
                    defer spans_list.deinit(allocator);

                    try parseInlineSpans(allocator, para_text.items, opts, opts.body_size, false, &spans_list);

                    if (spans_list.items.len == 0) {
                        try spans_list.append(allocator, .{
                            .text = para_text.items,
                            .font = opts.body_font,
                            .font_size = opts.body_size,
                            .color = opts.text_color,
                        });
                    }

                    // Check if we need a new page
                    if (y - opts.body_size * opts.line_height_factor < page_bottom) {
                        current_page = try addNewPage(&doc, opts, &font_handles);
                        y = page_top;
                    }

                    const height = try current_page.drawRichText(spans_list.items, .{
                        .x = opts.margin_left,
                        .y = y,
                        .max_width = content_width,
                        .line_height_factor = opts.line_height_factor,
                    });
                    y -= height + opts.paragraph_spacing;
                },
                .code_block => {
                    // Estimate height
                    const line_h = opts.code_size * opts.line_height_factor;
                    const total_h = line_h * @as(f32, @floatFromInt(block.lines.items.len)) + opts.code_block_padding * 2;

                    if (y - total_h < page_bottom) {
                        current_page = try addNewPage(&doc, opts, &font_handles);
                        y = page_top;
                    }

                    // Draw background rectangle (PDF y is bottom-up)
                    const bg_y = y - total_h + opts.code_block_padding;
                    try current_page.drawRect(.{
                        .x = opts.margin_left,
                        .y = bg_y,
                        .width = content_width,
                        .height = total_h,
                        .color = opts.code_bg_color,
                    });

                    // Draw each code line
                    var code_y = y - opts.code_block_padding;
                    for (block.lines.items) |line| {
                        if (code_y - line_h < page_bottom) {
                            current_page = try addNewPage(&doc, opts, &font_handles);
                            code_y = page_top - opts.code_block_padding;
                        }
                        try current_page.drawText(line, .{
                            .x = opts.margin_left + opts.code_block_padding,
                            .y = code_y,
                            .font = opts.code_font,
                            .font_size = opts.code_size,
                            .color = opts.code_color,
                        });
                        code_y -= line_h;
                    }
                    y = code_y - opts.code_block_padding + opts.paragraph_spacing;
                },
                .unordered_list => {
                    const result = try renderList(allocator, current_page, block, opts, y, page_bottom, page_top, &doc, &font_handles, false);
                    current_page = result.page;
                    y = result.y;
                },
                .ordered_list => {
                    const result = try renderList(allocator, current_page, block, opts, y, page_bottom, page_top, &doc, &font_handles, true);
                    current_page = result.page;
                    y = result.y;
                },
                .blockquote => {
                    // Join blockquote lines
                    var bq_text = std.ArrayListUnmanaged(u8){};
                    defer bq_text.deinit(allocator);
                    for (block.lines.items, 0..) |line, i| {
                        if (i > 0) try bq_text.append(allocator, ' ');
                        try bq_text.appendSlice(allocator, line);
                    }

                    if (y - opts.body_size * opts.line_height_factor < page_bottom) {
                        current_page = try addNewPage(&doc, opts, &font_handles);
                        y = page_top;
                    }

                    var spans_list = std.ArrayListUnmanaged(TextSpan){};
                    defer spans_list.deinit(allocator);

                    try parseInlineSpans(allocator, bq_text.items, opts, opts.body_size, false, &spans_list);

                    // Override color for blockquote
                    for (spans_list.items) |*span| {
                        span.color = opts.blockquote_color;
                    }

                    if (spans_list.items.len == 0) {
                        try spans_list.append(allocator, .{
                            .text = bq_text.items,
                            .font = opts.italic_font,
                            .font_size = opts.body_size,
                            .color = opts.blockquote_color,
                        });
                    }

                    const bq_content_width = content_width - opts.blockquote_indent;
                    const bq_x = opts.margin_left + opts.blockquote_indent;

                    const height = try current_page.drawRichText(spans_list.items, .{
                        .x = bq_x,
                        .y = y,
                        .max_width = bq_content_width,
                        .line_height_factor = opts.line_height_factor,
                    });

                    // Draw left border line
                    try current_page.drawLine(.{
                        .x1 = opts.margin_left + opts.blockquote_border_width / 2.0,
                        .y1 = y + opts.body_size * 0.3,
                        .x2 = opts.margin_left + opts.blockquote_border_width / 2.0,
                        .y2 = y - height + opts.body_size * 0.3,
                        .color = opts.blockquote_border_color,
                        .line_width = opts.blockquote_border_width,
                    });

                    y -= height + opts.paragraph_spacing;
                },
                .horizontal_rule => {
                    y -= opts.paragraph_spacing;
                    if (y < page_bottom) {
                        current_page = try addNewPage(&doc, opts, &font_handles);
                        y = page_top;
                    }
                    try current_page.drawLine(.{
                        .x1 = opts.margin_left,
                        .y1 = y,
                        .x2 = opts.margin_left + content_width,
                        .y2 = y,
                        .color = opts.rule_color,
                        .line_width = 1.0,
                    });
                    y -= opts.paragraph_spacing;
                },
            }
        }

        return doc.save(allocator);
    }
};

const ListRenderResult = struct {
    page: *Page,
    y: f32,
};

fn renderList(
    allocator: Allocator,
    initial_page: *Page,
    block: *Block,
    opts: MarkdownOptions,
    initial_y: f32,
    page_bottom: f32,
    page_top: f32,
    doc: *Document,
    font_handles: *[7]@import("../document/document.zig").FontHandle,
    ordered: bool,
) !ListRenderResult {
    var page = initial_page;
    var y = initial_y;
    const content_width = opts.page_size.dimensions().width - opts.margin_left - opts.margin_right;

    for (block.lines.items, 0..) |line, idx| {
        if (y - opts.body_size * opts.line_height_factor < page_bottom) {
            page = try addNewPage(doc, opts, font_handles);
            y = page_top;
        }

        // Draw marker
        var marker_buf: [16]u8 = undefined;
        const marker = if (ordered)
            lists_mod.formatNumber(@as(u32, @intCast(idx + 1)), &marker_buf)
        else
            "\xe2\x80\xa2"; // bullet character (we use a simple dash since standard fonts may not have bullet)

        // For standard fonts, use a simple dash/number
        const marker_text = if (ordered) marker else "-";
        const marker_width = opts.body_font.textWidth(marker_text, opts.body_size);

        try page.drawText(marker_text, .{
            .x = opts.margin_left + opts.list_indent,
            .y = y,
            .font = opts.body_font,
            .font_size = opts.body_size,
            .color = opts.text_color,
        });

        // Draw list item text with inline formatting
        var spans_list = std.ArrayListUnmanaged(TextSpan){};
        defer spans_list.deinit(allocator);

        try parseInlineSpans(allocator, line, opts, opts.body_size, false, &spans_list);

        if (spans_list.items.len == 0) {
            try spans_list.append(allocator, .{
                .text = line,
                .font = opts.body_font,
                .font_size = opts.body_size,
                .color = opts.text_color,
            });
        }

        const text_x = opts.margin_left + opts.list_indent + marker_width + 6;
        const text_width = content_width - opts.list_indent - marker_width - 6;

        const height = try page.drawRichText(spans_list.items, .{
            .x = text_x,
            .y = y,
            .max_width = text_width,
            .line_height_factor = opts.line_height_factor,
        });
        y -= height + opts.paragraph_spacing * 0.5;
    }

    return .{ .page = page, .y = y };
}

fn addNewPage(
    doc: *Document,
    opts: MarkdownOptions,
    font_handles: *[7]@import("../document/document.zig").FontHandle,
) !*Page {
    const page = try doc.addPage(opts.page_size);
    for (font_handles) |fh| {
        _ = try page.addFont(fh.font.pdfName(), fh.ref);
    }
    return page;
}

// ── Block Parser ──────────────────────────────────────────────────────

fn parseBlocks(allocator: Allocator, text: []const u8) !std.ArrayListUnmanaged(Block) {
    var blocks = std.ArrayListUnmanaged(Block){};
    errdefer {
        for (blocks.items) |*b| b.deinit(allocator);
        blocks.deinit(allocator);
    }

    var lines_iter = std.mem.splitScalar(u8, text, '\n');
    var in_code_block = false;
    var current_block: ?Block = null;

    while (lines_iter.next()) |raw_line| {
        const line = std.mem.trimRight(u8, raw_line, "\r");

        if (in_code_block) {
            if (std.mem.startsWith(u8, std.mem.trimLeft(u8, line, " "), "```")) {
                // End code block
                if (current_block) |*cb| {
                    try blocks.append(allocator, cb.*);
                    current_block = null;
                }
                in_code_block = false;
            } else {
                if (current_block) |*cb| {
                    try cb.lines.append(allocator, line);
                }
            }
            continue;
        }

        // Check for code block start
        if (std.mem.startsWith(u8, std.mem.trimLeft(u8, line, " "), "```")) {
            // Flush any pending block
            if (current_block) |*cb| {
                try blocks.append(allocator, cb.*);
                current_block = null;
            }
            current_block = .{ .block_type = .code_block };
            in_code_block = true;
            continue;
        }

        const trimmed = std.mem.trimLeft(u8, line, " ");

        // Blank line
        if (trimmed.len == 0) {
            if (current_block) |*cb| {
                try blocks.append(allocator, cb.*);
                current_block = null;
            }
            try blocks.append(allocator, .{ .block_type = .blank });
            continue;
        }

        // Horizontal rule (---, ***, ___)
        if (isHorizontalRule(trimmed)) {
            if (current_block) |*cb| {
                try blocks.append(allocator, cb.*);
                current_block = null;
            }
            try blocks.append(allocator, .{ .block_type = .horizontal_rule });
            continue;
        }

        // Heading
        if (trimmed.len > 0 and trimmed[0] == '#') {
            if (current_block) |*cb| {
                try blocks.append(allocator, cb.*);
                current_block = null;
            }
            var level: u8 = 0;
            var pos: usize = 0;
            while (pos < trimmed.len and trimmed[pos] == '#' and level < 4) {
                level += 1;
                pos += 1;
            }
            if (pos < trimmed.len and trimmed[pos] == ' ') {
                pos += 1;
            }
            const heading_text = if (pos < trimmed.len) trimmed[pos..] else "";
            var b = Block{ .block_type = .heading, .heading_level = level };
            try b.lines.append(allocator, heading_text);
            try blocks.append(allocator, b);
            continue;
        }

        // Blockquote
        if (trimmed.len > 0 and trimmed[0] == '>') {
            const bq_text = std.mem.trimLeft(u8, trimmed[1..], " ");
            if (current_block) |*cb| {
                if (cb.block_type == .blockquote) {
                    try cb.lines.append(allocator, bq_text);
                    continue;
                } else {
                    try blocks.append(allocator, cb.*);
                    current_block = null;
                }
            }
            current_block = .{ .block_type = .blockquote };
            try current_block.?.lines.append(allocator, bq_text);
            continue;
        }

        // Unordered list item
        if (isUnorderedListItem(trimmed)) {
            const item_text = std.mem.trimLeft(u8, trimmed[2..], " ");
            if (current_block) |*cb| {
                if (cb.block_type == .unordered_list) {
                    try cb.lines.append(allocator, item_text);
                    continue;
                } else {
                    try blocks.append(allocator, cb.*);
                    current_block = null;
                }
            }
            current_block = .{ .block_type = .unordered_list };
            try current_block.?.lines.append(allocator, item_text);
            continue;
        }

        // Ordered list item
        if (isOrderedListItem(trimmed)) {
            const dot_pos = std.mem.indexOfScalar(u8, trimmed, '.') orelse 0;
            const item_text = if (dot_pos + 1 < trimmed.len)
                std.mem.trimLeft(u8, trimmed[dot_pos + 1 ..], " ")
            else
                "";
            if (current_block) |*cb| {
                if (cb.block_type == .ordered_list) {
                    try cb.lines.append(allocator, item_text);
                    continue;
                } else {
                    try blocks.append(allocator, cb.*);
                    current_block = null;
                }
            }
            current_block = .{ .block_type = .ordered_list };
            try current_block.?.lines.append(allocator, item_text);
            continue;
        }

        // Paragraph text (continuation or new)
        if (current_block) |*cb| {
            if (cb.block_type == .paragraph) {
                try cb.lines.append(allocator, trimmed);
                continue;
            } else {
                try blocks.append(allocator, cb.*);
                current_block = null;
            }
        }
        current_block = .{ .block_type = .paragraph };
        try current_block.?.lines.append(allocator, trimmed);
    }

    // Flush remaining block
    if (current_block) |*cb| {
        try blocks.append(allocator, cb.*);
    }

    // Handle unclosed code block
    if (in_code_block) {
        // Already flushed above if current_block was set
    }

    return blocks;
}

fn isHorizontalRule(line: []const u8) bool {
    if (line.len < 3) return false;
    const ch = line[0];
    if (ch != '-' and ch != '*' and ch != '_') return false;
    var count: usize = 0;
    for (line) |c| {
        if (c == ch) {
            count += 1;
        } else if (c != ' ') {
            return false;
        }
    }
    return count >= 3;
}

fn isUnorderedListItem(line: []const u8) bool {
    if (line.len < 2) return false;
    return (line[0] == '-' or line[0] == '*' or line[0] == '+') and line[1] == ' ';
}

fn isOrderedListItem(line: []const u8) bool {
    if (line.len < 3) return false;
    var i: usize = 0;
    while (i < line.len and line[i] >= '0' and line[i] <= '9') : (i += 1) {}
    if (i == 0 or i >= line.len) return false;
    if (line[i] != '.') return false;
    if (i + 1 < line.len and line[i + 1] == ' ') return true;
    return false;
}

// ── Inline Parser ─────────────────────────────────────────────────────

fn parseInlineSpans(
    allocator: Allocator,
    text: []const u8,
    opts: MarkdownOptions,
    font_size: f32,
    is_heading: bool,
    spans_list: *std.ArrayListUnmanaged(TextSpan),
) !void {
    if (text.len == 0) return;

    var segments = std.ArrayListUnmanaged(InlineSegment){};
    defer segments.deinit(allocator);

    try parseInlineSegments(text, &segments, allocator);

    for (segments.items) |seg| {
        const font = resolveFont(seg.style, opts, is_heading);
        const clr = resolveColor(seg.style, opts, is_heading);
        const is_link = seg.style.link_url != null;
        const is_code = seg.style.code;

        try spans_list.append(allocator, .{
            .text = seg.text,
            .font = font,
            .font_size = if (is_code) opts.code_size else font_size,
            .color = clr,
            .underline = is_link,
        });
    }
}

fn resolveFont(style: InlineStyle, opts: MarkdownOptions, is_heading: bool) StandardFont {
    if (style.code) return opts.code_font;
    if (style.bold and style.italic) return opts.bold_italic_font;
    if (style.bold) {
        return if (is_heading) opts.heading_font else opts.bold_font;
    }
    if (style.italic) return opts.italic_font;
    return if (is_heading) opts.heading_font else opts.body_font;
}

fn resolveColor(style: InlineStyle, opts: MarkdownOptions, is_heading: bool) Color {
    if (style.link_url != null) return opts.link_color;
    if (style.code) return opts.code_color;
    return if (is_heading) opts.heading_color else opts.text_color;
}

fn parseInlineSegments(
    text: []const u8,
    segments: *std.ArrayListUnmanaged(InlineSegment),
    allocator: Allocator,
) !void {
    var pos: usize = 0;
    var current_start: usize = 0;
    var bold = false;
    var italic = false;

    while (pos < text.len) {
        // Check for inline code
        if (text[pos] == '`') {
            // Flush preceding text
            if (pos > current_start) {
                try segments.append(allocator, .{
                    .text = text[current_start..pos],
                    .style = .{ .bold = bold, .italic = italic },
                });
            }
            // Find closing backtick
            const code_start = pos + 1;
            var code_end = code_start;
            while (code_end < text.len and text[code_end] != '`') : (code_end += 1) {}
            if (code_end < text.len) {
                try segments.append(allocator, .{
                    .text = text[code_start..code_end],
                    .style = .{ .code = true },
                });
                pos = code_end + 1;
            } else {
                // No closing backtick, treat as literal
                pos = code_start;
            }
            current_start = pos;
            continue;
        }

        // Check for link [text](url)
        if (text[pos] == '[') {
            const bracket_end = std.mem.indexOfScalarPos(u8, text, pos + 1, ']');
            if (bracket_end) |be| {
                if (be + 1 < text.len and text[be + 1] == '(') {
                    const paren_end = std.mem.indexOfScalarPos(u8, text, be + 2, ')');
                    if (paren_end) |pe| {
                        // Flush preceding text
                        if (pos > current_start) {
                            try segments.append(allocator, .{
                                .text = text[current_start..pos],
                                .style = .{ .bold = bold, .italic = italic },
                            });
                        }
                        const link_text = text[pos + 1 .. be];
                        const link_url = text[be + 2 .. pe];
                        try segments.append(allocator, .{
                            .text = link_text,
                            .style = .{ .bold = bold, .italic = italic, .link_url = link_url },
                        });
                        pos = pe + 1;
                        current_start = pos;
                        continue;
                    }
                }
            }
        }

        // Check for bold+italic (***) or bold (**) or italic (*)
        if (text[pos] == '*') {
            const star_count = countConsecutive(text, pos, '*');
            if (star_count >= 3) {
                // Flush preceding text
                if (pos > current_start) {
                    try segments.append(allocator, .{
                        .text = text[current_start..pos],
                        .style = .{ .bold = bold, .italic = italic },
                    });
                }
                bold = !bold;
                italic = !italic;
                pos += 3;
                current_start = pos;
                continue;
            } else if (star_count == 2) {
                if (pos > current_start) {
                    try segments.append(allocator, .{
                        .text = text[current_start..pos],
                        .style = .{ .bold = bold, .italic = italic },
                    });
                }
                bold = !bold;
                pos += 2;
                current_start = pos;
                continue;
            } else {
                if (pos > current_start) {
                    try segments.append(allocator, .{
                        .text = text[current_start..pos],
                        .style = .{ .bold = bold, .italic = italic },
                    });
                }
                italic = !italic;
                pos += 1;
                current_start = pos;
                continue;
            }
        }

        pos += 1;
    }

    // Flush remaining text
    if (current_start < text.len) {
        try segments.append(allocator, .{
            .text = text[current_start..],
            .style = .{ .bold = bold, .italic = italic },
        });
    }
}

fn countConsecutive(text: []const u8, start: usize, ch: u8) usize {
    var count: usize = 0;
    var i = start;
    while (i < text.len and text[i] == ch) : (i += 1) {
        count += 1;
    }
    return count;
}

// ── Tests ─────────────────────────────────────────────────────────────

test "parse heading block" {
    const allocator = std.testing.allocator;
    var blocks = try parseBlocks(allocator, "# Hello World");
    defer {
        for (blocks.items) |*b| b.deinit(allocator);
        blocks.deinit(allocator);
    }
    try std.testing.expectEqual(@as(usize, 1), blocks.items.len);
    try std.testing.expectEqual(BlockType.heading, blocks.items[0].block_type);
    try std.testing.expectEqual(@as(u8, 1), blocks.items[0].heading_level);
    try std.testing.expectEqualStrings("Hello World", blocks.items[0].lines.items[0]);
}

test "parse horizontal rule" {
    const allocator = std.testing.allocator;
    var blocks = try parseBlocks(allocator, "---");
    defer {
        for (blocks.items) |*b| b.deinit(allocator);
        blocks.deinit(allocator);
    }
    try std.testing.expectEqual(@as(usize, 1), blocks.items.len);
    try std.testing.expectEqual(BlockType.horizontal_rule, blocks.items[0].block_type);
}

test "parse code block" {
    const allocator = std.testing.allocator;
    var blocks = try parseBlocks(allocator, "```\nfn main() {}\n```");
    defer {
        for (blocks.items) |*b| b.deinit(allocator);
        blocks.deinit(allocator);
    }
    try std.testing.expectEqual(@as(usize, 1), blocks.items.len);
    try std.testing.expectEqual(BlockType.code_block, blocks.items[0].block_type);
    try std.testing.expectEqualStrings("fn main() {}", blocks.items[0].lines.items[0]);
}

test "parse unordered list" {
    const allocator = std.testing.allocator;
    var blocks = try parseBlocks(allocator, "- item one\n- item two");
    defer {
        for (blocks.items) |*b| b.deinit(allocator);
        blocks.deinit(allocator);
    }
    try std.testing.expectEqual(@as(usize, 1), blocks.items.len);
    try std.testing.expectEqual(BlockType.unordered_list, blocks.items[0].block_type);
    try std.testing.expectEqual(@as(usize, 2), blocks.items[0].lines.items.len);
}

test "parse ordered list" {
    const allocator = std.testing.allocator;
    var blocks = try parseBlocks(allocator, "1. first\n2. second\n3. third");
    defer {
        for (blocks.items) |*b| b.deinit(allocator);
        blocks.deinit(allocator);
    }
    try std.testing.expectEqual(@as(usize, 1), blocks.items.len);
    try std.testing.expectEqual(BlockType.ordered_list, blocks.items[0].block_type);
    try std.testing.expectEqual(@as(usize, 3), blocks.items[0].lines.items.len);
}

test "parse blockquote" {
    const allocator = std.testing.allocator;
    var blocks = try parseBlocks(allocator, "> This is a quote");
    defer {
        for (blocks.items) |*b| b.deinit(allocator);
        blocks.deinit(allocator);
    }
    try std.testing.expectEqual(@as(usize, 1), blocks.items.len);
    try std.testing.expectEqual(BlockType.blockquote, blocks.items[0].block_type);
    try std.testing.expectEqualStrings("This is a quote", blocks.items[0].lines.items[0]);
}

test "parse inline segments with bold" {
    const allocator = std.testing.allocator;
    var segments = std.ArrayListUnmanaged(InlineSegment){};
    defer segments.deinit(allocator);

    try parseInlineSegments("hello **world** end", &segments, allocator);
    try std.testing.expectEqual(@as(usize, 3), segments.items.len);
    try std.testing.expectEqualStrings("hello ", segments.items[0].text);
    try std.testing.expect(!segments.items[0].style.bold);
    try std.testing.expectEqualStrings("world", segments.items[1].text);
    try std.testing.expect(segments.items[1].style.bold);
    try std.testing.expectEqualStrings(" end", segments.items[2].text);
    try std.testing.expect(!segments.items[2].style.bold);
}

test "parse inline segments with italic" {
    const allocator = std.testing.allocator;
    var segments = std.ArrayListUnmanaged(InlineSegment){};
    defer segments.deinit(allocator);

    try parseInlineSegments("hello *world* end", &segments, allocator);
    try std.testing.expectEqual(@as(usize, 3), segments.items.len);
    try std.testing.expectEqualStrings("world", segments.items[1].text);
    try std.testing.expect(segments.items[1].style.italic);
    try std.testing.expectEqualStrings(" end", segments.items[2].text);
    try std.testing.expect(!segments.items[2].style.italic);
}

test "parse inline segments with code" {
    const allocator = std.testing.allocator;
    var segments = std.ArrayListUnmanaged(InlineSegment){};
    defer segments.deinit(allocator);

    try parseInlineSegments("use `const x` here", &segments, allocator);
    try std.testing.expectEqual(@as(usize, 3), segments.items.len);
    try std.testing.expectEqualStrings("const x", segments.items[1].text);
    try std.testing.expect(segments.items[1].style.code);
}

test "parse inline segments with link" {
    const allocator = std.testing.allocator;
    var segments = std.ArrayListUnmanaged(InlineSegment){};
    defer segments.deinit(allocator);

    try parseInlineSegments("click [here](https://example.com) now", &segments, allocator);
    try std.testing.expectEqual(@as(usize, 3), segments.items.len);
    try std.testing.expectEqualStrings("here", segments.items[1].text);
    try std.testing.expect(segments.items[1].style.link_url != null);
    try std.testing.expectEqualStrings("https://example.com", segments.items[1].style.link_url.?);
}

test "isHorizontalRule" {
    try std.testing.expect(isHorizontalRule("---"));
    try std.testing.expect(isHorizontalRule("***"));
    try std.testing.expect(isHorizontalRule("___"));
    try std.testing.expect(isHorizontalRule("- - -"));
    try std.testing.expect(!isHorizontalRule("--"));
    try std.testing.expect(!isHorizontalRule("abc"));
}

test "isOrderedListItem" {
    try std.testing.expect(isOrderedListItem("1. item"));
    try std.testing.expect(isOrderedListItem("10. item"));
    try std.testing.expect(!isOrderedListItem("- item"));
    try std.testing.expect(!isOrderedListItem("abc"));
}

test "isUnorderedListItem" {
    try std.testing.expect(isUnorderedListItem("- item"));
    try std.testing.expect(isUnorderedListItem("* item"));
    try std.testing.expect(isUnorderedListItem("+ item"));
    try std.testing.expect(!isUnorderedListItem("1. item"));
}

test "render produces valid pdf bytes" {
    const allocator = std.testing.allocator;
    var renderer = MarkdownRenderer.init(allocator, .{});
    const bytes = try renderer.render("# Hello\n\nA paragraph.");
    defer allocator.free(bytes);
    // PDF must start with %PDF-
    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-"));
    try std.testing.expect(bytes.len > 100);
}
