const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a multi-page PDF document
    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Linearization Example");
    doc.setAuthor("zpdf");

    // Add several pages with content
    for (0..5) |i| {
        const page = try doc.addPage(.a4);
        var title_buf: [64]u8 = undefined;
        const title = std.fmt.bufPrint(&title_buf, "Page {d} of 5", .{i + 1}) catch "Page";
        try page.drawText(title, .{
            .x = 72,
            .y = 750,
            .font_size = 24,
            .color = zpdf.color.rgb(0, 51, 102),
        });
        try page.drawText("This document demonstrates PDF linearization for fast web viewing.", .{
            .x = 72,
            .y = 700,
            .font_size = 12,
        });
    }

    // Save the standard (non-linearized) PDF
    const pdf_bytes = try doc.save(allocator);
    defer allocator.free(pdf_bytes);

    std.debug.print("Original PDF: {d} bytes\n", .{pdf_bytes.len});
    std.debug.print("Is linearized: {}\n", .{zpdf.isLinearized(pdf_bytes)});

    // Linearize the PDF for fast web viewing
    const linearized = try zpdf.linearizePdf(allocator, pdf_bytes);
    defer allocator.free(linearized);

    std.debug.print("Linearized PDF: {d} bytes\n", .{linearized.len});
    std.debug.print("Is linearized: {}\n", .{zpdf.isLinearized(linearized)});

    // Write the linearized PDF to disk
    const file = try std.fs.cwd().createFile("linearized.pdf", .{});
    defer file.close();
    try file.writeAll(linearized);

    std.debug.print("Wrote linearized.pdf\n", .{});
}
