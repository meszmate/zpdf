const std = @import("std");
const zpdf = @import("zpdf");
const testing = std.testing;

const MergeField = zpdf.MergeField;
const MergeRecord = zpdf.MergeRecord;
const MailMerge = zpdf.MailMerge;
const Document = zpdf.Document;

test "MergeRecord get existing field" {
    const fields = [_]MergeField{
        .{ .name = "first", .value = "Alice" },
        .{ .name = "last", .value = "Smith" },
    };
    const record = MergeRecord{ .fields = &fields };

    try testing.expectEqualStrings("Alice", record.get("first").?);
    try testing.expectEqualStrings("Smith", record.get("last").?);
}

test "MergeRecord get missing field returns null" {
    const fields = [_]MergeField{
        .{ .name = "name", .value = "Bob" },
    };
    const record = MergeRecord{ .fields = &fields };
    try testing.expect(record.get("email") == null);
}

test "replacePlaceholders basic substitution" {
    const allocator = testing.allocator;
    const fields = [_]MergeField{
        .{ .name = "greeting", .value = "Hello" },
        .{ .name = "target", .value = "World" },
    };
    const record = MergeRecord{ .fields = &fields };

    const result = try zpdf.replacePlaceholders(allocator, "{{greeting}}, {{target}}!", record);
    defer allocator.free(result);
    try testing.expectEqualStrings("Hello, World!", result);
}

test "replacePlaceholders no placeholders" {
    const allocator = testing.allocator;
    const fields = [_]MergeField{};
    const record = MergeRecord{ .fields = &fields };

    const input = "No placeholders here.";
    const result = try zpdf.replacePlaceholders(allocator, input, record);
    defer allocator.free(result);
    try testing.expectEqualStrings(input, result);
}

test "replacePlaceholders preserves unknown fields" {
    const allocator = testing.allocator;
    const fields = [_]MergeField{
        .{ .name = "known", .value = "YES" },
    };
    const record = MergeRecord{ .fields = &fields };

    const result = try zpdf.replacePlaceholders(allocator, "{{known}} and {{unknown}}", record);
    defer allocator.free(result);
    try testing.expectEqualStrings("YES and {{unknown}}", result);
}

test "MailMerge error on no records" {
    var mm = MailMerge.init(testing.allocator);
    defer mm.deinit();
    mm.setTemplate("dummy");

    try testing.expectError(error.NoRecords, mm.generate(testing.allocator));
}

test "MailMerge error on no template or builder" {
    var mm = MailMerge.init(testing.allocator);
    defer mm.deinit();

    const fields = [_]MergeField{.{ .name = "x", .value = "y" }};
    try mm.addRecord(&fields);

    try testing.expectError(error.NoTemplate, mm.generate(testing.allocator));
}

test "MailMerge with builder produces valid PDF" {
    const allocator = testing.allocator;

    const S = struct {
        fn build(alloc: std.mem.Allocator, doc: *Document, record: MergeRecord) anyerror!void {
            _ = alloc;
            const page = try doc.addPage(.a4);
            const name = record.get("name") orelse "default";
            try page.drawText(name, .{ .x = 50, .y = 750 });
        }
    };

    var mm = MailMerge.init(allocator);
    defer mm.deinit();
    mm.setBuilder(S.build);

    const f1 = [_]MergeField{.{ .name = "name", .value = "Test1" }};
    const f2 = [_]MergeField{.{ .name = "name", .value = "Test2" }};
    try mm.addRecord(&f1);
    try mm.addRecord(&f2);

    const result = try mm.generate(allocator);
    defer allocator.free(result);

    try testing.expect(result.len > 0);
    try testing.expect(std.mem.startsWith(u8, result, "%PDF"));
}

test "MailMerge generateMultiple returns separate PDFs" {
    const allocator = testing.allocator;

    const S = struct {
        fn build(alloc: std.mem.Allocator, doc: *Document, record: MergeRecord) anyerror!void {
            _ = alloc;
            const page = try doc.addPage(.letter);
            const val = record.get("id") orelse "0";
            try page.drawText(val, .{ .x = 50, .y = 700 });
        }
    };

    var mm = MailMerge.init(allocator);
    defer mm.deinit();
    mm.setBuilder(S.build);

    const f1 = [_]MergeField{.{ .name = "id", .value = "A" }};
    const f2 = [_]MergeField{.{ .name = "id", .value = "B" }};
    const f3 = [_]MergeField{.{ .name = "id", .value = "C" }};
    try mm.addRecord(&f1);
    try mm.addRecord(&f2);
    try mm.addRecord(&f3);

    const results = try mm.generateMultiple(allocator);
    defer {
        for (results) |r| allocator.free(r);
        allocator.free(results);
    }

    try testing.expectEqual(@as(usize, 3), results.len);
    for (results) |r| {
        try testing.expect(r.len > 0);
        try testing.expect(std.mem.startsWith(u8, r, "%PDF"));
    }
}

test "mergeWithBuilder convenience function" {
    const allocator = testing.allocator;

    const S = struct {
        fn build(alloc: std.mem.Allocator, doc: *Document, record: MergeRecord) anyerror!void {
            _ = alloc;
            const page = try doc.addPage(.a4);
            const text = record.get("text") orelse "empty";
            try page.drawText(text, .{ .x = 50, .y = 750 });
        }
    };

    const f1 = [_]MergeField{.{ .name = "text", .value = "Page One" }};
    const f2 = [_]MergeField{.{ .name = "text", .value = "Page Two" }};
    const records = [_]MergeRecord{
        .{ .fields = &f1 },
        .{ .fields = &f2 },
    };

    const result = try zpdf.mergeWithBuilder(allocator, &records, S.build);
    defer allocator.free(result);

    try testing.expect(result.len > 0);
    try testing.expect(std.mem.startsWith(u8, result, "%PDF"));
}
