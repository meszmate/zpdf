const std = @import("std");
const Allocator = std.mem.Allocator;

/// Signature appearance options.
pub const SignatureAppearance = struct {
    /// Page index to place the visible signature on (null for invisible)
    page: ?usize = null,
    /// Rectangle for visible signature [x1, y1, x2, y2]
    rect: ?[4]f32 = null,
    /// Name displayed in signature
    name: ?[]const u8 = null,
    /// Reason for signing
    reason: ?[]const u8 = null,
    /// Location of signing
    location: ?[]const u8 = null,
    /// Contact info
    contact_info: ?[]const u8 = null,
};

/// Options for creating a digital signature.
pub const SignatureOptions = struct {
    appearance: SignatureAppearance = .{},
    /// Estimated signature size in bytes (for the hex placeholder)
    signature_size: u32 = 8192,
};

/// The result of preparing a document for signing.
pub const PreparedSignature = struct {
    /// The PDF bytes with placeholder for signature
    pdf_bytes: []u8,
    /// ByteRange: [offset1, length1, offset2, length2]
    byte_range: [4]u64,
    /// Offset where the hex signature value should be inserted
    signature_offset: u64,
    /// Maximum size of the hex signature string
    signature_max_length: u32,
    allocator: Allocator,

    pub fn deinit(self: *PreparedSignature) void {
        self.allocator.free(self.pdf_bytes);
    }

    /// Get the bytes that need to be signed (the two ByteRange segments).
    pub fn getSignedBytes(self: *const PreparedSignature) [2][]const u8 {
        const r = self.byte_range;
        return .{
            self.pdf_bytes[r[0] .. r[0] + r[1]],
            self.pdf_bytes[r[2] .. r[2] + r[3]],
        };
    }
};

/// External signing callback type.
/// Takes the data to sign and returns the DER-encoded signature.
pub const SignCallback = *const fn (data_to_sign: []const u8, context: ?*anyopaque) []const u8;

/// Result of verifying signature structure in a PDF.
pub const SignatureVerification = struct {
    has_signature: bool,
    byte_range_valid: bool,
    signer_name: ?[]const u8,
    reason: ?[]const u8,
    sign_date: ?[]const u8,
};

// ── Hex encoding helper ─────────────────────────────────────────────

const hex_chars = "0123456789abcdef";

fn hexEncode(out: []u8, data: []const u8) void {
    for (data, 0..) |b, i| {
        out[i * 2] = hex_chars[b >> 4];
        out[i * 2 + 1] = hex_chars[b & 0x0F];
    }
}

// ── Formatting helpers ──────────────────────────────────────────────

fn appendSlice(list: *std.ArrayListUnmanaged(u8), allocator: Allocator, data: []const u8) !void {
    try list.appendSlice(allocator, data);
}

fn formatInt(buf: *[20]u8, value: u64) []const u8 {
    var v = value;
    var pos: usize = buf.len;
    if (v == 0) {
        pos -= 1;
        buf[pos] = '0';
        return buf[pos..];
    }
    while (v > 0) {
        pos -= 1;
        buf[pos] = @truncate((v % 10) + '0');
        v /= 10;
    }
    return buf[pos..];
}

// ── Prepare for signing ─────────────────────────────────────────────

