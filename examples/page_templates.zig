const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Page Templates Example");
    doc.setAuthor("zpdf");

    // Build a reusable template with header, footer, and border
    var tmpl = zpdf.PageTemplate.init(allocator, .a4, zpdf.Margins.one_inch);
    defer tmpl.deinit();

    // Header text
    try tmpl.addText(.{
        .content = "zpdf - Page Templates",
        .x = 72,
        .y = 800,
        .font = .helvetica_bold,
        .font_size = 14,
        .color = zpdf.rgb(0, 51, 153),
    });

    // Header separator line
    try tmpl.addLine(.{
        .x1 = 72,
        .y1 = 793,
        .x2 = 523,
        .y2 = 793,
        .color = zpdf.rgb(0, 51, 153),
        .line_width = 1.0,
    });

    // Footer separator line
    try tmpl.addLine(.{
        .x1 = 72,
        .y1 = 50,
        .x2 = 523,
        .y2 = 50,
        .color = zpdf.rgb(150, 150, 150),
        .line_width = 0.5,
    });

    // Footer with page number
    try tmpl.addText(.{
        .content = "Page {page}",
        .x = 480,
        .y = 35,
        .font_size = 10,
        .color = zpdf.rgb(100, 100, 100),
        .use_page_number = true,
    });

    // Footer left text
    try tmpl.addText(.{
        .content = "Generated with zpdf",
        .x = 72,
        .y = 35,
        .font_size = 9,
        .color = zpdf.rgb(150, 150, 150),
    });

    // Create three pages from the template
    const content_area = tmpl.contentArea();

    for (0..3) |i| {
        const page = try doc.addPageFromTemplate(&tmpl, i + 1);

        // Add unique content within the content area
        const title = switch (i) {
            0 => "Introduction",
            1 => "Details",
            2 => "Conclusion",
            else => unreachable,
        };

        try page.drawText(title, .{
            .x = content_area.x,
            .y = content_area.y + content_area.height - 30,
            .font = .helvetica_bold,
            .font_size = 20,
            .color = zpdf.rgb(0, 0, 0),
        });

        try page.drawText("This page was created from a reusable template.", .{
            .x = content_area.x,
            .y = content_area.y + content_area.height - 60,
            .font = .helvetica,
            .font_size = 12,
        });
    }

    // Save the document
    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("page_templates.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);
}
