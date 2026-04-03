const std = @import("std");
const zpdf = @import("zpdf");
const Report = zpdf.Report;

test "report basic generation" {
    var report = Report.init(std.testing.allocator, .{
        .title = "Basic Report",
        .auto_number_sections = false,
    });
    defer report.deinit();

    try report.addSection("Overview", "A brief overview.", 0);

    const bytes = try report.generate(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    try std.testing.expect(bytes.len > 100);
    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-"));
}

test "report with numbering" {
    var report = Report.init(std.testing.allocator, .{
        .title = "Numbered Report",
        .auto_number_sections = true,
    });
    defer report.deinit();

    try report.addSection("First", "Content.", 0);
    try report.addSection("Nested", "Sub content.", 1);
    try report.addSection("Second", "More content.", 0);

    const bytes = try report.generate(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    try std.testing.expect(bytes.len > 100);
}

test "report with toc and headers footers" {
    var report = Report.init(std.testing.allocator, .{
        .title = "Full Report",
        .include_toc = true,
        .header_text = "Report Header",
        .footer_text = "Page {page} of {total}",
    });
    defer report.deinit();

    try report.addSection("Alpha", "Alpha body.", 0);
    try report.addSection("Beta", "Beta body.", 0);
    try report.addParagraph("A closing paragraph.");

    const bytes = try report.generate(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    try std.testing.expect(bytes.len > 100);
}

test "report empty" {
    var report = Report.init(std.testing.allocator, .{});
    defer report.deinit();

    const bytes = try report.generate(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    // Even with no content, should produce a valid single-page PDF
    try std.testing.expect(bytes.len > 50);
    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-"));
}

test "report page breaks" {
    var report = Report.init(std.testing.allocator, .{});
    defer report.deinit();

    try report.addParagraph("Page one content.");
    try report.addPageBreak();
    try report.addParagraph("Page two content.");

    const bytes = try report.generate(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    try std.testing.expect(bytes.len > 100);
}
