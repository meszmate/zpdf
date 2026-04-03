const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Document = zpdf.Document;
    const PageSize = zpdf.PageSize;
    const color = zpdf.color;
    const tiling = zpdf.tiling_pattern;

    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Tiling Pattern Examples");

    const page = try doc.addPage(PageSize.a4);

    // Register a font for labels
    const helv = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);

    // Title
    try page.drawText("Tiling Pattern Examples", .{
        .x = 72,
        .y = 780,
        .font = .helvetica_bold,
        .font_size = 22,
        .color = color.rgb(0, 0, 0),
    });

    // -- 1. Horizontal Stripes --
    const stripe_pat = try tiling.stripes(allocator, color.rgb(0, 0, 200), color.rgb(230, 230, 255), 4.0, 4.0);
    defer allocator.free(stripe_pat.content);

    const stripe_ref = try tiling.buildTilingPattern(allocator, &doc.object_store, stripe_pat);
    const stripe_name = try page.addPattern("stripes", stripe_ref);

    try page.setPatternFill(stripe_name);
    try page.drawRect(.{ .x = 72, .y = 640, .width = 180, .height = 80 });

    try page.drawText("Horizontal Stripes", .{
        .x = 72, .y = 625,
        .font = .helvetica_bold, .font_size = 10,
        .color = color.rgb(80, 80, 80),
    });

    // -- 2. Dots --
    const dot_pat = try tiling.dots(allocator, color.rgb(200, 0, 0), color.rgb(255, 240, 240), 3.0, 14.0);
    defer allocator.free(dot_pat.content);

    const dot_ref = try tiling.buildTilingPattern(allocator, &doc.object_store, dot_pat);
    const dot_name = try page.addPattern("dots", dot_ref);

    try page.setPatternFill(dot_name);
    try page.drawRect(.{ .x = 300, .y = 640, .width = 180, .height = 80 });

    try page.drawText("Polka Dots", .{
        .x = 300, .y = 625,
        .font = .helvetica_bold, .font_size = 10,
        .color = color.rgb(80, 80, 80),
    });

    // -- 3. Grid --
    const grid_pat = try tiling.grid(allocator, color.rgb(100, 100, 100), color.rgb(245, 245, 245), 1.0, 16.0);
    defer allocator.free(grid_pat.content);

    const grid_ref = try tiling.buildTilingPattern(allocator, &doc.object_store, grid_pat);
    const grid_name = try page.addPattern("grid", grid_ref);

    try page.setPatternFill(grid_name);
    try page.drawRect(.{ .x = 72, .y = 480, .width = 180, .height = 80 });

    try page.drawText("Grid", .{
        .x = 72, .y = 465,
        .font = .helvetica_bold, .font_size = 10,
        .color = color.rgb(80, 80, 80),
    });

    // -- 4. Checkerboard --
    const check_pat = try tiling.checkerboard(allocator, color.rgb(0, 0, 0), color.rgb(255, 255, 255), 8.0);
    defer allocator.free(check_pat.content);

    const check_ref = try tiling.buildTilingPattern(allocator, &doc.object_store, check_pat);
    const check_name = try page.addPattern("checker", check_ref);

    try page.setPatternFill(check_name);
    try page.drawRect(.{ .x = 300, .y = 480, .width = 180, .height = 80 });

    try page.drawText("Checkerboard", .{
        .x = 300, .y = 465,
        .font = .helvetica_bold, .font_size = 10,
        .color = color.rgb(80, 80, 80),
    });

    // -- 5. Diagonal Stripes --
    const diag_pat = try tiling.diagonalStripes(allocator, color.rgb(0, 128, 0), color.rgb(220, 255, 220), 4.0, 8.0);
    defer allocator.free(diag_pat.content);

    const diag_ref = try tiling.buildTilingPattern(allocator, &doc.object_store, diag_pat);
    const diag_name = try page.addPattern("diagonal", diag_ref);

    try page.setPatternFill(diag_name);
    try page.drawRect(.{ .x = 72, .y = 320, .width = 180, .height = 80 });

    try page.drawText("Diagonal Stripes", .{
        .x = 72, .y = 305,
        .font = .helvetica_bold, .font_size = 10,
        .color = color.rgb(80, 80, 80),
    });

    // -- 6. Custom pattern using PatternBuilder --
    var pb = zpdf.TilingPatternBuilder.init(allocator);
    defer pb.deinit();

    // Draw a small star-like cross pattern
    try pb.setFillColor(color.rgb(180, 0, 180));
    try pb.rect(4, 0, 4, 12);
    try pb.fill();
    try pb.rect(0, 4, 12, 4);
    try pb.fill();

    const custom_content = try allocator.dupe(u8, pb.getContent());
    defer allocator.free(custom_content);

    const custom_pat = zpdf.TilingPattern{
        .bbox_width = 12,
        .bbox_height = 12,
        .x_step = 14,
        .y_step = 14,
        .content = custom_content,
    };

    const custom_ref = try tiling.buildTilingPattern(allocator, &doc.object_store, custom_pat);
    const custom_name = try page.addPattern("custom", custom_ref);

    try page.setPatternFill(custom_name);
    try page.drawRect(.{ .x = 300, .y = 320, .width = 180, .height = 80 });

    try page.drawText("Custom (Cross)", .{
        .x = 300, .y = 305,
        .font = .helvetica_bold, .font_size = 10,
        .color = color.rgb(80, 80, 80),
    });

    // Save to file
    const pdf_bytes = try doc.save(allocator);
    defer allocator.free(pdf_bytes);

    const file = try std.fs.cwd().createFile("tiling_patterns.pdf", .{});
    defer file.close();
    try file.writeAll(pdf_bytes);

    std.debug.print("Created tiling_patterns.pdf\n", .{});
}
