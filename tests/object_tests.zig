const std = @import("std");
const zpdf = @import("zpdf");
const testing = std.testing;

const types = zpdf.core.types;
const PdfObject = types.PdfObject;

test "pdfNull creation and type check" {
    const obj = types.pdfNull();
    try testing.expect(obj.isNull());
    try testing.expect(!obj.isBool());
    try testing.expect(!obj.isInt());
}

test "pdfBool creation and getter" {
    const t = types.pdfBool(true);
    const f = types.pdfBool(false);
    try testing.expect(t.isBool());
    try testing.expectEqual(true, t.asBool().?);
    try testing.expectEqual(false, f.asBool().?);
}

test "pdfInt creation and getter" {
    const obj = types.pdfInt(42);
    try testing.expect(obj.isInt());
    try testing.expectEqual(@as(i64, 42), obj.asInt().?);
}

test "pdfReal creation and getter" {
    const obj = types.pdfReal(3.14);
    try testing.expect(obj.isReal());
    try testing.expectApproxEqAbs(3.14, obj.asReal().?, 0.001);
}

test "pdfString and pdfName creation" {
    const s = types.pdfString("hello");
    try testing.expect(s.isString());
    try testing.expectEqualStrings("hello", s.asString().?);

    const n = types.pdfName("Type");
    try testing.expect(n.isName());
    try testing.expectEqualStrings("Type", n.asName().?);
}

test "pdfRef creation and getter" {
    const obj = types.pdfRef(5, 0);
    try testing.expect(obj.isRef());
    const r = obj.asRef().?;
    try testing.expectEqual(@as(u32, 5), r.obj_num);
    try testing.expectEqual(@as(u16, 0), r.gen_num);
}

test "getter returns null for wrong type" {
    const obj = types.pdfInt(10);
    try testing.expect(obj.asBool() == null);
    try testing.expect(obj.asReal() == null);
    try testing.expect(obj.asString() == null);
    try testing.expect(obj.asName() == null);
    try testing.expect(obj.asRef() == null);
}

test "pdfArray append and length" {
    var obj = types.pdfArray(testing.allocator);
    defer obj.deinit(testing.allocator);

    try obj.array_obj.append(types.pdfInt(1));
    try obj.array_obj.append(types.pdfInt(2));

    try testing.expect(obj.isArray());
    try testing.expectEqual(@as(usize, 2), obj.array_obj.list.items.len);
}

test "pdfDict put and count" {
    var obj = types.pdfDict(testing.allocator);
    defer obj.deinit(testing.allocator);

    try obj.dict_obj.put(testing.allocator, "Type", types.pdfName("Page"));
    try testing.expect(obj.isDict());
    try testing.expectEqual(@as(usize, 1), obj.dict_obj.count());
}
