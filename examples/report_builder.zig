const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var report = zpdf.Report.init(allocator, .{
        .title = "Annual Progress Report",
        .author = "zpdf Report Builder",
        .page_size = .a4,
        .auto_number_sections = true,
        .include_toc = true,
        .header_text = "Annual Progress Report",
        .footer_text = "Page {page} of {total}",
    });
    defer report.deinit();

    try report.addSection(
        "Introduction",
        "This report provides an overview of the progress made during the year. " ++
            "It covers key milestones, challenges encountered, and the strategic direction " ++
            "for the upcoming period. The data presented herein has been gathered from " ++
            "multiple departments and reviewed by the executive team.",
        0,
    );

    try report.addSection(
        "Background",
        "The organization was established with the goal of delivering high-quality " ++
            "products and services. Over the past year, significant investments have been " ++
            "made in research and development, resulting in several new product launches.",
        1,
    );

    try report.addSection(
        "Methodology",
        "Data was collected through quarterly surveys, financial reports, and direct " ++
            "interviews with department heads. Statistical analysis was performed using " ++
            "standard methods to ensure accuracy and reliability of the findings.",
        1,
    );

    try report.addPageBreak();

    try report.addSection(
        "Results",
        "The results section presents the key findings from our analysis. Overall " ++
            "performance metrics show a positive trend across all major indicators.",
        0,
    );

    try report.addSection(
        "Financial Performance",
        "Revenue grew by 15% year-over-year, driven primarily by expansion into new " ++
            "markets. Operating margins improved by 3 percentage points due to efficiency " ++
            "gains in the supply chain. Capital expenditures remained within budget.",
        1,
    );

    try report.addSection(
        "Q1 Results",
        "The first quarter saw strong momentum with revenue exceeding targets by 5%. " ++
            "Customer acquisition costs decreased while retention rates improved.",
        2,
    );

    try report.addSection(
        "Q2 Results",
        "The second quarter maintained the positive trajectory with continued growth " ++
            "in all segments. New product introductions contributed significantly.",
        2,
    );

    try report.addParagraph(
        "Additional analysis reveals that the combination of strategic pricing and " ++
            "improved customer service led to higher customer satisfaction scores across " ++
            "all regions. These improvements are expected to have lasting positive effects.",
    );

    try report.addSection(
        "Conclusion",
        "The year has been marked by steady progress toward our strategic goals. " ++
            "The investments made in technology and talent are beginning to yield returns. " ++
            "Looking ahead, we plan to continue building on this foundation while exploring " ++
            "new opportunities for growth and innovation.",
        0,
    );

    const bytes = try report.generate(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("report_builder.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created report_builder.pdf ({d} bytes)\n", .{bytes.len});
}
