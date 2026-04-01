const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("PDF with Attachments");
    doc.setAuthor("zpdf");

    // Create a page with some text
    const page = try doc.addPage(.a4);
    const helv = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);

    const helv_bold = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv_bold.font.pdfName(), helv_bold.ref);

    try page.drawText("PDF with File Attachments", .{
        .x = 72,
        .y = 750,
        .font = .helvetica_bold,
        .font_size = 20,
        .color = zpdf.color.rgb(0, 51, 102),
    });

    try page.drawText("This PDF contains two embedded file attachments:", .{
        .x = 72,
        .y = 710,
        .font = .helvetica,
        .font_size = 12,
    });

    try page.drawText("1. readme.txt - A plain text file", .{
        .x = 90,
        .y = 685,
        .font = .helvetica,
        .font_size = 11,
    });

    try page.drawText("2. sales_data.csv - A CSV spreadsheet", .{
        .x = 90,
        .y = 665,
        .font = .helvetica,
        .font_size = 11,
    });

    try page.drawText("Open the attachments panel in your PDF viewer to access them.", .{
        .x = 72,
        .y = 630,
        .font = .helvetica,
        .font_size = 11,
        .color = zpdf.color.rgb(100, 100, 100),
    });

    // Attach a plain text file
    try doc.addAttachment(.{
        .name = "readme.txt",
        .data = "Welcome to zpdf!\n\nThis file was embedded as an attachment in a PDF document.\n",
        .mime_type = "text/plain",
        .description = "A readme text file",
    });

    // Attach a CSV file
    try doc.addAttachment(.{
        .name = "sales_data.csv",
        .data = "Month,Revenue,Units\nJanuary,12500,150\nFebruary,13200,165\nMarch,14800,180\nApril,11900,140\n",
        .mime_type = "text/csv",
        .description = "Quarterly sales data",
    });

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("attachments.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created attachments.pdf ({d} bytes) with 2 embedded files\n", .{bytes.len});
}
