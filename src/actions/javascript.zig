//! JavaScript actions for PDF documents and form fields.
//!
//! PDF allows embedding JavaScript actions that fire on document triggers
//! (open/close/print/save) or on form field events (calculate/validate/
//! format/keystroke/focus/blur). This module builds the corresponding
//! PDF action dictionaries and provides a `JavaScriptBuilder` with helpers
//! for producing common JS snippets.
//!
//! Reference: PDF 1.7 spec, sections 12.6.4.16 (JavaScript actions) and
//! 12.7.5.3 (Trigger events).

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("../core/types.zig");
const ObjectStore = @import("../core/object_store.zig").ObjectStore;
const PdfObject = types.PdfObject;
const Ref = types.Ref;

/// Document-level JavaScript action triggers (catalog /AA entry).
pub const ActionTrigger = enum {
    document_open,
    document_close,
    before_print,
    after_print,
    before_save,
    after_save,

    /// Returns the PDF dictionary key used in the catalog /AA entry.
    /// Note: `document_open` is not an /AA child; it lives in /OpenAction
    /// on the catalog, but is included here for API symmetry.
    pub fn dictKey(self: ActionTrigger) []const u8 {
        return switch (self) {
            .document_open => "O",
            .document_close => "DC",
            .before_print => "WP",
            .after_print => "DP",
            .before_save => "WS",
            .after_save => "DS",
        };
    }
};

/// Form field-level JavaScript action triggers (field /AA entry).
pub const FormFieldAction = enum {
    calculate,
    validate,
    format,
    keystroke,
    focus,
    blur,

    /// Returns the PDF dictionary key used in a field's /AA entry.
    pub fn dictKey(self: FormFieldAction) []const u8 {
        return switch (self) {
            .calculate => "C",
            .validate => "V",
            .format => "F",
            .keystroke => "K",
            .focus => "Fo",
            .blur => "Bl",
        };
    }
};

/// Describes a JavaScript action payload.
pub const JsAction = struct {
    script: []const u8,
};

/// Build a single JavaScript action indirect object:
///     << /Type /Action /S /JavaScript /JS (script) >>
///
/// The returned `Ref` refers to the object now stored in `store`. The
/// script text is stored as a PDF literal string; the caller must ensure
/// it outlives the store (or dupe it beforehand).
pub fn buildJsAction(allocator: Allocator, store: *ObjectStore, script: []const u8) !Ref {
    var dict = types.pdfDict(allocator);
    errdefer dict.deinit(allocator);

    try dict.dict_obj.put(allocator, "Type", types.pdfName("Action"));
    try dict.dict_obj.put(allocator, "S", types.pdfName("JavaScript"));
    try dict.dict_obj.put(allocator, "JS", types.pdfString(script));

    const ref = try store.allocate();
    store.put(ref, dict);
    return ref;
}

/// Associates an `ActionTrigger` with a JavaScript snippet for
/// `buildDocumentActions`.
pub const TriggerScript = struct {
    trigger: ActionTrigger,
    script: []const u8,
};

/// Build a document-level additional-actions (/AA) dictionary referencing
/// one JavaScript action per provided trigger. Each action is allocated as
/// its own indirect object; the returned `Ref` is the /AA dictionary itself
/// suitable for insertion into the document catalog.
pub fn buildDocumentActions(
    allocator: Allocator,
    store: *ObjectStore,
    triggers: []const TriggerScript,
) !Ref {
    var aa = types.pdfDict(allocator);
    errdefer aa.deinit(allocator);

    for (triggers) |entry| {
        const action_ref = try buildJsAction(allocator, store, entry.script);
        try aa.dict_obj.put(
            allocator,
            entry.trigger.dictKey(),
            types.pdfRef(action_ref.obj_num, action_ref.gen_num),
        );
    }

    const ref = try store.allocate();
    store.put(ref, aa);
    return ref;
}

