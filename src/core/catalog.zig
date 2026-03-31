const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const PdfObject = types.PdfObject;
const Ref = types.Ref;
const ObjectStore = @import("object_store.zig").ObjectStore;

/// Represents the PDF document catalog (/Catalog dictionary), the root object
/// of a PDF document's object hierarchy.
pub const Catalog = struct {
    page_tree_ref: ?Ref,
    outline_ref: ?Ref,
    metadata: ?[]const u8,

    /// Creates a catalog with no references set.
    pub fn init() Catalog {
        return .{
            .page_tree_ref = null,
            .outline_ref = null,
            .metadata = null,
        };
    }

    /// Builds the /Catalog dictionary as an indirect object in the given store
    /// and returns the reference to it.
    pub fn build(self: *const Catalog, store: *ObjectStore, page_tree_ref: Ref) Allocator.Error!Ref {
        const catalog_ref = try store.allocate();

        var dict = types.pdfDict(store.allocator);
        errdefer dict.deinit(store.allocator);

        try dict.dict_obj.put(store.allocator,"Type", types.pdfName("Catalog"));
        try dict.dict_obj.put(store.allocator,"Pages", types.pdfRef(page_tree_ref.obj_num, page_tree_ref.gen_num));

        if (self.outline_ref) |ref| {
            try dict.dict_obj.put(store.allocator,"Outlines", types.pdfRef(ref.obj_num, ref.gen_num));
        }

        if (self.metadata) |meta| {
            try dict.dict_obj.put(store.allocator,"Metadata", types.pdfString(meta));
        }

        // Also store the page_tree_ref on self for later use (via the built dict)
        store.put(catalog_ref, dict);

        return catalog_ref;
    }
};

// -- Tests --

test "catalog init" {
    const catalog = Catalog.init();
    try std.testing.expect(catalog.page_tree_ref == null);
    try std.testing.expect(catalog.outline_ref == null);
    try std.testing.expect(catalog.metadata == null);
}

test "build catalog" {
    var store = ObjectStore.init(std.testing.allocator);
    defer store.deinit();

    const catalog = Catalog.init();
    const page_tree_ref = Ref{ .obj_num = 1, .gen_num = 0 };

    const catalog_ref = try catalog.build(&store, page_tree_ref);
    const obj = store.get(catalog_ref);
    try std.testing.expect(obj != null);
    try std.testing.expect(obj.?.isDict());
}

test "build catalog with outlines" {
    var store = ObjectStore.init(std.testing.allocator);
    defer store.deinit();

    var catalog = Catalog.init();
    catalog.outline_ref = Ref{ .obj_num = 5, .gen_num = 0 };

    const page_tree_ref = Ref{ .obj_num = 1, .gen_num = 0 };
    const catalog_ref = try catalog.build(&store, page_tree_ref);
    const obj = store.get(catalog_ref);
    try std.testing.expect(obj != null);
}
