const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const pdf_parser = @import("pdf_parser.zig");
const ParsedPage = pdf_parser.ParsedPage;
const ParsedDocument = pdf_parser.ParsedDocument;

/// A single fragment of text with its position and style metadata.
pub const TextFragment = struct {
    text: []const u8,
    x: f64,
    y: f64,
    font_name: []const u8,
    font_size: f64,
    width: f64,
};

/// A line of text assembled from fragments at similar y-coordinates.
pub const TextLine = struct {
    fragments: []const TextFragment,
    y: f64,
    min_x: f64,
    max_x: f64,

    pub fn getText(self: *const TextLine, allocator: Allocator) ![]u8 {
        if (self.fragments.len == 0) return try allocator.alloc(u8, 0);

        var total_len: usize = 0;
        for (self.fragments, 0..) |frag, i| {
            total_len += frag.text.len;
            if (i + 1 < self.fragments.len) total_len += 1;
        }

        const buf = try allocator.alloc(u8, total_len);
        var pos: usize = 0;
        for (self.fragments, 0..) |frag, i| {
            @memcpy(buf[pos .. pos + frag.text.len], frag.text);
            pos += frag.text.len;
            if (i + 1 < self.fragments.len) {
                buf[pos] = ' ';
                pos += 1;
            }
        }
        return buf;
    }
};

/// The result of layout-aware text extraction.
pub const ExtractedText = struct {
    allocator: Allocator,
    lines: []TextLine,
    fragments: []TextFragment,
    plain_text: []const u8,

    pub fn deinit(self: *ExtractedText) void {
        self.allocator.free(self.plain_text);
        for (self.lines) |line| {
            self.allocator.free(line.fragments);
        }
        self.allocator.free(self.lines);
        for (self.fragments) |frag| {
            self.allocator.free(frag.text);
        }
        self.allocator.free(self.fragments);
    }
};

/// Options controlling text extraction behaviour.
pub const ExtractionOptions = struct {
    line_tolerance: f64 = 2.0,
    paragraph_gap_factor: f64 = 1.5,
    word_gap: f64 = 2.0,
    sort_by_position: bool = true,
    avg_char_width_factor: f64 = 0.5,
};

const TextState = struct {
    tm: [6]f64 = .{ 1, 0, 0, 1, 0, 0 },
    lm: [6]f64 = .{ 1, 0, 0, 1, 0, 0 },
    font_name: []const u8 = "Unknown",
    font_size: f64 = 12,
    leading: f64 = 0,
    in_text: bool = false,
};

/// Extract layout-aware text from a single parsed page.
pub fn extractText(
    allocator: Allocator,
    page: *const ParsedPage,
    options: ExtractionOptions,
) !ExtractedText {
    var fragments: ArrayList(TextFragment) = .{};
    defer fragments.deinit(allocator);

    try parseContentStream(allocator, page.content_data, &fragments, options);

    const owned_frags = try allocator.dupe(TextFragment, fragments.items);
    errdefer allocator.free(owned_frags);

    if (options.sort_by_position) {
        std.mem.sort(TextFragment, owned_frags, {}, struct {
            fn lessThan(_: void, a: TextFragment, b: TextFragment) bool {
                if (@abs(a.y - b.y) > 2.0) return a.y > b.y;
                return a.x < b.x;
            }
        }.lessThan);
    }

    var lines: ArrayList(TextLine) = .{};
    defer lines.deinit(allocator);

    try groupIntoLines(allocator, owned_frags, &lines);

    const owned_lines = try allocator.dupe(TextLine, lines.items);
    errdefer {
        for (owned_lines) |line| allocator.free(line.fragments);
        allocator.free(owned_lines);
    }

    const plain_text = try buildPlainText(allocator, owned_lines, options);

    return ExtractedText{
        .allocator = allocator,
        .lines = owned_lines,
        .fragments = owned_frags,
        .plain_text = plain_text,
    };
}

