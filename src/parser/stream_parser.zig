const std = @import("std");
const Allocator = std.mem.Allocator;
const pdf_parser = @import("pdf_parser.zig");
const ParsedDocument = pdf_parser.ParsedDocument;

/// A streaming PDF parser that can read from any `std.io.Reader` or accept
/// data incrementally via `feedData`, then parse once all bytes are available.
pub const StreamParser = struct {
    allocator: Allocator,
    buffer: std.ArrayListUnmanaged(u8),

    /// Initialize a new StreamParser.
    pub fn init(allocator: Allocator) StreamParser {
        return .{
            .allocator = allocator,
            .buffer = .{},
        };
    }

    /// Feed a chunk of PDF data into the internal buffer.
    pub fn feedData(self: *StreamParser, chunk: []const u8) Allocator.Error!void {
        try self.buffer.appendSlice(self.allocator, chunk);
    }

    /// Finalize parsing: hand the accumulated buffer to the existing PDF parser
    /// and return a `ParsedDocument`. The caller must call `deinit` on the
    /// returned document before freeing the StreamParser.
    ///
    /// Note: the returned `ParsedDocument` may reference memory owned by the
    /// StreamParser's internal buffer, so the StreamParser must remain alive
    /// (or the caller must not deinit it) until the document is no longer needed.
    pub fn finalize(self: *StreamParser) !ParsedDocument {
        return pdf_parser.parsePdf(self.allocator, self.buffer.items);
    }

    /// Release resources without parsing.
    pub fn deinit(self: *StreamParser) void {
        self.buffer.deinit(self.allocator);
    }
};

/// Parse a PDF from any `std.io.Reader` by buffering the full contents into
/// memory, then delegating to `parsePdf`.
///
/// The returned `ParsedDocument` takes ownership of the buffered data
/// internally. The caller is responsible for calling `deinit` on the document.
///
/// Important: because `parsePdf` returns slices into the input data, the
/// buffered bytes are kept alive as the `_owned_data` field of the result.
/// The caller must call `freeOwnedData` after `deinit` on the document, or
/// use the simpler pattern shown below.
///
/// Actually -- since `ParsedDocument` does not own the input bytes, we store
/// the owned buffer in a wrapper. To keep the API simple and avoid changing
/// `ParsedDocument`, this function allocates the buffer with the provided
/// allocator and the caller must free it after they are done with the document.
/// We return just a `ParsedDocument` whose fields point into allocator-owned
/// memory that stays valid for the document's lifetime.
///
/// To avoid leaking, callers should pair the returned doc with `freeReaderData`.
pub fn parseFromReader(allocator: Allocator, reader: anytype) !ReaderResult {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(allocator);

    // Read in 4 KiB chunks until EOF.
    while (true) {
        const old_len = buf.items.len;
        try buf.resize(allocator, old_len + 4096);
        const n = try reader.read(buf.items[old_len..]);
        buf.shrinkRetainingCapacity(old_len + n);
        if (n == 0) break;
    }

    const data = try buf.toOwnedSlice(allocator);
    errdefer allocator.free(data);

    const doc = try pdf_parser.parsePdf(allocator, data);
    return .{
        .document = doc,
        ._owned_data = data,
        ._allocator = allocator,
    };
}

/// Result from `parseFromReader` that bundles the parsed document with the
/// owned backing buffer so both can be freed together.
pub const ReaderResult = struct {
    document: ParsedDocument,
    _owned_data: []const u8,
    _allocator: Allocator,

    /// Free both the document and the backing data.
    pub fn deinit(self: *ReaderResult) void {
        self.document.deinit();
        self._allocator.free(self._owned_data);
    }
};

/// Convenience: open a file by path, read it fully, and parse the PDF.
pub fn parseFromFile(allocator: Allocator, path: []const u8) !ReaderResult {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const data = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    errdefer allocator.free(data);
    const doc = try pdf_parser.parsePdf(allocator, data);
    return .{
        .document = doc,
        ._owned_data = data,
        ._allocator = allocator,
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "stream_parser: parseFromReader with minimal pdf" {
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

    var stream = std.io.fixedBufferStream(pdf);
    var result = try parseFromReader(allocator, stream.reader());
    defer result.deinit();

    try std.testing.expectEqualStrings("1.4", result.document.version);
    try std.testing.expect(result.document.pages.items.len >= 1);
}

test "stream_parser: StreamParser incremental feed" {
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
        \\<< /Type /Page /MediaBox [0 0 612 792] /Parent 2 0 R >>
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

    var sp = StreamParser.init(allocator);
    defer sp.deinit();

    // Feed data in two chunks.
    const mid = pdf.len / 2;
    try sp.feedData(pdf[0..mid]);
    try sp.feedData(pdf[mid..]);

    var doc = try sp.finalize();
    defer doc.deinit();

    try std.testing.expectEqualStrings("1.4", doc.version);
    try std.testing.expect(doc.pages.items.len >= 1);
}

test "stream_parser: parseFromReader rejects invalid data" {
    const allocator = std.testing.allocator;
    var stream = std.io.fixedBufferStream("not a pdf at all");
    const result = parseFromReader(allocator, stream.reader());
    try std.testing.expectError(error.InvalidPdf, result);
}
