//! Improved Optional Content Groups (OCG / PDF Layers).
//!
//! This module provides a richer layer-building API on top of the
//! low-level `layer_builder.zig`. It supports:
//!
//! - Default visibility (on/off) per layer
//! - Intent (view / design / all)
//! - Print visibility (always / never / when visible)
//! - Radio button groups (mutually exclusive layers)
//! - Locked layers (user cannot toggle)
//!
//! The resulting `/OCProperties` dictionary has the shape:
//!
//! ```text
//! /OCProperties <<
//!   /OCGs [ ... ]
//!   /D <<
//!     /ON       [ ... ]
//!     /OFF      [ ... ]
//!     /Order    [ ... ]
//!     /RBGroups [ [ ... ] ... ]
//!     /Locked   [ ... ]
//!     /Intent   [ /View /Design ]
//!     /BaseState /ON
//!   >>
//! >>
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;

const types = @import("../core/types.zig");
const PdfObject = types.PdfObject;
const Ref = types.Ref;
const ObjectStore = @import("../core/object_store.zig").ObjectStore;

/// Intent of an optional content group, per PDF 1.7 spec (8.11.2.1).
pub const OcgIntent = enum {
    view,
    design,
    all,

    pub fn pdfName(self: OcgIntent) []const u8 {
        return switch (self) {
            .view => "View",
            .design => "Design",
            .all => "All",
        };
    }
};

/// Print visibility policy for an optional content group.
pub const PrintVisibility = enum {
    always_print,
    never_print,
    when_visible,
};

/// Default visibility state for a layer.
pub const DefaultState = enum {
    on,
    off,
};

/// Handle identifying a layer inside an `OcgBuilder`.
pub const LayerHandle = struct {
    index: u32,
};

/// Options for creating a new layer.
pub const LayerOptions = struct {
    default_state: DefaultState = .on,
    intent: OcgIntent = .view,
    print_visibility: PrintVisibility = .when_visible,
};

/// Internal representation of a layer tracked by the builder.
pub const OcgLayer = struct {
    name: []const u8,
    default_state: DefaultState,
    intent: OcgIntent,
    print_visibility: PrintVisibility,
    ref: Ref = .{ .obj_num = 0, .gen_num = 0 },
    locked: bool = false,
};