/// Extract text from all pages of a parsed document.
pub fn extractAllText(
    allocator: Allocator,
    doc: *const ParsedDocument,
    options: ExtractionOptions,
) !ExtractedText {
    var all_fragments: ArrayList(TextFragment) = .{};
    defer all_fragments.deinit(allocator);

    var all_lines: ArrayList(TextLine) = .{};
    defer all_lines.deinit(allocator);

    var text_parts: ArrayList([]const u8) = .{};
    defer {
        for (text_parts.items) |part| allocator.free(part);
        text_parts.deinit(allocator);
    }

    for (doc.pages.items) |*page| {
        const page_result = try extractText(allocator, page, options);

        try all_fragments.appendSlice(allocator, page_result.fragments);
        try all_lines.appendSlice(allocator, page_result.lines);
        try text_parts.append(allocator, page_result.plain_text);

        allocator.free(page_result.fragments);
        allocator.free(page_result.lines);
    }

    var total_len: usize = 0;
    for (text_parts.items, 0..) |part, i| {
        total_len += part.len;
        if (i + 1 < text_parts.items.len) total_len += 1;
    }

    const joined = try allocator.alloc(u8, total_len);
    var pos: usize = 0;
    for (text_parts.items, 0..) |part, i| {
        @memcpy(joined[pos .. pos + part.len], part);
        pos += part.len;
        if (i + 1 < text_parts.items.len) {
            joined[pos] = '\n';
            pos += 1;
        }
    }

    for (text_parts.items) |part| allocator.free(part);
    text_parts.clearRetainingCapacity();

    const owned_frags = try allocator.dupe(TextFragment, all_fragments.items);
    const owned_lines = try allocator.dupe(TextLine, all_lines.items);

    return ExtractedText{
        .allocator = allocator,
        .lines = owned_lines,
        .fragments = owned_frags,
        .plain_text = joined,
    };
}

fn parseContentStream(
    allocator: Allocator,
    data: []const u8,
    fragments: *ArrayList(TextFragment),
    options: ExtractionOptions,
) !void {
    if (data.len == 0) return;

    var state = TextState{};
    var tok = Tokenizer.init(data);
    var num_stack: [32]f64 = undefined;
    var num_count: usize = 0;
    var last_name: []const u8 = "";
    var last_string: []const u8 = "";
    var has_string = false;
    var last_string_allocated = false;

    while (true) {
        const token = tok.next();
        if (token == .eof) break;

        switch (token) {
            .number => {
                if (num_count < 32) {
                    num_stack[num_count] = parseFloat(tok.getValue());
                    num_count += 1;
                }
            },
            .name => {
                last_name = tok.getValue();
            },
            .string => {
                last_string = tok.getValue();
                has_string = true;
            },
            .keyword => {
                const kw = tok.getValue();
                try handleOperator(allocator, kw, &state, num_stack[0..num_count], last_name, last_string, has_string, fragments, options);
                num_count = 0;
                if (last_string_allocated and has_string) {
                    allocator.free(@constCast(last_string));
                    last_string_allocated = false;
                }
                has_string = false;
            },
            .array_start => {
                var arr_strings: ArrayList(u8) = .{};
                defer arr_strings.deinit(allocator);

                var inner_running = true;
                while (inner_running) {
                    const inner = tok.next();
                    switch (inner) {
                        .string => {
                            try arr_strings.appendSlice(allocator, tok.getValue());
                        },
                        .hex_string => {
                            const hex = tok.getValue();
                            var hi: usize = 0;
                            while (hi + 1 < hex.len) : (hi += 2) {
                                const byte = hexToByte(hex[hi], hex[hi + 1]);
                                if (byte >= 0x20 and byte < 0x7f) {
                                    try arr_strings.append(allocator, byte);
                                }
                            }
                        },
                        .number => {
                            const val = parseFloat(tok.getValue());
                            if (val < -100) {
                                try arr_strings.append(allocator, ' ');
                            }
                        },
                        .array_end => inner_running = false,
                        .eof => inner_running = false,
                        else => {},
                    }
                }

                if (arr_strings.items.len > 0) {
                    if (last_string_allocated) {
                        allocator.free(@constCast(last_string));
                    }
                    last_string = try allocator.dupe(u8, arr_strings.items);
                    last_string_allocated = true;
                    has_string = true;
                }
            },
            else => {},
        }
    }
}

