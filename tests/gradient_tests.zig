const std = @import("std");
const zpdf = @import("zpdf");
const ColorStop = zpdf.ColorStop;
const LinearGradient = zpdf.LinearGradient;
const RadialGradient = zpdf.RadialGradient;
const gradient = zpdf.gradient;
const ObjectStore = zpdf.ObjectStore;
const color = zpdf.color;

test "linear gradient with 2 stops" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const stops = [_]ColorStop{
        .{ .offset = 0.0, .color = color.rgb(0, 0, 255) },
        .{ .offset = 1.0, .color = color.rgb(255, 0, 0) },
    };

    const ref = try gradient.buildLinearGradient(allocator, &store, .{
        .x0 = 0, .y0 = 0,
        .x1 = 200, .y1 = 0,
        .stops = &stops,
    });

    // function + shading + pattern = 3 objects
    try std.testing.expectEqual(@as(usize, 3), store.count());

    const obj = store.get(ref);
    try std.testing.expect(obj != null);
    try std.testing.expect(obj.?.isDict());
}

test "linear gradient with multiple stops uses stitching function" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const stops = [_]ColorStop{
        .{ .offset = 0.0, .color = color.rgb(255, 0, 0) },
        .{ .offset = 0.33, .color = color.rgb(0, 255, 0) },
        .{ .offset = 0.66, .color = color.rgb(0, 0, 255) },
        .{ .offset = 1.0, .color = color.rgb(255, 255, 0) },
    };

    const ref = try gradient.buildLinearGradient(allocator, &store, .{
        .x0 = 0, .y0 = 0,
        .x1 = 300, .y1 = 0,
        .stops = &stops,
    });

    // 3 Type2 functions + 1 Type3 stitching + 1 shading + 1 pattern = 6
    try std.testing.expectEqual(@as(usize, 6), store.count());

    const obj = store.get(ref);
    try std.testing.expect(obj != null);
}

test "radial gradient" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const stops = [_]ColorStop{
        .{ .offset = 0.0, .color = color.rgb(255, 255, 255) },
        .{ .offset = 1.0, .color = color.rgb(0, 0, 0) },
    };

    const ref = try gradient.buildRadialGradient(allocator, &store, .{
        .cx0 = 100, .cy0 = 100, .r0 = 0,
        .cx1 = 100, .cy1 = 100, .r1 = 80,
        .stops = &stops,
        .extend_start = true,
        .extend_end = true,
    });

    try std.testing.expectEqual(@as(usize, 3), store.count());

    const obj = store.get(ref);
    try std.testing.expect(obj != null);
    try std.testing.expect(obj.?.isDict());
}

test "color stop validation - offsets in order" {
    try std.testing.expectError(
        gradient.GradientError.InvalidStopOrder,
        gradient.validateStops(&[_]ColorStop{
            .{ .offset = 0.0, .color = color.rgb(0, 0, 0) },
            .{ .offset = 0.8, .color = color.rgb(0, 0, 0) },
            .{ .offset = 0.5, .color = color.rgb(0, 0, 0) },
        }),
    );
}

test "color stop validation - offset range" {
    try std.testing.expectError(
        gradient.GradientError.InvalidStopOffset,
        gradient.validateStops(&[_]ColorStop{
            .{ .offset = 0.0, .color = color.rgb(0, 0, 0) },
            .{ .offset = 1.5, .color = color.rgb(0, 0, 0) },
        }),
    );
}

test "color stop validation - too few stops" {
    try std.testing.expectError(
        gradient.GradientError.TooFewStops,
        gradient.validateStops(&[_]ColorStop{
            .{ .offset = 0.0, .color = color.rgb(0, 0, 0) },
        }),
    );
}

test "pattern resources added to page" {
    const allocator = std.testing.allocator;

    var page = zpdf.Page.init(allocator, 612, 792);
    defer page.deinit();

    const ref = zpdf.Ref{ .obj_num = 10, .gen_num = 0 };
    const name = try page.addPattern("grad1", ref);
    try std.testing.expectEqualStrings("P1", name);
    try std.testing.expectEqual(@as(usize, 1), page.resources.patterns.count());

    // Adding same pattern returns same name
    const name2 = try page.addPattern("grad1", ref);
    try std.testing.expectEqualStrings("P1", name2);
    try std.testing.expectEqual(@as(usize, 1), page.resources.patterns.count());
}

test "setGradientFill writes correct operators" {
    const allocator = std.testing.allocator;

    var page = zpdf.Page.init(allocator, 612, 792);
    defer page.deinit();

    try page.setGradientFill("P1");

    const content = page.content.items;
    try std.testing.expect(std.mem.indexOf(u8, content, "/Pattern cs") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "/P1 scn") != null);
}
