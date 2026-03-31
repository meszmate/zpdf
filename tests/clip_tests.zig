const std = @import("std");
const zpdf = @import("zpdf");
const testing = std.testing;

const Page = zpdf.Page;
const PathBuilder = zpdf.PathBuilder;
const ClipMode = zpdf.ClipMode;

test "beginClipRect produces correct PDF operators" {
    var page = Page.init(testing.allocator, 612, 792);
    defer page.deinit();

    try page.beginClipRect(10, 20, 200, 100, .non_zero);
    try page.endClip();

    const content = page.content.items;
    try testing.expect(std.mem.indexOf(u8, content, "q\n") != null);
    try testing.expect(std.mem.indexOf(u8, content, "10.00 20.00 200.00 100.00 re\n") != null);
    try testing.expect(std.mem.indexOf(u8, content, "W n\n") != null);
    try testing.expect(std.mem.indexOf(u8, content, "Q\n") != null);
}

test "beginClipRect even_odd produces W* operator" {
    var page = Page.init(testing.allocator, 612, 792);
    defer page.deinit();

    try page.beginClipRect(0, 0, 100, 100, .even_odd);
    try page.endClip();

    const content = page.content.items;
    try testing.expect(std.mem.indexOf(u8, content, "W* n\n") != null);
}

test "beginClipCircle produces bezier curves with W n" {
    var page = Page.init(testing.allocator, 612, 792);
    defer page.deinit();

    try page.beginClipCircle(100, 100, 50, .non_zero);
    try page.endClip();

    const content = page.content.items;
    // Should have q, moveto, 4 bezier curves (c), close path (h), W n, Q
    try testing.expect(std.mem.indexOf(u8, content, "q\n") != null);
    try testing.expect(std.mem.indexOf(u8, content, " m\n") != null);
    try testing.expect(std.mem.indexOf(u8, content, " c\n") != null);
    try testing.expect(std.mem.indexOf(u8, content, "h\n") != null);
    try testing.expect(std.mem.indexOf(u8, content, "W n\n") != null);
    try testing.expect(std.mem.indexOf(u8, content, "Q\n") != null);
}

test "beginClipEllipse produces correct operators" {
    var page = Page.init(testing.allocator, 612, 792);
    defer page.deinit();

    try page.beginClipEllipse(200, 300, 80, 40, .non_zero);
    try page.endClip();

    const content = page.content.items;
    try testing.expect(std.mem.indexOf(u8, content, "q\n") != null);
    try testing.expect(std.mem.indexOf(u8, content, " m\n") != null);
    try testing.expect(std.mem.indexOf(u8, content, " c\n") != null);
    try testing.expect(std.mem.indexOf(u8, content, "h\n") != null);
    try testing.expect(std.mem.indexOf(u8, content, "W n\n") != null);
    try testing.expect(std.mem.indexOf(u8, content, "Q\n") != null);
}

test "beginClipPath with custom path" {
    var page = Page.init(testing.allocator, 612, 792);
    defer page.deinit();

    var path = PathBuilder.init(testing.allocator);
    defer path.deinit();

    try path.moveTo(0, 0);
    try path.lineTo(100, 0);
    try path.lineTo(50, 100);
    try path.closePath();

    try page.beginClipPath(&path, .non_zero);
    try page.endClip();

    const content = page.content.items;
    try testing.expect(std.mem.indexOf(u8, content, "q\n") != null);
    try testing.expect(std.mem.indexOf(u8, content, "0.00 0.00 m") != null);
    try testing.expect(std.mem.indexOf(u8, content, "100.00 0.00 l") != null);
    try testing.expect(std.mem.indexOf(u8, content, "50.00 100.00 l") != null);
    try testing.expect(std.mem.indexOf(u8, content, "W n\n") != null);
    try testing.expect(std.mem.indexOf(u8, content, "Q\n") != null);
}

test "beginClipPath with even_odd mode" {
    var page = Page.init(testing.allocator, 612, 792);
    defer page.deinit();

    var path = PathBuilder.init(testing.allocator);
    defer path.deinit();

    try path.moveTo(0, 0);
    try path.lineTo(100, 0);
    try path.lineTo(50, 100);
    try path.closePath();

    try page.beginClipPath(&path, .even_odd);
    try page.endClip();

    const content = page.content.items;
    try testing.expect(std.mem.indexOf(u8, content, "W* n\n") != null);
}

test "nested clipping" {
    var page = Page.init(testing.allocator, 612, 792);
    defer page.deinit();

    // Outer clip
    try page.beginClipRect(0, 0, 400, 400, .non_zero);
    // Inner clip
    try page.beginClipCircle(200, 200, 100, .non_zero);
    // Draw something inside
    try page.drawRect(.{ .x = 150, .y = 150, .width = 100, .height = 100, .color = zpdf.color.rgb(255, 0, 0) });
    // End inner clip
    try page.endClip();
    // End outer clip
    try page.endClip();

    const content = page.content.items;

    // Count q and Q - should have matching pairs
    // drawRect adds its own q/Q pair, plus 2 clips = 3 q's and 3 Q's minimum
    var q_count: usize = 0;
    var big_q_count: usize = 0;
    for (content, 0..) |ch, i| {
        if (ch == 'q' and (i == 0 or content[i - 1] == '\n')) {
            if (i + 1 < content.len and content[i + 1] == '\n') {
                q_count += 1;
            }
        }
        if (ch == 'Q' and (i == 0 or content[i - 1] == '\n')) {
            if (i + 1 < content.len and content[i + 1] == '\n') {
                big_q_count += 1;
            }
        }
    }
    try testing.expect(q_count >= 3);
    try testing.expect(big_q_count >= 3);
}