/// Prepare a PDF document for signing by inserting the signature dictionary
/// with a placeholder for the actual signature value.
///
/// This creates an incremental update appended to the original PDF,
/// containing a signature dictionary with a ByteRange and a hex-encoded
/// Contents placeholder. After signing, use `applySignature` to fill in
/// the actual signature.
pub fn prepareForSigning(
    allocator: Allocator,
    pdf_data: []const u8,
    options: SignatureOptions,
) !PreparedSignature {
    if (pdf_data.len < 20) return error.InvalidPdf;

    // Find the last xref offset from the original PDF (look for "startxref")
    const startxref_pos = findLastOccurrence(pdf_data, "startxref") orelse
        return error.InvalidPdf;

    // Parse the old startxref value
    var xref_scan = startxref_pos + 9; // len("startxref")
    while (xref_scan < pdf_data.len and (pdf_data[xref_scan] == ' ' or pdf_data[xref_scan] == '\n' or pdf_data[xref_scan] == '\r')) {
        xref_scan += 1;
    }
    var old_startxref: u64 = 0;
    while (xref_scan < pdf_data.len and pdf_data[xref_scan] >= '0' and pdf_data[xref_scan] <= '9') {
        old_startxref = old_startxref * 10 + (pdf_data[xref_scan] - '0');
        xref_scan += 1;
    }

    // Find the highest object number by scanning for "N 0 obj"
    var max_obj_num: u64 = 0;
    {
        var i: usize = 0;
        while (i + 5 < pdf_data.len) : (i += 1) {
            if (pdf_data[i] == ' ' and pdf_data[i + 1] == '0' and pdf_data[i + 2] == ' ' and
                pdf_data[i + 3] == 'o' and pdf_data[i + 4] == 'b' and pdf_data[i + 5] == 'j')
            {
                // Walk back to get the number
                var j = i;
                while (j > 0 and pdf_data[j - 1] >= '0' and pdf_data[j - 1] <= '9') {
                    j -= 1;
                }
                var num: u64 = 0;
                for (pdf_data[j..i]) |c| {
                    if (c >= '0' and c <= '9') {
                        num = num * 10 + (c - '0');
                    }
                }
                if (num > max_obj_num) max_obj_num = num;
            }
        }
    }

    // Find the catalog reference (look for "/Type /Catalog")
    const catalog_ref = findCatalogRef(pdf_data);

    // Find a page reference for the annotation
    const page_ref = findFirstPageRef(pdf_data);

    const sig_obj_num = max_obj_num + 1;
    const field_obj_num = max_obj_num + 2;

    // Hex placeholder size: each byte becomes 2 hex chars, plus < and >
    const hex_placeholder_len: u32 = options.signature_size * 2;

    // Build the incremental update
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(allocator);

    // Start after the original PDF
    try appendSlice(&buf, allocator, pdf_data);

    // Ensure we end with a newline
    if (pdf_data.len > 0 and pdf_data[pdf_data.len - 1] != '\n') {
        try buf.append(allocator, '\n');
    }

    // Record offsets for xref
    const sig_obj_offset = buf.items.len;

    // -- Signature dictionary object --
    var int_buf: [20]u8 = undefined;
    try appendSlice(&buf, allocator, formatInt(&int_buf, sig_obj_num));
    try appendSlice(&buf, allocator, " 0 obj\n");
    try appendSlice(&buf, allocator, "<< /Type /Sig\n");
    try appendSlice(&buf, allocator, "   /Filter /Adobe.PPKLite\n");
    try appendSlice(&buf, allocator, "   /SubFilter /adbe.pkcs7.detached\n");

    // ByteRange placeholder - will be updated later
    // We use a fixed-width placeholder so we can overwrite in place.
    // Format: /ByteRange [0000000000 0000000000 0000000000 0000000000]
    try appendSlice(&buf, allocator, "   /ByteRange [0000000000 0000000000 0000000000 0000000000]\n");

    // Contents hex placeholder
    try appendSlice(&buf, allocator, "   /Contents <");
    const contents_hex_offset = buf.items.len;
    // Fill with zeros
    try buf.appendNTimes(allocator, '0', hex_placeholder_len);
    try appendSlice(&buf, allocator, ">\n");

    // Signing time
    try appendSlice(&buf, allocator, "   /M (D:20260101120000+00'00')\n");

    // Optional fields
    if (options.appearance.name) |name| {
        try appendSlice(&buf, allocator, "   /Name (");
        try appendSlice(&buf, allocator, name);
        try appendSlice(&buf, allocator, ")\n");
    }
    if (options.appearance.reason) |reason| {
        try appendSlice(&buf, allocator, "   /Reason (");
        try appendSlice(&buf, allocator, reason);
        try appendSlice(&buf, allocator, ")\n");
    }
    if (options.appearance.location) |location| {
        try appendSlice(&buf, allocator, "   /Location (");
        try appendSlice(&buf, allocator, location);
        try appendSlice(&buf, allocator, ")\n");
    }
    if (options.appearance.contact_info) |contact| {
        try appendSlice(&buf, allocator, "   /ContactInfo (");
        try appendSlice(&buf, allocator, contact);
        try appendSlice(&buf, allocator, ")\n");
    }

    try appendSlice(&buf, allocator, ">>\nendobj\n\n");

    // -- Signature field (widget annotation) --
    const field_obj_offset = buf.items.len;
    try appendSlice(&buf, allocator, formatInt(&int_buf, field_obj_num));
    try appendSlice(&buf, allocator, " 0 obj\n");
    try appendSlice(&buf, allocator, "<< /Type /Annot\n");
    try appendSlice(&buf, allocator, "   /Subtype /Widget\n");
    try appendSlice(&buf, allocator, "   /FT /Sig\n");
    try appendSlice(&buf, allocator, "   /T (Signature1)\n");
    try appendSlice(&buf, allocator, "   /V ");
    try appendSlice(&buf, allocator, formatInt(&int_buf, sig_obj_num));
    try appendSlice(&buf, allocator, " 0 R\n");

    // Rect
    if (options.appearance.rect) |rect| {
        try appendSlice(&buf, allocator, "   /Rect [");
        var rect_buf: [64]u8 = undefined;
        const rect_str = std.fmt.bufPrint(&rect_buf, "{d} {d} {d} {d}", .{ rect[0], rect[1], rect[2], rect[3] }) catch "0 0 0 0";
        try appendSlice(&buf, allocator, rect_str);
        try appendSlice(&buf, allocator, "]\n");
    } else {
        try appendSlice(&buf, allocator, "   /Rect [0 0 0 0]\n");
    }

    // Page reference
    if (page_ref) |pr| {
        try appendSlice(&buf, allocator, "   /P ");
        try appendSlice(&buf, allocator, formatInt(&int_buf, pr));
        try appendSlice(&buf, allocator, " 0 R\n");
    }

    try appendSlice(&buf, allocator, ">>\nendobj\n\n");

    // -- Cross-reference table --
    const xref_offset = buf.items.len;
    try appendSlice(&buf, allocator, "xref\n");
    try appendSlice(&buf, allocator, formatInt(&int_buf, sig_obj_num));
    try appendSlice(&buf, allocator, " 2\n");

    // Format offset as 10-digit zero-padded
    var offset_buf: [11]u8 = undefined;
    formatOffset(&offset_buf, sig_obj_offset);
    try appendSlice(&buf, allocator, offset_buf[0..10]);
    try appendSlice(&buf, allocator, " 00000 n \n");

    formatOffset(&offset_buf, field_obj_offset);
    try appendSlice(&buf, allocator, offset_buf[0..10]);
    try appendSlice(&buf, allocator, " 00000 n \n");

    // -- Trailer --
    try appendSlice(&buf, allocator, "trailer\n");
    try appendSlice(&buf, allocator, "<< /Size ");
    try appendSlice(&buf, allocator, formatInt(&int_buf, field_obj_num + 1));
    try appendSlice(&buf, allocator, "\n");
    try appendSlice(&buf, allocator, "   /Prev ");
    try appendSlice(&buf, allocator, formatInt(&int_buf, old_startxref));
    try appendSlice(&buf, allocator, "\n");

    if (catalog_ref) |cr| {
        try appendSlice(&buf, allocator, "   /Root ");
        try appendSlice(&buf, allocator, formatInt(&int_buf, cr));
        try appendSlice(&buf, allocator, " 0 R\n");
    }

    try appendSlice(&buf, allocator, ">>\n");
    try appendSlice(&buf, allocator, "startxref\n");
    try appendSlice(&buf, allocator, formatInt(&int_buf, xref_offset));
    try appendSlice(&buf, allocator, "\n%%EOF\n");

    // Now compute the ByteRange
    // contents_hex_offset points to the first '0' after '<'
    // The '<' is at contents_hex_offset - 1
    // The '>' is at contents_hex_offset + hex_placeholder_len
    const contents_start = contents_hex_offset - 1; // position of '<'
    const contents_end = contents_hex_offset + hex_placeholder_len + 1; // position after '>'

    const byte_range = [4]u64{
        0,
        contents_start,
        contents_end,
        buf.items.len - contents_end,
    };

    // Write the ByteRange values back into the buffer
    // Find the ByteRange placeholder in our buffer
    if (findLastOccurrence(buf.items, "/ByteRange [")) |br_pos| {
        const values_start = br_pos + 12; // after "/ByteRange ["
        // Write the four 10-digit values
        var br_write_buf: [44]u8 = undefined;
        const br_str = std.fmt.bufPrint(&br_write_buf, "{d:0>10} {d:0>10} {d:0>10} {d:0>10}", .{
            byte_range[0],
            byte_range[1],
            byte_range[2],
            byte_range[3],
        }) catch unreachable;
        @memcpy(buf.items[values_start .. values_start + br_str.len], br_str);
    }

    const result = try buf.toOwnedSlice(allocator);
    return PreparedSignature{
        .pdf_bytes = result,
        .byte_range = byte_range,
        .signature_offset = contents_hex_offset,
        .signature_max_length = hex_placeholder_len,
        .allocator = allocator,
    };
}

