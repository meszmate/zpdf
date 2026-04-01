const std = @import("std");
const testing = std.testing;
const zpdf = @import("zpdf");

const Document = zpdf.Document;
const PageSize = zpdf.PageSize;
const FormBuilder = zpdf.FormBuilder;
const Rect = zpdf.form.Form.Rect;
const FieldValue = zpdf.FieldValue;

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

test "exportFdf: generates valid FDF structure" {
    const allocator = testing.allocator;

    const pdf_data = try createTestPdfWithForms(allocator);
    defer allocator.free(pdf_data);

    const fdf_data = try zpdf.exportFdf(allocator, pdf_data);
    defer allocator.free(fdf_data);

    // FDF should start with the header
    try testing.expect(std.mem.startsWith(u8, fdf_data, "%FDF-1.2"));

    // Should contain field markers
    try testing.expect(std.mem.indexOf(u8, fdf_data, "/Fields") != null);
    try testing.expect(std.mem.indexOf(u8, fdf_data, "/T (full_name)") != null);
    try testing.expect(std.mem.indexOf(u8, fdf_data, "/T (email)") != null);
    try testing.expect(std.mem.indexOf(u8, fdf_data, "/T (agree)") != null);

    // Should end with EOF
    try testing.expect(std.mem.indexOf(u8, fdf_data, "%%EOF") != null);
}

test "exportFdf: checkbox uses name syntax" {
    const allocator = testing.allocator;

    // Create a PDF with a checked checkbox
    var doc = Document.init(allocator);
    defer doc.deinit();
    const page = try doc.addPage(PageSize.a4);
    const helv = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(helv.font.pdfName(), helv.ref);

    var form = FormBuilder.init(allocator);
    defer form.deinit();
    try form.addCheckbox("check1", Rect{ .x = 10, .y = 10, .w = 14, .h = 14 }, true);
    _ = try form.build(&doc.object_store);

    const pdf_data = try doc.save(allocator);
    defer allocator.free(pdf_data);

    const fdf_data = try zpdf.exportFdf(allocator, pdf_data);
    defer allocator.free(fdf_data);

    // Checkbox value should use /Name syntax, not (string) syntax
    try testing.expect(std.mem.indexOf(u8, fdf_data, "/V /Yes") != null or
        std.mem.indexOf(u8, fdf_data, "/V /Off") != null);
}

test "parseFdf: parses text and checkbox fields" {
    const allocator = testing.allocator;
    const fdf_data =
        \\%FDF-1.2
        \\1 0 obj
        \\<< /FDF << /Fields [
        \\  << /T (name) /V (Alice) >>
        \\  << /T (ok) /V /Yes >>
        \\] >> >>
        \\endobj
        \\trailer
        \\<< /Root 1 0 R >>
        \\%%EOF
    ;

    const fields = try zpdf.parseFdf(allocator, fdf_data);
    defer {
        for (fields) |v| {
            allocator.free(v.name);
            allocator.free(v.value);
        }
        allocator.free(fields);
    }

    try testing.expectEqual(@as(usize, 2), fields.len);
    try testing.expectEqualStrings("name", fields[0].name);
    try testing.expectEqualStrings("Alice", fields[0].value);
    try testing.expectEqualStrings("ok", fields[1].name);
    try testing.expectEqualStrings("Yes", fields[1].value);
}

test "exportXfdf: generates valid XFDF structure" {
    const allocator = testing.allocator;

    const pdf_data = try createTestPdfWithForms(allocator);
    defer allocator.free(pdf_data);

    const xfdf_data = try zpdf.exportXfdf(allocator, pdf_data);
    defer allocator.free(xfdf_data);

    // XFDF should have XML header
    try testing.expect(std.mem.startsWith(u8, xfdf_data, "<?xml version=\"1.0\""));

    // Should contain proper structure
    try testing.expect(std.mem.indexOf(u8, xfdf_data, "<xfdf") != null);
    try testing.expect(std.mem.indexOf(u8, xfdf_data, "<fields>") != null);
    try testing.expect(std.mem.indexOf(u8, xfdf_data, "field name=\"full_name\"") != null);
    try testing.expect(std.mem.indexOf(u8, xfdf_data, "field name=\"email\"") != null);
    try testing.expect(std.mem.indexOf(u8, xfdf_data, "field name=\"agree\"") != null);
    try testing.expect(std.mem.indexOf(u8, xfdf_data, "</xfdf>") != null);
}

test "parseXfdf: parses fields correctly" {
    const allocator = testing.allocator;
    const xfdf_data =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<xfdf xmlns="http://ns.adobe.com/xfdf/">
        \\  <fields>
        \\    <field name="city">
        \\      <value>New York</value>
        \\    </field>
        \\  </fields>
        \\</xfdf>
    ;

    const fields = try zpdf.parseXfdf(allocator, xfdf_data);
    defer {
        for (fields) |v| {
            allocator.free(v.name);
            allocator.free(v.value);
        }
        allocator.free(fields);
    }

    try testing.expectEqual(@as(usize, 1), fields.len);
    try testing.expectEqualStrings("city", fields[0].name);
    try testing.expectEqualStrings("New York", fields[0].value);
}

