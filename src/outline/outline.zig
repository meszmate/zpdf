const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const types = @import("../core/types.zig");
const PdfObject = types.PdfObject;
const Ref = types.Ref;
const ObjectStore = @import("../core/object_store.zig").ObjectStore;

/// A single outline (bookmark) item.
pub const OutlineItem = struct {
    title: []const u8,
    page_index: usize,
    parent_index: ?usize,
    children: ArrayList(usize), // indices into the OutlineTree items list

    fn deinit(self: *OutlineItem, allocator: Allocator) void {
        self.children.deinit(allocator);
    }
};

/// A tree of outline (bookmark) items for a PDF document.
pub const OutlineTree = struct {
    allocator: Allocator,
    items: ArrayList(OutlineItem),
    root_items: ArrayList(usize),

    /// Initialize an empty outline tree.
    pub fn init(allocator: Allocator) OutlineTree {
        return .{
            .allocator = allocator,
            .items = .{},
            .root_items = .{},
        };
    }

    /// Free all resources.
    pub fn deinit(self: *OutlineTree) void {
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.deinit(self.allocator);
        self.root_items.deinit(self.allocator);
    }

    /// Add an outline item. If parent_index is null, it becomes a root item.
    /// Returns the index of the newly added item.
    pub fn addItem(self: *OutlineTree, title: []const u8, page_index: usize, parent_index: ?usize) !usize {
        const idx = self.items.items.len;
        try self.items.append(self.allocator, .{
            .title = title,
            .page_index = page_index,
            .parent_index = parent_index,
            .children = .{},
        });

        if (parent_index) |pi| {
            if (pi < self.items.items.len) {
                try self.items.items[pi].children.append(self.allocator, idx);
            }
        } else {
            try self.root_items.append(self.allocator, idx);
        }

        return idx;
    }

    /// Build the outline tree as PDF objects in the given store.
    /// Returns the reference to the root /Outlines dictionary, or null if the tree is empty.
    pub fn build(self: *OutlineTree, allocator: Allocator, store: *ObjectStore, page_refs: []const Ref) !?Ref {
        _ = allocator;
        if (self.root_items.items.len == 0) return null;

        // Allocate refs for all items first
        var item_refs = try self.allocator.alloc(Ref, self.items.items.len);
        defer self.allocator.free(item_refs);

        for (0..self.items.items.len) |i| {
            item_refs[i] = try store.allocate();
        }

        // Allocate the root outline dictionary
        const root_ref = try store.allocate();

        // Count total visible items
        var total_count: i64 = 0;
        for (self.items.items) |item| {
            _ = item;
            total_count += 1;
        }

        // Build root dictionary
        var root_dict = types.pdfDict(self.allocator);

        try root_dict.dict_obj.put(self.allocator, "Type", types.pdfName("Outlines"));
        try root_dict.dict_obj.put(self.allocator, "Count", types.pdfInt(total_count));

        if (self.root_items.items.len > 0) {
            try root_dict.dict_obj.put(self.allocator, "First", types.pdfRef(
                item_refs[self.root_items.items[0]].obj_num,
                item_refs[self.root_items.items[0]].gen_num,
            ));
            try root_dict.dict_obj.put(self.allocator, "Last", types.pdfRef(
                item_refs[self.root_items.items[self.root_items.items.len - 1]].obj_num,
                item_refs[self.root_items.items[self.root_items.items.len - 1]].gen_num,
            ));
        }

        store.put(root_ref, root_dict);

        // Build individual outline item dictionaries
        for (self.items.items, 0..) |item, i| {
            var item_dict = types.pdfDict(self.allocator);

            try item_dict.dict_obj.put(self.allocator, "Title", types.pdfString(item.title));

            // Parent reference
            const parent_ref = if (item.parent_index) |pi| item_refs[pi] else root_ref;
            try item_dict.dict_obj.put(self.allocator, "Parent", types.pdfRef(parent_ref.obj_num, parent_ref.gen_num));

            // Destination: page reference with /Fit
            if (item.page_index < page_refs.len) {
                var dest = types.pdfArray(self.allocator);
                try dest.array_obj.append(types.pdfRef(
                    page_refs[item.page_index].obj_num,
                    page_refs[item.page_index].gen_num,
                ));
                try dest.array_obj.append(types.pdfName("Fit"));
                try item_dict.dict_obj.put(self.allocator, "Dest", dest);
            }

            // Sibling links among items sharing the same parent
            const siblings = if (item.parent_index) |pi|
                &self.items.items[pi].children
            else
                &self.root_items;

            // Find position in siblings
            for (siblings.items, 0..) |sibling_idx, si| {
                if (sibling_idx == i) {
                    if (si > 0) {
                        const prev_ref = item_refs[siblings.items[si - 1]];
                        try item_dict.dict_obj.put(self.allocator, "Prev", types.pdfRef(prev_ref.obj_num, prev_ref.gen_num));
                    }
                    if (si + 1 < siblings.items.len) {
                        const next_ref = item_refs[siblings.items[si + 1]];
                        try item_dict.dict_obj.put(self.allocator, "Next", types.pdfRef(next_ref.obj_num, next_ref.gen_num));
                    }
                    break;
                }
            }

            // Children
            if (item.children.items.len > 0) {
                try item_dict.dict_obj.put(self.allocator, "First", types.pdfRef(
                    item_refs[item.children.items[0]].obj_num,
                    item_refs[item.children.items[0]].gen_num,
                ));
                try item_dict.dict_obj.put(self.allocator, "Last", types.pdfRef(
                    item_refs[item.children.items[item.children.items.len - 1]].obj_num,
                    item_refs[item.children.items[item.children.items.len - 1]].gen_num,
                ));
                try item_dict.dict_obj.put(self.allocator, "Count", types.pdfInt(@intCast(item.children.items.len)));
            }

            store.put(item_refs[i], item_dict);
        }

        return root_ref;
    }
};

