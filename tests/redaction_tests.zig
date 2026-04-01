const std = @import("std");
const zpdf = @import("zpdf");

const redactPdf = zpdf.modify.redaction.redactPdf;
const RedactionArea = zpdf.modify.redaction.RedactionArea;
const RedactionOptions = zpdf.modify.redaction.RedactionOptions;
const Color = zpdf.Color;

test "redaction: draw single black box" {
    const allocator = std.testing.allocator;
    const pdf = "stream\nBT /F1 12 Tf (Sensitive data) Tj ET\nendstream";

    const result = try redactPdf(allocator, pdf, .{
        .areas = &.{
            .{ .page_index = 0, .x = 72, .y = 700, .width = 200, .height = 20 },
        },
    });
    defer allocator.free(result);

    // Output should contain redaction rectangle operators.
    try std.testing.expect(std.mem.indexOf(u8, result, "re f") != null);
    // Should still contain the endstream marker.
    try std.testing.expect(std.mem.indexOf(u8, result, "endstream") != null);
    // Graphics state should be saved and restored.
    try std.testing.expect(std.mem.indexOf(u8, result, "q\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Q\n") != null);
}

test "redaction: overlay text appears in output" {
    const allocator = std.testing.allocator;
    const pdf = "stream\nBT /F1 12 Tf (Secret) Tj ET\nendstream";

    const result = try redactPdf(allocator, pdf, .{
        .areas = &.{
            .{
                .page_index = 0,
                .x = 50,
                .y = 700,
                .width = 200,
                .height = 25,
                .overlay_text = "REDACTED",
                .overlay_font_size = 12,
                .overlay_color = .{ .named = .white },
            },
        },
    });
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "(REDACTED) Tj") != null);
}

test "redaction: multiple areas on different pages" {
    const allocator = std.testing.allocator;
    // Simulate two page streams.
    const pdf = "stream\nBT (Page1) Tj ET\nendstream\nstream\nBT (Page2) Tj ET\nendstream";

    const result = try redactPdf(allocator, pdf, .{
        .areas = &.{
            .{ .page_index = 0, .x = 10, .y = 10, .width = 100, .height = 20 },
            .{ .page_index = 1, .x = 50, .y = 50, .width = 150, .height = 30 },
        },
    });
    defer allocator.free(result);

    // Both redaction boxes should appear.
    var count: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, result, search_pos, "re f")) |idx| {
        count += 1;
        search_pos = idx + 4;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
}

test "redaction: valid PDF structure preserved" {
    const allocator = std.testing.allocator;
    const pdf = "stream\nBT /F1 12 Tf (Hello world) Tj ET\nendstream";

    const result = try redactPdf(allocator, pdf, .{
        .areas = &.{
            .{ .page_index = 0, .x = 0, .y = 0, .width = 50, .height = 15 },
        },
    });
    defer allocator.free(result);

    // The endstream marker must still be present and properly placed.
    try std.testing.expect(std.mem.indexOf(u8, result, "endstream") != null);
    // Original content should still be present (we overlay, not erase at byte level here).
    try std.testing.expect(std.mem.indexOf(u8, result, "Hello world") != null);
}

test "redaction: empty areas returns unchanged copy" {
    const allocator = std.testing.allocator;
    const pdf = "stream\nBT (Hello) Tj ET\nendstream";

    const result = try redactPdf(allocator, pdf, .{ .areas = &.{} });
    defer allocator.free(result);

    try std.testing.expectEqualStrings(pdf, result);
}

test "redaction: custom box color" {
    const allocator = std.testing.allocator;
    const pdf = "stream\nBT (Data) Tj ET\nendstream";

    const result = try redactPdf(allocator, pdf, .{
        .areas = &.{
            .{
                .page_index = 0,
                .x = 10,
                .y = 10,
                .width = 80,
                .height = 20,
                .color = .{ .named = .red },
            },
        },
    });
    defer allocator.free(result);

    // Red fill color should appear.
    try std.testing.expect(std.mem.indexOf(u8, result, "1.0000 0.0000 0.0000 rg") != null);
}