test "parseXfdf: handles XML entities" {
    const allocator = testing.allocator;
    const xfdf_data =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<xfdf xmlns="http://ns.adobe.com/xfdf/">
        \\  <fields>
        \\    <field name="company">
        \\      <value>A &amp; B &lt;Corp&gt;</value>
        \\    </field>
        \\  </fields>
        \\</xfdf>
    ;

    const fields = try zpdf.parseXfdf(allocator, xfdf_data);
    defer {
        for (fields) |v| {
            allocator.free(v.name);
            allocator.free(v.value);
        }
        allocator.free(fields);
    }

    try testing.expectEqual(@as(usize, 1), fields.len);
    try testing.expectEqualStrings("A & B <Corp>", fields[0].value);
}

test "FDF round-trip: export then import preserves field values" {
    const allocator = testing.allocator;

    // Create a PDF with form fields and fill them
    const pdf_data = try createTestPdfWithForms(allocator);
    defer allocator.free(pdf_data);

    const values = [_]FieldValue{
        .{ .name = "full_name", .value = "Jane Smith" },
        .{ .name = "email", .value = "jane@test.com" },
        .{ .name = "agree", .value = "Yes" },
    };

    const filled = try zpdf.fillForm(allocator, pdf_data, &values);
    defer allocator.free(filled);

    // Export to FDF
    const fdf_data = try zpdf.exportFdf(allocator, filled);
    defer allocator.free(fdf_data);

    // Import FDF into the original (empty) PDF
    const reimported = try zpdf.importFdf(allocator, pdf_data, fdf_data);
    defer allocator.free(reimported);

    // Verify the reimported PDF contains the values
    try testing.expect(std.mem.indexOf(u8, reimported, "Jane Smith") != null);
    try testing.expect(std.mem.indexOf(u8, reimported, "jane@test.com") != null);
    try testing.expect(std.mem.indexOf(u8, reimported, "/V /Yes") != null);
}

test "XFDF round-trip: export then import preserves field values" {
    const allocator = testing.allocator;

    const pdf_data = try createTestPdfWithForms(allocator);
    defer allocator.free(pdf_data);

    const values = [_]FieldValue{
        .{ .name = "full_name", .value = "Bob Builder" },
        .{ .name = "email", .value = "bob@build.com" },
    };

    const filled = try zpdf.fillForm(allocator, pdf_data, &values);
    defer allocator.free(filled);

    // Export to XFDF
    const xfdf_data = try zpdf.exportXfdf(allocator, filled);
    defer allocator.free(xfdf_data);

    // Import XFDF into the original PDF
    const reimported = try zpdf.importXfdf(allocator, pdf_data, xfdf_data);
    defer allocator.free(reimported);

    // Verify the reimported PDF contains the values
    try testing.expect(std.mem.indexOf(u8, reimported, "Bob Builder") != null);
    try testing.expect(std.mem.indexOf(u8, reimported, "bob@build.com") != null);
}

test "importFdf: applies FDF values to PDF form" {
    const allocator = testing.allocator;

    const pdf_data = try createTestPdfWithForms(allocator);
    defer allocator.free(pdf_data);

    const fdf_data =
        \\%FDF-1.2
        \\1 0 obj
        \\<< /FDF << /Fields [
        \\  << /T (full_name) /V (Test User) >>
        \\  << /T (email) /V (test@example.com) >>
        \\] >> >>
        \\endobj
        \\trailer
        \\<< /Root 1 0 R >>
        \\%%EOF
    ;

    const result = try zpdf.importFdf(allocator, pdf_data, fdf_data);
    defer allocator.free(result);

    try testing.expect(std.mem.startsWith(u8, result, "%PDF-"));
    try testing.expect(std.mem.indexOf(u8, result, "Test User") != null);
    try testing.expect(std.mem.indexOf(u8, result, "test@example.com") != null);
}

test "importXfdf: applies XFDF values to PDF form" {
    const allocator = testing.allocator;

    const pdf_data = try createTestPdfWithForms(allocator);
    defer allocator.free(pdf_data);

    const xfdf_data =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<xfdf xmlns="http://ns.adobe.com/xfdf/">
        \\  <fields>
        \\    <field name="full_name">
        \\      <value>XFDF User</value>
        \\    </field>
        \\  </fields>
        \\</xfdf>
    ;

    const result = try zpdf.importXfdf(allocator, pdf_data, xfdf_data);
    defer allocator.free(result);

    try testing.expect(std.mem.startsWith(u8, result, "%PDF-"));
    try testing.expect(std.mem.indexOf(u8, result, "XFDF User") != null);
}

test "parseFdf: empty fields list" {
    const allocator = testing.allocator;
    const fdf_data =
        \\%FDF-1.2
        \\1 0 obj
        \\<< /FDF << /Fields [] >> >>
        \\endobj
        \\trailer
        \\<< /Root 1 0 R >>
        \\%%EOF
    ;

    const fields = try zpdf.parseFdf(allocator, fdf_data);
    defer allocator.free(fields);

    try testing.expectEqual(@as(usize, 0), fields.len);
}

test "parseXfdf: empty fields" {
    const allocator = testing.allocator;
    const xfdf_data =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<xfdf xmlns="http://ns.adobe.com/xfdf/">
        \\  <fields>
        \\  </fields>
        \\</xfdf>
    ;

    const fields = try zpdf.parseXfdf(allocator, xfdf_data);
    defer allocator.free(fields);

    try testing.expectEqual(@as(usize, 0), fields.len);
}
