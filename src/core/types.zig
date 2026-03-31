const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;
const StringHashMap = std.StringHashMapUnmanaged;
const Allocator = std.mem.Allocator;

/// A reference to an indirect PDF object identified by object number and generation number.
pub const Ref = struct {
    obj_num: u32,
    gen_num: u16,

    pub fn eql(self: Ref, other: Ref) bool {
        return self.obj_num == other.obj_num and self.gen_num == other.gen_num;
    }
};

/// A PDF stream object consisting of a dictionary and raw byte data.
pub const Stream = struct {
    dict: StringHashMap(PdfObject),
    data: []const u8,

    pub fn deinit(self: *Stream, allocator: Allocator) void {
        var it = self.dict.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        self.dict.deinit(allocator);
    }
};

/// Represents any PDF object type as defined in the PDF specification.
pub const PdfObject = union(enum) {
    null_obj,
    bool_obj: bool,
    int_obj: i64,
    real_obj: f64,
    string_obj: []const u8,
    hex_string: []const u8,
    name_obj: []const u8,
    array_obj: ArrayWithAllocator,
    dict_obj: StringHashMap(PdfObject),
    stream_obj: Stream,
    ref_obj: Ref,

    /// Wrapper that pairs an unmanaged ArrayList with its allocator so that
    /// recursive deinit can free child elements without requiring the caller
    /// to pass an allocator at every level.
    pub const ArrayWithAllocator = struct {
        list: ArrayList(PdfObject),
        allocator: Allocator,

        pub fn append(self: *ArrayWithAllocator, item: PdfObject) Allocator.Error!void {
            return self.list.append(self.allocator, item);
        }
    };

    /// Recursively frees all memory owned by this object and its children.
    pub fn deinit(self: *PdfObject, allocator: Allocator) void {
        switch (self.*) {
            .array_obj => |*arr| {
                for (arr.list.items) |*item| {
                    @constCast(item).deinit(allocator);
                }
                arr.list.deinit(arr.allocator);
            },
            .dict_obj => |*dict| {
                var it = dict.iterator();
                while (it.next()) |entry| {
                    entry.value_ptr.deinit(allocator);
                }
                dict.deinit(allocator);
            },
            .stream_obj => |*stream| {
                stream.deinit(allocator);
            },
            else => {},
        }
    }

    // -- Type checking functions --

    pub fn isNull(self: PdfObject) bool {
        return self == .null_obj;
    }

    pub fn isBool(self: PdfObject) bool {
        return self == .bool_obj;
    }

    pub fn isInt(self: PdfObject) bool {
        return self == .int_obj;
    }

    pub fn isReal(self: PdfObject) bool {
        return self == .real_obj;
    }

    pub fn isString(self: PdfObject) bool {
        return self == .string_obj;
    }

    pub fn isName(self: PdfObject) bool {
        return self == .name_obj;
    }

    pub fn isArray(self: PdfObject) bool {
        return self == .array_obj;
    }

    pub fn isDict(self: PdfObject) bool {
        return self == .dict_obj;
    }

    pub fn isStream(self: PdfObject) bool {
        return self == .stream_obj;
    }

    pub fn isRef(self: PdfObject) bool {
        return self == .ref_obj;
    }

    // -- Getter functions returning optionals --

    pub fn asBool(self: PdfObject) ?bool {
        return switch (self) {
            .bool_obj => |v| v,
            else => null,
        };
    }

    pub fn asInt(self: PdfObject) ?i64 {
        return switch (self) {
            .int_obj => |v| v,
            else => null,
        };
    }

    pub fn asReal(self: PdfObject) ?f64 {
        return switch (self) {
            .real_obj => |v| v,
            else => null,
        };
    }

    pub fn asString(self: PdfObject) ?[]const u8 {
        return switch (self) {
            .string_obj => |v| v,
            else => null,
        };
    }

    pub fn asName(self: PdfObject) ?[]const u8 {
        return switch (self) {
            .name_obj => |v| v,
            else => null,
        };
    }

    pub fn asArray(self: *PdfObject) ?*ArrayWithAllocator {
        return switch (self.*) {
            .array_obj => &self.array_obj,
            else => null,
        };
    }

    pub fn asDict(self: *PdfObject) ?*StringHashMap(PdfObject) {
        return switch (self.*) {
            .dict_obj => &self.dict_obj,
            else => null,
        };
    }

    pub fn asStream(self: *PdfObject) ?*Stream {
        return switch (self.*) {
            .stream_obj => &self.stream_obj,
            else => null,
        };
    }

    pub fn asRef(self: PdfObject) ?Ref {
        return switch (self) {
            .ref_obj => |v| v,
            else => null,
        };
    }
};

