const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("../core/types.zig");
const ObjectStore = @import("../core/object_store.zig").ObjectStore;
const Ref = core.Ref;
const PdfObject = core.PdfObject;
const form = @import("form.zig");
const FormField = form.FormField;
const FieldType = form.FieldType;
const FieldFlags = form.FieldFlags;
const Rect = form.Rect;
const TextFieldOptions = form.TextFieldOptions;
const DropdownOptions = form.DropdownOptions;
const RadioOption = form.RadioOption;
const StandardFont = @import("../font/standard_fonts.zig").StandardFont;

/// Builder for constructing PDF interactive forms (AcroForms).
pub const FormBuilder = struct {
    allocator: Allocator,
    fields: std.ArrayListUnmanaged(FormField),

    /// Initialize a new form builder.
    pub fn init(allocator: Allocator) FormBuilder {
        return .{
            .allocator = allocator,
            .fields = .empty,
        };
    }

    /// Free all resources owned by this builder.
    pub fn deinit(self: *FormBuilder) void {
        self.fields.deinit(self.allocator);
    }

    /// Add a text input field.
    pub fn addTextField(self: *FormBuilder, name: []const u8, rect: Rect, options: TextFieldOptions) !void {
        try self.fields.append(self.allocator, form.TextField(name, rect, options));
    }

    /// Add a checkbox field.
    pub fn addCheckbox(self: *FormBuilder, name: []const u8, rect: Rect, checked: bool) !void {
        try self.fields.append(self.allocator, form.CheckboxField(name, rect, checked));
    }

    /// Add a dropdown (combo box) field.
    pub fn addDropdown(self: *FormBuilder, name: []const u8, rect: Rect, options: []const []const u8, selected: ?[]const u8, opts: DropdownOptions) !void {
        try self.fields.append(self.allocator, form.DropdownField(name, rect, options, selected, opts));
    }

    /// Add a radio button group. Creates individual radio button fields
    /// sharing the same group name.
    pub fn addRadioGroup(self: *FormBuilder, name: []const u8, options: []const RadioOption) !void {
        for (options) |opt| {
            try self.fields.append(self.allocator, form.RadioField(name, opt.rect, opt.value));
        }
    }

    /// Build the AcroForm dictionary and all field objects in the object store.
    /// Returns a reference to the AcroForm dictionary object.
    pub fn build(self: *FormBuilder, store: *ObjectStore) !Ref {
        // Create field references
        var field_refs: std.ArrayListUnmanaged(PdfObject) = .empty;
        defer field_refs.deinit(self.allocator);

        for (self.fields.items) |field| {
            const field_ref = try store.allocate();
            const field_obj = try buildFieldObject(self.allocator, field);
            store.put(field_ref, field_obj);
            try field_refs.append(self.allocator, core.pdfRef(field_ref.obj_num, field_ref.gen_num));
        }

        // Create AcroForm dictionary
        const acroform_ref = try store.allocate();
        var acroform_dict: std.StringHashMapUnmanaged(PdfObject) = .{};

        // Fields array
        var fields_array = core.pdfArray(self.allocator);
        for (field_refs.items) |ref_obj| {
            try fields_array.array_obj.append(ref_obj);
        }
        try acroform_dict.put(self.allocator,"Fields", fields_array);

        // NeedAppearances flag
        try acroform_dict.put(self.allocator,"NeedAppearances", core.pdfBool(true));

        store.put(acroform_ref, .{ .dict_obj = acroform_dict });

        return acroform_ref;
    }
};

