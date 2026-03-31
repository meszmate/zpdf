const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;
const StringHashMap = std.StringHashMapUnmanaged;
const Allocator = std.mem.Allocator;
const types = @import("../core/types.zig");
const PdfObject = types.PdfObject;
const ByteBuffer = @import("../utils/buffer.zig").ByteBuffer;

/// Escapes special characters in a PDF literal string: backslash, parens, CR, LF.
pub fn escapeString(allocator: Allocator, s: []const u8) ![]u8 {
    var result: ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    for (s) |ch| {
        switch (ch) {
            '(' => try result.appendSlice(allocator, "\\("),
            ')' => try result.appendSlice(allocator, "\\)"),
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            '\n' => try result.appendSlice(allocator, "\\n"),
            else => try result.append(allocator, ch),
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Serializes a PdfObject to its PDF syntax representation.
pub fn serializeObject(allocator: Allocator, obj: PdfObject) ![]u8 {
    var buf = ByteBuffer.init(allocator);
    defer buf.deinit();

    try writeObject(&buf, obj);

    return buf.toOwnedSlice();
}

/// Serializes a PDF dictionary to its string representation.
pub fn serializeDict(allocator: Allocator, dict: StringHashMap(PdfObject)) ![]u8 {
    var buf = ByteBuffer.init(allocator);
    defer buf.deinit();

    try writeDictToBuf(&buf, dict);

    return buf.toOwnedSlice();
}

/// Serializes a PDF array to its string representation.
pub fn serializeArray(allocator: Allocator, array: types.PdfObject.ArrayWithAllocator) ![]u8 {
    var buf = ByteBuffer.init(allocator);
    defer buf.deinit();

    try writeArrayToBuf(&buf, array);

    return buf.toOwnedSlice();
}

/// Writes a PdfObject into a ByteBuffer in PDF syntax.
pub fn writeObject(buf: *ByteBuffer, obj: PdfObject) Allocator.Error!void {
    switch (obj) {
        .null_obj => try buf.write("null"),
        .bool_obj => |v| {
            if (v) {
                try buf.write("true");
            } else {
                try buf.write("false");
            }
        },
        .int_obj => |v| try buf.writeFmt("{d}", .{v}),
        .real_obj => |v| try buf.writeFmt("{d:.4}", .{v}),
        .string_obj => |v| {
            const escaped = try escapeString(buf.allocator, v);
            defer buf.allocator.free(escaped);
            try buf.write("(");
            try buf.write(escaped);
            try buf.write(")");
        },
        .hex_string => |v| {
            try buf.write("<");
            for (v) |byte| {
                try buf.writeFmt("{x:0>2}", .{byte});
            }
            try buf.write(">");
        },
        .name_obj => |v| {
            try buf.write("/");
            try buf.write(v);
        },
        .array_obj => |arr| try writeArrayToBuf(buf, arr),
        .dict_obj => |dict| try writeDictToBuf(buf, dict),
        .stream_obj => |stream| {
            try writeDictToBuf(buf, stream.dict);
            try buf.write("\nstream\n");
            try buf.write(stream.data);
            try buf.write("\nendstream");
        },
        .ref_obj => |ref| try buf.writeFmt("{d} {d} R", .{ ref.obj_num, ref.gen_num }),
    }
}

fn writeArrayToBuf(buf: *ByteBuffer, array: types.PdfObject.ArrayWithAllocator) Allocator.Error!void {
    try buf.write("[");
    for (array.list.items, 0..) |item, i| {
        if (i > 0) try buf.write(" ");
        try writeObject(buf, item);
    }
    try buf.write("]");
}

fn writeDictToBuf(buf: *ByteBuffer, dict: StringHashMap(PdfObject)) Allocator.Error!void {
    try buf.write("<< ");
    var it = dict.iterator();
    while (it.next()) |entry| {
        try buf.write("/");
        try buf.write(entry.key_ptr.*);
        try buf.write(" ");
        try writeObject(buf, entry.value_ptr.*);
        try buf.write(" ");
    }
    try buf.write(">>");
}

// -- Tests --

test "serialize null" {
    const result = try serializeObject(std.testing.allocator, .null_obj);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("null", result);
}

test "serialize bool" {
    const t = try serializeObject(std.testing.allocator, .{ .bool_obj = true });
    defer std.testing.allocator.free(t);
    try std.testing.expectEqualStrings("true", t);

    const f = try serializeObject(std.testing.allocator, .{ .bool_obj = false });
    defer std.testing.allocator.free(f);
    try std.testing.expectEqualStrings("false", f);
}

test "serialize int" {
    const result = try serializeObject(std.testing.allocator, .{ .int_obj = 42 });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("42", result);
}

test "serialize name" {
    const result = try serializeObject(std.testing.allocator, .{ .name_obj = "Type" });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("/Type", result);
}

test "serialize string with escapes" {
    const result = try serializeObject(std.testing.allocator, .{ .string_obj = "hello (world)" });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("(hello \\(world\\))", result);
}

test "serialize ref" {
    const result = try serializeObject(std.testing.allocator, .{ .ref_obj = .{ .obj_num = 5, .gen_num = 0 } });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("5 0 R", result);
}

test "escape string" {
    const result = try escapeString(std.testing.allocator, "a\\b(c)d\n");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("a\\\\b\\(c\\)d\\n", result);
}

test "serialize hex string" {
    const result = try serializeObject(std.testing.allocator, .{ .hex_string = &[_]u8{ 0xDE, 0xAD } });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("<dead>", result);
}
