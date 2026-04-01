const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Document = zpdf.Document;
    const PageSize = zpdf.PageSize;
    const color = zpdf.color;
    const soft_mask = zpdf.soft_mask;

    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Soft Mask Examples");

    const page = try doc.addPage(PageSize.a4);

    // Register a font for labels
    const helv = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);

    // Title
    try page.drawText("Soft Mask (Alpha Masking) Examples", .{
        .x = 72,
        .y = 780,
        .font = .helvetica_bold,
        .font_size = 20,
        .color = color.rgb(0, 0, 0),
    });

    // -- 1. Horizontal gradient fade (left to right) --
    try page.drawText("1. Horizontal Fade (Left to Right)", .{
        .x = 72,
        .y = 740,
        .font = .helvetica_bold,
        .font_size = 12,
        .color = color.rgb(80, 80, 80),
    });

    const fade_h = try soft_mask.buildSoftMask(allocator, &doc.object_store, .{
        .mask_type = .luminosity,
        .gradient_mask = .{
            .x0 = 72,
            .y0 = 680,
            .x1 = 300,
            .y1 = 680,
            .start_opacity = 1.0,
            .end_opacity = 0.0,
        },
    }, .{
        .x = 72,
        .y = 640,
        .width = 228,
        .height = 80,
    });

    try page.setSoftMask(fade_h.ext_g_state_ref);
    try page.drawRect(.{
        .x = 72,
        .y = 640,
        .width = 228,
        .height = 80,
        .color = color.rgb(0, 102, 204),
    });

    // Clear soft mask before next drawing
    const clear1 = try soft_mask.buildClearSoftMask(allocator, &doc.object_store);
    try page.clearSoftMask(clear1);

    // -- 2. Vertical gradient fade (top to bottom) --
    try page.drawText("2. Vertical Fade (Top to Bottom)", .{
        .x = 72,
        .y = 620,
        .font = .helvetica_bold,
        .font_size = 12,
        .color = color.rgb(80, 80, 80),
    });

    const fade_v = try soft_mask.buildSoftMask(allocator, &doc.object_store, .{
        .mask_type = .luminosity,
        .gradient_mask = .{
            .x0 = 200,
            .y0 = 600,
            .x1 = 200,
            .y1 = 520,
            .start_opacity = 1.0,
            .end_opacity = 0.0,
        },
    }, .{
        .x = 72,
        .y = 520,
        .width = 228,
        .height = 80,
    });

    try page.setSoftMask(fade_v.ext_g_state_ref);
    try page.drawRect(.{
        .x = 72,
        .y = 520,
        .width = 228,
        .height = 80,
        .color = color.rgb(204, 51, 0),
    });

    const clear2 = try soft_mask.buildClearSoftMask(allocator, &doc.object_store);
    try page.clearSoftMask(clear2);

    // -- 3. Partial opacity fade --
    try page.drawText("3. Partial Opacity Fade (80% to 20%)", .{
        .x = 72,
        .y = 500,
        .font = .helvetica_bold,
        .font_size = 12,
        .color = color.rgb(80, 80, 80),
    });

    const fade_partial = try soft_mask.buildSoftMask(allocator, &doc.object_store, .{
        .mask_type = .luminosity,
        .gradient_mask = .{
            .x0 = 72,
            .y0 = 440,
            .x1 = 300,
            .y1 = 440,
            .start_opacity = 0.8,
            .end_opacity = 0.2,
        },
    }, .{
        .x = 72,
        .y = 400,
        .width = 228,
        .height = 80,
    });

    try page.setSoftMask(fade_partial.ext_g_state_ref);
    try page.drawRect(.{
        .x = 72,
        .y = 400,
        .width = 228,
        .height = 80,
        .color = color.rgb(0, 153, 76),
    });

    const clear3 = try soft_mask.buildClearSoftMask(allocator, &doc.object_store);
    try page.clearSoftMask(clear3);

    // -- 4. Diagonal gradient fade --
    try page.drawText("4. Diagonal Fade", .{
        .x = 72,
        .y = 380,
        .font = .helvetica_bold,
        .font_size = 12,
        .color = color.rgb(80, 80, 80),
    });

    const fade_diag = try soft_mask.buildSoftMask(allocator, &doc.object_store, .{
        .mask_type = .luminosity,
        .gradient_mask = .{
            .x0 = 72,
            .y0 = 360,
            .x1 = 300,
            .y1 = 280,
            .start_opacity = 1.0,
            .end_opacity = 0.0,
        },
    }, .{
        .x = 72,
        .y = 280,
        .width = 228,
        .height = 80,
    });

    try page.setSoftMask(fade_diag.ext_g_state_ref);
    try page.drawRect(.{
        .x = 72,
        .y = 280,
        .width = 228,
        .height = 80,
        .color = color.rgb(153, 51, 204),
    });

    const clear4 = try soft_mask.buildClearSoftMask(allocator, &doc.object_store);
    try page.clearSoftMask(clear4);

    // -- 5. Side-by-side: without and with soft mask --
    try page.drawText("5. Comparison: Solid vs Soft-Masked", .{
        .x = 72,
        .y = 260,
        .font = .helvetica_bold,
        .font_size = 12,
        .color = color.rgb(80, 80, 80),
    });

    // Solid rectangle (no mask)
    try page.drawRect(.{
        .x = 72,
        .y = 170,
        .width = 150,
        .height = 70,
        .color = color.rgb(255, 165, 0),
    });

    // Masked rectangle
    const fade_compare = try soft_mask.buildSoftMask(allocator, &doc.object_store, .{
        .mask_type = .luminosity,
        .gradient_mask = .{
            .x0 = 250,
            .y0 = 200,
            .x1 = 450,
            .y1 = 200,
            .start_opacity = 1.0,
            .end_opacity = 0.0,
        },
    }, .{
        .x = 250,
        .y = 170,
        .width = 200,
        .height = 70,
    });

    try page.setSoftMask(fade_compare.ext_g_state_ref);
    try page.drawRect(.{
        .x = 250,
        .y = 170,
        .width = 200,
        .height = 70,
        .color = color.rgb(255, 165, 0),
    });

    const clear5 = try soft_mask.buildClearSoftMask(allocator, &doc.object_store);
    try page.clearSoftMask(clear5);

    try page.drawText("Solid", .{
        .x = 120,
        .y = 155,
        .font = .helvetica_bold,
        .font_size = 10,
        .color = color.rgb(80, 80, 80),
    });

    try page.drawText("With Soft Mask", .{
        .x = 310,
        .y = 155,
        .font = .helvetica_bold,
        .font_size = 10,
        .color = color.rgb(80, 80, 80),
    });

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("soft_masks.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created soft_masks.pdf ({d} bytes)\n", .{bytes.len});
}
