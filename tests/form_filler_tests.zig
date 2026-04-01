const std = @import("std");
const testing = std.testing;
const zpdf = @import("zpdf");

const Document = zpdf.Document;
const PageSize = zpdf.PageSize;
const FormBuilder = zpdf.FormBuilder;
const Rect = zpdf.form.Form.Rect;
const FieldValue = zpdf.FieldValue;
const FlattenOptions = zpdf.FlattenOptions;
const fillForm = zpdf.fillForm;
const flattenForm = zpdf.flattenForm;
const fillAndFlatten = zpdf.fillAndFlatten;
const scanFormFields = zpdf.form.form_filler.scanFormFields;

/// Helper: create a simple PDF with form fields for testing.
fn createTestPdfWithForms(allocator: std.mem.Allocator) ![]u8 {
    var doc = Document.init(allocator);
    defer doc.deinit();

    doc.setTitle("Test Form");
    const page = try doc.addPage(PageSize.a4);

    const helv = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);

    try page.drawText("Test Form", .{
        .x = 72,
        .y = 760,
        .font = .helvetica,
        .font_size = 18,
    });

    var form = FormBuilder.init(allocator);
    defer form.deinit();

    try form.addTextField("full_name", Rect{ .x = 100, .y = 700, .w = 200, .h = 20 }, .{
        .font = .helvetica,
        .font_size = 12,
    });

    try form.addTextField("email", Rect{ .x = 100, .y = 660, .w = 200, .h = 20 }, .{
        .font = .helvetica,
        .font_size = 12,
    });

    try form.addCheckbox("agree", Rect{ .x = 100, .y = 620, .w = 14, .h = 14 }, false);

    _ = try form.build(&doc.object_store);

    return doc.save(allocator);
}

test "scanFormFields: finds fields in test PDF" {
    const allocator = testing.allocator;

    const pdf_data = try createTestPdfWithForms(allocator);
    defer allocator.free(pdf_data);

    const fields = try scanFormFields(allocator, pdf_data);
    defer allocator.free(fields);

    // Should find 3 fields: full_name, email, agree
    try testing.expectEqual(@as(usize, 3), fields.len);

    // Verify we can find each field by name
    var found_name = false;
    var found_email = false;
    var found_agree = false;
    for (fields) |f| {
        if (std.mem.eql(u8, f.name, "full_name")) found_name = true;
        if (std.mem.eql(u8, f.name, "email")) found_email = true;
        if (std.mem.eql(u8, f.name, "agree")) found_agree = true;
    }
    try testing.expect(found_name);
    try testing.expect(found_email);
    try testing.expect(found_agree);
}

test "scanFormFields: field types are correct" {
    const allocator = testing.allocator;

    const pdf_data = try createTestPdfWithForms(allocator);
    defer allocator.free(pdf_data);

    const fields = try scanFormFields(allocator, pdf_data);
    defer allocator.free(fields);

    for (fields) |f| {
        if (std.mem.eql(u8, f.name, "full_name") or std.mem.eql(u8, f.name, "email")) {
            try testing.expectEqualStrings("Tx", f.field_type);
        }
        if (std.mem.eql(u8, f.name, "agree")) {
            try testing.expectEqualStrings("Btn", f.field_type);
        }
    }
}

test "fillForm: fill text field" {
    const allocator = testing.allocator;

    const pdf_data = try createTestPdfWithForms(allocator);
    defer allocator.free(pdf_data);

    const values = [_]FieldValue{
        .{ .name = "full_name", .value = "John Doe" },
    };

    const filled = try fillForm(allocator, pdf_data, &values);
    defer allocator.free(filled);

    // The filled PDF should contain the value
    try testing.expect(std.mem.indexOf(u8, filled, "John Doe") != null);

    // Should still be a valid PDF
    try testing.expect(std.mem.startsWith(u8, filled, "%PDF-"));
    try testing.expect(std.mem.indexOf(u8, filled, "%%EOF") != null);
}

test "fillForm: fill checkbox" {
    const allocator = testing.allocator;

    const pdf_data = try createTestPdfWithForms(allocator);
    defer allocator.free(pdf_data);

    const values = [_]FieldValue{
        .{ .name = "agree", .value = "Yes" },
    };

    const filled = try fillForm(allocator, pdf_data, &values);
    defer allocator.free(filled);

    // The filled PDF should contain /V /Yes and /AS /Yes
    try testing.expect(std.mem.indexOf(u8, filled, "/V /Yes") != null);
    try testing.expect(std.mem.indexOf(u8, filled, "/AS /Yes") != null);
}