/// Builder producing a PDF `/OCProperties` dictionary with rich options.
pub const OcgBuilder = struct {
    allocator: Allocator,
    layers: ArrayList(OcgLayer),
    radio_groups: ArrayList(ArrayList(LayerHandle)),

    /// Initialize an empty builder.
    pub fn init(allocator: Allocator) OcgBuilder {
        return .{
            .allocator = allocator,
            .layers = .{},
            .radio_groups = .{},
        };
    }

    /// Release all allocated memory owned by the builder. Does not touch the
    /// `ObjectStore`, which owns the OCG dictionaries created during `build`.
    pub fn deinit(self: *OcgBuilder) void {
        for (self.radio_groups.items) |*group| {
            group.deinit(self.allocator);
        }
        self.radio_groups.deinit(self.allocator);
        self.layers.deinit(self.allocator);
    }

    /// Add a new layer with the provided options. Returns a handle that can
    /// later be used to reference the layer (for radio groups, locking, or
    /// page-level `beginLayer` calls).
    pub fn addLayer(
        self: *OcgBuilder,
        name: []const u8,
        options: LayerOptions,
    ) !LayerHandle {
        const index: u32 = @intCast(self.layers.items.len);
        try self.layers.append(self.allocator, .{
            .name = name,
            .default_state = options.default_state,
            .intent = options.intent,
            .print_visibility = options.print_visibility,
        });
        return .{ .index = index };
    }

    /// Register a mutually exclusive radio-button group. Enabling any one of
    /// the provided layers turns the others off in the default configuration.
    pub fn addRadioGroup(self: *OcgBuilder, layer_handles: []const LayerHandle) !void {
        var group: ArrayList(LayerHandle) = .{};
        errdefer group.deinit(self.allocator);
        for (layer_handles) |h| {
            if (h.index >= self.layers.items.len) return error.InvalidLayerHandle;
            try group.append(self.allocator, h);
        }
        try self.radio_groups.append(self.allocator, group);
    }

    /// Mark a layer as locked. Locked layers cannot be toggled by the user in
    /// the PDF viewer (the state is still controllable programmatically).
    pub fn lockLayer(self: *OcgBuilder, handle: LayerHandle) !void {
        if (handle.index >= self.layers.items.len) return error.InvalidLayerHandle;
        self.layers.items[handle.index].locked = true;
    }

    /// Returns the reference for a previously-built layer. Only valid after
    /// `build` has been called successfully.
    pub fn layerRef(self: *const OcgBuilder, handle: LayerHandle) !Ref {
        if (handle.index >= self.layers.items.len) return error.InvalidLayerHandle;
        const layer = self.layers.items[handle.index];
        if (layer.ref.obj_num == 0) return error.NotBuilt;
        return layer.ref;
    }

    /// Create OCG dictionaries for every registered layer, build the
    /// `/OCProperties` dictionary, store it in the object store and return a
    /// reference to it. After this call `layerRef` is valid.
    pub fn build(self: *OcgBuilder, store: *ObjectStore) !Ref {
        // Allocate + populate each individual OCG dictionary.
        for (self.layers.items) |*layer| {
            const ref = try store.allocate();
            layer.ref = ref;

            var ocg = types.pdfDict(self.allocator);
            errdefer ocg.deinit(self.allocator);

            try ocg.dict_obj.put(self.allocator, "Type", types.pdfName("OCG"));
            try ocg.dict_obj.put(self.allocator, "Name", types.pdfString(layer.name));

            // /Usage << /Print << /PrintState /ON|/OFF >> /View << /ViewState /ON|/OFF >> >>
            var usage = types.pdfDict(self.allocator);

            var print_dict = types.pdfDict(self.allocator);
            const print_state: []const u8 = switch (layer.print_visibility) {
                .always_print => "ON",
                .never_print => "OFF",
                .when_visible => if (layer.default_state == .on) "ON" else "OFF",
            };
            try print_dict.dict_obj.put(self.allocator, "PrintState", types.pdfName(print_state));
            try print_dict.dict_obj.put(self.allocator, "Subtype", types.pdfName("Print"));
            try usage.dict_obj.put(self.allocator, "Print", print_dict);

            var view_dict = types.pdfDict(self.allocator);
            const view_state: []const u8 = if (layer.default_state == .on) "ON" else "OFF";
            try view_dict.dict_obj.put(self.allocator, "ViewState", types.pdfName(view_state));
            try view_dict.dict_obj.put(self.allocator, "Subtype", types.pdfName("View"));
            try usage.dict_obj.put(self.allocator, "View", view_dict);

            try ocg.dict_obj.put(self.allocator, "Usage", usage);

            // /Intent may be a single name or an array. Use array form for /All
            // to keep the writer happy with both intents.
            switch (layer.intent) {
                .view => try ocg.dict_obj.put(self.allocator, "Intent", types.pdfName("View")),
                .design => try ocg.dict_obj.put(self.allocator, "Intent", types.pdfName("Design")),
                .all => {
                    var intent_arr = types.pdfArray(self.allocator);
                    try intent_arr.array_obj.append(types.pdfName("View"));
                    try intent_arr.array_obj.append(types.pdfName("Design"));
                    try ocg.dict_obj.put(self.allocator, "Intent", intent_arr);
                },
            }

            store.put(ref, ocg);
        }

        // Build the /OCProperties dictionary.
        const oc_props_ref = try store.allocate();

        var oc_props = types.pdfDict(self.allocator);
        errdefer oc_props.deinit(self.allocator);

        // /OCGs array
        var ocgs_array = types.pdfArray(self.allocator);
        for (self.layers.items) |layer| {
            try ocgs_array.array_obj.append(types.pdfRef(layer.ref.obj_num, layer.ref.gen_num));
        }
        try oc_props.dict_obj.put(self.allocator, "OCGs", ocgs_array);

        // /D default configuration dictionary
        var d_dict = types.pdfDict(self.allocator);

        try d_dict.dict_obj.put(self.allocator, "Name", types.pdfString("Default"));
        try d_dict.dict_obj.put(self.allocator, "BaseState", types.pdfName("ON"));

        // /ON and /OFF arrays based on default_state
        var on_array = types.pdfArray(self.allocator);
        var off_array = types.pdfArray(self.allocator);
        for (self.layers.items) |layer| {
            const ref_obj = types.pdfRef(layer.ref.obj_num, layer.ref.gen_num);
            switch (layer.default_state) {
                .on => try on_array.array_obj.append(ref_obj),
                .off => try off_array.array_obj.append(ref_obj),
            }
        }
        try d_dict.dict_obj.put(self.allocator, "ON", on_array);
        try d_dict.dict_obj.put(self.allocator, "OFF", off_array);

        // /Order — flat list in creation order.
        var order_array = types.pdfArray(self.allocator);
        for (self.layers.items) |layer| {
            try order_array.array_obj.append(types.pdfRef(layer.ref.obj_num, layer.ref.gen_num));
        }
        try d_dict.dict_obj.put(self.allocator, "Order", order_array);

        // /RBGroups — array of arrays.
        var rb_array = types.pdfArray(self.allocator);
        for (self.radio_groups.items) |group| {
            var group_arr = types.pdfArray(self.allocator);
            for (group.items) |h| {
                const layer = self.layers.items[h.index];
                try group_arr.array_obj.append(types.pdfRef(layer.ref.obj_num, layer.ref.gen_num));
            }
            try rb_array.array_obj.append(group_arr);
        }
        try d_dict.dict_obj.put(self.allocator, "RBGroups", rb_array);

        // /Locked
        var locked_array = types.pdfArray(self.allocator);
        for (self.layers.items) |layer| {
            if (layer.locked) {
                try locked_array.array_obj.append(types.pdfRef(layer.ref.obj_num, layer.ref.gen_num));
            }
        }
        try d_dict.dict_obj.put(self.allocator, "Locked", locked_array);

        // /Intent on the configuration — advertise both intents so viewers
        // honouring either can display the document correctly.
        var cfg_intent = types.pdfArray(self.allocator);
        try cfg_intent.array_obj.append(types.pdfName("View"));
        try cfg_intent.array_obj.append(types.pdfName("Design"));
        try d_dict.dict_obj.put(self.allocator, "Intent", cfg_intent);

        try oc_props.dict_obj.put(self.allocator, "D", d_dict);

        store.put(oc_props_ref, oc_props);
        return oc_props_ref;
    }
};

