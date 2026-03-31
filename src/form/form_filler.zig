const std = @import("std");
const Allocator = std.mem.Allocator;
const Color = @import("../color/color.zig").Color;
const conversion = @import("../color/conversion.zig");
const StandardFont = @import("../font/standard_fonts.zig").StandardFont;
const ByteBuffer = @import("../utils/buffer.zig").ByteBuffer;
const escapeString = @import("../writer/object_serializer.zig").escapeString;

/// A field value to fill in.
pub const FieldValue = struct {
    name: []const u8,
    value: []const u8,
};

/// Options for form flattening.
pub const FlattenOptions = struct {
    font: StandardFont = .helvetica,
    font_size: f32 = 12,
    color: Color = .{ .named = .black },
    /// Padding inside the field rectangle.
    padding: f32 = 2,
};

/// Information about a form field found during scanning.
pub const ScannedField = struct {
    name: []const u8,
    value: []const u8,
    field_type: []const u8,
    rect: [4]f32,
    /// Byte offset of the object start (N N obj) in the PDF data.
    obj_start: usize,
    /// Byte offset of the endobj for this field object.
    obj_end: usize,
    /// Object number of this field.
    obj_num: u32,
};

/// Scan a PDF byte stream for form field objects.
/// Returns a list of ScannedField describing each field found.
pub fn scanFormFields(allocator: Allocator, pdf_data: []const u8) ![]ScannedField {
    var fields: std.ArrayListUnmanaged(ScannedField) = .{};
    errdefer fields.deinit(allocator);

    var pos: usize = 0;
    while (pos < pdf_data.len) {
        // Look for the next "obj" keyword preceded by object/gen numbers
        const obj_kw = std.mem.indexOf(u8, pdf_data[pos..], " obj\n") orelse
            std.mem.indexOf(u8, pdf_data[pos..], " obj\r") orelse break;
        const abs_obj = pos + obj_kw;

        // Find the end of this object
        const endobj_kw = std.mem.indexOf(u8, pdf_data[abs_obj..], "endobj") orelse {
            pos = abs_obj + 4;
            continue;
        };
        const abs_endobj = abs_obj + endobj_kw + 6; // past "endobj"

        const obj_region = pdf_data[abs_obj..abs_endobj];

        // Check if this object contains /FT (field type) - indicates a form field
        if (std.mem.indexOf(u8, obj_region, "/FT")) |_| {
            // Extract the field name from /T
            const name = extractPdfString(obj_region, "/T") orelse "";
            const value = extractPdfString(obj_region, "/V") orelse
                extractPdfName(obj_region, "/V") orelse "";
            const field_type = extractPdfName(obj_region, "/FT") orelse "";
            const rect = extractRect(obj_region);

            // Parse the object number from before " obj"
            const obj_num = parseObjNum(pdf_data, abs_obj);

            // Find the true start (the line with "N N obj")
            const line_start = findLineStart(pdf_data, abs_obj);

            try fields.append(allocator, .{
                .name = name,
                .value = value,
                .field_type = field_type,
                .rect = rect,
                .obj_start = line_start,
                .obj_end = abs_endobj,
                .obj_num = obj_num,
            });
        }

        pos = abs_endobj;
    }

    return fields.toOwnedSlice(allocator);
}

/// Fill form fields in a PDF byte stream.
/// Takes the original PDF bytes and a list of field names/values.
/// Returns new PDF bytes with the fields filled.
pub fn fillForm(allocator: Allocator, pdf_data: []const u8, values: []const FieldValue) ![]u8 {
    if (values.len == 0) {
        const copy = try allocator.alloc(u8, pdf_data.len);
        @memcpy(copy, pdf_data);
        return copy;
    }

    // Scan for form fields
    const fields = try scanFormFields(allocator, pdf_data);
    defer allocator.free(fields);

    // Build a name -> value lookup
    var value_map = std.StringHashMap([]const u8).init(allocator);
    defer value_map.deinit();
    for (values) |v| {
        try value_map.put(v.name, v.value);
    }

    // Build modified PDF by replacing object bodies for matched fields
    var out = ByteBuffer.init(allocator);
    defer out.deinit();

    var last_end: usize = 0;

    for (fields) |field| {
        const new_value = value_map.get(field.name) orelse continue;

        // Copy everything before this object
        try out.write(pdf_data[last_end..field.obj_start]);

        // Rebuild the object with the new /V value
        const obj_body = pdf_data[field.obj_start..field.obj_end];
        try writeModifiedFieldObject(&out, allocator, obj_body, field.field_type, new_value);

        last_end = field.obj_end;
    }

    // Copy the rest
    try out.write(pdf_data[last_end..]);

    // Rewrite xref table with corrected offsets
    const result = try out.toOwnedSlice();

    // Fix the xref table in the result
    const fixed = try fixXrefTable(allocator, result);
    if (fixed.ptr != result.ptr) {
        allocator.free(result);
    }

    return fixed;
}

