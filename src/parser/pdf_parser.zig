const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;
const DocumentInfo = @import("../metadata/info_dict.zig").DocumentInfo;

/// A text item extracted from a PDF page.
pub const TextItem = struct {
    text: []const u8,
    x: f64,
    y: f64,
    font_name: []const u8,
    font_size: f64,
};

/// Information about a form field found in the PDF.
pub const FormFieldInfo = struct {
    name: []const u8,
    field_type: []const u8,
    value: []const u8,
};

/// A parsed PDF page with basic properties.
pub const ParsedPage = struct {
    width: f64,
    height: f64,
    content_data: []const u8,

    /// Extract text items from the page content stream.
    /// This is a simplified parser that handles basic text operators.
    pub fn extractText(self: *const ParsedPage, allocator: Allocator) ![]TextItem {
        var items: ArrayList(TextItem) = .{};
        errdefer items.deinit(allocator);

        var current_x: f64 = 0;
        var current_y: f64 = 0;
        var current_font: []const u8 = "Unknown";
        var current_size: f64 = 12;

        // Simple text extraction: look for Td, Tf, Tj, TJ operators
        var tok = Tokenizer.init(self.content_data);
        var num_stack: [8]f64 = undefined;
        var num_count: usize = 0;
        var last_name: []const u8 = "";

        while (true) {
            const token = tok.next();
            if (token == .eof) break;

            switch (token) {
                .number => {
                    if (num_count < 8) {
                        num_stack[num_count] = parseFloat(tok.getValue());
                        num_count += 1;
                    }
                },
                .name => {
                    last_name = tok.getValue();
                },
                .string => {
                    // This might be a Tj operand
                    const text = tok.getValue();
                    // Wait for the operator
                    _ = text;
                },
                .keyword => {
                    const kw = tok.getValue();
                    if (std.mem.eql(u8, kw, "Td") or std.mem.eql(u8, kw, "TD")) {
                        if (num_count >= 2) {
                            current_x += num_stack[num_count - 2];
                            current_y += num_stack[num_count - 1];
                        }
                        num_count = 0;
                    } else if (std.mem.eql(u8, kw, "Tm")) {
                        if (num_count >= 6) {
                            current_x = num_stack[num_count - 2];
                            current_y = num_stack[num_count - 1];
                        }
                        num_count = 0;
                    } else if (std.mem.eql(u8, kw, "Tf")) {
                        if (num_count >= 1) {
                            current_size = num_stack[num_count - 1];
                        }
                        current_font = last_name;
                        num_count = 0;
                    } else if (std.mem.eql(u8, kw, "Tj") or std.mem.eql(u8, kw, "'")) {
                        // Find the string that precedes this operator
                        // We need to re-scan to get the string
                        if (findPrecedingString(self.content_data, tok.getPos())) |text| {
                            try items.append(allocator, .{
                                .text = text,
                                .x = current_x,
                                .y = current_y,
                                .font_name = current_font,
                                .font_size = current_size,
                            });
                        }
                        num_count = 0;
                    } else if (std.mem.eql(u8, kw, "BT")) {
                        // Begin text object - reset position
                        num_count = 0;
                    } else if (std.mem.eql(u8, kw, "ET")) {
                        num_count = 0;
                    } else {
                        num_count = 0;
                    }
                },
                else => {},
            }
        }

        return items.toOwnedSlice(allocator);
    }
};

/// Find a string literal (xxx) that ends just before the given position.
fn findPrecedingString(data: []const u8, pos: usize) ?[]const u8 {
    // Scan backwards from pos to find ')' then find matching '('
    var p = if (pos > 0) pos - 1 else return null;

    // Skip whitespace backwards
    while (p > 0 and (data[p] == ' ' or data[p] == '\t' or data[p] == '\n' or data[p] == '\r')) {
        p -= 1;
    }

    // Skip the operator keyword backwards (e.g., "Tj")
    while (p > 0 and data[p] != ')' and data[p] != '>' and data[p] != ']') {
        p -= 1;
    }

    if (p == 0 or data[p] != ')') return null;

    // Find matching '('
    const end = p;
    var depth: u32 = 1;
    p -= 1;
    while (p > 0 and depth > 0) : (p -= 1) {
        if (data[p] == ')' and (p == 0 or data[p - 1] != '\\')) {
            depth += 1;
        } else if (data[p] == '(' and (p == 0 or data[p - 1] != '\\')) {
            depth -= 1;
            if (depth == 0) {
                return data[p + 1 .. end];
            }
        }
        if (p == 0) break;
    }

    return null;
}

