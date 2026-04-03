const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Document = zpdf.Document;
    const PageSize = zpdf.PageSize;
    const color = zpdf.color;
    const transparency = zpdf.transparency;

    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Transparency and Blend Modes");

    const page = try doc.addPage(PageSize.a4);

    // Register font for labels
    const helv = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);

    // Title
    try page.drawText("Transparency and Blend Mode Examples", .{
        .x = 72,
        .y = 780,
        .font = .helvetica_bold,
        .font_size = 18,
        .color = color.rgb(0, 0, 0),
    });

    // -- 1. Overlapping rectangles with varying opacity --
    try page.drawText("1. Fill Opacity (30%, 50%, 70%)", .{
        .x = 72,
        .y = 740,
        .font = .helvetica_bold,
        .font_size = 12,
        .color = color.rgb(60, 60, 60),
    });

    // Opaque background rect
    try page.drawRect(.{
        .x = 72, .y = 640, .width = 300, .height = 80,
        .color = color.rgb(200, 200, 200),
    });

    // 30% opacity red
    const gs_30 = try transparency.buildTransparencyExtGState(allocator, &doc.object_store, .{
        .fill_opacity = 0.3,
    });
    try page.setTransparency(gs_30);
    try page.drawRect(.{
        .x = 80, .y = 650, .width = 120, .height = 60,
        .color = color.rgb(220, 40, 40),
    });

    // 50% opacity green
    const gs_50 = try transparency.buildTransparencyExtGState(allocator, &doc.object_store, .{
        .fill_opacity = 0.5,
    });
    try page.setTransparency(gs_50);
    try page.drawRect(.{
        .x = 160, .y = 650, .width = 120, .height = 60,
        .color = color.rgb(40, 180, 40),
    });

    // 70% opacity blue
    const gs_70 = try transparency.buildTransparencyExtGState(allocator, &doc.object_store, .{
        .fill_opacity = 0.7,
    });
    try page.setTransparency(gs_70);
    try page.drawRect(.{
        .x = 240, .y = 650, .width = 120, .height = 60,
        .color = color.rgb(40, 40, 220),
    });

    // Reset to full opacity
    const gs_full = try transparency.buildTransparencyExtGState(allocator, &doc.object_store, .{
        .fill_opacity = 1.0,
    });
    try page.setTransparency(gs_full);

    // -- 2. Blend modes with overlapping shapes --
    try page.drawText("2. Blend Modes (Multiply, Screen, Overlay)", .{
        .x = 72,
        .y = 620,
        .font = .helvetica_bold,
        .font_size = 12,
        .color = color.rgb(60, 60, 60),
    });

    // Base yellow rectangle
    try page.drawRect(.{
        .x = 72, .y = 510, .width = 400, .height = 90,
        .color = color.rgb(255, 220, 50),
    });

    // Multiply blend
    const gs_multiply = try transparency.buildTransparencyExtGState(allocator, &doc.object_store, .{
        .fill_opacity = 0.8,
        .blend_mode = .multiply,
    });
    try page.setTransparency(gs_multiply);
    try page.drawRect(.{
        .x = 80, .y = 520, .width = 100, .height = 70,
        .color = color.rgb(100, 100, 200),
    });

    // Screen blend
    const gs_screen = try transparency.buildTransparencyExtGState(allocator, &doc.object_store, .{
        .fill_opacity = 0.8,
        .blend_mode = .screen,
    });
    try page.setTransparency(gs_screen);
    try page.drawRect(.{
        .x = 200, .y = 520, .width = 100, .height = 70,
        .color = color.rgb(100, 100, 200),
    });

    // Overlay blend
    const gs_overlay = try transparency.buildTransparencyExtGState(allocator, &doc.object_store, .{
        .fill_opacity = 0.8,
        .blend_mode = .overlay,
    });
    try page.setTransparency(gs_overlay);
    try page.drawRect(.{
        .x = 320, .y = 520, .width = 100, .height = 70,
        .color = color.rgb(100, 100, 200),
    });

    // Reset
    try page.setTransparency(gs_full);

    // Labels for blend modes
    try page.drawText("Multiply", .{
        .x = 100, .y = 505, .font = .helvetica_bold, .font_size = 9,
        .color = color.rgb(60, 60, 60),
    });
    try page.drawText("Screen", .{
        .x = 225, .y = 505, .font = .helvetica_bold, .font_size = 9,
        .color = color.rgb(60, 60, 60),
    });
    try page.drawText("Overlay", .{
        .x = 345, .y = 505, .font = .helvetica_bold, .font_size = 9,
        .color = color.rgb(60, 60, 60),
    });

    // -- 3. Stroke opacity --
    try page.drawText("3. Stroke Opacity (50%)", .{
        .x = 72,
        .y = 480,
        .font = .helvetica_bold,
        .font_size = 12,
        .color = color.rgb(60, 60, 60),
    });

    const gs_stroke = try transparency.buildTransparencyExtGState(allocator, &doc.object_store, .{
        .stroke_opacity = 0.5,
    });
    try page.setTransparency(gs_stroke);
    try page.drawRect(.{
        .x = 80, .y = 400, .width = 200, .height = 60,
        .border_color = color.rgb(0, 0, 0),
        .border_width = 4.0,
    });

    // Reset
    try page.setTransparency(gs_full);

    // -- 4. Combined: opacity + blend mode --
    try page.drawText("4. Combined: 60% Opacity + Difference Blend", .{
        .x = 72,
        .y = 380,
        .font = .helvetica_bold,
        .font_size = 12,
        .color = color.rgb(60, 60, 60),
    });

    // Background
    try page.drawRect(.{
        .x = 72, .y = 280, .width = 250, .height = 80,
        .color = color.rgb(255, 140, 0),
    });

    const gs_combined = try transparency.buildTransparencyExtGState(allocator, &doc.object_store, .{
        .fill_opacity = 0.6,
        .blend_mode = .difference,
    });
    try page.setTransparency(gs_combined);
    try page.drawRect(.{
        .x = 150, .y = 260, .width = 250, .height = 80,
        .color = color.rgb(0, 150, 255),
    });

    // Reset for clean state
    try page.setTransparency(gs_full);

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("transparency.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created transparency.pdf ({d} bytes)\n", .{bytes.len});
}
