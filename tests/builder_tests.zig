const std = @import("std");
const zpdf = @import("zpdf");

test "build convenience function" {
    var builder = zpdf.build(std.testing.allocator);
    defer builder.deinit();

    const pdf = try builder
        .title("Test")
        .page(.a4)
        .text("Hello", .{ .x = 50, .y = 750 })
        .done()
        .save();
    defer std.testing.allocator.free(pdf);

    try std.testing.expect(pdf.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, pdf, "%PDF"));
}

test "builder multiple pages with drawing" {
    var builder = zpdf.build(std.testing.allocator);
    defer builder.deinit();

    const pdf = try builder
        .title("Multi Page")
        .author("Test")
        .page(.a4)
        .text("Page 1", .{ .x = 50, .y = 750 })
        .rect(.{ .x = 50, .y = 700, .width = 100, .height = 50, .color = zpdf.rgb(200, 220, 255) })
        .circle(.{ .cx = 300, .cy = 600, .r = 25, .color = zpdf.rgb(255, 200, 200) })
        .line(.{ .x1 = 50, .y1 = 500, .x2 = 300, .y2 = 500 })
        .done()
        .page(.letter)
        .text("Page 2", .{ .x = 50, .y = 750, .font = .helvetica_bold, .font_size = 18 })
        .done()
        .save();
    defer std.testing.allocator.free(pdf);

    try std.testing.expect(pdf.len > 0);
    try std.testing.expectEqual(@as(usize, 2), builder.doc.getPageCount());
}

test "builder custom page dimensions" {
    var builder = zpdf.build(std.testing.allocator);
    defer builder.deinit();

    const pdf = try builder
        .pageCustom(400, 300)
        .text("Custom", .{ .x = 10, .y = 280 })
        .done()
        .save();
    defer std.testing.allocator.free(pdf);

    try std.testing.expect(pdf.len > 0);
}

test "builder metadata setters" {
    var builder = zpdf.build(std.testing.allocator);
    defer builder.deinit();

    _ = builder
        .title("T")
        .author("A")
        .subject("S")
        .keywords("K")
        .creator("C");

    try std.testing.expectEqualStrings("T", builder.doc.title.?);
    try std.testing.expectEqualStrings("A", builder.doc.author.?);
    try std.testing.expectEqualStrings("S", builder.doc.subject.?);
    try std.testing.expectEqualStrings("K", builder.doc.keywords.?);
    try std.testing.expectEqualStrings("C", builder.doc.creator.?);
}

test "builder encrypt" {
    var builder = zpdf.build(std.testing.allocator);
    defer builder.deinit();

    _ = builder.encrypt(.{
        .user_password = "u",
        .owner_password = "o",
    });

    try std.testing.expect(builder.doc.encryption_options != null);
}

test "builder get document and page" {
    var builder = zpdf.build(std.testing.allocator);
    defer builder.deinit();

    const doc = builder.getDocument();
    try std.testing.expectEqual(@as(usize, 0), doc.getPageCount());

    const pb = builder.page(.a4);
    const pg = pb.getPage();
    try std.testing.expectApproxEqAbs(@as(f32, 595.28), pg.getWidth(), 0.01);
}
