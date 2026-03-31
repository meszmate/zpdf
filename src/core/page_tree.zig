const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const types = @import("types.zig");
const PdfObject = types.PdfObject;
const Ref = types.Ref;
const ObjectStore = @import("object_store.zig").ObjectStore;

/// Manages the PDF page tree (/Pages dictionary), tracking page references
/// and building the corresponding indirect objects in an ObjectStore.
pub const PageTree = struct {
    allocator: Allocator,
    kids: ArrayList(Ref),

    /// Initializes an empty page tree.
    pub fn init(allocator: Allocator) PageTree {
        return .{
            .allocator = allocator,
            .kids = .{},
        };
    }

    /// Frees internal storage.
    pub fn deinit(self: *PageTree) void {
        self.kids.deinit(self.allocator);
    }

    /// Appends a page reference to the tree.
    pub fn addPage(self: *PageTree, page_ref: Ref) Allocator.Error!void {
        try self.kids.append(self.allocator, page_ref);
    }

    /// Removes the page at the given index. Returns error if out of bounds.
    pub fn removePage(self: *PageTree, index: usize) error{IndexOutOfBounds}!void {
        if (index >= self.kids.items.len) {
            return error.IndexOutOfBounds;
        }
        _ = self.kids.orderedRemove(index);
    }

    /// Returns the number of pages in the tree.
    pub fn getPageCount(self: *const PageTree) usize {
        return self.kids.items.len;
    }

    /// Returns the reference for the page at the given index, or null if out of bounds.
    pub fn getPageRef(self: *const PageTree, index: usize) ?Ref {
        if (index >= self.kids.items.len) {
            return null;
        }
        return self.kids.items[index];
    }

    /// Builds the /Pages dictionary as an indirect object in the given store
    /// and returns the reference to it.
    pub fn build(self: *const PageTree, store: *ObjectStore) Allocator.Error!Ref {
        const pages_ref = try store.allocate();

        // Build the Kids array of indirect references
        var kids_array = types.pdfArray(self.allocator);
        errdefer kids_array.deinit(self.allocator);

        for (self.kids.items) |kid_ref| {
            try kids_array.array_obj.append(types.pdfRef(kid_ref.obj_num, kid_ref.gen_num));
        }

        // Build the /Pages dictionary
        var pages_dict = types.pdfDict(self.allocator);
        errdefer pages_dict.deinit(self.allocator);

        try pages_dict.dict_obj.put(self.allocator,"Type", types.pdfName("Pages"));
        try pages_dict.dict_obj.put(self.allocator,"Kids", kids_array);
        try pages_dict.dict_obj.put(self.allocator,"Count", types.pdfInt(@as(i64, @intCast(self.kids.items.len))));

        store.put(pages_ref, pages_dict);

        return pages_ref;
    }
};

// -- Tests --

test "add and count pages" {
    var tree = PageTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.addPage(.{ .obj_num = 2, .gen_num = 0 });
    try tree.addPage(.{ .obj_num = 3, .gen_num = 0 });

    try std.testing.expectEqual(@as(usize, 2), tree.getPageCount());
}

test "get page ref" {
    var tree = PageTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.addPage(.{ .obj_num = 5, .gen_num = 0 });

    const ref = tree.getPageRef(0);
    try std.testing.expect(ref != null);
    try std.testing.expectEqual(@as(u32, 5), ref.?.obj_num);
    try std.testing.expect(tree.getPageRef(1) == null);
}

test "remove page" {
    var tree = PageTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.addPage(.{ .obj_num = 2, .gen_num = 0 });
    try tree.addPage(.{ .obj_num = 3, .gen_num = 0 });

    try tree.removePage(0);
    try std.testing.expectEqual(@as(usize, 1), tree.getPageCount());
    try std.testing.expectEqual(@as(u32, 3), tree.getPageRef(0).?.obj_num);
}

test "remove page out of bounds" {
    var tree = PageTree.init(std.testing.allocator);
    defer tree.deinit();

    try std.testing.expectError(error.IndexOutOfBounds, tree.removePage(0));
}

test "build page tree in store" {
    var store = ObjectStore.init(std.testing.allocator);
    defer store.deinit();

    var tree = PageTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.addPage(.{ .obj_num = 10, .gen_num = 0 });
    try tree.addPage(.{ .obj_num = 11, .gen_num = 0 });

    const pages_ref = try tree.build(&store);
    const obj = store.get(pages_ref);
    try std.testing.expect(obj != null);
    try std.testing.expect(obj.?.isDict());
}
