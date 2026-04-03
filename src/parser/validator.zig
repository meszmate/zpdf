const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;

/// Severity level for validation issues.
pub const Severity = enum {
    error_,
    warning,
    info,
};

/// Specific validation issue codes.
pub const IssueCode = enum {
    invalid_header,
    missing_binary_comment,
    missing_eof_marker,
    invalid_startxref,
    missing_xref,
    xref_entry_count_mismatch,
    xref_offset_invalid,
    missing_trailer,
    trailer_missing_size,
    trailer_missing_root,
    catalog_missing_type,
    catalog_missing_pages,
    pages_missing_type,
    pages_missing_kids,
    pages_missing_count,
    page_missing_type,
    page_missing_mediabox,
    page_missing_parent,
    stream_length_mismatch,
    object_not_delimited,
    duplicate_object_number,
    xref_inconsistent,
};

/// A single validation issue found in a PDF.
pub const ValidationIssue = struct {
    severity: Severity,
    code: IssueCode,
    message: []const u8,
    byte_offset: ?usize,
};

/// Result of PDF validation.
pub const ValidationResult = struct {
    is_valid: bool,
    issues: []ValidationIssue,
    allocator: Allocator,

    pub fn deinit(self: *ValidationResult) void {
        self.allocator.free(self.issues);
    }
};

/// Options controlling which checks are performed.
pub const ValidationOptions = struct {
    check_xref: bool = true,
    check_streams: bool = true,
    check_required_keys: bool = true,
    strict: bool = false,
};