/// Flatten form fields - render field values as static text in the page content
/// and remove the interactive form field annotations.
/// Returns new PDF bytes with flattened content.
pub fn flattenForm(allocator: Allocator, pdf_data: []const u8, options: FlattenOptions) ![]u8 {
    // Scan for form fields
    const fields = try scanFormFields(allocator, pdf_data);
    defer allocator.free(fields);

    if (fields.len == 0) {
        const copy = try allocator.alloc(u8, pdf_data.len);
        @memcpy(copy, pdf_data);
        return copy;
    }

    var out = ByteBuffer.init(allocator);
    defer out.deinit();

    var last_end: usize = 0;

    // We need to find page content streams and append text drawing operations.
    // Also we need to remove field objects (replace with empty dicts).

    // First pass: collect fields with values and remove field objects
    var text_ops = ByteBuffer.init(allocator);
    defer text_ops.deinit();

    for (fields) |field| {
        if (field.value.len > 0 and !std.mem.eql(u8, field.value, "Off")) {
            // Generate text drawing operators for this field
            try generateTextOps(&text_ops, field, options);
        }

        // Remove this field object: replace it with a minimal empty dict
        try out.write(pdf_data[last_end..field.obj_start]);
        try out.writeFmt("{d} 0 obj\n<< >>\nendobj", .{field.obj_num});
        last_end = field.obj_end;
    }

    // Copy rest of PDF up to (but we need to inject content)
    try out.write(pdf_data[last_end..]);

    // Now we need to append the text operations into page content streams.
    // Find "stream" / "endstream" pairs inside page objects and append.
    var result = try out.toOwnedSlice();

    if (text_ops.len() > 0) {
        const with_content = try injectContentOps(allocator, result, text_ops.items());
        allocator.free(result);
        result = with_content;
    }

    // Remove /AcroForm reference from catalog
    const no_acroform = try removeAcroForm(allocator, result);
    if (no_acroform.ptr != result.ptr) {
        allocator.free(result);
        result = no_acroform;
    }

    // Fix the xref table
    const fixed = try fixXrefTable(allocator, result);
    if (fixed.ptr != result.ptr) {
        allocator.free(result);
    }

    return fixed;
}

/// Fill and flatten in one step.
pub fn fillAndFlatten(allocator: Allocator, pdf_data: []const u8, values: []const FieldValue, options: FlattenOptions) ![]u8 {
    const filled = try fillForm(allocator, pdf_data, values);
    defer allocator.free(filled);
    return flattenForm(allocator, filled, options);
}

// ── Internal helpers ────────────────────────────────────────────────

/// Find a PDF dictionary key in data, ensuring it's a complete key name
/// (the character after the key must be a delimiter, not a name character).
/// Returns the position right after the key, or null if not found.
fn findPdfKey(data: []const u8, key: []const u8) ?usize {
    var search_from: usize = 0;
    while (search_from < data.len) {
        const key_pos = std.mem.indexOf(u8, data[search_from..], key) orelse return null;
        const abs_pos = search_from + key_pos;
        const after_pos = abs_pos + key.len;
        // Check that the character after the key is a delimiter (not a name char)
        if (after_pos >= data.len or !isNameChar(data[after_pos])) {
            return after_pos;
        }
        // Not a complete key match, keep searching
        search_from = abs_pos + 1;
    }
    return null;
}

