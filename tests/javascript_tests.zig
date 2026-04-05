const std = @import("std");
const testing = std.testing;
const zpdf = @import("zpdf");

const ActionTrigger = zpdf.ActionTrigger;
const FormFieldAction = zpdf.FormFieldAction;
const JavaScriptBuilder = zpdf.JavaScriptBuilder;
const TriggerScript = zpdf.TriggerScript;
const ObjectStore = zpdf.ObjectStore;

test "trigger dict keys cover all document events" {
    try testing.expectEqualStrings("O", ActionTrigger.document_open.dictKey());
    try testing.expectEqualStrings("DC", ActionTrigger.document_close.dictKey());
    try testing.expectEqualStrings("WP", ActionTrigger.before_print.dictKey());
    try testing.expectEqualStrings("DP", ActionTrigger.after_print.dictKey());
    try testing.expectEqualStrings("WS", ActionTrigger.before_save.dictKey());
    try testing.expectEqualStrings("DS", ActionTrigger.after_save.dictKey());
}

test "form field action dict keys cover all events" {
    try testing.expectEqualStrings("C", FormFieldAction.calculate.dictKey());
    try testing.expectEqualStrings("V", FormFieldAction.validate.dictKey());
    try testing.expectEqualStrings("F", FormFieldAction.format.dictKey());
    try testing.expectEqualStrings("K", FormFieldAction.keystroke.dictKey());
    try testing.expectEqualStrings("Fo", FormFieldAction.focus.dictKey());
    try testing.expectEqualStrings("Bl", FormFieldAction.blur.dictKey());
}

test "buildJsAction stores a /Type /Action /S /JavaScript dict" {
    const allocator = testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const ref = try zpdf.buildJsAction(allocator, &store, "console.println(\"hi\");");
    const obj = store.get(ref).?;
    try testing.expect(obj.isDict());
    try testing.expectEqualStrings("Action", obj.dict_obj.get("Type").?.asName().?);
    try testing.expectEqualStrings("JavaScript", obj.dict_obj.get("S").?.asName().?);
    try testing.expectEqualStrings("console.println(\"hi\");", obj.dict_obj.get("JS").?.asString().?);
}

test "buildDocumentActions produces /AA with entries per trigger" {
    const allocator = testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const triggers = [_]TriggerScript{
        .{ .trigger = .document_open, .script = "1;" },
        .{ .trigger = .before_save, .script = "2;" },
        .{ .trigger = .after_save, .script = "3;" },
    };
    const aa_ref = try zpdf.buildDocumentActions(allocator, &store, &triggers);
    const aa_obj = store.get(aa_ref).?;
    try testing.expect(aa_obj.isDict());
    try testing.expectEqual(@as(usize, 3), aa_obj.dict_obj.count());
    try testing.expect(aa_obj.dict_obj.get("O").?.isRef());
    try testing.expect(aa_obj.dict_obj.get("WS").?.isRef());
    try testing.expect(aa_obj.dict_obj.get("DS").?.isRef());

    // Each trigger should allocate its own action object, plus the /AA dict.
    try testing.expectEqual(@as(usize, 4), store.count());
}

test "JavaScriptBuilder.calculateSum lists each field" {
    const allocator = testing.allocator;
    const jb = JavaScriptBuilder.init(allocator);

    const fields = [_][]const u8{ "a", "b", "c" };
    const script = try jb.calculateSum(&fields);
    defer allocator.free(script);

    try testing.expect(std.mem.indexOf(u8, script, "\"a\"") != null);
    try testing.expect(std.mem.indexOf(u8, script, "\"b\"") != null);
    try testing.expect(std.mem.indexOf(u8, script, "\"c\"") != null);
    try testing.expect(std.mem.indexOf(u8, script, "event.value = total;") != null);
}

test "JavaScriptBuilder.calculateSum handles empty list" {
    const allocator = testing.allocator;
    const jb = JavaScriptBuilder.init(allocator);

    const fields = [_][]const u8{};
    const script = try jb.calculateSum(&fields);
    defer allocator.free(script);

    try testing.expect(std.mem.indexOf(u8, script, "var total = 0;") != null);
    try testing.expect(std.mem.indexOf(u8, script, "event.value = total;") != null);
}

test "JavaScriptBuilder.validateRange returns non-empty snippet" {
    const s = JavaScriptBuilder.validateRange(1, 42);
    try testing.expect(s.len > 0);
    try testing.expect(std.mem.indexOf(u8, s, "event.rc") != null);
}

test "JavaScriptBuilder.formatNumber uses AFNumber_Format" {
    const s = JavaScriptBuilder.formatNumber(3);
    try testing.expect(std.mem.indexOf(u8, s, "AFNumber_Format") != null);
}

test "JavaScriptBuilder.formatDate uses AFDate_FormatEx" {
    const s = JavaScriptBuilder.formatDate("yyyy-mm-dd");
    try testing.expect(std.mem.indexOf(u8, s, "AFDate_FormatEx") != null);
}

test "JavaScriptBuilder.showAlert escapes special characters" {
    const allocator = testing.allocator;
    const jb = JavaScriptBuilder.init(allocator);

    const script = try jb.showAlert("Line1\nLine2 \"quoted\" \\path");
    defer allocator.free(script);

    try testing.expect(std.mem.indexOf(u8, script, "\\n") != null);
    try testing.expect(std.mem.indexOf(u8, script, "\\\"quoted\\\"") != null);
    try testing.expect(std.mem.indexOf(u8, script, "\\\\path") != null);
}

test "showAlert with plain ASCII message" {
    const allocator = testing.allocator;
    const jb = JavaScriptBuilder.init(allocator);

    const script = try jb.showAlert("Hello");
    defer allocator.free(script);

    try testing.expectEqualStrings("app.alert(\"Hello\");", script);
}
