//! Demonstrates zpdf's JavaScript action helpers: generating JS snippets
//! for common form scenarios (sum calculation, range validation, number
//! formatting, alert dialogs) and building PDF JavaScript action objects
//! wired to document-level triggers via an /AA dictionary.

const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // -- Generate a few JS snippets --
    const jb = zpdf.JavaScriptBuilder.init(allocator);

    const sum_fields = [_][]const u8{ "subtotal", "tax", "shipping" };
    const sum_script = try jb.calculateSum(&sum_fields);
    defer allocator.free(sum_script);
    std.debug.print("calculateSum:\n{s}\n\n", .{sum_script});

    const range = zpdf.JavaScriptBuilder.validateRange(0, 1000);
    std.debug.print("validateRange: {s}\n\n", .{range});

    const fmt_num = zpdf.JavaScriptBuilder.formatNumber(2);
    std.debug.print("formatNumber: {s}\n\n", .{fmt_num});

    const fmt_date = zpdf.JavaScriptBuilder.formatDate("mm/dd/yyyy");
    std.debug.print("formatDate: {s}\n\n", .{fmt_date});

    const alert_script = try jb.showAlert("Welcome to the form!");
    defer allocator.free(alert_script);
    std.debug.print("showAlert:\n{s}\n\n", .{alert_script});

    // -- Build PDF JavaScript actions tied to document triggers --
    var store = zpdf.ObjectStore.init(allocator);
    defer store.deinit();

    const single = try zpdf.buildJsAction(allocator, &store, "app.alert(\"Document opened\");");
    std.debug.print("Single JS action allocated as object #{d}\n", .{single.obj_num});

    const triggers = [_]zpdf.TriggerScript{
        .{ .trigger = .document_open, .script = "app.alert(\"Open\");" },
        .{ .trigger = .before_print, .script = "app.alert(\"About to print\");" },
        .{ .trigger = .before_save, .script = "app.alert(\"Saving\");" },
    };
    const aa = try zpdf.buildDocumentActions(allocator, &store, &triggers);
    std.debug.print("Catalog /AA dict allocated as object #{d}\n", .{aa.obj_num});
    std.debug.print("Total objects in store: {d}\n", .{store.count()});
}
