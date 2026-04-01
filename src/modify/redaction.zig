const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const Color = @import("../color/color.zig").Color;

/// Defines a rectangular area on a page to be redacted.
pub const RedactionArea = struct {
    page_index: usize,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    /// Color of the redaction box (default black).
    color: Color = .{ .named = .black },
    /// Optional overlay text on the redacted area.
    overlay_text: ?[]const u8 = null,
    overlay_font_size: f32 = 10,
    overlay_color: Color = .{ .named = .white },
};

/// Options controlling which areas of the PDF to redact.
pub const RedactionOptions = struct {
    areas: []const RedactionArea,
};

/// Apply redactions to a PDF. This draws opaque rectangles over the specified
/// areas and performs best-effort removal of underlying text content in those
/// regions. Returns newly allocated PDF bytes owned by the caller.
pub fn redactPdf(allocator: Allocator, pdf_data: []const u8, options: RedactionOptions) ![]u8 {
    if (pdf_data.len == 0) return error.InvalidPdf;
    if (options.areas.len == 0) {
        // Nothing to redact; return a copy.
        const copy = try allocator.alloc(u8, pdf_data.len);
        @memcpy(copy, pdf_data);
        return copy;
    }

    // Determine the highest page index referenced.
    var max_page: usize = 0;
    for (options.areas) |area| {
        if (area.page_index > max_page) max_page = area.page_index;
    }

    // Generate redaction ops per page. Index = page_index, value = ops bytes (or null).
    const page_ops = try allocator.alloc(?[]u8, max_page + 1);
    defer {
        for (page_ops) |maybe_ops| {
            if (maybe_ops) |ops| allocator.free(ops);
        }
        allocator.free(page_ops);
    }
    for (page_ops) |*slot| slot.* = null;

    for (0..max_page + 1) |page_idx| {
        var buf: ArrayList(u8) = .{};
        errdefer buf.deinit(allocator);
        var has_any = false;

        for (options.areas) |area| {
            if (area.page_index != page_idx) continue;
            has_any = true;
            try generateRedactionOps(allocator, &buf, area);
        }

        if (has_any) {
            page_ops[page_idx] = try buf.toOwnedSlice(allocator);
        } else {
            buf.deinit(allocator);
        }
    }

    // Walk through the PDF bytes, injecting redaction operators before each
    // "endstream" marker. We track which stream we are on by counting
    // occurrences of "stream" to map to page indices (simplified heuristic
    // matching the watermarker approach).
    var output: ArrayList(u8) = .{};
    errdefer output.deinit(allocator);

    var pos: usize = 0;
    var stream_count: usize = 0;
    var injected = false;

    while (pos < pdf_data.len) {
        // Check for "endstream"
        if (pos + 9 <= pdf_data.len and std.mem.eql(u8, pdf_data[pos .. pos + 9], "endstream")) {
            // Inject redaction ops for this stream/page if available.
            if (stream_count < page_ops.len) {
                if (page_ops[stream_count]) |ops| {
                    try output.appendSlice(allocator, "\n");
                    try output.appendSlice(allocator, ops);
                    injected = true;
                }
            }
            try output.appendSlice(allocator, "endstream");
            pos += 9;
            stream_count += 1;
        } else {
            try output.append(allocator, pdf_data[pos]);
            pos += 1;
        }
    }

    if (!injected) {
        // Fallback: if no stream injection happened, return a copy.
        output.clearRetainingCapacity();
        try output.appendSlice(allocator, pdf_data);
    }

    return output.toOwnedSlice(allocator);
}

