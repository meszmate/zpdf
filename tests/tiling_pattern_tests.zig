const std = @import("std");
const zpdf = @import("zpdf");
const tiling_pattern = zpdf.tiling_pattern;
const TilingPattern = zpdf.TilingPattern;
const ObjectStore = zpdf.ObjectStore;
const color = zpdf.color;
const Document = zpdf.Document;
const PageSize = zpdf.PageSize;

test "build tiling pattern creates stream object" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const content = "1 0 0 rg 0 0 10 10 re f";
    const pattern = TilingPattern{
        .bbox_width = 10,
        .bbox_height = 10,
        .x_step = 10,
        .y_step = 10,
        .content = content,
    };

    const ref = try tiling_pattern.buildTilingPattern(allocator, &store, pattern);
    try std.testing.expectEqual(@as(usize, 1), store.count());

    const obj = store.get(ref);
    try std.testing.expect(obj != null);
    try std.testing.expect(obj.?.isStream());
}

test "stripes preset produces valid pattern" {
    const allocator = std.testing.allocator;
    const pat = try tiling_pattern.stripes(allocator, color.rgb(0, 0, 255), color.rgb(255, 255, 255), 5.0, 5.0);
    defer allocator.free(pat.content);

    try std.testing.expectApproxEqAbs(@as(f32, 10.0), pat.bbox_width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), pat.bbox_height, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), pat.x_step, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), pat.y_step, 0.01);
    try std.testing.expect(pat.content.len > 0);
}

test "dots preset produces valid pattern" {
    const allocator = std.testing.allocator;
    const pat = try tiling_pattern.dots(allocator, color.rgb(255, 0, 0), color.rgb(255, 255, 255), 3.0, 12.0);
    defer allocator.free(pat.content);

    try std.testing.expectApproxEqAbs(@as(f32, 12.0), pat.bbox_width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 12.0), pat.x_step, 0.01);
    try std.testing.expect(pat.content.len > 0);
}

test "grid preset produces valid pattern" {
    const allocator = std.testing.allocator;
    const pat = try tiling_pattern.grid(allocator, color.rgb(0, 0, 0), color.rgb(255, 255, 255), 1.0, 20.0);
    defer allocator.free(pat.content);

    try std.testing.expectApproxEqAbs(@as(f32, 20.0), pat.bbox_width, 0.01);
    try std.testing.expect(pat.content.len > 0);
}

test "checkerboard preset produces valid pattern" {
    const allocator = std.testing.allocator;
    const pat = try tiling_pattern.checkerboard(allocator, color.rgb(0, 0, 0), color.rgb(255, 255, 255), 10.0);
    defer allocator.free(pat.content);

    try std.testing.expectApproxEqAbs(@as(f32, 20.0), pat.bbox_width, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), pat.bbox_height, 0.01);
    try std.testing.expect(pat.content.len > 0);
}

test "diagonal stripes preset produces valid pattern" {
    const allocator = std.testing.allocator;
    const pat = try tiling_pattern.diagonalStripes(allocator, color.rgb(255, 0, 0), color.rgb(255, 255, 255), 4.0, 8.0);
    defer allocator.free(pat.content);

    try std.testing.expectApproxEqAbs(@as(f32, 12.0), pat.x_step, 0.01);
    try std.testing.expect(pat.content.len > 0);
}

test "PatternBuilder custom pattern" {
    const allocator = std.testing.allocator;
    var pb = zpdf.TilingPatternBuilder.init(allocator);
    defer pb.deinit();

    try pb.setFillColor(color.rgb(255, 0, 0));
    try pb.rect(0, 0, 10, 10);
    try pb.fill();
    try pb.setStrokeColor(color.rgb(0, 0, 0));
    try pb.setLineWidth(1.0);
    try pb.moveTo(0, 0);
    try pb.lineTo(10, 10);
    try pb.stroke();

    const content = pb.getContent();
    try std.testing.expect(content.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, content, "rg") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "RG") != null);
}

test "tiling pattern integration with page" {
    const allocator = std.testing.allocator;

    var doc = Document.init(allocator);
    defer doc.deinit();

    const page = try doc.addPage(PageSize.a4);

    const pat = try tiling_pattern.stripes(allocator, color.rgb(0, 0, 255), color.rgb(255, 255, 255), 5.0, 5.0);
    defer allocator.free(pat.content);

    const pat_ref = try tiling_pattern.buildTilingPattern(allocator, &doc.object_store, pat);
    const pat_name = try page.addPattern("stripes1", pat_ref);

    try page.setPatternFill(pat_name);
    try page.drawRect(.{
        .x = 50,
        .y = 700,
        .width = 200,
        .height = 100,
    });

    try std.testing.expect(page.content.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, page.content.items, "/Pattern cs") != null);
}