/// Apply a DER-encoded PKCS#7 signature to a prepared PDF.
/// This writes the hex-encoded signature into the Contents placeholder.
pub fn applySignature(
    prepared: *PreparedSignature,
    signature_der: []const u8,
) !void {
    const hex_len = signature_der.len * 2;
    if (hex_len > prepared.signature_max_length) {
        return error.SignatureTooLarge;
    }

    const offset = prepared.signature_offset;

    // Hex-encode the signature
    hexEncode(prepared.pdf_bytes[offset .. offset + hex_len], signature_der);

    // The rest stays as '0' padding (already set)
}

/// Verify the structural validity of a signature in a PDF.
/// This checks that a signature dictionary exists and that ByteRange
/// covers the entire file except the Contents value.
pub fn verifySignatureStructure(
    pdf_data: []const u8,
) !SignatureVerification {
    var result = SignatureVerification{
        .has_signature = false,
        .byte_range_valid = false,
        .signer_name = null,
        .reason = null,
        .sign_date = null,
    };

    // Look for /Type /Sig
    const sig_pos = findLastOccurrence(pdf_data, "/Type /Sig") orelse return result;
    _ = sig_pos;
    result.has_signature = true;

    // Extract ByteRange
    if (findLastOccurrence(pdf_data, "/ByteRange [")) |br_pos| {
        const values_start = br_pos + 12;
        // Parse 4 integers
        var byte_range: [4]u64 = .{ 0, 0, 0, 0 };
        var idx: usize = 0;
        var pos = values_start;
        while (idx < 4 and pos < pdf_data.len and pdf_data[pos] != ']') {
            // Skip whitespace
            while (pos < pdf_data.len and (pdf_data[pos] == ' ' or pdf_data[pos] == '\n' or pdf_data[pos] == '\r')) {
                pos += 1;
            }
            if (pos >= pdf_data.len or pdf_data[pos] == ']') break;
            var num: u64 = 0;
            while (pos < pdf_data.len and pdf_data[pos] >= '0' and pdf_data[pos] <= '9') {
                num = num * 10 + (pdf_data[pos] - '0');
                pos += 1;
            }
            byte_range[idx] = num;
            idx += 1;
        }

        if (idx == 4) {
            // Validate: first segment starts at 0, segments cover everything except Contents
            const total_covered = byte_range[1] + byte_range[3];
            const gap = byte_range[2] - byte_range[1];
            result.byte_range_valid = (byte_range[0] == 0) and
                (byte_range[2] > byte_range[1]) and
                (byte_range[1] + gap + byte_range[3] == pdf_data.len) and
                (total_covered + gap == pdf_data.len);
        }
    }

    // Try to extract /Name
    if (findLastOccurrence(pdf_data, "/Name (")) |name_pos| {
        const start = name_pos + 7;
        if (findInRange(pdf_data, start, ')')) |end| {
            result.signer_name = pdf_data[start..end];
        }
    }

    // Try to extract /Reason
    if (findLastOccurrence(pdf_data, "/Reason (")) |reason_pos| {
        const start = reason_pos + 9;
        if (findInRange(pdf_data, start, ')')) |end| {
            result.reason = pdf_data[start..end];
        }
    }

    // Try to extract /M (signing date)
    if (findLastOccurrence(pdf_data, "/M (")) |m_pos| {
        const start = m_pos + 4;
        if (findInRange(pdf_data, start, ')')) |end| {
            result.sign_date = pdf_data[start..end];
        }
    }

    return result;
}