test "fillForm: no-op on empty values" {
    const allocator = testing.allocator;

    const pdf_data = try createTestPdfWithForms(allocator);
    defer allocator.free(pdf_data);

    const values = [_]FieldValue{};

    const filled = try fillForm(allocator, pdf_data, &values);
    defer allocator.free(filled);

    // Should be identical to original
    try testing.expectEqual(pdf_data.len, filled.len);
}

test "fillForm: unknown field name is gracefully skipped" {
    const allocator = testing.allocator;

    const pdf_data = try createTestPdfWithForms(allocator);
    defer allocator.free(pdf_data);

    const values = [_]FieldValue{
        .{ .name = "nonexistent_field", .value = "some value" },
    };

    const filled = try fillForm(allocator, pdf_data, &values);
    defer allocator.free(filled);

    // Should still be a valid PDF
    try testing.expect(std.mem.startsWith(u8, filled, "%PDF-"));
    try testing.expect(std.mem.indexOf(u8, filled, "%%EOF") != null);

    // The nonexistent value should not appear in the PDF
    try testing.expect(std.mem.indexOf(u8, filled, "some value") == null);
}

test "flattenForm: produces content stream operators" {
    const allocator = testing.allocator;

    // First create and fill a form
    const pdf_data = try createTestPdfWithForms(allocator);
    defer allocator.free(pdf_data);

    const values = [_]FieldValue{
        .{ .name = "full_name", .value = "Jane Smith" },
    };

    const filled = try fillForm(allocator, pdf_data, &values);
    defer allocator.free(filled);

    const flattened = try flattenForm(allocator, filled, .{});
    defer allocator.free(flattened);

    // Should be a valid PDF
    try testing.expect(std.mem.startsWith(u8, flattened, "%PDF-"));
    try testing.expect(std.mem.indexOf(u8, flattened, "%%EOF") != null);

    // The flattened PDF should contain text drawing operators with the value
    try testing.expect(std.mem.indexOf(u8, flattened, "Jane Smith") != null);
    // Should contain BT/ET text operators
    try testing.expect(std.mem.indexOf(u8, flattened, "BT") != null);
    try testing.expect(std.mem.indexOf(u8, flattened, "Tj") != null);
}

test "fillAndFlatten: combined operation" {
    const allocator = testing.allocator;

    const pdf_data = try createTestPdfWithForms(allocator);
    defer allocator.free(pdf_data);

    const values = [_]FieldValue{
        .{ .name = "full_name", .value = "Alice" },
        .{ .name = "email", .value = "alice@example.com" },
        .{ .name = "agree", .value = "Yes" },
    };

    const result = try fillAndFlatten(allocator, pdf_data, &values, .{
        .font = .helvetica,
        .font_size = 10,
    });
    defer allocator.free(result);

    // Should be a valid PDF
    try testing.expect(std.mem.startsWith(u8, result, "%PDF-"));
    try testing.expect(std.mem.indexOf(u8, result, "%%EOF") != null);
}

test "scanFormFields: PDF with no forms returns empty" {
    const allocator = testing.allocator;

    // Create a PDF without any form fields
    var doc = Document.init(allocator);
    defer doc.deinit();
    _ = try doc.addPage(PageSize.a4);
    const pdf_data = try doc.save(allocator);
    defer allocator.free(pdf_data);

    const fields = try scanFormFields(allocator, pdf_data);
    defer allocator.free(fields);

    try testing.expectEqual(@as(usize, 0), fields.len);
}

test "flattenForm: no-op on PDF without forms" {
    const allocator = testing.allocator;

    var doc = Document.init(allocator);
    defer doc.deinit();
    _ = try doc.addPage(PageSize.a4);
    const pdf_data = try doc.save(allocator);
    defer allocator.free(pdf_data);

    const flattened = try flattenForm(allocator, pdf_data, .{});
    defer allocator.free(flattened);

    // Should still be valid
    try testing.expect(std.mem.startsWith(u8, flattened, "%PDF-"));
    try testing.expectEqual(pdf_data.len, flattened.len);
}

test "fillForm: fill multiple fields" {
    const allocator = testing.allocator;

    const pdf_data = try createTestPdfWithForms(allocator);
    defer allocator.free(pdf_data);

    const values = [_]FieldValue{
        .{ .name = "full_name", .value = "Bob Builder" },
        .{ .name = "email", .value = "bob@build.com" },
    };

    const filled = try fillForm(allocator, pdf_data, &values);
    defer allocator.free(filled);

    try testing.expect(std.mem.indexOf(u8, filled, "Bob Builder") != null);
    try testing.expect(std.mem.indexOf(u8, filled, "bob@build.com") != null);
}
