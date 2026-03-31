const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Document = zpdf.Document;
    const PageSize = zpdf.PageSize;
    const Point = zpdf.document.page.Point;
    const PathBuilder = zpdf.PathBuilder;
    const color = zpdf.color;

    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Graphics Example");
    const page = try doc.addPage(PageSize.a4);

    const helv = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);

    // Title
    try page.drawText("Shape Gallery", .{
        .x = 72,
        .y = 780,
        .font = .helvetica_bold,
        .font_size = 22,
        .color = color.rgb(0, 0, 0),
    });

    // Filled rectangle
    try page.drawRect(.{
        .x = 72,
        .y = 680,
        .width = 120,
        .height = 70,
        .color = color.rgb(65, 105, 225),
        .border_color = color.rgb(0, 0, 139),
        .border_width = 2.0,
    });
    try label(page, "Rectangle", 92, 665);

    // Rounded rectangle
    try page.drawRect(.{
        .x = 220,
        .y = 680,
        .width = 120,
        .height = 70,
        .color = color.rgb(255, 165, 0),
        .border_color = color.rgb(200, 120, 0),
        .border_width = 1.5,
        .corner_radius = 12,
    });
    try label(page, "Rounded Rect", 235, 665);

    // Circle
    try page.drawCircle(.{
        .cx = 440,
        .cy = 715,
        .r = 35,
        .color = color.rgb(220, 20, 60),
        .border_color = color.rgb(139, 0, 0),
        .border_width = 2.0,
    });
    try label(page, "Circle", 420, 665);

    // Ellipse
    try page.drawEllipse(.{
        .cx = 132,
        .cy = 590,
        .rx = 60,
        .ry = 30,
        .color = color.rgb(50, 205, 50),
        .border_color = color.rgb(0, 100, 0),
        .border_width = 1.5,
    });
    try label(page, "Ellipse", 107, 545);

    // Lines with different styles
    try page.drawLine(.{
        .x1 = 220,
        .y1 = 620,
        .x2 = 340,
        .y2 = 560,
        .color = color.rgb(0, 0, 0),
        .line_width = 2.0,
    });
    try page.drawLine(.{
        .x1 = 220,
        .y1 = 600,
        .x2 = 340,
        .y2 = 600,
        .color = color.rgb(128, 0, 128),
        .line_width = 1.0,
        .dash_pattern = &[_]f32{ 6, 3 },
    });
    try label(page, "Lines", 260, 545);

    // Polygon (triangle)
    const triangle = [_]Point{
        .{ .x = 400, .y = 560 },
        .{ .x = 480, .y = 560 },
        .{ .x = 440, .y = 625 },
    };
    try page.drawPolygon(.{
        .points = &triangle,
        .color = color.rgb(255, 215, 0),
        .border_color = color.rgb(184, 134, 11),
        .border_width = 2.0,
    });
    try label(page, "Polygon", 415, 545);

    // Custom path (star shape using PathBuilder)
    var path = PathBuilder.init(allocator);
    defer path.deinit();
    try path.moveTo(132, 480);
    try path.lineTo(145, 440);
    try path.lineTo(180, 440);
    try path.lineTo(152, 415);
    try path.lineTo(165, 375);
    try path.lineTo(132, 400);
    try path.lineTo(99, 375);
    try path.lineTo(112, 415);
    try path.lineTo(84, 440);
    try path.lineTo(119, 440);
    try path.closePath();

    try page.drawPath(&path, .{
        .color = color.rgb(138, 43, 226),
        .border_color = color.rgb(75, 0, 130),
        .border_width = 1.5,
    });
    try label(page, "Custom Path", 97, 360);

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("graphics.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created graphics.pdf ({d} bytes)\n", .{bytes.len});
}

fn label(page: *zpdf.Page, text: []const u8, x: f32, y: f32) !void {
    try page.drawText(text, .{
        .x = x,
        .y = y,
        .font = .helvetica,
        .font_size = 9,
        .color = zpdf.color.rgb(80, 80, 80),
    });
}
