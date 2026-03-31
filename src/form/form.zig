const std = @import("std");
const Allocator = std.mem.Allocator;
const StandardFont = @import("../font/standard_fonts.zig").StandardFont;

/// Types of interactive form fields in PDF.
pub const FieldType = enum {
    text,
    checkbox,
    radio,
    dropdown,
    listbox,
    button,
    signature,

    /// Returns the PDF field type string (/FT value).
    pub fn pdfFieldType(self: FieldType) []const u8 {
        return switch (self) {
            .text => "Tx",
            .checkbox, .radio => "Btn",
            .dropdown, .listbox => "Ch",
            .button => "Btn",
            .signature => "Sig",
        };
    }
};

/// Rectangle defining the position and size of a form field.
pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    /// Convert to PDF rect array format [x1, y1, x2, y2].
    pub fn toPdfRect(self: Rect) [4]f32 {
        return .{
            self.x,
            self.y,
            self.x + self.w,
            self.y + self.h,
        };
    }
};

/// Bit flags for form field properties (PDF spec Table 221, 226, 230).
pub const FieldFlags = struct {
    pub const read_only: u32 = 1 << 0;
    pub const required: u32 = 1 << 1;
    pub const no_export: u32 = 1 << 2;
    // Text field flags
    pub const multiline: u32 = 1 << 12;
    pub const password: u32 = 1 << 13;
    pub const file_select: u32 = 1 << 20;
    pub const do_not_spell_check: u32 = 1 << 22;
    pub const do_not_scroll: u32 = 1 << 23;
    pub const comb: u32 = 1 << 24;
    // Button field flags
    pub const no_toggle_to_off: u32 = 1 << 14;
    pub const radio_flag: u32 = 1 << 15;
    pub const push_button: u32 = 1 << 16;
    // Choice field flags
    pub const combo: u32 = 1 << 17;
    pub const editable: u32 = 1 << 18;
    pub const sort: u32 = 1 << 19;
    pub const multi_select: u32 = 1 << 21;
    pub const commit_on_sel_change: u32 = 1 << 26;
};

/// A single interactive form field.
pub const FormField = struct {
    name: []const u8,
    field_type: FieldType,
    rect: Rect,
    value: ?[]const u8 = null,
    options: ?[]const []const u8 = null,
    font: ?StandardFont = null,
    font_size: ?f32 = null,
    flags: u32 = 0,
};

/// Options for creating a text field.
pub const TextFieldOptions = struct {
    value: ?[]const u8 = null,
    font: ?StandardFont = null,
    font_size: ?f32 = null,
    multiline: bool = false,
    password: bool = false,
    read_only: bool = false,
    required: bool = false,
    max_length: ?u32 = null,
};

/// Options for creating a dropdown field.
pub const DropdownOptions = struct {
    font: ?StandardFont = null,
    font_size: ?f32 = null,
    editable: bool = false,
    read_only: bool = false,
    required: bool = false,
};

/// Options for creating a radio group.
pub const RadioOption = struct {
    value: []const u8,
    rect: Rect,
};

/// Create a text field with convenience options.
pub fn TextField(name: []const u8, rect: Rect, opts: TextFieldOptions) FormField {
    var flags: u32 = 0;
    if (opts.multiline) flags |= FieldFlags.multiline;
    if (opts.password) flags |= FieldFlags.password;
    if (opts.read_only) flags |= FieldFlags.read_only;
    if (opts.required) flags |= FieldFlags.required;

    return FormField{
        .name = name,
        .field_type = .text,
        .rect = rect,
        .value = opts.value,
        .font = opts.font,
        .font_size = opts.font_size,
        .flags = flags,
    };
}

/// Create a checkbox field.
pub fn CheckboxField(name: []const u8, rect: Rect, checked: bool) FormField {
    return FormField{
        .name = name,
        .field_type = .checkbox,
        .rect = rect,
        .value = if (checked) "Yes" else "Off",
        .flags = 0,
    };
}

/// Create a dropdown (combo box) field.
pub fn DropdownField(name: []const u8, rect: Rect, options: []const []const u8, selected: ?[]const u8, opts: DropdownOptions) FormField {
    var flags: u32 = FieldFlags.combo;
    if (opts.editable) flags |= FieldFlags.editable;
    if (opts.read_only) flags |= FieldFlags.read_only;
    if (opts.required) flags |= FieldFlags.required;

    return FormField{
        .name = name,
        .field_type = .dropdown,
        .rect = rect,
        .value = selected,
        .options = options,
        .font = opts.font,
        .font_size = opts.font_size,
        .flags = flags,
    };
}

/// Create a radio button field (one button in a radio group).
pub fn RadioField(name: []const u8, rect: Rect, value: []const u8) FormField {
    return FormField{
        .name = name,
        .field_type = .radio,
        .rect = rect,
        .value = value,
        .flags = FieldFlags.radio_flag | FieldFlags.no_toggle_to_off,
    };
}

// -- Tests --

test "FieldType: pdfFieldType" {
    try std.testing.expectEqualStrings("Tx", FieldType.text.pdfFieldType());
    try std.testing.expectEqualStrings("Btn", FieldType.checkbox.pdfFieldType());
    try std.testing.expectEqualStrings("Ch", FieldType.dropdown.pdfFieldType());
    try std.testing.expectEqualStrings("Sig", FieldType.signature.pdfFieldType());
}

test "Rect: toPdfRect" {
    const r = Rect{ .x = 10, .y = 20, .w = 100, .h = 30 };
    const pdf_rect = r.toPdfRect();
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), pdf_rect[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), pdf_rect[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 110.0), pdf_rect[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), pdf_rect[3], 0.001);
}

test "TextField: basic" {
    const field = TextField("name", .{ .x = 10, .y = 20, .w = 200, .h = 24 }, .{});
    try std.testing.expectEqualStrings("name", field.name);
    try std.testing.expectEqual(FieldType.text, field.field_type);
    try std.testing.expectEqual(@as(u32, 0), field.flags);
}

test "TextField: with flags" {
    const field = TextField("notes", .{ .x = 10, .y = 20, .w = 200, .h = 80 }, .{
        .multiline = true,
        .required = true,
    });
    try std.testing.expect(field.flags & FieldFlags.multiline != 0);
    try std.testing.expect(field.flags & FieldFlags.required != 0);
}

test "CheckboxField" {
    const checked = CheckboxField("agree", .{ .x = 10, .y = 20, .w = 14, .h = 14 }, true);
    try std.testing.expectEqualStrings("Yes", checked.value.?);

    const unchecked = CheckboxField("agree", .{ .x = 10, .y = 20, .w = 14, .h = 14 }, false);
    try std.testing.expectEqualStrings("Off", unchecked.value.?);
}

test "RadioField" {
    const field = RadioField("color", .{ .x = 10, .y = 20, .w = 14, .h = 14 }, "red");
    try std.testing.expectEqual(FieldType.radio, field.field_type);
    try std.testing.expect(field.flags & FieldFlags.radio_flag != 0);
}

test "FieldFlags: constants" {
    try std.testing.expectEqual(@as(u32, 1), FieldFlags.read_only);
    try std.testing.expectEqual(@as(u32, 2), FieldFlags.required);
    try std.testing.expectEqual(@as(u32, 4), FieldFlags.no_export);
    try std.testing.expectEqual(@as(u32, 1 << 12), FieldFlags.multiline);
    try std.testing.expectEqual(@as(u32, 1 << 13), FieldFlags.password);
}