/// Build a PDF dictionary object for a single form field.
fn buildFieldObject(allocator: Allocator, field: FormField) !PdfObject {
    var dict = std.StringHashMapUnmanaged(PdfObject){};

    // Field type
    try dict.put(allocator,"FT", core.pdfName(field.field_type.pdfFieldType()));

    // Field name
    try dict.put(allocator,"T", core.pdfString(field.name));

    // Rectangle
    const pdf_rect = field.rect.toPdfRect();
    var rect_array = core.pdfArray(allocator);
    try rect_array.array_obj.append(core.pdfReal(@floatCast(pdf_rect[0])));
    try rect_array.array_obj.append(core.pdfReal(@floatCast(pdf_rect[1])));
    try rect_array.array_obj.append(core.pdfReal(@floatCast(pdf_rect[2])));
    try rect_array.array_obj.append(core.pdfReal(@floatCast(pdf_rect[3])));
    try dict.put(allocator,"Rect", rect_array);

    // Type annotation
    try dict.put(allocator,"Type", core.pdfName("Annot"));
    try dict.put(allocator,"Subtype", core.pdfName("Widget"));

    // Value
    if (field.value) |val| {
        if (field.field_type == .checkbox) {
            try dict.put(allocator,"V", core.pdfName(val));
            try dict.put(allocator,"AS", core.pdfName(val));
        } else {
            try dict.put(allocator,"V", core.pdfString(val));
        }
    }

    // Flags
    if (field.flags != 0) {
        try dict.put(allocator,"Ff", core.pdfInt(@intCast(field.flags)));
    }

    // Options (for dropdown/listbox)
    if (field.options) |opts| {
        var opt_array = core.pdfArray(allocator);
        for (opts) |opt| {
            try opt_array.array_obj.append(core.pdfString(opt));
        }
        try dict.put(allocator,"Opt", opt_array);
    }

    // Default appearance string for text fields
    if (field.field_type == .text or field.field_type == .dropdown or field.field_type == .listbox) {
        const font_name = if (field.font) |f| f.pdfName() else "Helvetica";
        const font_size = field.font_size orelse 12.0;
        var da_buf: [128]u8 = undefined;
        const da = std.fmt.bufPrint(&da_buf, "/{s} {d:.1} Tf 0 g", .{ font_name, font_size }) catch "/Helvetica 12.0 Tf 0 g";
        try dict.put(allocator, "DA", core.pdfString(da));
    }

    return .{ .dict_obj = dict };
}

// -- Tests --

test "FormBuilder: init and deinit" {
    var builder = FormBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try std.testing.expectEqual(@as(usize, 0), builder.fields.items.len);
}

test "FormBuilder: addTextField" {
    var builder = FormBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.addTextField("name", .{ .x = 10, .y = 700, .w = 200, .h = 24 }, .{});

    try std.testing.expectEqual(@as(usize, 1), builder.fields.items.len);
    try std.testing.expectEqualStrings("name", builder.fields.items[0].name);
    try std.testing.expectEqual(FieldType.text, builder.fields.items[0].field_type);
}

test "FormBuilder: addCheckbox" {
    var builder = FormBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.addCheckbox("agree", .{ .x = 10, .y = 650, .w = 14, .h = 14 }, true);

    try std.testing.expectEqual(@as(usize, 1), builder.fields.items.len);
    try std.testing.expectEqualStrings("Yes", builder.fields.items[0].value.?);
}

test "FormBuilder: addDropdown" {
    var builder = FormBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const opts = [_][]const u8{ "Red", "Green", "Blue" };
    try builder.addDropdown("color", .{ .x = 10, .y = 600, .w = 150, .h = 24 }, &opts, "Red", .{});

    try std.testing.expectEqual(@as(usize, 1), builder.fields.items.len);
    try std.testing.expectEqual(FieldType.dropdown, builder.fields.items[0].field_type);
    try std.testing.expect(builder.fields.items[0].options != null);
}

test "FormBuilder: addRadioGroup" {
    var builder = FormBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const radio_opts = [_]RadioOption{
        .{ .value = "option1", .rect = .{ .x = 10, .y = 500, .w = 14, .h = 14 } },
        .{ .value = "option2", .rect = .{ .x = 10, .y = 480, .w = 14, .h = 14 } },
    };
    try builder.addRadioGroup("choice", &radio_opts);

    try std.testing.expectEqual(@as(usize, 2), builder.fields.items.len);
    try std.testing.expectEqual(FieldType.radio, builder.fields.items[0].field_type);
    try std.testing.expectEqual(FieldType.radio, builder.fields.items[1].field_type);
}

test "FormBuilder: build" {
    var store = ObjectStore.init(std.testing.allocator);
    defer store.deinit();

    var builder = FormBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.addTextField("name", .{ .x = 10, .y = 700, .w = 200, .h = 24 }, .{});
    try builder.addCheckbox("agree", .{ .x = 10, .y = 650, .w = 14, .h = 14 }, false);

    const acroform_ref = try builder.build(&store);

    // Verify the AcroForm was created
    const acroform = store.get(acroform_ref);
    try std.testing.expect(acroform != null);

    // Should have created 3 objects: 2 fields + 1 AcroForm
    try std.testing.expectEqual(@as(usize, 3), store.count());
}
