const std = @import("std");
const Allocator = std.mem.Allocator;

pub const EncodingError = error{
    InvalidUtf8,
    InvalidUtf16,
    Unmappable,
};

/// PDFDocEncoding table: maps byte values 0x80..0x9F to Unicode codepoints.
/// Values outside this range map 1:1 with Unicode (same as Latin-1 for 0xA0..0xFF).
const pdf_doc_encoding_extra = [32]u21{
    0x2022, // 0x80 BULLET
    0x2020, // 0x81 DAGGER
    0x2021, // 0x82 DOUBLE DAGGER
    0x2026, // 0x83 HORIZONTAL ELLIPSIS
    0x2014, // 0x84 EM DASH
    0x2013, // 0x85 EN DASH
    0x0192, // 0x86 LATIN SMALL LETTER F WITH HOOK
    0x2044, // 0x87 FRACTION SLASH
    0x2039, // 0x88 SINGLE LEFT-POINTING ANGLE QUOTATION MARK
    0x203A, // 0x89 SINGLE RIGHT-POINTING ANGLE QUOTATION MARK
    0x2212, // 0x8A MINUS SIGN
    0x2030, // 0x8B PER MILLE SIGN
    0x201E, // 0x8C DOUBLE LOW-9 QUOTATION MARK
    0x201C, // 0x8D LEFT DOUBLE QUOTATION MARK
    0x201D, // 0x8E RIGHT DOUBLE QUOTATION MARK
    0x2018, // 0x8F LEFT SINGLE QUOTATION MARK
    0x2019, // 0x90 RIGHT SINGLE QUOTATION MARK
    0x201A, // 0x91 SINGLE LOW-9 QUOTATION MARK
    0x2122, // 0x92 TRADE MARK SIGN
    0xFB01, // 0x93 LATIN SMALL LIGATURE FI
    0xFB02, // 0x94 LATIN SMALL LIGATURE FL
    0x0141, // 0x95 LATIN CAPITAL LETTER L WITH STROKE
    0x0152, // 0x96 LATIN CAPITAL LIGATURE OE
    0x0160, // 0x97 LATIN CAPITAL LETTER S WITH CARON
    0x0178, // 0x98 LATIN CAPITAL LETTER Y WITH DIAERESIS
    0x017D, // 0x99 LATIN CAPITAL LETTER Z WITH CARON
    0x0131, // 0x9A LATIN SMALL LETTER DOTLESS I
    0x0142, // 0x9B LATIN SMALL LETTER L WITH STROKE
    0x0153, // 0x9C LATIN SMALL LIGATURE OE
    0x0161, // 0x9D LATIN SMALL LETTER S WITH CARON
    0x017E, // 0x9E LATIN SMALL LETTER Z WITH CARON
    0xFFFD, // 0x9F UNDEFINED -> REPLACEMENT CHARACTER
};

/// Convert Latin-1 encoded data to UTF-8.
pub fn latin1ToUtf8(allocator: Allocator, data: []const u8) Allocator.Error![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(allocator);

    for (data) |byte| {
        if (byte < 0x80) {
            try result.append(allocator, byte);
        } else {
            const codepoint: u21 = byte;
            var buf: [4]u8 = undefined;
            const utf8_len = std.unicode.utf8Encode(codepoint, &buf) catch unreachable;
            try result.appendSlice(allocator, buf[0..utf8_len]);
        }
    }

    return try result.toOwnedSlice(allocator);
}

/// Convert UTF-8 encoded data to Latin-1. Returns error for unmappable characters.
pub fn utf8ToLatin1(allocator: Allocator, data: []const u8) (Allocator.Error || EncodingError)![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(allocator);

    var view = std.unicode.Utf8View.initUnchecked(data);
    var iter = view.iterator();

    while (iter.nextCodepoint()) |cp| {
        if (cp <= 0xFF) {
            try result.append(allocator, @intCast(cp));
        } else {
            return EncodingError.Unmappable;
        }
    }

    return try result.toOwnedSlice(allocator);
}

/// Encode a UTF-8 string as UTF-16BE with BOM (0xFEFF prefix).
pub fn utf16beEncode(allocator: Allocator, text: []const u8) (Allocator.Error || EncodingError)![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(allocator);

    // Write BOM
    try result.appendSlice(allocator, &[_]u8{ 0xFE, 0xFF });

    var view = std.unicode.Utf8View.initUnchecked(text);
    var iter = view.iterator();

    while (iter.nextCodepoint()) |cp| {
        if (cp < 0x10000) {
            const val: u16 = @intCast(cp);
            try result.appendSlice(allocator, &std.mem.toBytes(std.mem.nativeToBig(u16, val)));
        } else {
            const adjusted = cp - 0x10000;
            const high: u16 = @intCast(0xD800 + (adjusted >> 10));
            const low: u16 = @intCast(0xDC00 + (adjusted & 0x3FF));
            try result.appendSlice(allocator, &std.mem.toBytes(std.mem.nativeToBig(u16, high)));
            try result.appendSlice(allocator, &std.mem.toBytes(std.mem.nativeToBig(u16, low)));
        }
    }

    return try result.toOwnedSlice(allocator);
}