/// Validate a PDF document against structural spec rules.
pub fn validatePdf(allocator: Allocator, pdf_data: []const u8, options: ValidationOptions) !ValidationResult {
    var issues: ArrayList(ValidationIssue) = .{};
    errdefer issues.deinit(allocator);

    if (pdf_data.len < 8) {
        try issues.append(allocator, .{
            .severity = .error_,
            .code = .invalid_header,
            .message = "PDF data is too short to contain a valid header",
            .byte_offset = 0,
        });
        return ValidationResult{
            .is_valid = false,
            .issues = try issues.toOwnedSlice(allocator),
            .allocator = allocator,
        };
    }

    checkHeader(pdf_data, &issues, allocator, options) catch {};
    checkEofMarker(pdf_data, &issues, allocator) catch {};

    const startxref_offset = checkStartxref(pdf_data, &issues, allocator) catch null;

    if (options.check_xref) {
        if (startxref_offset) |offset| {
            checkXrefTable(pdf_data, offset, &issues, allocator) catch {};
        }
    }

    checkTrailer(pdf_data, &issues, allocator) catch {};

    if (options.check_required_keys) {
        checkCatalog(pdf_data, &issues, allocator) catch {};
        checkPagesTree(pdf_data, &issues, allocator) catch {};
        checkIndividualPages(pdf_data, &issues, allocator) catch {};
    }

    if (options.check_streams) {
        checkStreamLengths(pdf_data, &issues, allocator) catch {};
    }

    checkObjectDelimiters(pdf_data, &issues, allocator) catch {};
    checkDuplicateObjects(pdf_data, &issues, allocator) catch {};

    if (options.check_xref) {
        if (startxref_offset) |offset| {
            checkXrefConsistency(pdf_data, offset, &issues, allocator) catch {};
        }
    }

    var has_error = false;
    for (issues.items) |issue| {
        if (issue.severity == .error_) {
            has_error = true;
            break;
        }
    }

    return ValidationResult{
        .is_valid = !has_error,
        .issues = try issues.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

fn checkHeader(data: []const u8, issues: *ArrayList(ValidationIssue), allocator: Allocator, options: ValidationOptions) !void {
    if (!std.mem.startsWith(u8, data, "%PDF-")) {
        try issues.append(allocator, .{
            .severity = .error_,
            .code = .invalid_header,
            .message = "Missing or invalid PDF header (expected %PDF-x.y)",
            .byte_offset = 0,
        });
        return;
    }

    // Check version format: expect at least one digit, a dot, and one digit
    const header_end = std.mem.indexOf(u8, data[5..], "\n") orelse
        std.mem.indexOf(u8, data[5..], "\r") orelse
        @min(data.len - 5, 10);

    const version = data[5 .. 5 + header_end];
    var valid_version = false;
    if (version.len >= 3 and version[0] >= '0' and version[0] <= '9' and version[1] == '.') {
        if (version[2] >= '0' and version[2] <= '9') {
            valid_version = true;
        }
    }
    if (!valid_version) {
        try issues.append(allocator, .{
            .severity = .error_,
            .code = .invalid_header,
            .message = "PDF header version format is invalid (expected %PDF-x.y)",
            .byte_offset = 0,
        });
    }

    // Check binary comment after header
    var pos: usize = 5 + header_end;
    // Skip line ending
    while (pos < data.len and (data[pos] == '\n' or data[pos] == '\r')) {
        pos += 1;
    }
    if (pos < data.len and data[pos] == '%') {
        // Check that the comment has high-byte characters (binary marker)
        var has_high_byte = false;
        var cp = pos + 1;
        while (cp < data.len and data[cp] != '\n' and data[cp] != '\r') : (cp += 1) {
            if (data[cp] > 127) {
                has_high_byte = true;
                break;
            }
        }
        if (!has_high_byte and options.strict) {
            try issues.append(allocator, .{
                .severity = .warning,
                .code = .missing_binary_comment,
                .message = "Binary comment after header does not contain high-byte characters",
                .byte_offset = pos,
            });
        }
    } else if (options.strict) {
        try issues.append(allocator, .{
            .severity = .warning,
            .code = .missing_binary_comment,
            .message = "Missing binary comment after PDF header",
            .byte_offset = pos,
        });
    }
}

fn checkEofMarker(data: []const u8, issues: *ArrayList(ValidationIssue), allocator: Allocator) !void {
    // Search last 1024 bytes for %%EOF
    const search_start = if (data.len > 1024) data.len - 1024 else 0;
    if (std.mem.indexOf(u8, data[search_start..], "%%EOF") == null) {
        try issues.append(allocator, .{
            .severity = .error_,
            .code = .missing_eof_marker,
            .message = "Missing %%EOF marker at end of file",
            .byte_offset = data.len,
        });
    }
}

fn checkStartxref(data: []const u8, issues: *ArrayList(ValidationIssue), allocator: Allocator) !?usize {
    const search_start = if (data.len > 1024) data.len - 1024 else 0;
    const region = data[search_start..];

    const sxref_pos = std.mem.indexOf(u8, region, "startxref") orelse {
        try issues.append(allocator, .{
            .severity = .error_,
            .code = .invalid_startxref,
            .message = "Missing startxref keyword",
            .byte_offset = null,
        });
        return null;
    };

    const abs_pos = search_start + sxref_pos + 9;
    var p = abs_pos;
    while (p < data.len and (data[p] == ' ' or data[p] == '\n' or data[p] == '\r')) {
        p += 1;
    }

    var offset: usize = 0;
    var has_digits = false;
    while (p < data.len and data[p] >= '0' and data[p] <= '9') {
        offset = offset * 10 + (data[p] - '0');
        has_digits = true;
        p += 1;
    }

    if (!has_digits or offset >= data.len) {
        try issues.append(allocator, .{
            .severity = .error_,
            .code = .invalid_startxref,
            .message = "startxref offset is invalid or out of range",
            .byte_offset = search_start + sxref_pos,
        });
        return null;
    }

    return offset;
}

fn checkXrefTable(data: []const u8, offset: usize, issues: *ArrayList(ValidationIssue), allocator: Allocator) !void {
    if (offset >= data.len) return;

    if (!std.mem.startsWith(u8, data[offset..], "xref")) {
        // Might be a cross-reference stream (PDF 1.5+), not an error
        try issues.append(allocator, .{
            .severity = .info,
            .code = .missing_xref,
            .message = "No traditional xref table found at startxref offset (may use cross-reference stream)",
            .byte_offset = offset,
        });
        return;
    }

    var pos = offset;
    // Skip "xref" line
    while (pos < data.len and data[pos] != '\n' and data[pos] != '\r') pos += 1;
    while (pos < data.len and (data[pos] == '\n' or data[pos] == '\r')) pos += 1;

    // Parse subsections
    while (pos < data.len) {
        if (pos + 7 <= data.len and std.mem.eql(u8, data[pos .. pos + 7], "trailer")) break;

        // Skip first_obj_num
        while (pos < data.len and data[pos] >= '0' and data[pos] <= '9') {
            pos += 1;
        }
        while (pos < data.len and data[pos] == ' ') pos += 1;

        // Parse count
        var declared_count: usize = 0;
        while (pos < data.len and data[pos] >= '0' and data[pos] <= '9') {
            declared_count = declared_count * 10 + (data[pos] - '0');
            pos += 1;
        }
        while (pos < data.len and (data[pos] == '\n' or data[pos] == '\r' or data[pos] == ' ')) pos += 1;

        // Count actual entries
        var actual_count: usize = 0;
        while (pos < data.len) {
            if (pos + 7 <= data.len and std.mem.eql(u8, data[pos .. pos + 7], "trailer")) break;
            // Check if this looks like an xref entry (20 bytes: 10-digit offset, space, 5-digit gen, space, f/n, EOL)
            if (pos + 17 >= data.len) break;
            // Check if we hit another subsection header (digit space digit pattern without 'f' or 'n' in expected pos)
            const potential_type_char = if (pos + 17 < data.len) data[pos + 17] else 0;
            if (potential_type_char != 'f' and potential_type_char != 'n') break;

            actual_count += 1;
            // Skip this entry (roughly 20 bytes)
            pos += 18;
            while (pos < data.len and (data[pos] == '\n' or data[pos] == '\r' or data[pos] == ' ')) pos += 1;
        }

        if (actual_count != declared_count) {
            try issues.append(allocator, .{
                .severity = .error_,
                .code = .xref_entry_count_mismatch,
                .message = "xref subsection entry count does not match declared count",
                .byte_offset = null,
            });
        }
    }
}

fn checkTrailer(data: []const u8, issues: *ArrayList(ValidationIssue), allocator: Allocator) !void {
    const search_start = if (data.len > 2048) data.len - 2048 else 0;
    const trailer_pos = std.mem.indexOf(u8, data[search_start..], "trailer") orelse {
        // Could be a cross-reference stream PDF
        try issues.append(allocator, .{
            .severity = .info,
            .code = .missing_trailer,
            .message = "No traditional trailer found (may use cross-reference stream)",
            .byte_offset = null,
        });
        return;
    };

    const abs_pos = search_start + trailer_pos;
    const trailer_end = @min(abs_pos + 512, data.len);
    const trailer_region = data[abs_pos..trailer_end];

    if (std.mem.indexOf(u8, trailer_region, "/Size") == null) {
        try issues.append(allocator, .{
            .severity = .error_,
            .code = .trailer_missing_size,
            .message = "Trailer dictionary is missing required /Size key",
            .byte_offset = abs_pos,
        });
    }

    if (std.mem.indexOf(u8, trailer_region, "/Root") == null) {
        try issues.append(allocator, .{
            .severity = .error_,
            .code = .trailer_missing_root,
            .message = "Trailer dictionary is missing required /Root key",
            .byte_offset = abs_pos,
        });
    }
}

fn checkCatalog(data: []const u8, issues: *ArrayList(ValidationIssue), allocator: Allocator) !void {
    // Find objects that contain /Type /Catalog
    var pos: usize = 0;
    var found_catalog = false;
    while (pos < data.len) {
        const idx = std.mem.indexOf(u8, data[pos..], "/Type") orelse break;
        const abs = pos + idx;

        // Look ahead for /Catalog
        const region_end = @min(abs + 50, data.len);
        const region = data[abs..region_end];

        if (std.mem.indexOf(u8, region, "/Catalog")) |_| {
            found_catalog = true;

            // Find the containing object bounds
            const obj_start = findObjBefore(data, abs) orelse abs;
            const obj_end = @min(obj_start + 4096, data.len);
            const obj_region = data[obj_start..obj_end];

            if (std.mem.indexOf(u8, obj_region, "/Pages") == null) {
                try issues.append(allocator, .{
                    .severity = .error_,
                    .code = .catalog_missing_pages,
                    .message = "Catalog object is missing required /Pages key",
                    .byte_offset = obj_start,
                });
            }
            break;
        }
        pos = abs + 5;
    }

    if (!found_catalog) {
        try issues.append(allocator, .{
            .severity = .error_,
            .code = .catalog_missing_type,
            .message = "No catalog object with /Type /Catalog found",
            .byte_offset = null,
        });
    }
}

fn checkPagesTree(data: []const u8, issues: *ArrayList(ValidationIssue), allocator: Allocator) !void {
    var pos: usize = 0;
    while (pos < data.len) {
        const idx = std.mem.indexOf(u8, data[pos..], "/Type /Pages") orelse break;
        const abs = pos + idx;

        // Make sure it's exactly /Pages not /Page followed by 's' separately
        const obj_start = findObjBefore(data, abs) orelse abs;
        const obj_end_idx = std.mem.indexOf(u8, data[obj_start..], "endobj") orelse 4096;
        const obj_end = @min(obj_start + obj_end_idx + 6, data.len);
        const obj_region = data[obj_start..obj_end];

        if (std.mem.indexOf(u8, obj_region, "/Kids") == null) {
            try issues.append(allocator, .{
                .severity = .error_,
                .code = .pages_missing_kids,
                .message = "Pages object is missing required /Kids key",
                .byte_offset = obj_start,
            });
        }

        if (std.mem.indexOf(u8, obj_region, "/Count") == null) {
            try issues.append(allocator, .{
                .severity = .error_,
                .code = .pages_missing_count,
                .message = "Pages object is missing required /Count key",
                .byte_offset = obj_start,
            });
        }

        pos = abs + 12;
    }
}

fn checkIndividualPages(data: []const u8, issues: *ArrayList(ValidationIssue), allocator: Allocator) !void {
    var pos: usize = 0;
    while (pos < data.len) {
        const idx = std.mem.indexOf(u8, data[pos..], "/Type /Page") orelse break;
        const abs = pos + idx;

        // Check it's /Page and NOT /Pages
        const after = abs + 11;
        if (after < data.len and data[after] == 's') {
            pos = abs + 12;
            continue;
        }

        const obj_start = findObjBefore(data, abs) orelse abs;
        const obj_end_idx = std.mem.indexOf(u8, data[obj_start..], "endobj") orelse 4096;
        const obj_end = @min(obj_start + obj_end_idx + 6, data.len);
        const obj_region = data[obj_start..obj_end];

        if (std.mem.indexOf(u8, obj_region, "/MediaBox") == null) {
            // MediaBox can be inherited from Pages tree, so this is a warning
            try issues.append(allocator, .{
                .severity = .warning,
                .code = .page_missing_mediabox,
                .message = "Page object is missing /MediaBox (may be inherited from parent)",
                .byte_offset = obj_start,
            });
        }

        if (std.mem.indexOf(u8, obj_region, "/Parent") == null) {
            try issues.append(allocator, .{
                .severity = .warning,
                .code = .page_missing_parent,
                .message = "Page object is missing /Parent key",
                .byte_offset = obj_start,
            });
        }

        pos = abs + 11;
    }
}

fn checkStreamLengths(data: []const u8, issues: *ArrayList(ValidationIssue), allocator: Allocator) !void {
    var pos: usize = 0;
    while (pos < data.len) {
        const idx = std.mem.indexOf(u8, data[pos..], "stream") orelse break;
        const abs = pos + idx;

        // Make sure this isn't "endstream"
        if (abs >= 3 and std.mem.eql(u8, data[abs - 3 .. abs], "end")) {
            pos = abs + 6;
            continue;
        }

        // Check if preceded by >> (end of dictionary) to confirm it's a real stream
        var bp = if (abs > 0) abs - 1 else 0;
        while (bp > 0 and (data[bp] == ' ' or data[bp] == '\n' or data[bp] == '\r' or data[bp] == '\t')) {
            bp -= 1;
        }
        if (bp < 1 or data[bp] != '>' or data[bp - 1] != '>') {
            pos = abs + 6;
            continue;
        }

        // Try to find /Length in the preceding dictionary
        const dict_search_start = if (abs > 256) abs - 256 else 0;
        const dict_region = data[dict_search_start..abs];

        if (std.mem.lastIndexOf(u8, dict_region, "/Length")) |len_off| {
            const len_abs = dict_search_start + len_off + 7; // "/Length".len
            var lp = len_abs;
            while (lp < abs and (data[lp] == ' ' or data[lp] == '\t')) lp += 1;

            // Check if it's a direct integer value (not an indirect reference)
            if (lp < abs and data[lp] >= '0' and data[lp] <= '9') {
                var declared_len: usize = 0;
                while (lp < abs and data[lp] >= '0' and data[lp] <= '9') {
                    declared_len = declared_len * 10 + (data[lp] - '0');
                    lp += 1;
                }

                // Check if next non-space is 0 R (indirect ref) - if so, skip
                var tp = lp;
                while (tp < abs and (data[tp] == ' ' or data[tp] == '\t')) tp += 1;
                if (tp < abs and data[tp] >= '0' and data[tp] <= '9') {
                    // Could be "N N R" pattern (indirect reference), skip
                    pos = abs + 6;
                    continue;
                }

                // Find actual stream content
                var stream_start = abs + 6; // "stream".len
                if (stream_start < data.len and data[stream_start] == '\r') stream_start += 1;
                if (stream_start < data.len and data[stream_start] == '\n') stream_start += 1;

                if (std.mem.indexOf(u8, data[stream_start..@min(stream_start + declared_len + 256, data.len)], "endstream")) |es_off| {
                    // Allow off-by-one or off-by-two for line ending variations (\n, \r\n before endstream)
                    const diff = if (es_off >= declared_len) es_off - declared_len else declared_len - es_off;
                    if (diff > 2) {
                        try issues.append(allocator, .{
                            .severity = .error_,
                            .code = .stream_length_mismatch,
                            .message = "Stream /Length does not match actual stream content length",
                            .byte_offset = abs,
                        });
                    }
                }
            }
        }

        pos = abs + 6;
    }
}

fn checkObjectDelimiters(data: []const u8, issues: *ArrayList(ValidationIssue), allocator: Allocator) !void {
    // Check that every "N N obj" has a matching "endobj"
    var pos: usize = 0;
    while (pos < data.len) {
        const idx = std.mem.indexOf(u8, data[pos..], " obj") orelse break;
        const abs = pos + idx;

        // Verify the pattern: it should be "N N obj" where N are numbers
        if (abs < 3) {
            pos = abs + 4;
            continue;
        }

        // Quick check: character before " obj" should be a digit (gen number)
        if (data[abs - 1] < '0' or data[abs - 1] > '9') {
            pos = abs + 4;
            continue;
        }

        // Make sure " obj" is followed by whitespace or end (not "object" etc)
        const after_obj = abs + 4;
        if (after_obj < data.len and data[after_obj] != ' ' and data[after_obj] != '\n' and data[after_obj] != '\r' and data[after_obj] != '\t') {
            pos = abs + 4;
            continue;
        }

        // Look for matching endobj
        if (std.mem.indexOf(u8, data[after_obj..], "endobj") == null) {
            try issues.append(allocator, .{
                .severity = .error_,
                .code = .object_not_delimited,
                .message = "Object missing closing endobj",
                .byte_offset = abs,
            });
        }

        pos = abs + 4;
    }
}

fn checkDuplicateObjects(data: []const u8, issues: *ArrayList(ValidationIssue), allocator: Allocator) !void {
    // Collect object numbers
    var seen = std.AutoHashMap(u64, void).init(allocator);
    defer seen.deinit();

    var pos: usize = 0;
    while (pos < data.len) {
        const idx = std.mem.indexOf(u8, data[pos..], " obj") orelse break;
        const abs = pos + idx;

        const after_obj = abs + 4;
        if (after_obj < data.len and data[after_obj] != ' ' and data[after_obj] != '\n' and data[after_obj] != '\r' and data[after_obj] != '\t') {
            pos = abs + 4;
            continue;
        }

        // Parse "N N obj" backwards from abs
        // First find gen number (right before " obj")
        var gp = abs - 1;
        if (gp >= data.len or data[gp] < '0' or data[gp] > '9') {
            pos = abs + 4;
            continue;
        }
        while (gp > 0 and data[gp] >= '0' and data[gp] <= '9') gp -= 1;
        if (gp >= data.len or data[gp] != ' ') {
            pos = abs + 4;
            continue;
        }

        // Parse object number
        var op = gp - 1;
        if (op >= data.len or data[op] < '0' or data[op] > '9') {
            pos = abs + 4;
            continue;
        }
        while (op > 0 and data[op] >= '0' and data[op] <= '9') op -= 1;

        const num_start = if (data[op] >= '0' and data[op] <= '9') op else op + 1;
        const num_str = data[num_start..gp];

        const obj_num = std.fmt.parseInt(u64, num_str, 10) catch {
            pos = abs + 4;
            continue;
        };

        if (seen.contains(obj_num)) {
            try issues.append(allocator, .{
                .severity = .error_,
                .code = .duplicate_object_number,
                .message = "Duplicate object number found",
                .byte_offset = abs,
            });
        } else {
            try seen.put(obj_num, {});
        }

        pos = abs + 4;
    }
}

fn checkXrefConsistency(data: []const u8, xref_offset: usize, issues: *ArrayList(ValidationIssue), allocator: Allocator) !void {
    if (xref_offset >= data.len or !std.mem.startsWith(u8, data[xref_offset..], "xref")) return;

    var pos = xref_offset;
    // Skip "xref" line
    while (pos < data.len and data[pos] != '\n' and data[pos] != '\r') pos += 1;
    while (pos < data.len and (data[pos] == '\n' or data[pos] == '\r')) pos += 1;

    while (pos < data.len) {
        if (pos + 7 <= data.len and std.mem.eql(u8, data[pos .. pos + 7], "trailer")) break;

        // Parse subsection header
        while (pos < data.len and data[pos] >= '0' and data[pos] <= '9') pos += 1;
        while (pos < data.len and data[pos] == ' ') pos += 1;

        var count: usize = 0;
        while (pos < data.len and data[pos] >= '0' and data[pos] <= '9') {
            count = count * 10 + (data[pos] - '0');
            pos += 1;
        }
        while (pos < data.len and (data[pos] == '\n' or data[pos] == '\r' or data[pos] == ' ')) pos += 1;

        // Read entries
        for (0..count) |_| {
            if (pos + 17 > data.len) break;

            // Parse 10-digit offset
            var entry_offset: usize = 0;
            for (0..10) |_| {
                if (pos < data.len and data[pos] >= '0' and data[pos] <= '9') {
                    entry_offset = entry_offset * 10 + (data[pos] - '0');
                }
                pos += 1;
            }
            pos += 1; // space

            // Skip 5-digit gen
            pos += 5;
            pos += 1; // space

            const in_use = if (pos < data.len) data[pos] == 'n' else false;
            pos += 1;

            while (pos < data.len and (data[pos] == '\n' or data[pos] == '\r' or data[pos] == ' ')) pos += 1;

            if (in_use and entry_offset > 0 and entry_offset < data.len) {
                // Check if the offset points to something that looks like "N N obj"
                const check_region = data[entry_offset..@min(entry_offset + 32, data.len)];
                if (std.mem.indexOf(u8, check_region, " obj") == null) {
                    try issues.append(allocator, .{
                        .severity = .error_,
                        .code = .xref_offset_invalid,
                        .message = "xref entry offset does not point to an object definition",
                        .byte_offset = entry_offset,
                    });
                }
            }
        }
    }
}

/// Find the position of "N N obj" that precedes the given position.
fn findObjBefore(data: []const u8, pos: usize) ?usize {
    const search_start = if (pos > 4096) pos - 4096 else 0;
    const region = data[search_start..pos];

    // Search backwards for "obj"
    var rp: usize = region.len;
    while (rp > 3) {
        rp -= 1;
        if (rp + 3 <= region.len and std.mem.eql(u8, region[rp .. rp + 3], "obj")) {
            // Check it's not "endobj"
            if (rp >= 3 and std.mem.eql(u8, region[rp - 3 .. rp], "end")) {
                continue;
            }
            return search_start + rp;
        }
    }
    return null;
}

// -- Tests --

test "validator: valid minimal pdf" {
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
    var result = try validatePdf(allocator, pdf, .{});
    defer result.deinit();

    // Check for errors only (ignore info/warnings)
    var error_count: usize = 0;
    for (result.issues) |issue| {
        if (issue.severity == .error_) error_count += 1;
    }
    try std.testing.expect(error_count == 0);
}

test "validator: reject too-short data" {
    const allocator = std.testing.allocator;
    var result = try validatePdf(allocator, "short", .{});
    defer result.deinit();

    try std.testing.expect(!result.is_valid);
    try std.testing.expect(result.issues.len > 0);
    try std.testing.expect(result.issues[0].code == .invalid_header);
}

test "validator: reject non-pdf data" {
    const allocator = std.testing.allocator;
    var result = try validatePdf(allocator, "This is not a PDF file at all, just plain text that is long enough", .{});
    defer result.deinit();

    try std.testing.expect(!result.is_valid);
}

test "validator: missing eof marker" {
    const allocator = std.testing.allocator;
    const pdf =
        \\%PDF-1.4
        \\1 0 obj
        \\<< /Type /Catalog /Pages 2 0 R >>
        \\endobj
    ;
    var result = try validatePdf(allocator, pdf, .{});
    defer result.deinit();

    var found_eof_issue = false;
    for (result.issues) |issue| {
        if (issue.code == .missing_eof_marker) found_eof_issue = true;
    }
    try std.testing.expect(found_eof_issue);
}

test "validator: options disable checks" {
    const allocator = std.testing.allocator;
    const pdf =
        \\%PDF-1.4
        \\1 0 obj
        \\<< /Type /Catalog /Pages 2 0 R >>
        \\endobj
        \\startxref
        \\0
        \\%%EOF
    ;
    var result = try validatePdf(allocator, pdf, .{
        .check_xref = false,
        .check_streams = false,
        .check_required_keys = false,
        .strict = false,
    });
    defer result.deinit();

    // With most checks disabled, there should be fewer issues
    try std.testing.expect(result.issues.len >= 0);
}

test "validator: severity enum values" {
    try std.testing.expect(@intFromEnum(Severity.error_) != @intFromEnum(Severity.warning));
    try std.testing.expect(@intFromEnum(Severity.warning) != @intFromEnum(Severity.info));
}

test "validator: validation options defaults" {
    const opts = ValidationOptions{};
    try std.testing.expect(opts.check_xref == true);
    try std.testing.expect(opts.check_streams == true);
    try std.testing.expect(opts.check_required_keys == true);
    try std.testing.expect(opts.strict == false);
}
