const std = @import("std");
const Allocator = std.mem.Allocator;
const ByteBuffer = @import("../utils/buffer.zig").ByteBuffer;
const form_filler = @import("form_filler.zig");
const FieldValue = form_filler.FieldValue;
const scanFormFields = form_filler.scanFormFields;
const fillForm = form_filler.fillForm;

/// Export form field values from a PDF to FDF (Forms Data Format) bytes.
/// The caller owns the returned slice and must free it with the same allocator.
pub fn exportFdf(allocator: Allocator, pdf_data: []const u8) ![]u8 {
    const fields = try scanFormFields(allocator, pdf_data);
    defer allocator.free(fields);

    var buf = ByteBuffer.init(allocator);
    defer buf.deinit();

    try buf.write("%FDF-1.2\n1 0 obj\n<< /FDF << /Fields [\n");

    for (fields) |field| {
        if (field.name.len == 0) continue;

        const is_checkbox = std.mem.eql(u8, field.field_type, "Btn");
        try buf.write("  << /T (");
        try writeFdfEscaped(&buf, field.name);
        try buf.write(") /V ");

        if (is_checkbox and field.value.len > 0) {
            try buf.write("/");
            try buf.write(field.value);
        } else {
            try buf.write("(");
            try writeFdfEscaped(&buf, field.value);
            try buf.write(")");
        }
        try buf.write(" >>\n");
    }

    try buf.write("] >> >>\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n");

    return buf.toOwnedSlice();
}

/// Export form field values from a PDF to XFDF (XML-based FDF) bytes.
/// The caller owns the returned slice and must free it with the same allocator.
pub fn exportXfdf(allocator: Allocator, pdf_data: []const u8) ![]u8 {
    const fields = try scanFormFields(allocator, pdf_data);
    defer allocator.free(fields);

    var buf = ByteBuffer.init(allocator);
    defer buf.deinit();

    try buf.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    try buf.write("<xfdf xmlns=\"http://ns.adobe.com/xfdf/\">\n");
    try buf.write("  <fields>\n");

    for (fields) |field| {
        if (field.name.len == 0) continue;
        try buf.write("    <field name=\"");
        try writeXmlEscaped(&buf, field.name);
        try buf.write("\">\n      <value>");
        try writeXmlEscaped(&buf, field.value);
        try buf.write("</value>\n    </field>\n");
    }

    try buf.write("  </fields>\n");
    try buf.write("</xfdf>\n");

    return buf.toOwnedSlice();
}

/// Import FDF data and apply it to a PDF form, returning modified PDF bytes.
/// The caller owns the returned slice and must free it with the same allocator.
pub fn importFdf(allocator: Allocator, pdf_data: []const u8, fdf_data: []const u8) ![]u8 {
    const values = try parseFdf(allocator, fdf_data);
    defer {
        for (values) |v| {
            allocator.free(v.name);
            allocator.free(v.value);
        }
        allocator.free(values);
    }

    return fillForm(allocator, pdf_data, values);
}

/// Import XFDF data and apply it to a PDF form, returning modified PDF bytes.
/// The caller owns the returned slice and must free it with the same allocator.
pub fn importXfdf(allocator: Allocator, pdf_data: []const u8, xfdf_data: []const u8) ![]u8 {
    const values = try parseXfdf(allocator, xfdf_data);
    defer {
        for (values) |v| {
            allocator.free(v.name);
            allocator.free(v.value);
        }
        allocator.free(values);
    }

    return fillForm(allocator, pdf_data, values);
}