/// Decode UTF-16BE data (with or without BOM) to UTF-8.
pub fn utf16beDecode(allocator: Allocator, data: []const u8) (Allocator.Error || EncodingError)![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(allocator);

    if (data.len % 2 != 0) return EncodingError.InvalidUtf16;

    var offset: usize = 0;

    // Skip BOM if present
    if (data.len >= 2 and data[0] == 0xFE and data[1] == 0xFF) {
        offset = 2;
    }

    while (offset + 1 < data.len) {
        const unit: u16 = @as(u16, data[offset]) << 8 | data[offset + 1];
        offset += 2;

        var codepoint: u21 = undefined;

        if (unit >= 0xD800 and unit <= 0xDBFF) {
            if (offset + 1 >= data.len) return EncodingError.InvalidUtf16;
            const low: u16 = @as(u16, data[offset]) << 8 | data[offset + 1];
            offset += 2;
            if (low < 0xDC00 or low > 0xDFFF) return EncodingError.InvalidUtf16;
            codepoint = @as(u21, unit - 0xD800) << 10 | @as(u21, low - 0xDC00);
            codepoint += 0x10000;
        } else if (unit >= 0xDC00 and unit <= 0xDFFF) {
            return EncodingError.InvalidUtf16;
        } else {
            codepoint = unit;
        }

        var buf: [4]u8 = undefined;
        const utf8_len = std.unicode.utf8Encode(codepoint, &buf) catch return EncodingError.InvalidUtf16;
        try result.appendSlice(allocator, buf[0..utf8_len]);
    }

    return try result.toOwnedSlice(allocator);
}

/// Convert PDFDocEncoding data to UTF-8.
/// PDFDocEncoding is similar to Latin-1 but differs in the 0x80..0x9F range.
pub fn pdfDocEncodingToUtf8(allocator: Allocator, data: []const u8) Allocator.Error![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(allocator);

    for (data) |byte| {
        const codepoint: u21 = if (byte >= 0x80 and byte <= 0x9F)
            pdf_doc_encoding_extra[byte - 0x80]
        else
            byte;

        if (codepoint < 0x80) {
            try result.append(allocator, @intCast(codepoint));
        } else {
            var buf: [4]u8 = undefined;
            const utf8_len = std.unicode.utf8Encode(codepoint, &buf) catch unreachable;
            try result.appendSlice(allocator, buf[0..utf8_len]);
        }
    }

    return try result.toOwnedSlice(allocator);
}

test "latin1ToUtf8: ASCII passthrough" {
    const result = try latin1ToUtf8(std.testing.allocator, "Hello");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualSlices(u8, "Hello", result);
}

test "latin1ToUtf8: high bytes" {
    const input = &[_]u8{ 0x48, 0xE9, 0x6C, 0x6C, 0x6F };
    const result = try latin1ToUtf8(std.testing.allocator, input);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualSlices(u8, "H\xc3\xa9llo", result);
}

test "utf8ToLatin1: roundtrip" {
    const original = &[_]u8{ 0x48, 0xE9, 0x6C, 0x6C, 0x6F };
    const utf8 = try latin1ToUtf8(std.testing.allocator, original);
    defer std.testing.allocator.free(utf8);
    const back = try utf8ToLatin1(std.testing.allocator, utf8);
    defer std.testing.allocator.free(back);
    try std.testing.expectEqualSlices(u8, original, back);
}

test "utf8ToLatin1: unmappable" {
    const result = utf8ToLatin1(std.testing.allocator, "\xe2\x80\xa2");
    try std.testing.expectError(EncodingError.Unmappable, result);
}

test "utf16beEncode and decode roundtrip" {
    const input = "Hello, World!";
    const encoded = try utf16beEncode(std.testing.allocator, input);
    defer std.testing.allocator.free(encoded);

    try std.testing.expectEqual(@as(u8, 0xFE), encoded[0]);
    try std.testing.expectEqual(@as(u8, 0xFF), encoded[1]);

    const decoded = try utf16beDecode(std.testing.allocator, encoded);
    defer std.testing.allocator.free(decoded);
    try std.testing.expectEqualSlices(u8, input, decoded);
}

test "utf16beEncode: supplementary characters" {
    const input = "\xF0\x9F\x98\x80";
    const encoded = try utf16beEncode(std.testing.allocator, input);
    defer std.testing.allocator.free(encoded);

    const decoded = try utf16beDecode(std.testing.allocator, encoded);
    defer std.testing.allocator.free(decoded);
    try std.testing.expectEqualSlices(u8, input, decoded);
}

test "utf16beDecode: invalid odd length" {
    const result = utf16beDecode(std.testing.allocator, &[_]u8{ 0x00, 0x41, 0x00 });
    try std.testing.expectError(EncodingError.InvalidUtf16, result);
}

test "pdfDocEncodingToUtf8: ASCII passthrough" {
    const result = try pdfDocEncodingToUtf8(std.testing.allocator, "test");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualSlices(u8, "test", result);
}

test "pdfDocEncodingToUtf8: special range 0x80" {
    const input = &[_]u8{0x80};
    const result = try pdfDocEncodingToUtf8(std.testing.allocator, input);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualSlices(u8, "\xe2\x80\xa2", result);
}

test "pdfDocEncodingToUtf8: latin-1 range preserved" {
    const input = &[_]u8{0xE9};
    const result = try pdfDocEncodingToUtf8(std.testing.allocator, input);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualSlices(u8, "\xc3\xa9", result);
}