fn parseFloat(s: []const u8) f64 {
    return std.fmt.parseFloat(f64, s) catch 0;
}

/// A parsed PDF document.
pub const ParsedDocument = struct {
    allocator: Allocator,
    info: ?DocumentInfo,
    pages: ArrayList(ParsedPage),
    form_fields: ?ArrayList(FormFieldInfo),
    version: []const u8,

    pub fn deinit(self: *ParsedDocument) void {
        self.pages.deinit(self.allocator);
        if (self.form_fields) |*fields| {
            fields.deinit(self.allocator);
        }
    }
};

/// Cross-reference entry.
const XrefEntry = struct {
    offset: u64,
    gen_num: u16,
    in_use: bool,
};

/// Parse a PDF document from raw bytes.
pub fn parsePdf(allocator: Allocator, data: []const u8) !ParsedDocument {
    if (data.len < 8) return error.InvalidPdf;

    // Verify PDF header
    if (!std.mem.startsWith(u8, data, "%PDF-")) {
        return error.InvalidPdf;
    }

    // Extract version
    const version_end = std.mem.indexOf(u8, data[5..], "\n") orelse
        std.mem.indexOf(u8, data[5..], "\r") orelse 3;
    const version = data[5 .. 5 + version_end];

    // Find startxref
    const xref_offset = findStartxref(data) orelse return error.InvalidPdf;

    // Parse xref table
    var xref_entries: ArrayList(XrefEntry) = .{};
    defer xref_entries.deinit(allocator);

    if (xref_offset < data.len and std.mem.startsWith(u8, data[xref_offset..], "xref")) {
        try parseXrefTable(allocator, data, xref_offset, &xref_entries);
    }

    // Parse trailer
    var info: ?DocumentInfo = null;
    if (findTrailer(data)) |trailer_pos| {
        info = parseTrailerInfo(data, trailer_pos);
    }

    // Extract pages
    var pages: ArrayList(ParsedPage) = .{};
    try extractPages(allocator, data, &xref_entries, &pages);

    // If no pages were found via xref, try a direct scan
    if (pages.items.len == 0) {
        try scanForPages(allocator, data, &pages);
    }

    return ParsedDocument{
        .allocator = allocator,
        .info = info,
        .pages = pages,
        .form_fields = null,
        .version = version,
    };
}

fn findStartxref(data: []const u8) ?usize {
    // Search backwards from the end for "startxref"
    const search_region_start = if (data.len > 1024) data.len - 1024 else 0;
    const region = data[search_region_start..];

    if (std.mem.indexOf(u8, region, "startxref")) |pos| {
        const abs_pos = search_region_start + pos + 9; // "startxref".len

        // Skip whitespace after "startxref"
        var p = abs_pos;
        while (p < data.len and (data[p] == ' ' or data[p] == '\n' or data[p] == '\r')) {
            p += 1;
        }

        // Parse the offset number
        var offset: usize = 0;
        while (p < data.len and data[p] >= '0' and data[p] <= '9') {
            offset = offset * 10 + (data[p] - '0');
            p += 1;
        }

        if (offset > 0 and offset < data.len) return offset;
    }

    return null;
}