// ── Internal helpers ────────────────────────────────────────────────

fn findLastOccurrence(data: []const u8, needle: []const u8) ?usize {
    if (needle.len > data.len) return null;
    var i: usize = data.len - needle.len;
    while (true) {
        if (std.mem.eql(u8, data[i .. i + needle.len], needle)) return i;
        if (i == 0) break;
        i -= 1;
    }
    return null;
}

fn findInRange(data: []const u8, start: usize, char: u8) ?usize {
    var pos = start;
    while (pos < data.len) : (pos += 1) {
        if (data[pos] == char) return pos;
    }
    return null;
}

fn findCatalogRef(data: []const u8) ?u64 {
    // Look for "/Type /Catalog" and walk backward to find the object number
    const marker = "/Type /Catalog";
    var pos: usize = 0;
    while (pos + marker.len <= data.len) : (pos += 1) {
        if (std.mem.eql(u8, data[pos .. pos + marker.len], marker)) {
            // Walk backward to find "N 0 obj"
            var j = pos;
            while (j > 0) : (j -= 1) {
                if (j + 5 < data.len and
                    data[j] == ' ' and data[j + 1] == '0' and data[j + 2] == ' ' and
                    data[j + 3] == 'o' and data[j + 4] == 'b' and data[j + 5] == 'j')
                {
                    // Get the number before the space
                    var k = j;
                    while (k > 0 and data[k - 1] >= '0' and data[k - 1] <= '9') {
                        k -= 1;
                    }
                    var num: u64 = 0;
                    for (data[k..j]) |c| {
                        if (c >= '0' and c <= '9') {
                            num = num * 10 + (c - '0');
                        }
                    }
                    return num;
                }
            }
            break;
        }
    }
    return null;
}

