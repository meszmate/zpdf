const std = @import("std");
const zpdf = @import("zpdf");
const soft_mask = zpdf.soft_mask;
const SoftMask = zpdf.SoftMask;
const SoftMaskType = zpdf.SoftMaskType;
const GradientMask = zpdf.GradientMask;
const ObjectStore = zpdf.ObjectStore;
const Page = zpdf.Page;

test "SoftMaskType enum values" {
    try std.testing.expectEqualStrings("Alpha", SoftMaskType.alpha.pdfName());
    try std.testing.expectEqualStrings("Luminosity", SoftMaskType.luminosity.pdfName());
}

test "buildSoftMask creates all required objects" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const result = try soft_mask.buildSoftMask(allocator, &store, .{
        .mask_type = .luminosity,
        .gradient_mask = .{
            .x0 = 0,
            .y0 = 0,
            .x1 = 300,
            .y1 = 0,
            .start_opacity = 1.0,
            .end_opacity = 0.0,
        },
    }, .{
        .width = 300,
        .height = 200,
    });

    // function + shading + form XObject + SMask dict + ExtGState = 5
    try std.testing.expectEqual(@as(usize, 5), store.count());

    // Verify ExtGState is a dict
    const gs = store.get(result.ext_g_state_ref);
    try std.testing.expect(gs != null);
    try std.testing.expect(gs.?.isDict());

    // Verify Form XObject is a stream
    const form = store.get(result.form_ref);
    try std.testing.expect(form != null);
    try std.testing.expect(form.?.isStream());

    // Verify SMask is a dict
    const smask = store.get(result.smask_ref);
    try std.testing.expect(smask != null);
    try std.testing.expect(smask.?.isDict());
}

test "buildSoftMask with alpha type" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const result = try soft_mask.buildSoftMask(allocator, &store, .{
        .mask_type = .alpha,
        .gradient_mask = .{
            .x0 = 50,
            .y0 = 50,
            .x1 = 150,
            .y1 = 150,
            .start_opacity = 0.8,
            .end_opacity = 0.1,
        },
    }, .{
        .x = 50,
        .y = 50,
        .width = 100,
        .height = 100,
    });

    try std.testing.expectEqual(@as(usize, 5), store.count());
    try std.testing.expect(store.get(result.ext_g_state_ref) != null);
}

test "buildClearSoftMask creates single ExtGState" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const ref = try soft_mask.buildClearSoftMask(allocator, &store);

    try std.testing.expectEqual(@as(usize, 1), store.count());

    const obj = store.get(ref);
    try std.testing.expect(obj != null);
    try std.testing.expect(obj.?.isDict());
}

test "page setSoftMask writes gs operator" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const result = try soft_mask.buildSoftMask(allocator, &store, .{
        .gradient_mask = .{
            .x0 = 0,
            .y0 = 0,
            .x1 = 200,
            .y1 = 0,
        },
    }, .{
        .width = 200,
        .height = 100,
    });

    var page = Page.init(allocator, 612, 792);
    defer page.deinit();

    try page.setSoftMask(result.ext_g_state_ref);

    const content = page.content.items;
    try std.testing.expect(std.mem.indexOf(u8, content, "/GS1 gs") != null);
    try std.testing.expectEqual(@as(usize, 1), page.resources.ext_g_states.items.len);
}

test "page clearSoftMask writes gs operator" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const clear_ref = try soft_mask.buildClearSoftMask(allocator, &store);

    var page = Page.init(allocator, 612, 792);
    defer page.deinit();

    try page.clearSoftMask(clear_ref);

    const content = page.content.items;
    try std.testing.expect(std.mem.indexOf(u8, content, "/GS1 gs") != null);
}

test "page addExtGState increments counter" {
    const allocator = std.testing.allocator;

    var page = Page.init(allocator, 612, 792);
    defer page.deinit();

    const ref1 = zpdf.Ref{ .obj_num = 10, .gen_num = 0 };
    const ref2 = zpdf.Ref{ .obj_num = 11, .gen_num = 0 };

    const name1 = try page.addExtGState(ref1);
    try std.testing.expectEqualStrings("GS1", name1);

    const name2 = try page.addExtGState(ref2);
    try std.testing.expectEqualStrings("GS2", name2);

    try std.testing.expectEqual(@as(usize, 2), page.resources.ext_g_states.items.len);
}

test "gradient mask default opacity values" {
    const mask = GradientMask{
        .x0 = 0,
        .y0 = 0,
        .x1 = 100,
        .y1 = 0,
    };
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), mask.start_opacity, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), mask.end_opacity, 0.001);
}

test "full soft mask workflow with page content" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    // Build the soft mask
    const mask_result = try soft_mask.buildSoftMask(allocator, &store, .{
        .mask_type = .luminosity,
        .gradient_mask = .{
            .x0 = 72,
            .y0 = 700,
            .x1 = 272,
            .y1 = 700,
            .start_opacity = 1.0,
            .end_opacity = 0.0,
        },
    }, .{
        .x = 72,
        .y = 650,
        .width = 200,
        .height = 100,
    });

    var page = Page.init(allocator, 595.28, 841.89);
    defer page.deinit();

    // Apply the mask
    try page.setSoftMask(mask_result.ext_g_state_ref);

    // Draw something
    try page.drawRect(.{
        .x = 72,
        .y = 650,
        .width = 200,
        .height = 100,
        .color = zpdf.rgb(255, 0, 0),
    });

    // Clear the mask
    const clear_ref = try soft_mask.buildClearSoftMask(allocator, &store);
    try page.clearSoftMask(clear_ref);

    // Verify content stream has the gs operators and drawing commands
    const content = page.content.items;
    try std.testing.expect(std.mem.indexOf(u8, content, "/GS1 gs") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "/GS2 gs") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, " re\n") != null);

    // Verify ExtGState resources were registered
    try std.testing.expectEqual(@as(usize, 2), page.resources.ext_g_states.items.len);
}