fn handleOperator(
    allocator: Allocator,
    kw: []const u8,
    state: *TextState,
    nums: []const f64,
    last_name: []const u8,
    last_string: []const u8,
    has_string: bool,
    fragments: *ArrayList(TextFragment),
    options: ExtractionOptions,
) !void {
    if (std.mem.eql(u8, kw, "BT")) {
        state.in_text = true;
        state.tm = .{ 1, 0, 0, 1, 0, 0 };
        state.lm = .{ 1, 0, 0, 1, 0, 0 };
    } else if (std.mem.eql(u8, kw, "ET")) {
        state.in_text = false;
    } else if (std.mem.eql(u8, kw, "Td")) {
        if (nums.len >= 2) {
            state.lm[4] += nums[nums.len - 2];
            state.lm[5] += nums[nums.len - 1];
            state.tm = state.lm;
        }
    } else if (std.mem.eql(u8, kw, "TD")) {
        if (nums.len >= 2) {
            state.leading = -nums[nums.len - 1];
            state.lm[4] += nums[nums.len - 2];
            state.lm[5] += nums[nums.len - 1];
            state.tm = state.lm;
        }
    } else if (std.mem.eql(u8, kw, "Tm")) {
        if (nums.len >= 6) {
            const b = nums.len - 6;
            state.tm = .{ nums[b], nums[b + 1], nums[b + 2], nums[b + 3], nums[b + 4], nums[b + 5] };
            state.lm = state.tm;
        }
    } else if (std.mem.eql(u8, kw, "T*")) {
        state.lm[5] -= state.leading;
        state.tm = state.lm;
    } else if (std.mem.eql(u8, kw, "TL")) {
        if (nums.len >= 1) state.leading = nums[nums.len - 1];
    } else if (std.mem.eql(u8, kw, "Tf")) {
        if (nums.len >= 1) state.font_size = nums[nums.len - 1];
        state.font_name = last_name;
    } else if (std.mem.eql(u8, kw, "Tj") or std.mem.eql(u8, kw, "TJ")) {
        if (has_string) try emitFragment(allocator, state, last_string, fragments, options);
    } else if (std.mem.eql(u8, kw, "'")) {
        state.lm[5] -= state.leading;
        state.tm = state.lm;
        if (has_string) try emitFragment(allocator, state, last_string, fragments, options);
    } else if (std.mem.eql(u8, kw, "\"")) {
        state.lm[5] -= state.leading;
        state.tm = state.lm;
        if (has_string) try emitFragment(allocator, state, last_string, fragments, options);
    }
}

fn emitFragment(
    allocator: Allocator,
    state: *const TextState,
    text: []const u8,
    fragments: *ArrayList(TextFragment),
    options: ExtractionOptions,
) !void {
    if (text.len == 0) return;

    const char_count: f64 = @floatFromInt(text.len);
    const width = char_count * state.font_size * options.avg_char_width_factor;

    try fragments.append(allocator, .{
        .text = try allocator.dupe(u8, text),
        .x = state.tm[4],
        .y = state.tm[5],
        .font_name = state.font_name,
        .font_size = state.font_size,
        .width = width,
    });
}

fn groupIntoLines(
    allocator: Allocator,
    fragments: []const TextFragment,
    lines: *ArrayList(TextLine),
) !void {
    if (fragments.len == 0) return;

    var line_start: usize = 0;
    var current_y = fragments[0].y;

    for (fragments, 0..) |frag, i| {
        if (@abs(frag.y - current_y) > 2.0) {
            try addLine(allocator, fragments[line_start..i], current_y, lines);
            line_start = i;
            current_y = frag.y;
        }
    }
    if (line_start < fragments.len) {
        try addLine(allocator, fragments[line_start..], current_y, lines);
    }
}

fn addLine(
    allocator: Allocator,
    frags: []const TextFragment,
    y: f64,
    lines: *ArrayList(TextLine),
) !void {
    if (frags.len == 0) return;

    const owned = try allocator.dupe(TextFragment, frags);
    var min_x: f64 = frags[0].x;
    var max_x: f64 = frags[0].x + frags[0].width;
    for (frags[1..]) |f| {
        if (f.x < min_x) min_x = f.x;
        const right = f.x + f.width;
        if (right > max_x) max_x = right;
    }

    try lines.append(allocator, .{ .fragments = owned, .y = y, .min_x = min_x, .max_x = max_x });
}