// -- Constructor functions --

/// Creates a PDF null object.
pub fn pdfNull() PdfObject {
    return .null_obj;
}

/// Creates a PDF boolean object.
pub fn pdfBool(val: bool) PdfObject {
    return .{ .bool_obj = val };
}

/// Creates a PDF integer object.
pub fn pdfInt(val: i64) PdfObject {
    return .{ .int_obj = val };
}

/// Creates a PDF real (floating-point) object.
pub fn pdfReal(val: f64) PdfObject {
    return .{ .real_obj = val };
}

/// Creates a PDF string object (literal string).
pub fn pdfString(val: []const u8) PdfObject {
    return .{ .string_obj = val };
}

/// Creates a PDF hexadecimal string object.
pub fn pdfHexString(val: []const u8) PdfObject {
    return .{ .hex_string = val };
}

/// Creates a PDF name object.
pub fn pdfName(val: []const u8) PdfObject {
    return .{ .name_obj = val };
}

/// Creates an empty PDF array object.
pub fn pdfArray(allocator: Allocator) PdfObject {
    return .{ .array_obj = .{
        .list = .{},
        .allocator = allocator,
    } };
}

/// Creates an empty PDF dictionary object.
pub fn pdfDict(allocator: Allocator) PdfObject {
    _ = allocator;
    return .{ .dict_obj = .{} };
}

/// Creates a PDF indirect reference object.
pub fn pdfRef(obj_num: u32, gen_num: u16) PdfObject {
    return .{ .ref_obj = .{ .obj_num = obj_num, .gen_num = gen_num } };
}

// -- Tests --

test "null object" {
    const obj = pdfNull();
    try std.testing.expect(obj.isNull());
    try std.testing.expect(!obj.isBool());
}

test "bool object" {
    const obj = pdfBool(true);
    try std.testing.expect(obj.isBool());
    try std.testing.expectEqual(true, obj.asBool().?);
}

test "int object" {
    const obj = pdfInt(42);
    try std.testing.expect(obj.isInt());
    try std.testing.expectEqual(@as(i64, 42), obj.asInt().?);
}

test "real object" {
    const obj = pdfReal(3.14);
    try std.testing.expect(obj.isReal());
    try std.testing.expectApproxEqAbs(3.14, obj.asReal().?, 0.001);
}

test "string object" {
    const obj = pdfString("hello");
    try std.testing.expect(obj.isString());
    try std.testing.expectEqualStrings("hello", obj.asString().?);
}

test "name object" {
    const obj = pdfName("Type");
    try std.testing.expect(obj.isName());
    try std.testing.expectEqualStrings("Type", obj.asName().?);
}

test "ref object" {
    const obj = pdfRef(1, 0);
    try std.testing.expect(obj.isRef());
    const r = obj.asRef().?;
    try std.testing.expectEqual(@as(u32, 1), r.obj_num);
    try std.testing.expectEqual(@as(u16, 0), r.gen_num);
}

test "array object" {
    const allocator = std.testing.allocator;
    var obj = pdfArray(allocator);
    defer obj.deinit(allocator);

    try obj.array_obj.append(pdfInt(1));
    try obj.array_obj.append(pdfInt(2));

    try std.testing.expect(obj.isArray());
    try std.testing.expectEqual(@as(usize, 2), obj.array_obj.list.items.len);
}

test "dict object" {
    const allocator = std.testing.allocator;
    var obj = pdfDict(allocator);
    defer obj.deinit(allocator);

    try obj.dict_obj.put(allocator, "Type", pdfName("Page"));

    try std.testing.expect(obj.isDict());
    try std.testing.expectEqual(@as(usize, 1), obj.dict_obj.count());
}

test "getter returns null for wrong type" {
    const obj = pdfInt(10);
    try std.testing.expect(obj.asBool() == null);
    try std.testing.expect(obj.asReal() == null);
    try std.testing.expect(obj.asString() == null);
    try std.testing.expect(obj.asName() == null);
    try std.testing.expect(obj.asRef() == null);
}
