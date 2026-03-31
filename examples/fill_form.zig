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

    // ── Step 1: Create a PDF with form fields ───────────────────────
    std.debug.print("Step 1: Creating PDF with form fields...\n", .{});

    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Form Fill Example");
    const page = try doc.addPage(PageSize.a4);

    const helv = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);
    const helv_bold = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv_bold.font.pdfName(), helv_bold.ref);

    // Title
    try page.drawText("Application Form", .{
        .x = 72,
        .y = 760,
        .font = .helvetica_bold,
        .font_size = 20,
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

    _ = try form.build(&doc.object_store);

    const original_pdf = try doc.save(allocator);
    defer allocator.free(original_pdf);

    // Save the original form PDF
    {
        const file = try std.fs.cwd().createFile("form_original.pdf", .{});
        defer file.close();
        try file.writeAll(original_pdf);
        std.debug.print("  Saved form_original.pdf ({d} bytes)\n", .{original_pdf.len});
    }

    // ── Step 2: Fill in the form fields ─────────────────────────────
    std.debug.print("Step 2: Filling form fields...\n", .{});

    const values = [_]zpdf.FieldValue{
        .{ .name = "full_name", .value = "Jane Smith" },
        .{ .name = "email", .value = "jane.smith@example.com" },
        .{ .name = "notes", .value = "Looking forward to joining!" },
        .{ .name = "agree_terms", .value = "Yes" },
        .{ .name = "language", .value = "French" },
    };

    const filled_pdf = try zpdf.fillForm(allocator, original_pdf, &values);
    defer allocator.free(filled_pdf);

    // Save the filled (still interactive) form
    {
        const file = try std.fs.cwd().createFile("form_filled.pdf", .{});
        defer file.close();
        try file.writeAll(filled_pdf);
        std.debug.print("  Saved form_filled.pdf ({d} bytes)\n", .{filled_pdf.len});
    }

    // ── Step 3: Flatten the form ────────────────────────────────────
    std.debug.print("Step 3: Flattening form (baking values into content)...\n", .{});

    const flattened_pdf = try zpdf.flattenForm(allocator, filled_pdf, .{
        .font = .helvetica,
        .font_size = 11,
        .color = zpdf.color.rgb(0, 0, 0),
        .padding = 3,
    });
    defer allocator.free(flattened_pdf);

    // Save the flattened (static, non-editable) form
    {
        const file = try std.fs.cwd().createFile("form_flattened.pdf", .{});
        defer file.close();
        try file.writeAll(flattened_pdf);
        std.debug.print("  Saved form_flattened.pdf ({d} bytes)\n", .{flattened_pdf.len});
    }

    // ── Step 4: Fill and flatten in one step ────────────────────────
    std.debug.print("Step 4: Fill and flatten in one step...\n", .{});

    const combined = try zpdf.fillAndFlatten(allocator, original_pdf, &values, .{
        .font = .helvetica,
        .font_size = 11,
    });
    defer allocator.free(combined);

    {
        const file = try std.fs.cwd().createFile("form_combined.pdf", .{});
        defer file.close();
        try file.writeAll(combined);
        std.debug.print("  Saved form_combined.pdf ({d} bytes)\n", .{combined.len});
    }

    std.debug.print("\nDone! Created 4 PDF files:\n", .{});
    std.debug.print("  - form_original.pdf   (empty interactive form)\n", .{});
    std.debug.print("  - form_filled.pdf     (filled interactive form)\n", .{});
    std.debug.print("  - form_flattened.pdf  (flattened static form)\n", .{});
    std.debug.print("  - form_combined.pdf   (fill+flatten in one step)\n", .{});
}
