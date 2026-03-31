const std = @import("std");
const zpdf = @import("zpdf");
const testing = std.testing;

const types = zpdf.core.types;
const serializeObject = zpdf.writer.object_serializer.serializeObject;

test "serialize null" {
    const result = try serializeObject(testing.allocator, types.pdfNull());
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("null", result);
}

test "serialize bool true and false" {
    const t = try serializeObject(testing.allocator, types.pdfBool(true));
    defer testing.allocator.free(t);
    try testing.expectEqualStrings("true", t);

    const f = try serializeObject(testing.allocator, types.pdfBool(false));
    defer testing.allocator.free(f);
    try testing.expectEqualStrings("false", f);
}

test "serialize int" {
    const result = try serializeObject(testing.allocator, types.pdfInt(42));
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("42", result);
}

test "serialize real" {
    const result = try serializeObject(testing.allocator, types.pdfReal(3.14));
    defer testing.allocator.free(result);
    try testing.expect(std.mem.startsWith(u8, result, "3.14"));
}

test "serialize string with escapes" {
    const result = try serializeObject(testing.allocator, types.pdfString("hello (world)"));
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("(hello \\(world\\))", result);
}

test "serialize name" {
    const result = try serializeObject(testing.allocator, types.pdfName("Type"));
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("/Type", result);
}

test "serialize ref" {
    const result = try serializeObject(testing.allocator, types.pdfRef(5, 0));
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("5 0 R", result);
}

test "serialize hex string" {
    const result = try serializeObject(testing.allocator, .{ .hex_string = &[_]u8{ 0xDE, 0xAD } });
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("<dead>", result);
}

test "serialize array" {
    var obj = types.pdfArray(testing.allocator);
    defer obj.deinit(testing.allocator);
    try obj.array_obj.append(types.pdfInt(1));
    try obj.array_obj.append(types.pdfInt(2));

    const result = try serializeObject(testing.allocator, obj);
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("[1 2]", result);
}
