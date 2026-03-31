const std = @import("std");
const zpdf = @import("zpdf");
const testing = std.testing;

const Document = zpdf.Document;
const PageSize = zpdf.PageSize;
const color = zpdf.color;

test "create document and add page" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    try testing.expectEqual(@as(usize, 0), doc.getPageCount());

    const page = try doc.addPage(.a4);
    try testing.expectEqual(@as(usize, 1), doc.getPageCount());
    try testing.expectApproxEqAbs(@as(f32, 595.28), page.getWidth(), 0.01);
    try testing.expectApproxEqAbs(@as(f32, 841.89), page.getHeight(), 0.01);
}

test "set document metadata" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    doc.setTitle("Test PDF");
    doc.setAuthor("zpdf library");
    try testing.expectEqualStrings("Test PDF", doc.title.?);
    try testing.expectEqualStrings("zpdf library", doc.author.?);
}

test "add multiple pages and remove" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    _ = try doc.addPage(.a4);
    _ = try doc.addPage(.letter);
    try testing.expectEqual(@as(usize, 2), doc.getPageCount());

    try doc.removePage(0);
    try testing.expectEqual(@as(usize, 1), doc.getPageCount());
}

test "draw text on page and save to bytes" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    const font_handle = try doc.getStandardFont(.helvetica);
    const page = try doc.addPage(.a4);
    const font_res_name = try page.addFont(font_handle.font.pdfName(), font_handle.ref);

    try page.drawText("Hello, zpdf!", .{
        .x = 72,
        .y = 720,
        .font = .helvetica,
        .font_size = 24,
        .color = color.rgb(0, 0, 0),
    });
    _ = font_res_name;

    const pdf_bytes = try doc.save(testing.allocator);
    defer testing.allocator.free(pdf_bytes);

    // Verify PDF header
    try testing.expect(pdf_bytes.len > 0);
    try testing.expect(std.mem.startsWith(u8, pdf_bytes, "%PDF-1.7"));
}

test "get standard font returns same ref for same font" {
    var doc = Document.init(testing.allocator);
    defer doc.deinit();

    const h1 = try doc.getStandardFont(.helvetica);
    const h2 = try doc.getStandardFont(.helvetica);
    try testing.expect(h1.ref.eql(h2.ref));
}

test "page size dimensions for letter" {
    const dims = PageSize.letter.dimensions();
    try testing.expectApproxEqAbs(@as(f32, 612.0), dims.width, 0.01);
    try testing.expectApproxEqAbs(@as(f32, 792.0), dims.height, 0.01);
}