// -- Tests --

test "outline: init and deinit" {
    var tree = OutlineTree.init(std.testing.allocator);
    defer tree.deinit();
    try std.testing.expectEqual(@as(usize, 0), tree.items.items.len);
}

test "outline: add root items" {
    var tree = OutlineTree.init(std.testing.allocator);
    defer tree.deinit();

    const idx0 = try tree.addItem("Chapter 1", 0, null);
    const idx1 = try tree.addItem("Chapter 2", 5, null);

    try std.testing.expectEqual(@as(usize, 0), idx0);
    try std.testing.expectEqual(@as(usize, 1), idx1);
    try std.testing.expectEqual(@as(usize, 2), tree.root_items.items.len);
}

test "outline: add child items" {
    var tree = OutlineTree.init(std.testing.allocator);
    defer tree.deinit();

    const parent = try tree.addItem("Chapter 1", 0, null);
    const child = try tree.addItem("Section 1.1", 1, parent);

    try std.testing.expectEqual(@as(usize, 1), child);
    try std.testing.expectEqual(@as(usize, 1), tree.items.items[parent].children.items.len);
}

test "outline: build empty tree returns null" {
    var tree = OutlineTree.init(std.testing.allocator);
    defer tree.deinit();
    var store = ObjectStore.init(std.testing.allocator);
    defer store.deinit();

    const result = try tree.build(std.testing.allocator, &store, &[_]Ref{});
    try std.testing.expect(result == null);
}

test "outline: build non-empty tree" {
    var tree = OutlineTree.init(std.testing.allocator);
    defer tree.deinit();
    var store = ObjectStore.init(std.testing.allocator);
    defer store.deinit();

    _ = try tree.addItem("Page 1", 0, null);
    _ = try tree.addItem("Page 2", 1, null);

    const page_refs = [_]Ref{
        .{ .obj_num = 10, .gen_num = 0 },
        .{ .obj_num = 11, .gen_num = 0 },
    };

    const result = try tree.build(std.testing.allocator, &store, &page_refs);
    try std.testing.expect(result != null);
}
