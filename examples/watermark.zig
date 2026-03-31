const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Document = zpdf.Document;
    const PageSize = zpdf.PageSize;
    const addWatermark = zpdf.modify.watermarker.addWatermark;
    const WatermarkOptions = zpdf.modify.watermarker.WatermarkOptions;
    const color = zpdf.color;

    // First, create a base PDF document
    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Watermarked Document");
    const page = try doc.addPage(PageSize.letter);

    const helv = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);
    const helv_reg = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(helv_reg.font.pdfName(), helv_reg.ref);

    try page.drawText("Company Report - Q1 2026", .{
        .x = 72,
        .y = 720,
        .font = .helvetica_bold,
        .font_size = 22,
        .color = color.rgb(0, 0, 0),
    });

    try page.drawText("Revenue increased by 15% compared to the previous quarter.", .{
        .x = 72,
        .y = 690,
        .font = .helvetica,
        .font_size = 12,
    });
    try page.drawText("Operating costs were reduced through automation initiatives.", .{
        .x = 72,
        .y = 670,
        .font = .helvetica,
        .font_size = 12,
    });
    try page.drawText("Customer satisfaction scores reached an all-time high of 94%.", .{
        .x = 72,
        .y = 650,
        .font = .helvetica,
        .font_size = 12,
    });

    try page.drawRect(.{
        .x = 72,
        .y = 530,
        .width = 468,
        .height = 100,
        .color = color.rgb(240, 248, 255),
        .border_color = color.rgb(70, 130, 180),
        .border_width = 1.0,
    });
    try page.drawText("Summary: Strong performance across all divisions.", .{
        .x = 90,
        .y = 600,
        .font = .helvetica_bold,
        .font_size = 13,
        .color = color.rgb(0, 51, 102),
    });

    // Save the base PDF
    const base_bytes = try doc.save(allocator);
    defer allocator.free(base_bytes);

    // Apply a "DRAFT" watermark
    const watermarked = try addWatermark(allocator, base_bytes, WatermarkOptions{
        .text = "DRAFT",
        .font_size = 72.0,
        .color = .{ .r = 0.8, .g = 0.2, .b = 0.2 },
        .opacity = 0.25,
        .rotation = 45.0,
    });
    defer allocator.free(watermarked);

    const file = try std.fs.cwd().createFile("watermarked.pdf", .{});
    defer file.close();
    try file.writeAll(watermarked);

    std.debug.print("Created watermarked.pdf ({d} bytes)\n", .{watermarked.len});
}