/// Parse FDF bytes into field name/value pairs.
/// The caller owns the returned slice and the strings within each FieldValue.
pub fn parseFdf(allocator: Allocator, fdf_data: []const u8) ![]FieldValue {
    var fields: std.ArrayListUnmanaged(FieldValue) = .{};
    errdefer {
        for (fields.items) |v| {
            allocator.free(v.name);
            allocator.free(v.value);
        }
        fields.deinit(allocator);
    }

    var pos: usize = 0;
    while (pos < fdf_data.len) {
        // Look for /T which marks a field name
        const t_pos = std.mem.indexOf(u8, fdf_data[pos..], "/T") orelse break;
        const abs_t = pos + t_pos;

        // Make sure /T is followed by a non-name character
        if (abs_t + 2 < fdf_data.len and isNameChar(fdf_data[abs_t + 2])) {
            pos = abs_t + 2;
            continue;
        }

        // Extract field name (parenthesized string after /T)
        const name = extractParenString(fdf_data, abs_t + 2) orelse {
            pos = abs_t + 2;
            continue;
        };

        // Look for /V after /T within the same field dict (before next >> or /T)
        const search_end = findFieldDictEnd(fdf_data, abs_t);
        const field_region = fdf_data[abs_t..search_end];

        const v_pos = std.mem.indexOf(u8, field_region, "/V") orelse {
            pos = abs_t + 2;
            continue;
        };
        const abs_v = abs_t + v_pos;

        // Check /V is a complete key
        if (abs_v + 2 < fdf_data.len and isNameChar(fdf_data[abs_v + 2])) {
            pos = abs_t + 2;
            continue;
        }

        // Extract value - could be a parenthesized string or a name (like /Yes)
        const value = extractFdfValue(fdf_data, abs_v + 2) orelse {
            pos = abs_t + 2;
            continue;
        };

        const name_owned = try allocator.dupe(u8, name);
        errdefer allocator.free(name_owned);
        const value_owned = try allocator.dupe(u8, value);
        errdefer allocator.free(value_owned);

        try fields.append(allocator, .{
            .name = name_owned,
            .value = value_owned,
        });

        pos = search_end;
    }

    return fields.toOwnedSlice(allocator);
}

/// Parse XFDF (XML) bytes into field name/value pairs.
/// The caller owns the returned slice and the strings within each FieldValue.
pub fn parseXfdf(allocator: Allocator, xfdf_data: []const u8) ![]FieldValue {
    var fields: std.ArrayListUnmanaged(FieldValue) = .{};
    errdefer {
        for (fields.items) |v| {
            allocator.free(v.name);
            allocator.free(v.value);
        }
        fields.deinit(allocator);
    }

    var pos: usize = 0;
    while (pos < xfdf_data.len) {
        // Look for <field name="
        const tag_start = std.mem.indexOf(u8, xfdf_data[pos..], "<field name=\"") orelse break;
        const abs_tag = pos + tag_start;
        const name_start = abs_tag + "<field name=\"".len;

        // Find closing quote for name
        const name_end = std.mem.indexOf(u8, xfdf_data[name_start..], "\"") orelse break;
        const name_raw = xfdf_data[name_start .. name_start + name_end];

        // Find the <value> tag
        const after_field = name_start + name_end;
        const value_tag = std.mem.indexOf(u8, xfdf_data[after_field..], "<value>") orelse {
            pos = after_field;
            continue;
        };
        const value_start = after_field + value_tag + "<value>".len;

        // Find </value>
        const value_end_tag = std.mem.indexOf(u8, xfdf_data[value_start..], "</value>") orelse {
            pos = value_start;
            continue;
        };
        const value_raw = xfdf_data[value_start .. value_start + value_end_tag];

        // Unescape XML entities
        const name_unescaped = try xmlUnescape(allocator, name_raw);
        errdefer allocator.free(name_unescaped);
        const value_unescaped = try xmlUnescape(allocator, value_raw);
        errdefer allocator.free(value_unescaped);

        try fields.append(allocator, .{
            .name = name_unescaped,
            .value = value_unescaped,
        });

        pos = value_start + value_end_tag + "</value>".len;
    }

    return fields.toOwnedSlice(allocator);
}

// ── Internal helpers ─────────────────────────────────────────────────

fn isNameChar(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or
        (c >= '0' and c <= '9') or c == '_' or c == '-' or c == '.';
}