/// Extract a PDF literal string value after a key like /T or /V.
/// e.g., from "/T (full_name)" returns "full_name".
fn extractPdfString(data: []const u8, key: []const u8) ?[]const u8 {
    const after_pos = findPdfKey(data, key) orelse return null;
    const after_key = data[after_pos..];

    // Skip whitespace
    var i: usize = 0;
    while (i < after_key.len and (after_key[i] == ' ' or after_key[i] == '\n' or after_key[i] == '\r')) {
        i += 1;
    }

    if (i >= after_key.len) return null;

    if (after_key[i] == '(') {
        // Literal string
        i += 1;
        const start = i;
        var depth: u32 = 1;
        while (i < after_key.len and depth > 0) {
            if (after_key[i] == '(' and (i == 0 or after_key[i - 1] != '\\')) {
                depth += 1;
            } else if (after_key[i] == ')' and (i == 0 or after_key[i - 1] != '\\')) {
                depth -= 1;
                if (depth == 0) {
                    return after_key[start..i];
                }
            }
            i += 1;
        }
    }

    return null;
}

/// Extract a PDF name value after a key, e.g., /FT /Tx returns "Tx".
fn extractPdfName(data: []const u8, key: []const u8) ?[]const u8 {
    const after_pos = findPdfKey(data, key) orelse return null;
    const after_key = data[after_pos..];

    var i: usize = 0;
    while (i < after_key.len and (after_key[i] == ' ' or after_key[i] == '\n' or after_key[i] == '\r')) {
        i += 1;
    }

    if (i >= after_key.len) return null;

    if (after_key[i] == '/') {
        i += 1;
        const start = i;
        while (i < after_key.len and after_key[i] != ' ' and after_key[i] != '\n' and
            after_key[i] != '\r' and after_key[i] != '/' and after_key[i] != '>' and
            after_key[i] != ']')
        {
            i += 1;
        }
        return after_key[start..i];
    }

    // Could also be a literal string for /V
    if (after_key[i] == '(') {
        return extractPdfString(data, key);
    }

    return null;
}

/// Extract /Rect [x1 y1 x2 y2] values from object data.
fn extractRect(data: []const u8) [4]f32 {
    var result = [4]f32{ 0, 0, 0, 0 };
    const rect_pos = std.mem.indexOf(u8, data, "/Rect") orelse return result;
    const after = data[rect_pos + 5 ..];

    // Find the '['
    var i: usize = 0;
    while (i < after.len and after[i] != '[') : (i += 1) {}
    if (i >= after.len) return result;
    i += 1; // skip '['

    // Parse 4 numbers
    var num_idx: usize = 0;
    while (num_idx < 4 and i < after.len) {
        // skip whitespace
        while (i < after.len and (after[i] == ' ' or after[i] == '\n' or after[i] == '\r')) {
            i += 1;
        }
        if (i >= after.len or after[i] == ']') break;

        // parse number
        const start = i;
        while (i < after.len and after[i] != ' ' and after[i] != ']' and after[i] != '\n' and after[i] != '\r') {
            i += 1;
        }
        result[num_idx] = std.fmt.parseFloat(f32, after[start..i]) catch 0;
        num_idx += 1;
    }

    return result;
}

/// Parse the object number from just before " N obj" pattern.
fn parseObjNum(data: []const u8, obj_keyword_pos: usize) u32 {
    // The pattern is "N N obj" - we need to go back to find the object number
    // obj_keyword_pos points to the space before "obj"
    // We need to find "N N " before that
    const line_start = findLineStart(data, obj_keyword_pos);
    const line = data[line_start..obj_keyword_pos];

    // Parse "N N" from the line (obj_num gen_num)
    var num: u32 = 0;
    for (line) |c| {
        if (c >= '0' and c <= '9') {
            num = num * 10 + (c - '0');
        } else if (c == ' ') {
            break;
        }
    }
    return num;
}

/// Find the start of the line containing the given position.
fn findLineStart(data: []const u8, pos: usize) usize {
    var p = pos;
    while (p > 0) {
        p -= 1;
        if (data[p] == '\n' or data[p] == '\r') {
            return p + 1;
        }
    }
    return 0;
}