fn findFirstPageRef(data: []const u8) ?u64 {
    // Look for "/Type /Page" (not /Pages)
    const marker = "/Type /Page";
    var pos: usize = 0;
    while (pos + marker.len <= data.len) : (pos += 1) {
        if (std.mem.eql(u8, data[pos .. pos + marker.len], marker)) {
            // Make sure it's not /Pages
            if (pos + marker.len < data.len and data[pos + marker.len] == 's') {
                continue;
            }
            // Walk backward to find "N 0 obj"
            var j = pos;
            while (j > 0) : (j -= 1) {
                if (j + 5 < data.len and
                    data[j] == ' ' and data[j + 1] == '0' and data[j + 2] == ' ' and
                    data[j + 3] == 'o' and data[j + 4] == 'b' and data[j + 5] == 'j')
                {
                    var k = j;
                    while (k > 0 and data[k - 1] >= '0' and data[k - 1] <= '9') {
                        k -= 1;
                    }
                    var num: u64 = 0;
                    for (data[k..j]) |c| {
                        if (c >= '0' and c <= '9') {
                            num = num * 10 + (c - '0');
                        }
                    }
                    return num;
                }
            }
            break;
        }
    }
    return null;
}

fn formatOffset(buf: *[11]u8, value: usize) void {
    var v = value;
    var i: usize = 10;
    while (i > 0) {
        i -= 1;
        buf[i] = @truncate((v % 10) + '0');
        v /= 10;
    }
    buf[10] = 0; // null terminator (unused but safe)
}

// ── Tests ───────────────────────────────────────────────────────────

test "findLastOccurrence: basic" {
    const data = "hello world hello";
    try std.testing.expectEqual(@as(?usize, 12), findLastOccurrence(data, "hello"));
    try std.testing.expectEqual(@as(?usize, null), findLastOccurrence(data, "xyz"));
}

test "formatOffset: zero" {
    var buf: [11]u8 = undefined;
    formatOffset(&buf, 0);
    try std.testing.expectEqualSlices(u8, "0000000000", buf[0..10]);
}

test "formatOffset: value" {
    var buf: [11]u8 = undefined;
    formatOffset(&buf, 12345);
    try std.testing.expectEqualSlices(u8, "0000012345", buf[0..10]);
}

