const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const types = @import("../core/types.zig");
const PdfObject = types.PdfObject;
const Ref = types.Ref;
const ObjectStore = @import("../core/object_store.zig").ObjectStore;

/// Represents a single optional content layer (OCG).
pub const Layer = struct {
    name: []const u8,
    ref: Ref,
};

/// Builds optional content groups (layers) for a PDF document.
pub const LayerBuilder = struct {
    allocator: Allocator,
    layers: ArrayList(Layer),

    /// Initialize a new layer builder.
    pub fn init(allocator: Allocator) LayerBuilder {
        return .{
            .allocator = allocator,
            .layers = .{},
        };
    }

    /// Free all resources.
    pub fn deinit(self: *LayerBuilder) void {
        self.layers.deinit(self.allocator);
    }

    /// Add a new layer with the given name.
    /// Allocates an object in the store and returns the Layer descriptor.
    pub fn addLayer(self: *LayerBuilder, store: *ObjectStore, name: []const u8) !Layer {
        const ref = try store.allocate();

        // Create the OCG dictionary
        var ocg_dict = types.pdfDict(self.allocator);
        try ocg_dict.dict_obj.put(self.allocator,"Type", types.pdfName("OCG"));
        try ocg_dict.dict_obj.put(self.allocator,"Name", types.pdfString(name));
        store.put(ref, ocg_dict);

        const layer = Layer{ .name = name, .ref = ref };
        try self.layers.append(self.allocator, layer);

        return layer;
    }

    /// Build the optional content properties dictionary and register it in the store.
    /// This creates:
    /// - /OCProperties dictionary for the catalog
    /// - /D (default configuration) dictionary
    pub fn build(self: *LayerBuilder, store: *ObjectStore) !Ref {
        // Build OCProperties dictionary
        const oc_props_ref = try store.allocate();

        var oc_props = types.pdfDict(self.allocator);
        errdefer oc_props.deinit(self.allocator);

        // OCGs array - list of all optional content groups
        var ocgs_array = types.pdfArray(self.allocator);
        for (self.layers.items) |layer| {
            try ocgs_array.array_obj.append(types.pdfRef(layer.ref.obj_num, layer.ref.gen_num));
        }
        try oc_props.dict_obj.put(self.allocator,"OCGs", ocgs_array);

        // Default configuration dictionary
        var d_dict = types.pdfDict(self.allocator);
        try d_dict.dict_obj.put(self.allocator,"Name", types.pdfString("Default"));
        try d_dict.dict_obj.put(self.allocator,"BaseState", types.pdfName("ON"));

        // ON array (all layers on by default)
        var on_array = types.pdfArray(self.allocator);
        for (self.layers.items) |layer| {
            try on_array.array_obj.append(types.pdfRef(layer.ref.obj_num, layer.ref.gen_num));
        }
        try d_dict.dict_obj.put(self.allocator,"ON", on_array);

        // Order array (display order)
        var order_array = types.pdfArray(self.allocator);
        for (self.layers.items) |layer| {
            try order_array.array_obj.append(types.pdfRef(layer.ref.obj_num, layer.ref.gen_num));
        }
        try d_dict.dict_obj.put(self.allocator,"Order", order_array);

        try oc_props.dict_obj.put(self.allocator,"D", d_dict);

        store.put(oc_props_ref, oc_props);

        return oc_props_ref;
    }
};

// -- Tests --

test "layer builder: init and deinit" {
    var builder = LayerBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try std.testing.expectEqual(@as(usize, 0), builder.layers.items.len);
}

test "layer builder: add layer" {
    var store = ObjectStore.init(std.testing.allocator);
    defer store.deinit();
    var builder = LayerBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const layer = try builder.addLayer(&store, "Background");
    try std.testing.expectEqualStrings("Background", layer.name);
    try std.testing.expectEqual(@as(usize, 1), builder.layers.items.len);
}

test "layer builder: add multiple layers" {
    var store = ObjectStore.init(std.testing.allocator);
    defer store.deinit();
    var builder = LayerBuilder.init(std.testing.allocator);
    defer builder.deinit();

    _ = try builder.addLayer(&store, "Layer 1");
    _ = try builder.addLayer(&store, "Layer 2");
    _ = try builder.addLayer(&store, "Layer 3");

    try std.testing.expectEqual(@as(usize, 3), builder.layers.items.len);
}

test "layer builder: build produces valid dict" {
    var store = ObjectStore.init(std.testing.allocator);
    defer store.deinit();
    var builder = LayerBuilder.init(std.testing.allocator);
    defer builder.deinit();

    _ = try builder.addLayer(&store, "Text");
    _ = try builder.addLayer(&store, "Images");

    const ref = try builder.build(&store);
    const obj = store.get(ref);
    try std.testing.expect(obj != null);
    try std.testing.expect(obj.?.isDict());
}
