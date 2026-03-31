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

    doc.setTitle("Barcode Examples");
    const page = try doc.addPage(PageSize.a4);

    const helv = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);
    const helv_reg = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(helv_reg.font.pdfName(), helv_reg.ref);

    // Title
    try page.drawText("Barcode Gallery", .{
        .x = 72,
        .y = 780,
        .font = .helvetica_bold,
        .font_size = 22,
        .color = color.rgb(0, 0, 0),
    });

    // --- Code 128 ---
    try page.drawText("Code 128", .{
        .x = 72, .y = 730, .font = .helvetica_bold, .font_size = 13,
    });
    const code128_ops = try drawBarcode(allocator, BarcodeOptions{
        .barcode_type = .code128,
        .value = "ZPDF-2026",
        .x = 72,
        .y = 670,
        .width = 250,
        .height = 50,
    });
    defer allocator.free(code128_ops);
    try page.content.appendSlice(page.allocator, code128_ops);
    try page.drawText("Value: ZPDF-2026", .{
        .x = 72, .y = 658, .font = .helvetica, .font_size = 9,
        .color = color.rgb(100, 100, 100),
    });

    // --- Code 39 ---
    try page.drawText("Code 39", .{
        .x = 72, .y = 630, .font = .helvetica_bold, .font_size = 13,
    });
    const code39_ops = try drawBarcode(allocator, BarcodeOptions{
        .barcode_type = .code39,
        .value = "HELLO",
        .x = 72,
        .y = 570,
        .width = 250,
        .height = 50,
    });
    defer allocator.free(code39_ops);
    try page.content.appendSlice(page.allocator, code39_ops);
    try page.drawText("Value: HELLO", .{
        .x = 72, .y = 558, .font = .helvetica, .font_size = 9,
        .color = color.rgb(100, 100, 100),
    });

    // --- EAN-13 ---
    try page.drawText("EAN-13", .{
        .x = 72, .y = 530, .font = .helvetica_bold, .font_size = 13,
    });
    const ean13_ops = try drawBarcode(allocator, BarcodeOptions{
        .barcode_type = .ean13,
        .value = "5901234123457",
        .x = 72,
        .y = 465,
        .width = 200,
        .height = 55,
    });
    defer allocator.free(ean13_ops);
    try page.content.appendSlice(page.allocator, ean13_ops);
    try page.drawText("Value: 5901234123457", .{
        .x = 72, .y = 453, .font = .helvetica, .font_size = 9,
        .color = color.rgb(100, 100, 100),
    });

    // --- QR Code ---
    try page.drawText("QR Code", .{
        .x = 72, .y = 425, .font = .helvetica_bold, .font_size = 13,
    });
    const qr_ops = try drawBarcode(allocator, BarcodeOptions{
        .barcode_type = .qr,
        .value = "https://github.com/user/zpdf",
        .x = 72,
        .y = 300,
        .width = 120,
        .height = 120,
        .qr_error_level = .medium,
    });
    defer allocator.free(qr_ops);
    try page.content.appendSlice(page.allocator, qr_ops);
    try page.drawText("Value: https://github.com/user/zpdf", .{
        .x = 72, .y = 288, .font = .helvetica, .font_size = 9,
        .color = color.rgb(100, 100, 100),
    });

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("barcodes.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created barcodes.pdf ({d} bytes)\n", .{bytes.len});
}