/// Write a modified field object with updated /V value.
fn writeModifiedFieldObject(out: *ByteBuffer, allocator: Allocator, obj_body: []const u8, field_type: []const u8, new_value: []const u8) !void {
    // Find the dict start "<<" and end ">>"
    const dict_start = std.mem.indexOf(u8, obj_body, "<<") orelse {
        try out.write(obj_body);
        return;
    };

    // Find the outermost ">>" (the one that closes the main dict)
    const dict_end = findMatchingDictEnd(obj_body, dict_start) orelse {
        try out.write(obj_body);
        return;
    };

    const is_checkbox = std.mem.eql(u8, field_type, "Btn");

    // Copy the "N N obj\n" prefix and "<<"
    try out.write(obj_body[0 .. dict_start + 2]);

    // Process dict contents: copy everything but replace /V and /AS entries
    const dict_contents = obj_body[dict_start + 2 .. dict_end];

    var wrote_v = false;
    var wrote_as = false;

    var i: usize = 0;
    while (i < dict_contents.len) {
        if (dict_contents[i] == '/' and i + 1 < dict_contents.len) {
            // Check if this is /V or /AS
            if (dict_contents[i + 1] == 'V' and (i + 2 >= dict_contents.len or !isNameChar(dict_contents[i + 2]))) {
                // Skip old /V and its value
                i = skipKeyValue(dict_contents, i);
                // Write new /V
                if (!wrote_v) {
                    try writeFieldValue(out, allocator, is_checkbox, new_value);
                    wrote_v = true;
                }
                continue;
            } else if (is_checkbox and i + 2 < dict_contents.len and
                dict_contents[i + 1] == 'A' and dict_contents[i + 2] == 'S' and
                (i + 3 >= dict_contents.len or !isNameChar(dict_contents[i + 3])))
            {
                // Skip old /AS and its value
                i = skipKeyValue(dict_contents, i);
                if (!wrote_as) {
                    try out.writeFmt(" /AS /{s}", .{new_value});
                    wrote_as = true;
                }
                continue;
            }
        }
        try out.writeByte(dict_contents[i]);
        i += 1;
    }

    // If /V wasn't in the original, insert it
    if (!wrote_v) {
        try writeFieldValue(out, allocator, is_checkbox, new_value);
    }
    if (is_checkbox and !wrote_as) {
        try out.writeFmt(" /AS /{s}", .{new_value});
    }

    // Write the closing ">>" and the rest (endobj)
    try out.write(obj_body[dict_end..]);
}

fn writeFieldValue(out: *ByteBuffer, allocator: Allocator, is_checkbox: bool, value: []const u8) !void {
    if (is_checkbox) {
        try out.writeFmt(" /V /{s}", .{value});
    } else {
        const escaped = try escapeString(allocator, value);
        defer allocator.free(escaped);
        try out.write(" /V (");
        try out.write(escaped);
        try out.write(")");
    }
}

fn isNameChar(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '_' or c == '-' or c == '.';
}

/// Skip a PDF key and its value. Returns the index past the value.
fn skipKeyValue(data: []const u8, start: usize) usize {
    // Skip the key name /Name
    var i = start + 1; // skip '/'
    while (i < data.len and isNameChar(data[i])) : (i += 1) {}

    // Skip whitespace
    while (i < data.len and (data[i] == ' ' or data[i] == '\n' or data[i] == '\r')) : (i += 1) {}

    if (i >= data.len) return i;

    // Skip the value
    return skipPdfValue(data, i);
}

