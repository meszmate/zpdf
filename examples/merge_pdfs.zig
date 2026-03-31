const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Document = zpdf.Document;
    const PageSize = zpdf.PageSize;
    const PdfMerger = zpdf.PdfMerger;
    const color = zpdf.color;

    // --- Create first PDF ---
    var doc1 = Document.init(allocator);
    defer doc1.deinit();
    doc1.setTitle("Document One");

    const page1 = try doc1.addPage(PageSize.letter);
    const helv1 = try doc1.getStandardFont(.helvetica_bold);
    _ = try page1.addFont(helv1.font.pdfName(), helv1.ref);

    try page1.drawText("Page from Document 1", .{
        .x = 72,
        .y = 700,
        .font = .helvetica_bold,
        .font_size = 24,
        .color = color.rgb(0, 102, 204),
    });
    try page1.drawText("This is the first PDF that will be merged.", .{
        .x = 72,
        .y = 670,
        .font = .helvetica,
        .font_size = 12,
    });
    try page1.drawRect(.{
        .x = 72,
        .y = 580,
        .width = 200,
        .height = 60,
        .color = color.rgb(100, 149, 237),
        .corner_radius = 8,
    });

    const bytes1 = try doc1.save(allocator);
    defer allocator.free(bytes1);

    // --- Create second PDF ---
    var doc2 = Document.init(allocator);
    defer doc2.deinit();
    doc2.setTitle("Document Two");

    const page2 = try doc2.addPage(PageSize.letter);
    const helv2 = try doc2.getStandardFont(.helvetica_bold);
    _ = try page2.addFont(helv2.font.pdfName(), helv2.ref);

    try page2.drawText("Page from Document 2", .{
        .x = 72,
        .y = 700,
        .font = .helvetica_bold,
        .font_size = 24,
        .color = color.rgb(204, 51, 0),
    });
    try page2.drawText("This is the second PDF that will be merged.", .{
        .x = 72,
        .y = 670,
        .font = .helvetica,
        .font_size = 12,
    });
    try page2.drawCircle(.{
        .cx = 172,
        .cy = 600,
        .r = 40,
        .color = color.rgb(255, 99, 71),
    });

    const bytes2 = try doc2.save(allocator);
    defer allocator.free(bytes2);

    // --- Merge both PDFs ---
    var merger = PdfMerger.init(allocator);
    defer merger.deinit();

    try merger.add(bytes1);
    try merger.add(bytes2);

    const merged_bytes = try merger.merge(allocator);
    defer allocator.free(merged_bytes);

    const file = try std.fs.cwd().createFile("merged.pdf", .{});
    defer file.close();
    try file.writeAll(merged_bytes);

    std.debug.print("Created merged.pdf ({d} bytes) from 2 source PDFs\n", .{merged_bytes.len});
}
