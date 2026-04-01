const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var doc = zpdf.Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Multi-Column Layout Example");
    doc.setAuthor("zpdf");

    const helv = try doc.getStandardFont(.helvetica);
    const helv_bold = try doc.getStandardFont(.helvetica_bold);

    // -- Page 1: Two-column newspaper layout --
    {
        const page = try doc.addPage(zpdf.PageSize.a4);
        _ = try page.addFont(helv.font.pdfName(), helv.ref);
        _ = try page.addFont(helv_bold.font.pdfName(), helv_bold.ref);

        // Title
        try page.drawText("The Daily Zig", .{
            .x = 150,
            .y = 780,
            .font = .helvetica_bold,
            .font_size = 30,
            .color = zpdf.rgb(0, 51, 102),
        });

        // Separator line
        try page.drawLine(.{
            .x1 = 50,
            .y1 = 770,
            .x2 = 545,
            .y2 = 770,
            .color = zpdf.rgb(0, 51, 102),
            .line_width = 2,
        });

        // Two-column article
        const article =
            "In a major advancement for systems programming, the Zig programming language " ++
            "continues to gain traction among developers who value simplicity and performance. " ++
            "The language, designed by Andrew Kelley, offers a unique approach to low-level " ++
            "programming that eliminates many of the pitfalls found in C and C++. " ++
            "One of the key features that sets Zig apart is its comptime evaluation system, " ++
            "which allows developers to run arbitrary code at compile time. This powerful " ++
            "mechanism enables generic programming without the complexity of templates or macros. " ++
            "The standard library provides robust cross-platform support, making it an excellent " ++
            "choice for building portable applications and libraries. " ++
            "Community adoption has been growing steadily, with several high-profile projects " ++
            "choosing Zig for their implementation. The build system, which is integrated " ++
            "directly into the language, simplifies dependency management and cross-compilation. " ++
            "As the ecosystem matures, more tools and libraries become available, creating a " ++
            "positive feedback loop that attracts even more developers to the platform.";

        _ = try page.drawColumns(.{
            .num_columns = 2,
            .column_gap = 25,
            .x = 50,
            .y = 740,
            .width = 495,
            .max_height = 350,
        }, .{ .text = .{
            .text = article,
            .font = .helvetica,
            .font_size = 11,
            .line_height = 14,
            .color = zpdf.grayscale(30),
        } });

        // Section header for bottom half
        try page.drawText("Technical Highlights", .{
            .x = 50,
            .y = 370,
            .font = .helvetica_bold,
            .font_size = 16,
            .color = zpdf.rgb(0, 51, 102),
        });

        const tech_text =
            "Memory safety without garbage collection is achieved through careful " ++
            "ownership semantics and optional pointer types. The allocator interface " ++
            "gives programmers explicit control over memory allocation strategies. " ++
            "Error handling uses a return-based approach with errdefer for cleanup, " ++
            "avoiding the overhead and complexity of exceptions. Async/await support " ++
            "enables efficient concurrent programming without callback complexity.";

        _ = try page.drawColumns(.{
            .num_columns = 2,
            .column_gap = 25,
            .x = 50,
            .y = 350,
            .width = 495,
            .max_height = 200,
        }, .{ .text = .{
            .text = tech_text,
            .font = .helvetica,
            .font_size = 10,
            .line_height = 13,
            .color = zpdf.grayscale(40),
        } });
    }

    // -- Page 2: Three-column layout --
    {
        const page = try doc.addPage(zpdf.PageSize.a4);
        _ = try page.addFont(helv.font.pdfName(), helv.ref);
        _ = try page.addFont(helv_bold.font.pdfName(), helv_bold.ref);

        try page.drawText("Three-Column Layout", .{
            .x = 160,
            .y = 780,
            .font = .helvetica_bold,
            .font_size = 22,
            .color = zpdf.rgb(0, 0, 0),
        });

        const content =
            "This page demonstrates a three-column layout, commonly used in magazines, " ++
            "brochures, and newsletters. The text flows naturally from one column to the " ++
            "next, filling each column before moving on. " ++
            "Multi-column layouts improve readability for large blocks of text by keeping " ++
            "line lengths short. Studies show that optimal line length for reading is " ++
            "between 50 and 75 characters. By splitting a wide page into multiple narrower " ++
            "columns, we achieve better readability without reducing the font size. " ++
            "The zpdf library makes it simple to create these layouts programmatically. " ++
            "You specify the number of columns, the gap between them, and the content " ++
            "area dimensions. The library handles all the text wrapping and positioning " ++
            "automatically. This is useful for generating reports, newsletters, and other " ++
            "documents that benefit from a professional multi-column appearance.";

        _ = try page.drawColumns(.{
            .num_columns = 3,
            .column_gap = 20,
            .x = 50,
            .y = 740,
            .width = 495,
            .max_height = 500,
        }, .{ .text = .{
            .text = content,
            .font = .helvetica,
            .font_size = 10,
            .line_height = 13,
            .color = zpdf.grayscale(20),
        } });
    }

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("multi_column.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);
}
