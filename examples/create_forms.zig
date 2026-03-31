const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Document = zpdf.Document;
    const PageSize = zpdf.PageSize;
    const color = zpdf.color;
    const FormBuilder = zpdf.FormBuilder;
    const Rect = zpdf.form.Form.Rect;

    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Form Example");
    const page = try doc.addPage(PageSize.a4);

    const helv = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);
    const helv_bold = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv_bold.font.pdfName(), helv_bold.ref);

    // Title
    try page.drawText("Registration Form", .{
        .x = 72,
        .y = 760,
        .font = .helvetica_bold,
        .font_size = 22,
        .color = color.rgb(0, 51, 102),
    });

    try page.drawLine(.{
        .x1 = 72, .y1 = 750, .x2 = 523, .y2 = 750,
        .color = color.rgb(0, 51, 102), .line_width = 1.0,
    });

    // Labels
    try page.drawText("Full Name:", .{ .x = 72, .y = 710, .font = .helvetica, .font_size = 12 });
    try page.drawText("Email:", .{ .x = 72, .y = 670, .font = .helvetica, .font_size = 12 });
    try page.drawText("Notes:", .{ .x = 72, .y = 630, .font = .helvetica, .font_size = 12 });
    try page.drawText("I agree to the terms:", .{ .x = 72, .y = 540, .font = .helvetica, .font_size = 12 });
    try page.drawText("Preferred language:", .{ .x = 72, .y = 500, .font = .helvetica, .font_size = 12 });

    // Draw field backgrounds
    try page.drawRect(.{ .x = 180, .y = 700, .width = 300, .height = 20, .border_color = color.rgb(180, 180, 180) });
    try page.drawRect(.{ .x = 180, .y = 660, .width = 300, .height = 20, .border_color = color.rgb(180, 180, 180) });
    try page.drawRect(.{ .x = 180, .y = 570, .width = 300, .height = 60, .border_color = color.rgb(180, 180, 180) });

    // Build interactive form fields
    var form = FormBuilder.init(allocator);
    defer form.deinit();

    try form.addTextField("full_name", Rect{ .x = 180, .y = 700, .w = 300, .h = 20 }, .{
        .font = .helvetica,
        .font_size = 12,
        .required = true,
    });

    try form.addTextField("email", Rect{ .x = 180, .y = 660, .w = 300, .h = 20 }, .{
        .font = .helvetica,
        .font_size = 12,
    });

    try form.addTextField("notes", Rect{ .x = 180, .y = 570, .w = 300, .h = 60 }, .{
        .font = .helvetica,
        .font_size = 10,
        .multiline = true,
    });

    try form.addCheckbox("agree_terms", Rect{ .x = 250, .y = 534, .w = 14, .h = 14 }, false);

    const lang_opts = [_][]const u8{ "English", "Spanish", "French", "German", "Japanese" };
    try form.addDropdown("language", Rect{ .x = 250, .y = 490, .w = 150, .h = 20 }, &lang_opts, "English", .{
        .font = .helvetica,
        .font_size = 11,
    });

    // Build the AcroForm into the document object store
    _ = try form.build(&doc.object_store);

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("forms.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created forms.pdf ({d} bytes)\n", .{bytes.len});
}
