const std = @import("std");
const zpdf = @import("zpdf");
const testing = std.testing;

const ObjectStore = zpdf.core.object_store.ObjectStore;
const PageTree = zpdf.core.page_tree.PageTree;
const types = zpdf.core.types;
const Ref = types.Ref;

test "ObjectStore: allocate increments object numbers" {
    var store = ObjectStore.init(testing.allocator);
    defer store.deinit();

    const ref1 = try store.allocate();
    const ref2 = try store.allocate();

    try testing.expectEqual(@as(u32, 1), ref1.obj_num);
    try testing.expectEqual(@as(u32, 2), ref2.obj_num);
    try testing.expectEqual(@as(usize, 2), store.count());
}

test "ObjectStore: put and get object" {
    var store = ObjectStore.init(testing.allocator);
    defer store.deinit();

    const ref = try store.allocate();
    store.put(ref, types.pdfInt(42));

    const obj = store.get(ref);
    try testing.expect(obj != null);
    try testing.expectEqual(@as(i64, 42), obj.?.asInt().?);
}

test "ObjectStore: get returns null for unknown ref" {
    var store = ObjectStore.init(testing.allocator);
    defer store.deinit();

    const unknown = Ref{ .obj_num = 999, .gen_num = 0 };
    try testing.expect(store.get(unknown) == null);
}

test "ObjectStore: put replaces existing object" {
    var store = ObjectStore.init(testing.allocator);
    defer store.deinit();

    const ref = try store.allocate();
    store.put(ref, types.pdfInt(1));
    store.put(ref, types.pdfInt(2));

    const obj = store.get(ref);
    try testing.expectEqual(@as(i64, 2), obj.?.asInt().?);
}

test "PageTree: add pages and count" {
    var tree = PageTree.init(testing.allocator);
    defer tree.deinit();

    try tree.addPage(.{ .obj_num = 2, .gen_num = 0 });
    try tree.addPage(.{ .obj_num = 3, .gen_num = 0 });

    try testing.expectEqual(@as(usize, 2), tree.getPageCount());
}

test "PageTree: getPageRef and out of bounds" {
    var tree = PageTree.init(testing.allocator);
    defer tree.deinit();

    try tree.addPage(.{ .obj_num = 5, .gen_num = 0 });

    const ref = tree.getPageRef(0);
    try testing.expect(ref != null);
    try testing.expectEqual(@as(u32, 5), ref.?.obj_num);
    try testing.expect(tree.getPageRef(1) == null);
}

test "PageTree: removePage" {
    var tree = PageTree.init(testing.allocator);
    defer tree.deinit();

    try tree.addPage(.{ .obj_num = 2, .gen_num = 0 });
    try tree.addPage(.{ .obj_num = 3, .gen_num = 0 });

    try tree.removePage(0);
    try testing.expectEqual(@as(usize, 1), tree.getPageCount());
    try testing.expectEqual(@as(u32, 3), tree.getPageRef(0).?.obj_num);
}