/// Write a string with FDF/PDF parenthesis escaping.
fn writeFdfEscaped(buf: *ByteBuffer, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '(' => try buf.write("\\("),
            ')' => try buf.write("\\)"),
            '\\' => try buf.write("\\\\"),
            else => try buf.writeByte(c),
        }
    }
}

/// Write a string with XML entity escaping.
fn writeXmlEscaped(buf: *ByteBuffer, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '&' => try buf.write("&amp;"),
            '<' => try buf.write("&lt;"),
            '>' => try buf.write("&gt;"),
            '"' => try buf.write("&quot;"),
            '\'' => try buf.write("&apos;"),
            else => try buf.writeByte(c),
        }
    }
}

/// Unescape XML entities in a string. Caller owns the returned slice.
fn xmlUnescape(allocator: Allocator, s: []const u8) ![]u8 {
    var out = ByteBuffer.init(allocator);
    defer out.deinit();

    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '&') {
            if (std.mem.startsWith(u8, s[i..], "&amp;")) {
                try out.writeByte('&');
                i += 5;
            } else if (std.mem.startsWith(u8, s[i..], "&lt;")) {
                try out.writeByte('<');
                i += 4;
            } else if (std.mem.startsWith(u8, s[i..], "&gt;")) {
                try out.writeByte('>');
                i += 4;
            } else if (std.mem.startsWith(u8, s[i..], "&quot;")) {
                try out.writeByte('"');
                i += 6;
            } else if (std.mem.startsWith(u8, s[i..], "&apos;")) {
                try out.writeByte('\'');
                i += 6;
            } else {
                try out.writeByte(s[i]);
                i += 1;
            }
        } else {
            try out.writeByte(s[i]);
            i += 1;
        }
    }

    return out.toOwnedSlice();
}

/// Extract a parenthesized string starting at or after the given position.
fn extractParenString(data: []const u8, start: usize) ?[]const u8 {
    var i = start;
    // Skip whitespace
    while (i < data.len and (data[i] == ' ' or data[i] == '\n' or data[i] == '\r' or data[i] == '\t')) {
        i += 1;
    }
    if (i >= data.len or data[i] != '(') return null;
    i += 1;
    const str_start = i;
    var depth: u32 = 1;
    while (i < data.len and depth > 0) {
        if (data[i] == '(' and (i == 0 or data[i - 1] != '\\')) {
            depth += 1;
        } else if (data[i] == ')' and (i == 0 or data[i - 1] != '\\')) {
            depth -= 1;
            if (depth == 0) return data[str_start..i];
        }
        i += 1;
    }
    return null;
}

/// Extract an FDF value after /V - can be a parenthesized string or a /Name.
fn extractFdfValue(data: []const u8, start: usize) ?[]const u8 {
    var i = start;
    // Skip whitespace
    while (i < data.len and (data[i] == ' ' or data[i] == '\n' or data[i] == '\r' or data[i] == '\t')) {
        i += 1;
    }
    if (i >= data.len) return null;

    if (data[i] == '(') {
        return extractParenString(data, i);
    } else if (data[i] == '/') {
        // PDF name value like /Yes or /Off
        i += 1;
        const name_start = i;
        while (i < data.len and isNameChar(data[i])) {
            i += 1;
        }
        return data[name_start..i];
    }
    return null;
}

/// Find the end of a field dictionary entry (next >> after the given position).
fn findFieldDictEnd(data: []const u8, start: usize) usize {
    var i = start;
    while (i + 1 < data.len) {
        if (data[i] == '>' and data[i + 1] == '>') {
            return i + 2;
        }
        i += 1;
    }
    return data.len;
}

// ── Tests ────────────────────────────────────────────────────────────

test "writeFdfEscaped: escapes parens and backslash" {
    var buf = ByteBuffer.init(std.testing.allocator);
    defer buf.deinit();
    try writeFdfEscaped(&buf, "hello (world) \\end");
    try std.testing.expectEqualStrings("hello \\(world\\) \\\\end", buf.items());
}