test "hexEncode: basic" {
    var out: [6]u8 = undefined;
    hexEncode(&out, &[_]u8{ 0xDE, 0xAD, 0xBE });
    try std.testing.expectEqualSlices(u8, "deadbe", &out);
}

test "prepareForSigning: minimal pdf" {
    const allocator = std.testing.allocator;

    // A minimal valid-ish PDF
    const minimal_pdf =
        \\%PDF-1.4
        \\1 0 obj
        \\<< /Type /Catalog /Pages 2 0 R >>
        \\endobj
        \\2 0 obj
        \\<< /Type /Pages /Kids [3 0 R] /Count 1 >>
        \\endobj
        \\3 0 obj
        \\<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>
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
        \\192
        \\%%EOF
    ;

    var prepared = try prepareForSigning(allocator, minimal_pdf, .{
        .appearance = .{
            .name = "Test Signer",
            .reason = "Testing",
        },
        .signature_size = 256,
    });
    defer prepared.deinit();

    // Verify byte range structure
    try std.testing.expectEqual(@as(u64, 0), prepared.byte_range[0]);
    try std.testing.expect(prepared.byte_range[1] > 0);
    try std.testing.expect(prepared.byte_range[2] > prepared.byte_range[1]);

    // ByteRange should cover entire file except Contents value
    const gap = prepared.byte_range[2] - prepared.byte_range[1];
    const total = prepared.byte_range[1] + gap + prepared.byte_range[3];
    try std.testing.expectEqual(prepared.pdf_bytes.len, total);

    // Verify the signed bytes are accessible
    const signed = prepared.getSignedBytes();
    try std.testing.expectEqual(prepared.byte_range[1], signed[0].len);
    try std.testing.expectEqual(prepared.byte_range[3], signed[1].len);
}

test "applySignature: writes hex" {
    const allocator = std.testing.allocator;

    const minimal_pdf =
        \\%PDF-1.4
        \\1 0 obj
        \\<< /Type /Catalog /Pages 2 0 R >>
        \\endobj
        \\2 0 obj
        \\<< /Type /Pages /Kids [3 0 R] /Count 1 >>
        \\endobj
        \\3 0 obj
        \\<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>
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
        \\192
        \\%%EOF
    ;

    var prepared = try prepareForSigning(allocator, minimal_pdf, .{
        .signature_size = 256,
    });
    defer prepared.deinit();

    // Apply a fake signature
    const fake_sig = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    try applySignature(&prepared, &fake_sig);

    // Check the hex was written
    const offset = prepared.signature_offset;
    try std.testing.expectEqualSlices(u8, "deadbeef", prepared.pdf_bytes[offset .. offset + 8]);
}

test "verifySignatureStructure: detects signature" {
    const allocator = std.testing.allocator;

    const minimal_pdf =
        \\%PDF-1.4
        \\1 0 obj
        \\<< /Type /Catalog /Pages 2 0 R >>
        \\endobj
        \\2 0 obj
        \\<< /Type /Pages /Kids [3 0 R] /Count 1 >>
        \\endobj
        \\3 0 obj
        \\<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>
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
        \\192
        \\%%EOF
    ;

    var prepared = try prepareForSigning(allocator, minimal_pdf, .{
        .appearance = .{
            .name = "Alice",
            .reason = "Approval",
        },
        .signature_size = 256,
    });
    defer prepared.deinit();

    const verification = try verifySignatureStructure(prepared.pdf_bytes);
    try std.testing.expect(verification.has_signature);
    try std.testing.expect(verification.byte_range_valid);
    try std.testing.expectEqualSlices(u8, "Alice", verification.signer_name.?);
    try std.testing.expectEqualSlices(u8, "Approval", verification.reason.?);
    try std.testing.expect(verification.sign_date != null);
}

test "verifySignatureStructure: no signature" {
    const plain_pdf =
        \\%PDF-1.4
        \\1 0 obj
        \\<< /Type /Catalog >>
        \\endobj
        \\xref
        \\0 1
        \\0000000000 65535 f
        \\trailer
        \\<< /Size 2 >>
        \\startxref
        \\0
        \\%%EOF
    ;
    const verification = try verifySignatureStructure(plain_pdf);
    try std.testing.expect(!verification.has_signature);
    try std.testing.expect(!verification.byte_range_valid);
}
