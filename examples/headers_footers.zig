const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Document = zpdf.Document;
    const PageSize = zpdf.PageSize;

    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Headers and Footers Example");
    doc.setAuthor("zpdf");

    // Register a font so pages can render text
    const helv = try doc.getStandardFont(.helvetica);
    const helv_bold = try doc.getStandardFont(.helvetica_bold);

    // Create 5 pages with some content
    for (0..5) |i| {
        const page = try doc.addPage(PageSize.a4);
        _ = try page.addFont(helv.font.pdfName(), helv.ref);
        _ = try page.addFont(helv_bold.font.pdfName(), helv_bold.ref);

        if (i == 0) {
            // Title page
            try page.drawText("Document Title", .{
                .x = 150,
                .y = 500,
                .font = .helvetica_bold,
                .font_size = 36,
                .color = zpdf.rgb(0, 51, 102),
            });
            try page.drawText("A demonstration of headers and footers in zpdf", .{
                .x = 120,
                .y = 460,
                .font = .helvetica,
                .font_size = 14,
                .color = zpdf.rgb(100, 100, 100),
            });
        } else {
            try page.drawText(
                try std.fmt.allocPrint(allocator, "This is page {d} content.", .{i + 1}),
                .{
                    .x = 72,
                    .y = 700,
                    .font = .helvetica,
                    .font_size = 12,
                },
            );
        }
    }

    // Header: left="Company Name", right="Confidential"
    // Skip first page (title page)
    const header_elements = [_]zpdf.HFElement{
        .{
            .position = .left,
            .content = .{ .text = "Company Name" },
            .font = .helvetica_bold,
            .font_size = 9,
            .color = zpdf.rgb(0, 51, 102),
        },
        .{
            .position = .right,
            .content = .{ .text = "Confidential" },
            .font = .helvetica_oblique,
            .font_size = 9,
            .color = zpdf.rgb(180, 0, 0),
        },
    };

    doc.setHeader(.{
        .elements = &header_elements,
        .separator_line = true,
        .separator_color = zpdf.rgb(0, 51, 102),
        .separator_width = 0.75,
        .skip_first_page = true,
    });

    // Footer: center="Page X of Y"
    // Skip first page (title page)
    const footer_elements = [_]zpdf.HFElement{
        .{
            .position = .center,
            .content = .page_x_of_y,
            .font = .helvetica,
            .font_size = 9,
            .color = .{ .named = .gray },
        },
    };

    doc.setFooter(.{
        .elements = &footer_elements,
        .separator_line = true,
        .separator_color = .{ .named = .light_gray },
        .separator_width = 0.5,
        .skip_first_page = true,
    });

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("headers_footers.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created headers_footers.pdf ({d} bytes)\n", .{bytes.len});
}