fn buildPlainText(
    allocator: Allocator,
    lines: []const TextLine,
    options: ExtractionOptions,
) ![]u8 {
    if (lines.len == 0) return try allocator.alloc(u8, 0);

    var parts: ArrayList(u8) = .{};
    defer parts.deinit(allocator);

    for (lines, 0..) |line, i| {
        for (line.fragments, 0..) |frag, j| {
            try parts.appendSlice(allocator, frag.text);
            if (j + 1 < line.fragments.len) {
                const next_frag = line.fragments[j + 1];
                const gap = next_frag.x - (frag.x + frag.width);
                if (gap > options.word_gap) {
                    try parts.append(allocator, ' ');
                }
            }
        }

        if (i + 1 < lines.len) {
            const gap = @abs(line.y - lines[i + 1].y);
            const avg_size = if (line.fragments.len > 0) line.fragments[0].font_size else 12.0;

            if (gap > avg_size * options.paragraph_gap_factor) {
                try parts.append(allocator, '\n');
                try parts.append(allocator, '\n');
            } else {
                try parts.append(allocator, '\n');
            }
        }
    }

    return try allocator.dupe(u8, parts.items);
}

fn parseFloat(s: []const u8) f64 {
    return std.fmt.parseFloat(f64, s) catch 0;
}

fn hexToByte(hi: u8, lo: u8) u8 {
    return (hexDigit(hi) << 4) | hexDigit(lo);
}

fn hexDigit(c: u8) u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => 0,
    };
}

// -- Tests --

test "text_extractor: empty content" {
    const allocator = std.testing.allocator;
    const page = ParsedPage{ .width = 612, .height = 792, .content_data = "" };
    var result = try extractText(allocator, &page, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 0), result.fragments.len);
    try std.testing.expectEqual(@as(usize, 0), result.plain_text.len);
}

test "text_extractor: single Tj" {
    const allocator = std.testing.allocator;
    const page = ParsedPage{ .width = 612, .height = 792, .content_data = "BT /F1 12 Tf 72 720 Td (Hello World) Tj ET" };
    var result = try extractText(allocator, &page, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 1), result.fragments.len);
    try std.testing.expectEqualStrings("Hello World", result.fragments[0].text);
    try std.testing.expect(result.fragments[0].x == 72.0);
    try std.testing.expect(result.fragments[0].y == 720.0);
}

test "text_extractor: Tm sets position" {
    const allocator = std.testing.allocator;
    const page = ParsedPage{ .width = 612, .height = 792, .content_data = "BT /F1 10 Tf 1 0 0 1 100 500 Tm (Positioned) Tj ET" };
    var result = try extractText(allocator, &page, .{});
    defer result.deinit();
    try std.testing.expect(result.fragments[0].x == 100.0);
    try std.testing.expect(result.fragments[0].y == 500.0);
}

test "text_extractor: multiple lines" {
    const allocator = std.testing.allocator;
    const page = ParsedPage{ .width = 612, .height = 792, .content_data = "BT /F1 12 Tf 72 720 Td (Line one) Tj 0 -14 Td (Line two) Tj ET" };
    var result = try extractText(allocator, &page, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 2), result.lines.len);
    try std.testing.expect(result.plain_text.len > 0);
}

test "text_extractor: TJ array" {
    const allocator = std.testing.allocator;
    const page = ParsedPage{ .width = 612, .height = 792, .content_data = "BT /F1 12 Tf 72 700 Td [(Hello) -50 ( World)] TJ ET" };
    var result = try extractText(allocator, &page, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 1), result.fragments.len);
    try std.testing.expectEqualStrings("Hello World", result.fragments[0].text);
}

test "text_extractor: paragraph detection" {
    const allocator = std.testing.allocator;
    const page = ParsedPage{ .width = 612, .height = 792, .content_data = "BT /F1 12 Tf 72 720 Td (Para one) Tj 0 -14 Td (Still para one) Tj 0 -30 Td (Para two) Tj ET" };
    var result = try extractText(allocator, &page, .{});
    defer result.deinit();
    try std.testing.expect(std.mem.indexOf(u8, result.plain_text, "\n\n") != null);
}

test "text_extractor: T* operator" {
    const allocator = std.testing.allocator;
    const page = ParsedPage{ .width = 612, .height = 792, .content_data = "BT /F1 12 Tf 14 TL 72 720 Td (First) Tj T* (Second) Tj ET" };
    var result = try extractText(allocator, &page, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 2), result.fragments.len);
    try std.testing.expect(result.fragments[1].y == 706.0);
}

test "text_extractor: defaults" {
    const opts = ExtractionOptions{};
    try std.testing.expect(opts.line_tolerance == 2.0);
    try std.testing.expect(opts.sort_by_position == true);
}
