const std = @import("std");
const zpdf = @import("zpdf");

const Document = zpdf.Document;
const CountingWriter = zpdf.CountingWriter;
const countingWriter = zpdf.countingWriter;

test "CountingWriter tracks bytes correctly" {
    var backing: std.ArrayListUnmanaged(u8) = .{};
    defer backing.deinit(std.testing.allocator);

    var cw = countingWriter(backing.writer(std.testing.allocator));
    const wr = cw.writer();

    try wr.writeAll("hello");
    try std.testing.expectEqual(@as(u64, 5), cw.bytes_written);

    try wr.writeAll(" world!");
    try std.testing.expectEqual(@as(u64, 12), cw.bytes_written);

    try std.testing.expectEqualStrings("hello world!", backing.items);
}

test "streaming a simple document produces valid PDF" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    doc.setTitle("Stream Test");
    _ = try doc.addPage(.a4);

    var output: std.ArrayListUnmanaged(u8) = .{};
    defer output.deinit(std.testing.allocator);

    try doc.saveTo(std.testing.allocator, output.writer(std.testing.allocator));

    const pdf = output.items;

    // Check header
    try std.testing.expect(std.mem.startsWith(u8, pdf, "%PDF-1.7\n"));

    // Check trailer elements
    try std.testing.expect(std.mem.indexOf(u8, pdf, "%%EOF") != null);
    try std.testing.expect(std.mem.indexOf(u8, pdf, "xref") != null);
    try std.testing.expect(std.mem.indexOf(u8, pdf, "trailer") != null);
    try std.testing.expect(std.mem.indexOf(u8, pdf, "startxref") != null);

    // Check metadata
    try std.testing.expect(std.mem.indexOf(u8, pdf, "Stream Test") != null);
    try std.testing.expect(std.mem.indexOf(u8, pdf, "/Catalog") != null);
}

test "streaming produces same output as in-memory save" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    doc.setTitle("Identical Output Test");
    doc.setAuthor("zpdf test");

    const page = try doc.addPage(.a4);
    try page.drawText("Hello from zpdf", .{
        .x = 72,
        .y = 700,
        .font_size = 12,
    });

    // Get in-memory output
    const mem_pdf = try doc.save(std.testing.allocator);
    defer std.testing.allocator.free(mem_pdf);

    // Get streamed output
    var stream_output: std.ArrayListUnmanaged(u8) = .{};
    defer stream_output.deinit(std.testing.allocator);
    try doc.saveTo(std.testing.allocator, stream_output.writer(std.testing.allocator));

    try std.testing.expectEqualSlices(u8, mem_pdf, stream_output.items);
}

test "streaming to a fixedBufferStream" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    _ = try doc.addPage(.letter);

    // First, figure out how big the output is
    var sizing: std.ArrayListUnmanaged(u8) = .{};
    defer sizing.deinit(std.testing.allocator);
    try doc.saveTo(std.testing.allocator, sizing.writer(std.testing.allocator));

    // Now stream into a fixed buffer of exactly that size
    const buf = try std.testing.allocator.alloc(u8, sizing.items.len);
    defer std.testing.allocator.free(buf);

    var fbs = std.io.fixedBufferStream(buf);
    try doc.saveTo(std.testing.allocator, fbs.writer());

    try std.testing.expectEqualSlices(u8, sizing.items, fbs.getWritten());
}

test "streaming a multi-page document" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    doc.setTitle("Multi-Page Streaming");

    // Add several pages with different sizes
    _ = try doc.addPage(.a4);
    _ = try doc.addPage(.letter);
    _ = try doc.addPage(.a4);

    var output: std.ArrayListUnmanaged(u8) = .{};
    defer output.deinit(std.testing.allocator);
    try doc.saveTo(std.testing.allocator, output.writer(std.testing.allocator));

    const pdf = output.items;

    // Basic structural checks
    try std.testing.expect(std.mem.startsWith(u8, pdf, "%PDF-1.7\n"));
    try std.testing.expect(std.mem.indexOf(u8, pdf, "%%EOF") != null);

    // Should have /Count 3 for three pages
    try std.testing.expect(std.mem.indexOf(u8, pdf, "/Count 3") != null);

    // Verify it matches in-memory output
    const mem_pdf = try doc.save(std.testing.allocator);
    defer std.testing.allocator.free(mem_pdf);
    try std.testing.expectEqualSlices(u8, mem_pdf, output.items);
}
