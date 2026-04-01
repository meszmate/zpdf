const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Document = zpdf.Document;
    const PageSize = zpdf.PageSize;
    const drawBarcode = zpdf.drawBarcode;
    const BarcodeOptions = zpdf.barcode.barcode_api.BarcodeOptions;
    const color = zpdf.color;

    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("UPC-A and EAN-8 Barcode Examples");
    const page = try doc.addPage(PageSize.a4);

    const helv = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);
    const helv_reg = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(helv_reg.font.pdfName(), helv_reg.ref);

    // Title
    try page.drawText("UPC-A and EAN-8 Barcodes", .{
        .x = 72,
        .y = 780,
        .font = .helvetica_bold,
        .font_size = 22,
        .color = color.rgb(0, 0, 0),
    });

    // --- UPC-A ---
    try page.drawText("UPC-A", .{
        .x = 72, .y = 730, .font = .helvetica_bold, .font_size = 13,
    });
    const upca_ops = try drawBarcode(allocator, BarcodeOptions{
        .barcode_type = .upca,
        .value = "036000291452",
        .x = 72,
        .y = 670,
        .width = 200,
        .height = 55,
    });
    defer allocator.free(upca_ops);
    try page.content.appendSlice(page.allocator, upca_ops);
    try page.drawText("Value: 036000291452", .{
        .x = 72, .y = 658, .font = .helvetica, .font_size = 9,
        .color = color.rgb(100, 100, 100),
    });

    // --- EAN-8 ---
    try page.drawText("EAN-8", .{
        .x = 72, .y = 630, .font = .helvetica_bold, .font_size = 13,
    });
    const ean8_ops = try drawBarcode(allocator, BarcodeOptions{
        .barcode_type = .ean8,
        .value = "96385074",
        .x = 72,
        .y = 570,
        .width = 150,
        .height = 55,
    });
    defer allocator.free(ean8_ops);
    try page.content.appendSlice(page.allocator, ean8_ops);
    try page.drawText("Value: 96385074", .{
        .x = 72, .y = 558, .font = .helvetica, .font_size = 9,
        .color = color.rgb(100, 100, 100),
    });

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("upca_ean8.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created upca_ean8.pdf ({d} bytes)\n", .{bytes.len});
}