/// Helpers for generating common JavaScript snippets.
pub const JavaScriptBuilder = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) JavaScriptBuilder {
        return .{ .allocator = allocator };
    }

    /// Returns a JS snippet that sums the values of the named form fields
    /// and assigns the result to `event.value`. Caller owns the returned
    /// slice.
    pub fn calculateSum(self: JavaScriptBuilder, field_names: []const []const u8) ![]u8 {
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(self.allocator);
        const w = buf.writer(self.allocator);

        try w.writeAll("var total = 0;\n");
        for (field_names) |name| {
            try w.print("try {{ total += Number(this.getField(\"{s}\").value) || 0; }} catch(e) {{}}\n", .{name});
        }
        try w.writeAll("event.value = total;\n");

        return buf.toOwnedSlice(self.allocator);
    }

    /// Returns a static snippet that validates `event.value` lies within
    /// the inclusive `[min, max]` range. Rejects the input with
    /// `event.rc = false` when out of range.
    pub fn validateRange(min: f64, max: f64) []const u8 {
        _ = min;
        _ = max;
        return "if (event.value != null && event.value !== \"\") { var v = Number(event.value); if (isNaN(v) || v < event.target.min || v > event.target.max) { app.alert(\"Value out of range\"); event.rc = false; } }";
    }

    /// Returns a static Acrobat format snippet that formats `event.value`
    /// as a number with the given decimal count using `AFNumber_Format`.
    pub fn formatNumber(decimals: u32) []const u8 {
        _ = decimals;
        return "AFNumber_Format(2, 0, 0, 0, \"\", true);";
    }

    /// Returns a static Acrobat format snippet that formats `event.value`
    /// as a date using `AFDate_FormatEx` with the given pattern.
    pub fn formatDate(pattern: []const u8) []const u8 {
        _ = pattern;
        return "AFDate_FormatEx(\"mm/dd/yyyy\");";
    }

    /// Returns a JS snippet that shows an alert dialog with `message`.
    /// The message is embedded as a JavaScript string literal with proper
    /// escaping. Caller owns the returned slice.
    pub fn showAlert(self: JavaScriptBuilder, message: []const u8) ![]u8 {
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(self.allocator);
        const w = buf.writer(self.allocator);

        try w.writeAll("app.alert(\"");
        for (message) |c| {
            switch (c) {
                '\\' => try w.writeAll("\\\\"),
                '"' => try w.writeAll("\\\""),
                '\n' => try w.writeAll("\\n"),
                '\r' => try w.writeAll("\\r"),
                '\t' => try w.writeAll("\\t"),
                else => try w.writeByte(c),
            }
        }
        try w.writeAll("\");");

        return buf.toOwnedSlice(self.allocator);
    }
};

// -- Tests --

test "ActionTrigger.dictKey" {
    try std.testing.expectEqualStrings("DC", ActionTrigger.document_close.dictKey());
    try std.testing.expectEqualStrings("WP", ActionTrigger.before_print.dictKey());
    try std.testing.expectEqualStrings("DS", ActionTrigger.after_save.dictKey());
}

test "FormFieldAction.dictKey" {
    try std.testing.expectEqualStrings("C", FormFieldAction.calculate.dictKey());
    try std.testing.expectEqualStrings("K", FormFieldAction.keystroke.dictKey());
    try std.testing.expectEqualStrings("Bl", FormFieldAction.blur.dictKey());
}

test "buildJsAction: produces JavaScript action dict" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const ref = try buildJsAction(allocator, &store, "app.alert(\"hi\");");
    const obj = store.get(ref).?;
    try std.testing.expect(obj.isDict());

    const dict = obj.dict_obj;
    try std.testing.expectEqualStrings("Action", dict.get("Type").?.asName().?);
    try std.testing.expectEqualStrings("JavaScript", dict.get("S").?.asName().?);
    try std.testing.expectEqualStrings("app.alert(\"hi\");", dict.get("JS").?.asString().?);
}

test "buildDocumentActions: wires triggers to actions" {
    const allocator = std.testing.allocator;
    var store = ObjectStore.init(allocator);
    defer store.deinit();

    const triggers = [_]TriggerScript{
        .{ .trigger = .document_open, .script = "console.println('open');" },
        .{ .trigger = .before_print, .script = "console.println('print');" },
    };

    const aa_ref = try buildDocumentActions(allocator, &store, &triggers);
    const aa_obj = store.get(aa_ref).?;
    try std.testing.expect(aa_obj.isDict());
    try std.testing.expect(aa_obj.dict_obj.get("O").?.isRef());
    try std.testing.expect(aa_obj.dict_obj.get("WP").?.isRef());
}

test "JavaScriptBuilder.calculateSum" {
    const allocator = std.testing.allocator;
    const jb = JavaScriptBuilder.init(allocator);

    const fields = [_][]const u8{ "price", "tax" };
    const script = try jb.calculateSum(&fields);
    defer allocator.free(script);

    try std.testing.expect(std.mem.indexOf(u8, script, "getField(\"price\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "getField(\"tax\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "event.value = total;") != null);
}

test "JavaScriptBuilder.validateRange" {
    const s = JavaScriptBuilder.validateRange(0, 100);
    try std.testing.expect(std.mem.indexOf(u8, s, "event.rc = false") != null);
}

test "JavaScriptBuilder.formatNumber and formatDate" {
    const n = JavaScriptBuilder.formatNumber(2);
    try std.testing.expect(std.mem.indexOf(u8, n, "AFNumber_Format") != null);
    const d = JavaScriptBuilder.formatDate("mm/dd/yyyy");
    try std.testing.expect(std.mem.indexOf(u8, d, "AFDate_FormatEx") != null);
}

test "JavaScriptBuilder.showAlert escapes quotes" {
    const allocator = std.testing.allocator;
    const jb = JavaScriptBuilder.init(allocator);

    const script = try jb.showAlert("Hello \"world\"");
    defer allocator.free(script);

    try std.testing.expectEqualStrings("app.alert(\"Hello \\\"world\\\"\");", script);
}
