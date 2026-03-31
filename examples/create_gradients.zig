const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Document = zpdf.Document;
    const PageSize = zpdf.PageSize;
    const color = zpdf.color;
    const gradient = zpdf.gradient;
    const ColorStop = zpdf.ColorStop;

    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Gradient Examples");

    const page = try doc.addPage(PageSize.a4);

    // Register a font for labels
    const helv = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);

    // Title
    try page.drawText("Gradient Fill Examples", .{
        .x = 72,
        .y = 780,
        .font = .helvetica_bold,
        .font_size = 22,
        .color = color.rgb(0, 0, 0),
    });

    // -- 1. Linear gradient: blue to red --
    const linear_stops = [_]ColorStop{
        .{ .offset = 0.0, .color = color.rgb(0, 0, 255) },
        .{ .offset = 1.0, .color = color.rgb(255, 0, 0) },
    };
    const linear_ref = try gradient.buildLinearGradient(allocator, &doc.object_store, .{
        .x0 = 72,
        .y0 = 650,
        .x1 = 272,
        .y1 = 650,
        .stops = &linear_stops,
        .extend_start = true,
        .extend_end = true,
    });

    const p1_name = try page.addPattern("linear1", linear_ref);

    // Draw a rectangle and fill it with the linear gradient
    try page.setGradientFill(p1_name);
    try page.drawRect(.{
        .x = 72,
        .y = 620,
        .width = 200,
        .height = 80,
    });

    try page.drawText("Linear Gradient (Blue to Red)", .{
        .x = 72,
        .y = 605,
        .font = .helvetica_bold,
        .font_size = 10,
        .color = color.rgb(80, 80, 80),
    });

    // -- 2. Radial gradient --
    const radial_stops = [_]ColorStop{
        .{ .offset = 0.0, .color = color.rgb(255, 255, 255) },
        .{ .offset = 1.0, .color = color.rgb(0, 100, 200) },
    };
    const radial_ref = try gradient.buildRadialGradient(allocator, &doc.object_store, .{
        .cx0 = 430,
        .cy0 = 660,
        .r0 = 0,
        .cx1 = 430,
        .cy1 = 660,
        .r1 = 60,
        .stops = &radial_stops,
        .extend_start = true,
        .extend_end = true,
    });

    const p2_name = try page.addPattern("radial1", radial_ref);

    try page.setGradientFill(p2_name);
    try page.drawRect(.{
        .x = 360,
        .y = 620,
        .width = 140,
        .height = 80,
    });

    try page.drawText("Radial Gradient", .{
        .x = 390,
        .y = 605,
        .font = .helvetica_bold,
        .font_size = 10,
        .color = color.rgb(80, 80, 80),
    });

    // -- 3. Multi-stop gradient (rainbow-like) --
    const rainbow_stops = [_]ColorStop{
        .{ .offset = 0.0, .color = color.rgb(255, 0, 0) },
        .{ .offset = 0.17, .color = color.rgb(255, 127, 0) },
        .{ .offset = 0.33, .color = color.rgb(255, 255, 0) },
        .{ .offset = 0.5, .color = color.rgb(0, 255, 0) },
        .{ .offset = 0.67, .color = color.rgb(0, 0, 255) },
        .{ .offset = 0.83, .color = color.rgb(75, 0, 130) },
        .{ .offset = 1.0, .color = color.rgb(148, 0, 211) },
    };
    const rainbow_ref = try gradient.buildLinearGradient(allocator, &doc.object_store, .{
        .x0 = 72,
        .y0 = 500,
        .x1 = 522,
        .y1 = 500,
        .stops = &rainbow_stops,
        .extend_start = false,
        .extend_end = false,
    });

    const p3_name = try page.addPattern("rainbow", rainbow_ref);

    try page.setGradientFill(p3_name);
    try page.drawRect(.{
        .x = 72,
        .y = 460,
        .width = 450,
        .height = 80,
    });

    try page.drawText("Multi-Stop Gradient (Rainbow)", .{
        .x = 72,
        .y = 445,
        .font = .helvetica_bold,
        .font_size = 10,
        .color = color.rgb(80, 80, 80),
    });

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("gradients.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created gradients.pdf ({d} bytes)\n", .{bytes.len});
}
