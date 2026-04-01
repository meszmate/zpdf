const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Document = zpdf.Document;
    const PageSize = zpdf.PageSize;
    const color = zpdf.color;
    const redactPdf = zpdf.modify.redaction.redactPdf;

    // Step 1: Create a sample PDF document with sensitive content.
    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Redaction Example");
    const page = try doc.addPage(PageSize.letter);

    const helv_bold = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv_bold.font.pdfName(), helv_bold.ref);
    const helv = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);

    try page.drawText("Employee Records", .{
        .x = 72,
        .y = 720,
        .font = .helvetica_bold,
        .font_size = 20,
        .color = color.rgb(0, 0, 0),
    });

    try page.drawText("Name: John Smith", .{
        .x = 72,
        .y = 680,
        .font = .helvetica,
        .font_size = 12,
    });
    try page.drawText("SSN: 123-45-6789", .{
        .x = 72,
        .y = 660,
        .font = .helvetica,
        .font_size = 12,
    });
    try page.drawText("Salary: $125,000", .{
        .x = 72,
        .y = 640,
        .font = .helvetica,
        .font_size = 12,
    });
    try page.drawText("Department: Engineering", .{
        .x = 72,
        .y = 620,
        .font = .helvetica,
        .font_size = 12,
    });

    // Save the original PDF.
    const original_bytes = try doc.save(allocator);
    defer allocator.free(original_bytes);

    // Step 2: Redact sensitive fields (SSN and Salary).
    const redacted = try redactPdf(allocator, original_bytes, .{
        .areas = &.{
            // Redact the SSN value area.
            .{
                .page_index = 0,
                .x = 110,
                .y = 655,
                .width = 120,
                .height = 16,
                .overlay_text = "REDACTED",
                .overlay_font_size = 10,
            },
            // Redact the Salary value area.
            .{
                .page_index = 0,
                .x = 120,
                .y = 635,
                .width = 100,
                .height = 16,
                .color = .{ .named = .black },
            },
        },
    });
    defer allocator.free(redacted);

    // Write the redacted PDF.
    const file = try std.fs.cwd().createFile("redacted.pdf", .{});
    defer file.close();
    try file.writeAll(redacted);

    std.debug.print("Created redacted.pdf ({d} bytes)\n", .{redacted.len});
}