/// Skip a single PDF value starting at pos. Returns the index past the value.
fn skipPdfValue(data: []const u8, pos: usize) usize {
    if (pos >= data.len) return pos;

    var i = pos;
    switch (data[i]) {
        '(' => {
            // Literal string
            i += 1;
            var depth: u32 = 1;
            while (i < data.len and depth > 0) {
                if (data[i] == '(' and (i == 0 or data[i - 1] != '\\')) {
                    depth += 1;
                } else if (data[i] == ')' and (i == 0 or data[i - 1] != '\\')) {
                    depth -= 1;
                }
                i += 1;
            }
            return i;
        },
        '<' => {
            if (i + 1 < data.len and data[i + 1] == '<') {
                // Dictionary - find matching >>
                i += 2;
                var depth: u32 = 1;
                while (i + 1 < data.len and depth > 0) {
                    if (data[i] == '<' and data[i + 1] == '<') {
                        depth += 1;
                        i += 2;
                    } else if (data[i] == '>' and data[i + 1] == '>') {
                        depth -= 1;
                        i += 2;
                    } else {
                        i += 1;
                    }
                }
                return i;
            } else {
                // Hex string
                while (i < data.len and data[i] != '>') : (i += 1) {}
                if (i < data.len) i += 1;
                return i;
            }
        },
        '[' => {
            // Array
            i += 1;
            while (i < data.len and data[i] != ']') : (i += 1) {}
            if (i < data.len) i += 1;
            return i;
        },
        '/' => {
            // Name
            i += 1;
            while (i < data.len and isNameChar(data[i])) : (i += 1) {}
            return i;
        },
        else => {
            // Number, bool, null, or reference (N N R)
            while (i < data.len and data[i] != ' ' and data[i] != '\n' and
                data[i] != '\r' and data[i] != '/' and data[i] != '>' and data[i] != ']')
            {
                i += 1;
            }
            // Check if this is a reference "N N R"
            // Skip whitespace
            var j = i;
            while (j < data.len and (data[j] == ' ' or data[j] == '\n' or data[j] == '\r')) : (j += 1) {}
            // Check if next token is a number followed by R
            if (j < data.len and data[j] >= '0' and data[j] <= '9') {
                var k = j;
                while (k < data.len and data[k] >= '0' and data[k] <= '9') : (k += 1) {}
                while (k < data.len and (data[k] == ' ' or data[k] == '\n' or data[k] == '\r')) : (k += 1) {}
                if (k < data.len and data[k] == 'R') {
                    return k + 1;
                }
            }
            return i;
        },
    }
}

/// Find the ">>" that closes the dict opening at dict_start.
fn findMatchingDictEnd(data: []const u8, dict_start: usize) ?usize {
    var i = dict_start + 2;
    var depth: u32 = 1;
    while (i + 1 < data.len and depth > 0) {
        if (data[i] == '<' and data[i + 1] == '<') {
            depth += 1;
            i += 2;
        } else if (data[i] == '>' and data[i + 1] == '>') {
            depth -= 1;
            if (depth == 0) return i;
            i += 2;
        } else if (data[i] == '(') {
            // Skip string literal to avoid false matches
            i += 1;
            var sdepth: u32 = 1;
            while (i < data.len and sdepth > 0) {
                if (data[i] == '(' and (i == 0 or data[i - 1] != '\\')) {
                    sdepth += 1;
                } else if (data[i] == ')' and (i == 0 or data[i - 1] != '\\')) {
                    sdepth -= 1;
                }
                i += 1;
            }
        } else {
            i += 1;
        }
    }
    return null;
}

/// Generate PDF text drawing operators for a flattened field.
fn generateTextOps(ops: *ByteBuffer, field: ScannedField, options: FlattenOptions) !void {
    const x = field.rect[0] + options.padding;
    const y = field.rect[1] + options.padding;
    const font_name = options.font.pdfName();

    // Determine the text to render
    const text = if (std.mem.eql(u8, field.field_type, "Btn")) blk: {
        // For checkboxes, render a checkmark if value is not "Off"
        if (std.mem.eql(u8, field.value, "Yes")) {
            break :blk "X";
        } else {
            break :blk "";
        }
    } else field.value;

    if (text.len == 0) return;

    // Get color operators
    const c = options.color.toRgb();
    const r_f: f32 = @as(f32, @floatFromInt(c.r)) / 255.0;
    const g_f: f32 = @as(f32, @floatFromInt(c.g)) / 255.0;
    const b_f: f32 = @as(f32, @floatFromInt(c.b)) / 255.0;

    try ops.writeFmt("q BT /{s} {d:.1} Tf {d:.4} {d:.4} {d:.4} rg {d:.2} {d:.2} Td ({s}) Tj ET Q\n", .{
        font_name,
        options.font_size,
        r_f,
        g_f,
        b_f,
        x,
        y,
        text,
    });
}