// -- Tests --

test "ocg builder: init and deinit" {
    var b = OcgBuilder.init(std.testing.allocator);
    defer b.deinit();
    try std.testing.expectEqual(@as(usize, 0), b.layers.items.len);
    try std.testing.expectEqual(@as(usize, 0), b.radio_groups.items.len);
}

test "ocg builder: add layer returns sequential handles" {
    var b = OcgBuilder.init(std.testing.allocator);
    defer b.deinit();

    const h1 = try b.addLayer("One", .{});
    const h2 = try b.addLayer("Two", .{ .default_state = .off });
    try std.testing.expectEqual(@as(u32, 0), h1.index);
    try std.testing.expectEqual(@as(u32, 1), h2.index);
    try std.testing.expectEqual(DefaultState.off, b.layers.items[1].default_state);
}

test "ocg builder: lock layer" {
    var b = OcgBuilder.init(std.testing.allocator);
    defer b.deinit();
    const h = try b.addLayer("L", .{});
    try b.lockLayer(h);
    try std.testing.expect(b.layers.items[0].locked);
}

test "ocg builder: radio group validates handles" {
    var b = OcgBuilder.init(std.testing.allocator);
    defer b.deinit();
    const a = try b.addLayer("A", .{});
    const c = try b.addLayer("C", .{});
    try b.addRadioGroup(&.{ a, c });
    try std.testing.expectEqual(@as(usize, 1), b.radio_groups.items.len);

    try std.testing.expectError(error.InvalidLayerHandle, b.addRadioGroup(&.{.{ .index = 99 }}));
}

test "ocg builder: build creates OCProperties with all sections" {
    var store = ObjectStore.init(std.testing.allocator);
    defer store.deinit();

    var b = OcgBuilder.init(std.testing.allocator);
    defer b.deinit();

    const bg = try b.addLayer("Background", .{ .default_state = .on, .intent = .view });
    const notes = try b.addLayer("Notes", .{ .default_state = .off, .intent = .design });
    const grid = try b.addLayer("Grid", .{ .print_visibility = .never_print });
    try b.lockLayer(grid);
    try b.addRadioGroup(&.{ bg, notes });

    const ref = try b.build(&store);

    const props = store.get(ref).?;
    try std.testing.expect(props.isDict());

    // /OCGs
    const ocgs = props.dict_obj.get("OCGs").?;
    try std.testing.expect(ocgs.isArray());
    try std.testing.expectEqual(@as(usize, 3), ocgs.array_obj.list.items.len);

    // /D
    const d = props.dict_obj.get("D").?;
    try std.testing.expect(d.isDict());

    const on_arr = d.dict_obj.get("ON").?;
    try std.testing.expectEqual(@as(usize, 2), on_arr.array_obj.list.items.len);
    const off_arr = d.dict_obj.get("OFF").?;
    try std.testing.expectEqual(@as(usize, 1), off_arr.array_obj.list.items.len);

    const order = d.dict_obj.get("Order").?;
    try std.testing.expectEqual(@as(usize, 3), order.array_obj.list.items.len);

    const rb = d.dict_obj.get("RBGroups").?;
    try std.testing.expectEqual(@as(usize, 1), rb.array_obj.list.items.len);

    const locked = d.dict_obj.get("Locked").?;
    try std.testing.expectEqual(@as(usize, 1), locked.array_obj.list.items.len);

    // Each layer should have a resolved ref.
    const bg_ref = try b.layerRef(bg);
    try std.testing.expect(bg_ref.obj_num != 0);
}
