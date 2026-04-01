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

    doc.setTitle("Data Matrix Examples");
    const page = try doc.addPage(PageSize.a4);

    const helv = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);
    const helv_reg = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(helv_reg.font.pdfName(), helv_reg.ref);

    // Title
    try page.drawText("Data Matrix Barcode Examples", .{
        .x = 72,
        .y = 780,
        .font = .helvetica_bold,
        .font_size = 22,
        .color = color.rgb(0, 0, 0),
    });

    // --- Data Matrix with text ---
    try page.drawText("Data Matrix - Text", .{
        .x = 72, .y = 720, .font = .helvetica_bold, .font_size = 13,
    });
    const dm_text_ops = try drawBarcode(allocator, BarcodeOptions{
        .barcode_type = .data_matrix,
        .value = "Hello zpdf!",
        .x = 72,
        .y = 580,
        .width = 120,
        .height = 120,
    });
    defer allocator.free(dm_text_ops);
    try page.content.appendSlice(page.allocator, dm_text_ops);
    try page.drawText("Value: Hello zpdf!", .{
        .x = 72, .y = 568, .font = .helvetica, .font_size = 9,
        .color = color.rgb(100, 100, 100),
    });

    // --- Data Matrix with numeric data ---
    try page.drawText("Data Matrix - Numeric", .{
        .x = 300, .y = 720, .font = .helvetica_bold, .font_size = 13,
    });
    const dm_num_ops = try drawBarcode(allocator, BarcodeOptions{
        .barcode_type = .data_matrix,
        .value = "0123456789",
        .x = 300,
        .y = 580,
        .width = 120,
        .height = 120,
    });
    defer allocator.free(dm_num_ops);
    try page.content.appendSlice(page.allocator, dm_num_ops);
    try page.drawText("Value: 0123456789", .{
        .x = 300, .y = 568, .font = .helvetica, .font_size = 9,
        .color = color.rgb(100, 100, 100),
    });

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("data_matrix.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created data_matrix.pdf ({d} bytes)\n", .{bytes.len});
}
