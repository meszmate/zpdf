const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. Create a PDF in memory so we have something to parse.
    std.debug.print("=== Creating a test PDF ===\n", .{});

    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Stream-Parsed Document");
    const page = try doc.addPage(.a4);
    try page.drawText("Streamed content", .{
        .x = 72,
        .y = 750,
        .font = .helvetica,
        .font_size = 16,
    });

    const pdf_bytes = try doc.save(allocator);
    defer allocator.free(pdf_bytes);

    std.debug.print("Generated PDF: {d} bytes\n\n", .{pdf_bytes.len});

    // 2. Parse via parseFromReader (simulating a stream with fixedBufferStream).
    std.debug.print("=== parseFromReader ===\n", .{});
    var stream = std.io.fixedBufferStream(pdf_bytes);
    var result = try zpdf.parseFromReader(allocator, stream.reader());
    defer result.deinit();

    std.debug.print("Version: {s}\n", .{result.document.version});
    std.debug.print("Pages: {d}\n\n", .{result.document.pages.items.len});

    // 3. Parse via StreamParser (incremental feed).
    std.debug.print("=== StreamParser (incremental) ===\n", .{});
    var sp = zpdf.StreamParser.init(allocator);
    defer sp.deinit();

    // Feed data in 512-byte chunks.
    var offset: usize = 0;
    while (offset < pdf_bytes.len) {
        const end = @min(offset + 512, pdf_bytes.len);
        try sp.feedData(pdf_bytes[offset..end]);
        offset = end;
    }

    var parsed2 = try sp.finalize();
    defer parsed2.deinit();

    std.debug.print("Version: {s}\n", .{parsed2.version});
    std.debug.print("Pages: {d}\n", .{parsed2.pages.items.len});

    std.debug.print("\nDone.\n", .{});
}