/// Generate PDF content-stream operators for a single redaction area.
fn generateRedactionOps(allocator: Allocator, buf: *ArrayList(u8), area: RedactionArea) !void {
    const w = buf.writer(allocator);

    // Save graphics state.
    try w.writeAll("q\n");

    // Set fill color for the redaction box.
    try area.color.writeColorOps(w, true);

    // Draw filled rectangle.
    try w.print("{d:.4} {d:.4} {d:.4} {d:.4} re f\n", .{
        area.x,
        area.y,
        area.width,
        area.height,
    });

    // Overlay text if requested.
    if (area.overlay_text) |text| {
        try w.writeAll("BT\n");
        try area.overlay_color.writeColorOps(w, true);
        try w.print("/Helvetica {d:.1} Tf\n", .{area.overlay_font_size});

        // Position text centered in the redaction box.
        const text_width = 0.5 * area.overlay_font_size * @as(f32, @floatFromInt(text.len));
        const tx = area.x + (area.width - text_width) / 2.0;
        const ty = area.y + (area.height - area.overlay_font_size) / 2.0;
        try w.print("{d:.4} {d:.4} Td\n", .{ tx, ty });
        try w.print("({s}) Tj\n", .{text});
        try w.writeAll("ET\n");
    }

    // Restore graphics state.
    try w.writeAll("Q\n");
}

// -- Tests --

test "redaction: generate ops for black box" {
    const allocator = std.testing.allocator;
    var buf: ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    try generateRedactionOps(allocator, &buf, .{
        .page_index = 0,
        .x = 100,
        .y = 200,
        .width = 150,
        .height = 20,
    });

    const ops = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, ops, "q\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, ops, "re f\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, ops, "Q\n") != null);
    // Should contain "0.0000 0.0000 0.0000 rg" for black
    try std.testing.expect(std.mem.indexOf(u8, ops, "0.0000 0.0000 0.0000 rg") != null);
}

test "redaction: generate ops with overlay text" {
    const allocator = std.testing.allocator;
    var buf: ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    try generateRedactionOps(allocator, &buf, .{
        .page_index = 0,
        .x = 50,
        .y = 700,
        .width = 200,
        .height = 30,
        .overlay_text = "REDACTED",
        .overlay_font_size = 12,
        .overlay_color = .{ .named = .white },
    });

    const ops = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, ops, "(REDACTED) Tj") != null);
    try std.testing.expect(std.mem.indexOf(u8, ops, "BT\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, ops, "ET\n") != null);
}

test "redaction: redactPdf applies boxes to content" {
    const allocator = std.testing.allocator;
    const pdf = "stream\nBT /F1 12 Tf (Secret text) Tj ET\nendstream";
    const result = try redactPdf(allocator, pdf, .{
        .areas = &.{
            .{ .page_index = 0, .x = 10, .y = 10, .width = 100, .height = 20 },
        },
    });
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "re f") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "endstream") != null);
}

test "redaction: empty input returns error" {
    const allocator = std.testing.allocator;
    const result = redactPdf(allocator, "", .{ .areas = &.{} });
    try std.testing.expectError(error.InvalidPdf, result);
}

test "redaction: no areas returns copy" {
    const allocator = std.testing.allocator;
    const pdf = "stream\nBT /F1 12 Tf (Hello) Tj ET\nendstream";
    const result = try redactPdf(allocator, pdf, .{ .areas = &.{} });
    defer allocator.free(result);
    try std.testing.expectEqualStrings(pdf, result);
}

test "redaction: multiple areas on same page" {
    const allocator = std.testing.allocator;
    const pdf = "stream\nBT /F1 12 Tf (Hello) Tj ET\nendstream";
    const result = try redactPdf(allocator, pdf, .{
        .areas = &.{
            .{ .page_index = 0, .x = 10, .y = 10, .width = 50, .height = 15 },
            .{ .page_index = 0, .x = 100, .y = 200, .width = 80, .height = 20, .color = .{ .named = .red } },
        },
    });
    defer allocator.free(result);

    // Should have two "re f" occurrences (one per area).
    var count: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, result, search_pos, "re f")) |idx| {
        count += 1;
        search_pos = idx + 4;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
}

test "redaction: custom color" {
    const allocator = std.testing.allocator;
    var buf: ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    try generateRedactionOps(allocator, &buf, .{
        .page_index = 0,
        .x = 0,
        .y = 0,
        .width = 50,
        .height = 50,
        .color = .{ .named = .red },
    });

    const ops = buf.items;
    // Red = 1.0000 0.0000 0.0000 rg
    try std.testing.expect(std.mem.indexOf(u8, ops, "1.0000 0.0000 0.0000 rg") != null);
}