fn parseXrefTable(allocator: Allocator, data: []const u8, offset: usize, entries: *ArrayList(XrefEntry)) !void {
    var pos = offset;

    // Skip "xref\n"
    while (pos < data.len and data[pos] != '\n' and data[pos] != '\r') {
        pos += 1;
    }
    while (pos < data.len and (data[pos] == '\n' or data[pos] == '\r')) {
        pos += 1;
    }

    // Parse subsections
    while (pos < data.len) {
        // Check for "trailer"
        if (pos + 7 <= data.len and std.mem.eql(u8, data[pos .. pos + 7], "trailer")) {
            break;
        }

        // Read subsection header: first_obj_num count
        // Skip the first object number (not needed for our simplified parsing)
        while (pos < data.len and data[pos] >= '0' and data[pos] <= '9') {
            pos += 1;
        }
        while (pos < data.len and data[pos] == ' ') pos += 1;

        var count: usize = 0;
        while (pos < data.len and data[pos] >= '0' and data[pos] <= '9') {
            count = count * 10 + (data[pos] - '0');
            pos += 1;
        }
        while (pos < data.len and (data[pos] == '\n' or data[pos] == '\r' or data[pos] == ' ')) pos += 1;

        // Read entries
        for (0..count) |_| {
            if (pos + 20 > data.len) break;

            var entry_offset: u64 = 0;
            for (0..10) |_| {
                if (pos < data.len and data[pos] >= '0' and data[pos] <= '9') {
                    entry_offset = entry_offset * 10 + (data[pos] - '0');
                }
                pos += 1;
            }
            pos += 1; // space

            var gen: u16 = 0;
            for (0..5) |_| {
                if (pos < data.len and data[pos] >= '0' and data[pos] <= '9') {
                    gen = gen * 10 + @as(u16, @intCast(data[pos] - '0'));
                }
                pos += 1;
            }
            pos += 1; // space

            const in_use = if (pos < data.len) data[pos] == 'n' else false;
            pos += 1; // f or n

            // Skip line ending
            while (pos < data.len and (data[pos] == '\n' or data[pos] == '\r' or data[pos] == ' ')) {
                pos += 1;
            }

            try entries.append(allocator, .{
                .offset = entry_offset,
                .gen_num = gen,
                .in_use = in_use,
            });
        }
    }
}

fn findTrailer(data: []const u8) ?usize {
    const search_start = if (data.len > 1024) data.len - 1024 else 0;
    if (std.mem.indexOf(u8, data[search_start..], "trailer")) |pos| {
        return search_start + pos;
    }
    return null;
}

fn parseTrailerInfo(data: []const u8, trailer_pos: usize) ?DocumentInfo {
    // Look for /Info reference in trailer dictionary
    const trailer_region = data[trailer_pos..@min(trailer_pos + 512, data.len)];

    var info = DocumentInfo{};

    // Try to extract title from metadata
    if (std.mem.indexOf(u8, trailer_region, "/Title")) |_| {
        // In a full implementation, we would follow the /Info reference
    }

    // Check if there's a /Info key at all
    if (std.mem.indexOf(u8, trailer_region, "/Info")) |_| {
        info.producer = "zpdf";
    }

    return info;
}

fn extractPages(allocator: Allocator, data: []const u8, xref_entries: *const ArrayList(XrefEntry), pages: *ArrayList(ParsedPage)) !void {
    // For each xref entry, check if it's a page object
    for (xref_entries.items) |entry| {
        if (!entry.in_use or entry.offset == 0) continue;
        if (entry.offset >= data.len) continue;

        // Check if this object contains /Type /Page
        const obj_start = @as(usize, @intCast(entry.offset));
        const obj_region_end = @min(obj_start + 4096, data.len);
        const obj_region = data[obj_start..obj_region_end];

        if (std.mem.indexOf(u8, obj_region, "/Type /Page")) |_| {
            // Check it's not /Type /Pages (with an 's')
            if (std.mem.indexOf(u8, obj_region, "/Type /Pages")) |_| continue;

            var width: f64 = 612; // default US Letter
            var height: f64 = 792;

            // Try to extract MediaBox
            if (std.mem.indexOf(u8, obj_region, "/MediaBox")) |mb_pos| {
                const mb_region = obj_region[mb_pos..];
                if (std.mem.indexOf(u8, mb_region, "[")) |arr_start| {
                    if (std.mem.indexOf(u8, mb_region[arr_start..], "]")) |arr_end| {
                        const box_str = mb_region[arr_start + 1 .. arr_start + arr_end];
                        var nums: [4]f64 = .{ 0, 0, 612, 792 };
                        var num_idx: usize = 0;
                        var tok = Tokenizer.init(box_str);
                        while (num_idx < 4) {
                            const t = tok.next();
                            if (t == .eof) break;
                            if (t == .number) {
                                nums[num_idx] = parseFloat(tok.getValue());
                                num_idx += 1;
                            }
                        }
                        width = nums[2] - nums[0];
                        height = nums[3] - nums[1];
                    }
                }
            }

            // Extract content stream data
            var content_data: []const u8 = "";
            if (std.mem.indexOf(u8, obj_region, "stream")) |stream_start| {
                var s = stream_start + 6; // "stream".len
                // Skip line ending after "stream"
                if (s < obj_region.len and obj_region[s] == '\r') s += 1;
                if (s < obj_region.len and obj_region[s] == '\n') s += 1;

                if (std.mem.indexOf(u8, obj_region[s..], "endstream")) |stream_end| {
                    content_data = obj_region[s .. s + stream_end];
                }
            }

            try pages.append(allocator, .{
                .width = width,
                .height = height,
                .content_data = content_data,
            });
        }
    }
}

