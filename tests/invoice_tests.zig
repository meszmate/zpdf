const std = @import("std");
const zpdf = @import("zpdf");
const Invoice = zpdf.Invoice;
const InvoiceItem = zpdf.InvoiceItem;
const CompanyInfo = zpdf.CompanyInfo;
const InvoiceOptions = zpdf.InvoiceOptions;
const InvoiceColors = zpdf.InvoiceColors;

test "Invoice init and deinit" {
    var inv = Invoice.init(std.testing.allocator);
    defer inv.deinit();

    try std.testing.expect(inv.seller == null);
    try std.testing.expect(inv.buyer == null);
    try std.testing.expectEqual(@as(usize, 0), inv.items.items.len);
}

test "Invoice setHeader stores seller and buyer" {
    var inv = Invoice.init(std.testing.allocator);
    defer inv.deinit();

    inv.setHeader(
        .{ .name = "Seller Corp", .email = "sell@corp.com" },
        .{ .name = "Buyer Ltd", .phone = "555-1234" },
    );

    try std.testing.expectEqualStrings("Seller Corp", inv.seller.?.name);
    try std.testing.expectEqualStrings("sell@corp.com", inv.seller.?.email);
    try std.testing.expectEqualStrings("Buyer Ltd", inv.buyer.?.name);
    try std.testing.expectEqualStrings("555-1234", inv.buyer.?.phone);
}

test "Invoice addItem accumulates items" {
    var inv = Invoice.init(std.testing.allocator);
    defer inv.deinit();

    try inv.addItem(.{ .description = "Item A", .quantity = 1, .unit_price = 10.0 });
    try inv.addItem(.{ .description = "Item B", .quantity = 2, .unit_price = 20.0, .tax_rate = 5.0 });
    try inv.addItem(.{ .description = "Item C", .quantity = 3, .unit_price = 30.0, .discount = 10.0 });

    try std.testing.expectEqual(@as(usize, 3), inv.items.items.len);
    try std.testing.expectEqualStrings("Item B", inv.items.items[1].description);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), inv.items.items[1].tax_rate.?, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), inv.items.items[2].discount.?, 0.001);
}

test "Invoice setNotes and setTerms" {
    var inv = Invoice.init(std.testing.allocator);
    defer inv.deinit();

    inv.setNotes("Some notes");
    inv.setTerms("Some terms");

    try std.testing.expectEqualStrings("Some notes", inv.options.notes);
    try std.testing.expectEqualStrings("Some terms", inv.options.terms);
}

test "Invoice setOptions" {
    var inv = Invoice.init(std.testing.allocator);
    defer inv.deinit();

    inv.setOptions(.{
        .invoice_number = "INV-999",
        .date = "2026-06-01",
        .due_date = "2026-07-01",
        .currency_symbol = "EUR ",
    });

    try std.testing.expectEqualStrings("INV-999", inv.options.invoice_number);
    try std.testing.expectEqualStrings("2026-06-01", inv.options.date);
    try std.testing.expectEqualStrings("EUR ", inv.options.currency_symbol);
}

test "Invoice generate produces PDF bytes" {
    var inv = Invoice.init(std.testing.allocator);
    defer inv.deinit();

    inv.setOptions(.{
        .invoice_number = "TEST-001",
        .date = "2026-01-01",
        .due_date = "2026-02-01",
    });

    inv.setHeader(
        .{ .name = "Test Seller", .address_line1 = "100 Test Rd" },
        .{ .name = "Test Buyer", .email = "buyer@test.com" },
    );

    try inv.addItem(.{ .description = "Service A", .quantity = 5, .unit_price = 100.00, .tax_rate = 10.0 });
    try inv.addItem(.{ .description = "Service B", .quantity = 1, .unit_price = 250.00, .discount = 5.0 });

    inv.setNotes("Test notes");
    inv.setTerms("Test terms");

    const bytes = try inv.generate(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    // Verify it is a valid PDF
    try std.testing.expect(bytes.len > 200);
    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-"));
    // Should contain EOF marker
    try std.testing.expect(std.mem.endsWith(u8, bytes, "%%EOF\n"));
}

test "Invoice generate with empty items" {
    var inv = Invoice.init(std.testing.allocator);
    defer inv.deinit();

    const bytes = try inv.generate(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-"));
}

test "Invoice generate with custom colors" {
    var inv = Invoice.init(std.testing.allocator);
    defer inv.deinit();

    inv.setOptions(.{
        .invoice_number = "COLOR-001",
        .colors = .{
            .accent = zpdf.rgb(200, 30, 30),
            .text = zpdf.rgb(10, 10, 10),
        },
    });

    try inv.addItem(.{ .description = "Red Invoice Item", .quantity = 1, .unit_price = 42.00 });

    const bytes = try inv.generate(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    try std.testing.expect(bytes.len > 200);
}

test "InvoiceItem defaults" {
    const item = InvoiceItem{ .description = "X", .quantity = 1, .unit_price = 5.0 };
    try std.testing.expect(item.tax_rate == null);
    try std.testing.expect(item.discount == null);
}

test "CompanyInfo defaults" {
    const info = CompanyInfo{ .name = "Test" };
    try std.testing.expectEqualStrings("", info.address_line1);
    try std.testing.expectEqualStrings("", info.phone);
    try std.testing.expect(info.logo_text == null);
}

test "InvoiceColors defaults" {
    const colors = InvoiceColors{};
    const accent = colors.accent.toRgb();
    try std.testing.expectEqual(@as(u8, 41), accent.r);
}
