const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Document = zpdf.Document;
    const PageSize = zpdf.PageSize;
    const PathBuilder = zpdf.PathBuilder;
    const color = zpdf.color;

    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Clipping Paths Example");
    const page = try doc.addPage(PageSize.a4);

    const helv = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);

    const helv_reg = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(helv_reg.font.pdfName(), helv_reg.ref);

    // Title
    try page.drawText("Clipping Paths Demo", .{
        .x = 72,
        .y = 780,
        .font = .helvetica_bold,
        .font_size = 22,
        .color = color.rgb(0, 0, 0),
    });

    // --- Section 1: Rectangle clip ---
    try page.drawText("1. Rectangle Clip", .{
        .x = 72,
        .y = 740,
        .font = .helvetica_bold,
        .font_size = 14,
        .color = color.rgb(0, 0, 0),
    });

    try page.beginClipRect(72, 640, 200, 80, .non_zero);

    // Draw colorful stripes that extend beyond the clip region
    var i: usize = 0;
    while (i < 15) : (i += 1) {
        const fi: f32 = @floatFromInt(i);
        const r_val: u8 = @intFromFloat(@min(255.0, fi * 17.0));
        const g_val: u8 = @intFromFloat(@min(255.0, 255.0 - fi * 17.0));
        try page.drawRect(.{
            .x = 50 + fi * 20,
            .y = 620,
            .width = 18,
            .height = 120,
            .color = color.rgb(r_val, g_val, 100),
        });
    }

    try page.endClip();

    // --- Section 2: Circle clip ---
    try page.drawText("2. Circle Clip", .{
        .x = 72,
        .y = 610,
        .font = .helvetica_bold,
        .font_size = 14,
        .color = color.rgb(0, 0, 0),
    });

    try page.beginClipCircle(172, 540, 60, .non_zero);

    // Draw a grid of colored squares behind the circle clip
    var row: usize = 0;
    while (row < 8) : (row += 1) {
        var col: usize = 0;
        while (col < 8) : (col += 1) {
            const fr: f32 = @floatFromInt(row);
            const fc: f32 = @floatFromInt(col);
            const r_val: u8 = @intFromFloat(fr * 32.0);
            const g_val: u8 = @intFromFloat(fc * 32.0);
            const b_val: u8 = @intFromFloat(@min(255.0, (fr + fc) * 20.0));
            try page.drawRect(.{
                .x = 100 + fc * 18,
                .y = 470 + fr * 18,
                .width = 17,
                .height = 17,
                .color = color.rgb(r_val, g_val, b_val),
            });
        }
    }

    try page.endClip();

    // --- Section 3: Star clip using PathBuilder ---
    try page.drawText("3. Star Clip (PathBuilder)", .{
        .x = 320,
        .y = 740,
        .font = .helvetica_bold,
        .font_size = 14,
        .color = color.rgb(0, 0, 0),
    });

    // Build a 5-pointed star path
    var star = PathBuilder.init(allocator);
    defer star.deinit();

    const star_cx: f32 = 420;
    const star_cy: f32 = 650;
    const outer_r: f32 = 60;
    const inner_r: f32 = 25;

    var pt: usize = 0;
    while (pt < 10) : (pt += 1) {
        const fpt: f32 = @floatFromInt(pt);
        const angle = fpt * std.math.pi / 5.0 - std.math.pi / 2.0;
        const r_use = if (pt % 2 == 0) outer_r else inner_r;
        const px = star_cx + r_use * @cos(angle);
        const py = star_cy + r_use * @sin(angle);
        if (pt == 0) {
            try star.moveTo(px, py);
        } else {
            try star.lineTo(px, py);
        }
    }
    try star.closePath();

    try page.beginClipPath(&star, .non_zero);

    // Draw a gradient-like background inside the star
    var stripe: usize = 0;
    while (stripe < 20) : (stripe += 1) {
        const fs: f32 = @floatFromInt(stripe);
        const r_val: u8 = @intFromFloat(@min(255.0, fs * 13.0));
        const b_val: u8 = @intFromFloat(@min(255.0, 255.0 - fs * 13.0));
        try page.drawRect(.{
            .x = 350 + fs * 7,
            .y = 580,
            .width = 6,
            .height = 140,
            .color = color.rgb(r_val, 50, b_val),
        });
    }

    try page.endClip();

    // --- Section 4: Nested clipping ---
    try page.drawText("4. Nested Clipping", .{
        .x = 320,
        .y = 560,
        .font = .helvetica_bold,
        .font_size = 14,
        .color = color.rgb(0, 0, 0),
    });

    // Outer clip: rectangle
    try page.beginClipRect(340, 430, 160, 110, .non_zero);
    // Inner clip: circle within the rectangle
    try page.beginClipCircle(420, 485, 50, .non_zero);

    // Draw diagonal lines that are clipped by both
    var line: usize = 0;
    while (line < 25) : (line += 1) {
        const fl: f32 = @floatFromInt(line);
        try page.drawLine(.{
            .x1 = 320 + fl * 8,
            .y1 = 420,
            .x2 = 320 + fl * 8,
            .y2 = 560,
            .color = color.rgb(0, 100, 200),
            .line_width = 3,
        });
    }

    try page.endClip(); // inner circle
    try page.endClip(); // outer rectangle

    // --- Section 5: Even-odd clipping ---
    try page.drawText("5. Even-Odd Clip Mode", .{
        .x = 72,
        .y = 440,
        .font = .helvetica_bold,
        .font_size = 14,
        .color = color.rgb(0, 0, 0),
    });

    try page.beginClipRect(72, 320, 200, 100, .even_odd);

    var j: usize = 0;
    while (j < 12) : (j += 1) {
        const fj: f32 = @floatFromInt(j);
        try page.drawRect(.{
            .x = 60 + fj * 20,
            .y = 310,
            .width = 18,
            .height = 120,
            .color = color.rgb(200, 80, @intFromFloat(@min(255.0, fj * 22.0))),
        });
    }

    try page.endClip();

    const bytes = try doc.save(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("clipping.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created clipping.pdf ({d} bytes)\n", .{bytes.len});
}