/// Inject content drawing operations into the first page's content stream.
fn injectContentOps(allocator: Allocator, pdf_data: []u8, ops: []const u8) ![]u8 {
    // Find the first content stream in a page object
    // Strategy: find "stream\n" ... "endstream" inside a page object and append before endstream
    var out = ByteBuffer.init(allocator);
    defer out.deinit();

    // Find a page object's content stream
    var injected = false;

    if (std.mem.indexOf(u8, pdf_data, "\nendstream")) |endstream_pos| {
        try out.write(pdf_data[0..endstream_pos]);
        try out.writeByte('\n');
        try out.write(ops);
        try out.write(pdf_data[endstream_pos..]);
        injected = true;
    }

    if (!injected) {
        // No content stream found - return a copy
        try out.write(pdf_data);
    }

    return out.toOwnedSlice();
}

/// Remove /AcroForm entry from the catalog dictionary.
fn removeAcroForm(allocator: Allocator, pdf_data: []u8) ![]u8 {
    const acroform_pos = std.mem.indexOf(u8, pdf_data, "/AcroForm") orelse {
        // No AcroForm to remove - return as-is
        const copy = try allocator.alloc(u8, pdf_data.len);
        @memcpy(copy, pdf_data);
        return copy;
    };

    var out = ByteBuffer.init(allocator);
    defer out.deinit();

    // Copy everything before /AcroForm
    try out.write(pdf_data[0..acroform_pos]);

    // Skip /AcroForm and its value
    const after = pdf_data[acroform_pos..];
    const skip = skipKeyValue(after, 0);
    // Also skip trailing whitespace
    var end = skip;
    while (end < after.len and (after[end] == ' ' or after[end] == '\n' or after[end] == '\r')) {
        end += 1;
    }

    try out.write(pdf_data[acroform_pos + end ..]);

    return out.toOwnedSlice();
}

/// Rebuild the xref table with corrected byte offsets.
/// This scans the PDF for all "N N obj" patterns and rewrites the xref table.
fn fixXrefTable(allocator: Allocator, pdf_data: []u8) ![]u8 {
    // Find the xref position
    const xref_pos = findXrefPos(pdf_data) orelse {
        // No xref table - return as-is
        const copy = try allocator.alloc(u8, pdf_data.len);
        @memcpy(copy, pdf_data);
        return copy;
    };

    // Scan all objects to build new xref entries
    const ObjInfo = struct { num: u32, gen: u16, offset: u64 };
    var objects: std.ArrayListUnmanaged(ObjInfo) = .{};
    defer objects.deinit(allocator);

    var pos: usize = 0;
    while (pos < xref_pos) {
        const obj_kw = std.mem.indexOf(u8, pdf_data[pos..], " obj\n") orelse
            std.mem.indexOf(u8, pdf_data[pos..], " obj\r") orelse break;
        const abs_pos = pos + obj_kw;

        // Parse "N N" before " obj"
        const line_start = findLineStart(pdf_data, abs_pos);
        const prefix = pdf_data[line_start..abs_pos];

        // Parse obj_num and gen_num from "N N"
        var obj_num: u32 = 0;
        var gen_num: u16 = 0;
        var saw_space = false;
        for (prefix) |c| {
            if (c >= '0' and c <= '9') {
                if (!saw_space) {
                    obj_num = obj_num * 10 + (c - '0');
                } else {
                    gen_num = gen_num * 10 + @as(u16, @intCast(c - '0'));
                }
            } else if (c == ' ') {
                saw_space = true;
            }
        }

        try objects.append(allocator, .{
            .num = obj_num,
            .gen = gen_num,
            .offset = @intCast(line_start),
        });

        pos = abs_pos + 4;
    }

    if (objects.items.len == 0) {
        const copy = try allocator.alloc(u8, pdf_data.len);
        @memcpy(copy, pdf_data);
        return copy;
    }

    // Find the max object number
    var max_obj: u32 = 0;
    for (objects.items) |obj| {
        if (obj.num > max_obj) max_obj = obj.num;
    }

    // Build the output: everything before xref + new xref + trailer + startxref
    var out = ByteBuffer.init(allocator);
    defer out.deinit();

    // Copy everything before the xref table
    try out.write(pdf_data[0..xref_pos]);

    // Write new xref table
    const new_xref_offset = out.len();
    try out.write("xref\n");
    try out.writeFmt("0 {d}\n", .{max_obj + 1});

    // Entry 0: free head
    try out.write("0000000000 65535 f \n");

    // Write entries for objects 1..max_obj
    for (1..max_obj + 1) |num| {
        var found = false;
        for (objects.items) |obj| {
            if (obj.num == @as(u32, @intCast(num))) {
                try out.writeFmt("{d:0>10} {d:0>5} n \n", .{ obj.offset, obj.gen });
                found = true;
                break;
            }
        }
        if (!found) {
            try out.write("0000000000 00000 f \n");
        }
    }

    // Find and copy trailer
    const trailer_pos = std.mem.indexOf(u8, pdf_data[xref_pos..], "trailer") orelse {
        const copy = try allocator.alloc(u8, pdf_data.len);
        @memcpy(copy, pdf_data);
        return copy;
    };
    const abs_trailer = xref_pos + trailer_pos;

    // Find startxref
    const startxref_pos = std.mem.indexOf(u8, pdf_data[abs_trailer..], "startxref") orelse {
        const copy = try allocator.alloc(u8, pdf_data.len);
        @memcpy(copy, pdf_data);
        return copy;
    };
    const abs_startxref = abs_trailer + startxref_pos;

    // Copy trailer dict (from "trailer" to just before "startxref")
    try out.write(pdf_data[abs_trailer..abs_startxref]);

    // Write new startxref
    try out.writeFmt("startxref\n{d}\n%%EOF\n", .{new_xref_offset});

    return out.toOwnedSlice();
}

