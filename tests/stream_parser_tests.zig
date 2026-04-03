const std = @import("std");
const zpdf = @import("zpdf");

const minimal_pdf =
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

test "parseFromReader parses a valid pdf" {
    const allocator = std.testing.allocator;
    var stream = std.io.fixedBufferStream(minimal_pdf);
    var result = try zpdf.parseFromReader(allocator, stream.reader());
    defer result.deinit();

    try std.testing.expectEqualStrings("1.4", result.document.version);
    try std.testing.expect(result.document.pages.items.len >= 1);
}

test "parseFromReader rejects invalid data" {
    const allocator = std.testing.allocator;
    var stream = std.io.fixedBufferStream("not a pdf");
    const result = zpdf.parseFromReader(allocator, stream.reader());
    try std.testing.expectError(error.InvalidPdf, result);
}

test "StreamParser feed and finalize" {
    const allocator = std.testing.allocator;

    var sp = zpdf.StreamParser.init(allocator);
    defer sp.deinit();

    // Feed in three chunks.
    const c1 = minimal_pdf.len / 3;
    const c2 = 2 * minimal_pdf.len / 3;
    try sp.feedData(minimal_pdf[0..c1]);
    try sp.feedData(minimal_pdf[c1..c2]);
    try sp.feedData(minimal_pdf[c2..]);

    var doc = try sp.finalize();
    defer doc.deinit();

    try std.testing.expectEqualStrings("1.4", doc.version);
    try std.testing.expect(doc.pages.items.len >= 1);
}

test "StreamParser finalize rejects invalid data" {
    const allocator = std.testing.allocator;

    var sp = zpdf.StreamParser.init(allocator);
    defer sp.deinit();

    try sp.feedData("garbage input");
    const result = sp.finalize();
    try std.testing.expectError(error.InvalidPdf, result);
}

test "parseFromReader with generated pdf" {
    const allocator = std.testing.allocator;

    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Stream Test");
    const page = try doc.addPage(.a4);
    try page.drawText("Hello", .{ .x = 72, .y = 720, .font = .helvetica, .font_size = 12 });

    const pdf_bytes = try doc.save(allocator);
    defer allocator.free(pdf_bytes);

    var stream = std.io.fixedBufferStream(pdf_bytes);
    var result = try zpdf.parseFromReader(allocator, stream.reader());
    defer result.deinit();

    try std.testing.expect(result.document.pages.items.len >= 1);
}
