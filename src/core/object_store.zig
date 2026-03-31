const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const types = @import("types.zig");
const PdfObject = types.PdfObject;
const Ref = types.Ref;

/// Entry in the object store, holding an optional object for a given reference slot.
const ObjectEntry = struct {
    ref: Ref,
    object: ?PdfObject,
};

/// Stores indirect PDF objects keyed by their reference (object number + generation).
pub const ObjectStore = struct {
    allocator: Allocator,
    objects: ArrayList(ObjectEntry),
    next_obj_num: u32,

    /// Initializes an empty object store.
    pub fn init(allocator: Allocator) ObjectStore {
        return .{
            .allocator = allocator,
            .objects = .{},
            .next_obj_num = 1,
        };
    }

    /// Frees all stored objects and the internal list.
    pub fn deinit(self: *ObjectStore) void {
        for (self.objects.items) |*entry| {
            if (entry.object) |*obj| {
                obj.deinit(self.allocator);
            }
        }
        self.objects.deinit(self.allocator);
    }

    /// Allocates the next available object number and returns a reference to it.
    /// The object slot is created but left empty until `put` is called.
    pub fn allocate(self: *ObjectStore) Allocator.Error!Ref {
        const ref = Ref{ .obj_num = self.next_obj_num, .gen_num = 0 };
        self.next_obj_num += 1;
        try self.objects.append(self.allocator, .{ .ref = ref, .object = null });
        return ref;
    }

    /// Stores a PDF object at the given reference. If the reference already exists
    /// its previous value is replaced (and deinited).
    pub fn put(self: *ObjectStore, ref: Ref, object: PdfObject) void {
        for (self.objects.items) |*entry| {
            if (entry.ref.eql(ref)) {
                if (entry.object) |*old| {
                    old.deinit(self.allocator);
                }
                entry.object = object;
                return;
            }
        }
    }

    /// Retrieves the PDF object stored at the given reference, or null if not found.
    pub fn get(self: *ObjectStore, ref: Ref) ?PdfObject {
        for (self.objects.items) |entry| {
            if (entry.ref.eql(ref)) {
                return entry.object;
            }
        }
        return null;
    }

    /// Returns the number of allocated object slots.
    pub fn count(self: *const ObjectStore) usize {
        return self.objects.items.len;
    }
};

// -- Tests --

test "allocate increments object numbers" {
    var store = ObjectStore.init(std.testing.allocator);
    defer store.deinit();

    const ref1 = try store.allocate();
    const ref2 = try store.allocate();

    try std.testing.expectEqual(@as(u32, 1), ref1.obj_num);
    try std.testing.expectEqual(@as(u32, 2), ref2.obj_num);
    try std.testing.expectEqual(@as(usize, 2), store.count());
}

test "put and get object" {
    var store = ObjectStore.init(std.testing.allocator);
    defer store.deinit();

    const ref = try store.allocate();
    store.put(ref, types.pdfInt(42));

    const obj = store.get(ref);
    try std.testing.expect(obj != null);
    try std.testing.expectEqual(@as(i64, 42), obj.?.asInt().?);
}

test "get returns null for unknown ref" {
    var store = ObjectStore.init(std.testing.allocator);
    defer store.deinit();

    const unknown = Ref{ .obj_num = 999, .gen_num = 0 };
    try std.testing.expect(store.get(unknown) == null);
}

test "put replaces existing object" {
    var store = ObjectStore.init(std.testing.allocator);
    defer store.deinit();

    const ref = try store.allocate();
    store.put(ref, types.pdfInt(1));
    store.put(ref, types.pdfInt(2));

    const obj = store.get(ref);
    try std.testing.expectEqual(@as(i64, 2), obj.?.asInt().?);
}
