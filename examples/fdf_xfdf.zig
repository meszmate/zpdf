const std = @import("std");
const zpdf = @import("zpdf");

const Document = zpdf.Document;
const PageSize = zpdf.PageSize;
const FormBuilder = zpdf.FormBuilder;
const Rect = zpdf.form.Form.Rect;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // ── Step 1: Create a PDF with form fields ──────────────────────
    std.debug.print("Step 1: Creating PDF with form fields...\n", .{});

    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("FDF/XFDF Example");
    const page = try doc.addPage(PageSize.a4);

    const helv = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);
    const helv_bold = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv_bold.font.pdfName(), helv_bold.ref);

    try page.drawText("FDF / XFDF Import/Export Demo", .{
        .x = 72,
        .y = 760,
        .font = .helvetica_bold,
        .font_size = 18,
        .color = zpdf.color.rgb(0, 51, 102),
    });

    // Labels
    try page.drawText("Full Name:", .{ .x = 72, .y = 710, .font = .helvetica, .font_size = 12 });
    try page.drawText("Email:", .{ .x = 72, .y = 670, .font = .helvetica, .font_size = 12 });
    try page.drawText("I agree:", .{ .x = 72, .y = 630, .font = .helvetica, .font_size = 12 });

    // Build form fields
    var form = FormBuilder.init(allocator);
    defer form.deinit();

    try form.addTextField("full_name", Rect{ .x = 180, .y = 700, .w = 300, .h = 20 }, .{
        .font = .helvetica,
        .font_size = 12,
    });

    try form.addTextField("email", Rect{ .x = 180, .y = 660, .w = 300, .h = 20 }, .{
        .font = .helvetica,
        .font_size = 12,
    });

    try form.addCheckbox("agree", Rect{ .x = 180, .y = 624, .w = 14, .h = 14 }, false);

    _ = try form.build(&doc.object_store);

    const original_pdf = try doc.save(allocator);
    defer allocator.free(original_pdf);

    std.debug.print("  Created form PDF ({d} bytes)\n", .{original_pdf.len});

    // ── Step 2: Fill the form and export to FDF ────────────────────
    std.debug.print("\nStep 2: Filling form and exporting to FDF...\n", .{});

    const values = [_]zpdf.FieldValue{
        .{ .name = "full_name", .value = "Jane Smith" },
        .{ .name = "email", .value = "jane@example.com" },
        .{ .name = "agree", .value = "Yes" },
    };

    const filled_pdf = try zpdf.fillForm(allocator, original_pdf, &values);
    defer allocator.free(filled_pdf);

    const fdf_data = try zpdf.exportFdf(allocator, filled_pdf);
    defer allocator.free(fdf_data);

    std.debug.print("  FDF output ({d} bytes):\n", .{fdf_data.len});
    std.debug.print("{s}\n", .{fdf_data});

    // ── Step 3: Export to XFDF ─────────────────────────────────────
    std.debug.print("Step 3: Exporting to XFDF...\n", .{});

    const xfdf_data = try zpdf.exportXfdf(allocator, filled_pdf);
    defer allocator.free(xfdf_data);

    std.debug.print("  XFDF output ({d} bytes):\n", .{xfdf_data.len});
    std.debug.print("{s}\n", .{xfdf_data});

    // ── Step 4: Import FDF back into the original PDF ──────────────
    std.debug.print("Step 4: Importing FDF back into original PDF...\n", .{});

    const fdf_filled = try zpdf.importFdf(allocator, original_pdf, fdf_data);
    defer allocator.free(fdf_filled);

    std.debug.print("  FDF-imported PDF ({d} bytes)\n", .{fdf_filled.len});

    // ── Step 5: Import XFDF back into the original PDF ─────────────
    std.debug.print("Step 5: Importing XFDF back into original PDF...\n", .{});

    const xfdf_filled = try zpdf.importXfdf(allocator, original_pdf, xfdf_data);
    defer allocator.free(xfdf_filled);

    std.debug.print("  XFDF-imported PDF ({d} bytes)\n", .{xfdf_filled.len});

    std.debug.print("\nDone! FDF and XFDF import/export working correctly.\n", .{});
}