test "writeXmlEscaped: escapes XML entities" {
    var buf = ByteBuffer.init(std.testing.allocator);
    defer buf.deinit();
    try writeXmlEscaped(&buf, "a < b & c > d \"e\" 'f'");
    try std.testing.expectEqualStrings("a &lt; b &amp; c &gt; d &quot;e&quot; &apos;f&apos;", buf.items());
}

test "xmlUnescape: roundtrip" {
    const allocator = std.testing.allocator;
    const result = try xmlUnescape(allocator, "a &lt; b &amp; c &gt; d &quot;e&quot; &apos;f&apos;");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("a < b & c > d \"e\" 'f'", result);
}

test "extractParenString: basic" {
    const data = "  (hello world)";
    const result = extractParenString(data, 0);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("hello world", result.?);
}

test "extractParenString: nested parens" {
    const data = "(nested (paren) test)";
    const result = extractParenString(data, 0);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("nested (paren) test", result.?);
}

test "extractFdfValue: parenthesized string" {
    const data = " (some value) >>";
    const result = extractFdfValue(data, 0);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("some value", result.?);
}

test "extractFdfValue: name value" {
    const data = " /Yes >>";
    const result = extractFdfValue(data, 0);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("Yes", result.?);
}

test "parseFdf: basic FDF" {
    const allocator = std.testing.allocator;
    const fdf_data =
        \\%FDF-1.2
        \\1 0 obj
        \\<< /FDF << /Fields [
        \\  << /T (full_name) /V (John Doe) >>
        \\  << /T (agree) /V /Yes >>
        \\] >> >>
        \\endobj
        \\trailer
        \\<< /Root 1 0 R >>
        \\%%EOF
    ;
    const fields = try parseFdf(allocator, fdf_data);
    defer {
        for (fields) |v| {
            allocator.free(v.name);
            allocator.free(v.value);
        }
        allocator.free(fields);
    }

    try std.testing.expectEqual(@as(usize, 2), fields.len);
    try std.testing.expectEqualStrings("full_name", fields[0].name);
    try std.testing.expectEqualStrings("John Doe", fields[0].value);
    try std.testing.expectEqualStrings("agree", fields[1].name);
    try std.testing.expectEqualStrings("Yes", fields[1].value);
}

test "parseXfdf: basic XFDF" {
    const allocator = std.testing.allocator;
    const xfdf_data =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<xfdf xmlns="http://ns.adobe.com/xfdf/">
        \\  <fields>
        \\    <field name="full_name">
        \\      <value>John Doe</value>
        \\    </field>
        \\    <field name="agree">
        \\      <value>Yes</value>
        \\    </field>
        \\  </fields>
        \\</xfdf>
    ;
    const fields = try parseXfdf(allocator, xfdf_data);
    defer {
        for (fields) |v| {
            allocator.free(v.name);
            allocator.free(v.value);
        }
        allocator.free(fields);
    }

    try std.testing.expectEqual(@as(usize, 2), fields.len);
    try std.testing.expectEqualStrings("full_name", fields[0].name);
    try std.testing.expectEqualStrings("John Doe", fields[0].value);
    try std.testing.expectEqualStrings("agree", fields[1].name);
    try std.testing.expectEqualStrings("Yes", fields[1].value);
}

test "parseXfdf: XML entities" {
    const allocator = std.testing.allocator;
    const xfdf_data =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<xfdf xmlns="http://ns.adobe.com/xfdf/">
        \\  <fields>
        \\    <field name="note">
        \\      <value>a &amp; b &lt; c</value>
        \\    </field>
        \\  </fields>
        \\</xfdf>
    ;
    const fields = try parseXfdf(allocator, xfdf_data);
    defer {
        for (fields) |v| {
            allocator.free(v.name);
            allocator.free(v.value);
        }
        allocator.free(fields);
    }

    try std.testing.expectEqual(@as(usize, 1), fields.len);
    try std.testing.expectEqualStrings("a & b < c", fields[0].value);
}