fn scanForPages(allocator: Allocator, data: []const u8, pages: *ArrayList(ParsedPage)) !void {
    // Fallback: scan the entire document for /Type /Page patterns
    var pos: usize = 0;
    while (pos < data.len) {
        if (std.mem.indexOf(u8, data[pos..], "/Type /Page")) |page_pos| {
            const abs_pos = pos + page_pos;

            // Verify it's /Page and not /Pages
            if (abs_pos + 11 < data.len and data[abs_pos + 11] == 's') {
                pos = abs_pos + 12;
                continue;
            }

            var width: f64 = 612;
            var height: f64 = 792;

            // Look for MediaBox nearby
            const search_end = @min(abs_pos + 1024, data.len);
            const region = data[abs_pos..search_end];

            if (std.mem.indexOf(u8, region, "/MediaBox")) |mb_off| {
                const mb_region = region[mb_off..];
                if (std.mem.indexOf(u8, mb_region, "[")) |arr_start| {
                    if (std.mem.indexOf(u8, mb_region[arr_start..], "]")) |arr_end| {
                        const box_str = mb_region[arr_start + 1 .. arr_start + arr_end];
                        var nums: [4]f64 = .{ 0, 0, 612, 792 };
                        var num_idx: usize = 0;
                        var tok = Tokenizer.init(box_str);
                        while (num_idx < 4) {
                            const t = tok.next();
                            if (t == .eof) break;
                            if (t == .number) {
                                nums[num_idx] = parseFloat(tok.getValue());
                                num_idx += 1;
                            }
                        }
                        width = nums[2] - nums[0];
                        height = nums[3] - nums[1];
                    }
                }
            }

            try pages.append(allocator, .{
                .width = width,
                .height = height,
                .content_data = "",
            });

            pos = abs_pos + 11;
        } else {
            break;
        }
    }
}

// -- Tests --

test "parser: reject invalid pdf" {
    const allocator = std.testing.allocator;
    const result = parsePdf(allocator, "not a pdf");
    try std.testing.expectError(error.InvalidPdf, result);
}

test "parser: reject short input" {
    const allocator = std.testing.allocator;
    const result = parsePdf(allocator, "short");
    try std.testing.expectError(error.InvalidPdf, result);
}

test "parser: parse minimal pdf" {
    const allocator = std.testing.allocator;
    const pdf =
        \\%PDF-1.4
        \\1 0 obj
        \\<< /Type /Catalog /Pages 2 0 R >>
        \\endobj
        \\2 0 obj
        \\<< /Type /Pages /Kids [3 0 R] /Count 1 >>
        \\endobj
        \\3 0 obj
        \\<< /Type /Page /MediaBox [0 0 595 842] /Parent 2 0 R >>
        \\endobj
        \\xref
        \\0 4
        \\0000000000 65535 f
        \\0000000009 00000 n
        \\0000000058 00000 n
        \\0000000115 00000 n
        \\trailer
        \\<< /Size 4 /Root 1 0 R >>
        \\startxref
        \\196
        \\%%EOF
    ;

    var doc = try parsePdf(allocator, pdf);
    defer doc.deinit();

    try std.testing.expectEqualStrings("1.4", doc.version);
    try std.testing.expect(doc.pages.items.len >= 1);
}

test "parser: text item struct" {
    const item = TextItem{
        .text = "Hello",
        .x = 72,
        .y = 720,
        .font_name = "Helvetica",
        .font_size = 12,
    };
    try std.testing.expectEqualStrings("Hello", item.text);
    try std.testing.expectEqual(@as(f64, 72), item.x);
}

test "parser: form field info" {
    const field = FormFieldInfo{
        .name = "email",
        .field_type = "Tx",
        .value = "test@example.com",
    };
    try std.testing.expectEqualStrings("email", field.name);
    try std.testing.expectEqualStrings("Tx", field.field_type);
}

test "parser: parsed page extract text empty" {
    const allocator = std.testing.allocator;
    const page = ParsedPage{
        .width = 612,
        .height = 792,
        .content_data = "",
    };

    const items = try page.extractText(allocator);
    defer allocator.free(items);
    try std.testing.expectEqual(@as(usize, 0), items.len);
}
