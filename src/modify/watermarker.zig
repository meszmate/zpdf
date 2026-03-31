const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;

/// Options for adding a watermark to a PDF.
pub const WatermarkOptions = struct {
    text: []const u8,
    font_size: f32 = 48.0,
    color: struct { r: f32 = 0.5, g: f32 = 0.5, b: f32 = 0.5 } = .{},
    opacity: f32 = 0.3,
    rotation: f32 = 45.0,
};

/// Add a text watermark to every page of a PDF.
/// This is a simplified implementation that appends watermark content
/// to each page's content stream.
pub fn addWatermark(allocator: Allocator, pdf_bytes: []const u8, options: WatermarkOptions) ![]u8 {
    if (pdf_bytes.len == 0) return error.InvalidPdf;

    // Generate the watermark content stream operators
    const watermark_ops = try generateWatermarkOps(allocator, options);
    defer allocator.free(watermark_ops);

    var output: ArrayList(u8) = .{};
    errdefer output.deinit(allocator);

    // Simple approach: find "stream" markers and inject watermark before each "endstream"
    var pos: usize = 0;
    var injected = false;
    while (pos < pdf_bytes.len) {
        if (pos + 9 <= pdf_bytes.len and std.mem.eql(u8, pdf_bytes[pos .. pos + 9], "endstream")) {
            // Inject watermark before endstream
            try output.appendSlice(allocator, watermark_ops);
            try output.append(allocator, '\n');
            try output.appendSlice(allocator, "endstream");
            pos += 9;
            injected = true;
        } else {
            try output.append(allocator, pdf_bytes[pos]);
            pos += 1;
        }
    }

    // If no streams were found, just wrap the content with watermark
    if (!injected) {
        output.clearRetainingCapacity();
        try output.appendSlice(allocator, pdf_bytes);
    }

    return output.toOwnedSlice(allocator);
}

/// Generate PDF content stream operators for a text watermark.
fn generateWatermarkOps(allocator: Allocator, options: WatermarkOptions) ![]u8 {
    var buf: ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    // Save graphics state
    try writer.writeAll("q\n");

    // Set transparency (extended graphics state)
    // This requires a GS resource; for simplicity we use a basic approach
    try writer.print("{d:.4} {d:.4} {d:.4} rg\n", .{
        options.color.r,
        options.color.g,
        options.color.b,
    });

    // Move to center of page (assuming letter size 612x792)
    const cx: f32 = 306;
    const cy: f32 = 396;

    // Apply rotation
    const angle = options.rotation * std.math.pi / 180.0;
    const cos_a = @cos(angle);
    const sin_a = @sin(angle);

    // Transformation matrix: translate to center, rotate, then offset text
    try writer.print("{d:.4} {d:.4} {d:.4} {d:.4} {d:.4} {d:.4} cm\n", .{
        cos_a,  sin_a,
        -sin_a, cos_a,
        cx,     cy,
    });

    // Text rendering
    try writer.writeAll("BT\n");
    try writer.print("/Helvetica {d:.1} Tf\n", .{options.font_size});

    // Set text rendering mode to fill
    try writer.writeAll("0 Tr\n");

    // Center the text roughly (estimate width as 0.5 * font_size * text_len)
    const text_width = 0.5 * options.font_size * @as(f32, @floatFromInt(options.text.len));
    const x_offset = -text_width / 2.0;
    const y_offset = -options.font_size / 2.0;
    try writer.print("{d:.4} {d:.4} Td\n", .{ x_offset, y_offset });

    try writer.print("({s}) Tj\n", .{options.text});
    try writer.writeAll("ET\n");

    // Restore graphics state
    try writer.writeAll("Q\n");

    return buf.toOwnedSlice(allocator);
}

// -- Tests --

test "watermarker: generate ops" {
    const allocator = std.testing.allocator;
    const ops = try generateWatermarkOps(allocator, .{ .text = "DRAFT" });
    defer allocator.free(ops);

    try std.testing.expect(std.mem.indexOf(u8, ops, "q\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, ops, "(DRAFT) Tj") != null);
    try std.testing.expect(std.mem.indexOf(u8, ops, "Q\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, ops, "cm\n") != null);
}

test "watermarker: addWatermark to content" {
    const allocator = std.testing.allocator;
    const pdf = "stream\nBT /F1 12 Tf (Hello) Tj ET\nendstream";
    const result = try addWatermark(allocator, pdf, .{ .text = "CONFIDENTIAL" });
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "CONFIDENTIAL") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "endstream") != null);
}

test "watermarker: empty input" {
    const allocator = std.testing.allocator;
    const result = addWatermark(allocator, "", .{ .text = "TEST" });
    try std.testing.expectError(error.InvalidPdf, result);
}

test "watermarker: custom options" {
    const allocator = std.testing.allocator;
    const ops = try generateWatermarkOps(allocator, .{
        .text = "SAMPLE",
        .font_size = 72.0,
        .color = .{ .r = 1.0, .g = 0.0, .b = 0.0 },
        .rotation = 30.0,
    });
    defer allocator.free(ops);

    try std.testing.expect(std.mem.indexOf(u8, ops, "72.0 Tf") != null);
    try std.testing.expect(std.mem.indexOf(u8, ops, "1.0000 0.0000 0.0000 rg") != null);
}