/// Find the position of "xref" keyword near the end of the PDF.
fn findXrefPos(data: []const u8) ?usize {
    // Search for last occurrence of "xref\n"
    var pos: usize = 0;
    var last_xref: ?usize = null;
    while (pos < data.len) {
        const found = std.mem.indexOf(u8, data[pos..], "xref\n") orelse
            std.mem.indexOf(u8, data[pos..], "xref\r") orelse break;
        last_xref = pos + found;
        pos = pos + found + 5;
    }
    return last_xref;
}

// ── Tests ───────────────────────────────────────────────────────────

test "extractPdfString: basic" {
    const data = "/T (full_name) /V (John)";
    const name = extractPdfString(data, "/T");
    try std.testing.expect(name != null);
    try std.testing.expectEqualStrings("full_name", name.?);

    const val = extractPdfString(data, "/V");
    try std.testing.expect(val != null);
    try std.testing.expectEqualStrings("John", val.?);
}

test "extractPdfName: basic" {
    const data = "/FT /Tx /V (test)";
    const ft = extractPdfName(data, "/FT");
    try std.testing.expect(ft != null);
    try std.testing.expectEqualStrings("Tx", ft.?);
}

test "extractRect: basic" {
    const data = "/Rect [10 20 110 50]";
    const rect = extractRect(data);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), rect[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), rect[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 110.0), rect[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), rect[3], 0.001);
}

test "skipPdfValue: string" {
    const data = "(hello world) /Next";
    const end = skipPdfValue(data, 0);
    try std.testing.expectEqualStrings(" /Next", data[end..]);
}

test "skipPdfValue: name" {
    const data = "/Yes /Next";
    const end = skipPdfValue(data, 0);
    try std.testing.expectEqualStrings(" /Next", data[end..]);
}

test "skipPdfValue: array" {
    const data = "[1 2 3 4] /Next";
    const end = skipPdfValue(data, 0);
    try std.testing.expectEqualStrings(" /Next", data[end..]);
}

test "isNameChar" {
    try std.testing.expect(isNameChar('A'));
    try std.testing.expect(isNameChar('z'));
    try std.testing.expect(isNameChar('0'));
    try std.testing.expect(!isNameChar(' '));
    try std.testing.expect(!isNameChar('/'));
    try std.testing.expect(!isNameChar('>'));
}

test "findMatchingDictEnd" {
    const data = "<< /Key /Value >>";
    const end = findMatchingDictEnd(data, 0);
    try std.testing.expect(end != null);
    try std.testing.expectEqual(@as(usize, 15), end.?);
}

test "findMatchingDictEnd: nested" {
    const data = "<< /Inner << /A /B >> /C /D >>";
    const end = findMatchingDictEnd(data, 0);
    try std.testing.expect(end != null);
    try std.testing.expectEqual(@as(usize, 28), end.?);
}
