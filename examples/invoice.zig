const std = @import("std");
const zpdf = @import("zpdf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var inv = zpdf.Invoice.init(allocator);
    defer inv.deinit();

    inv.setOptions(.{
        .invoice_number = "INV-2026-0042",
        .date = "2026-03-15",
        .due_date = "2026-04-15",
        .currency_symbol = "$",
        .colors = .{
            .accent = zpdf.rgb(0, 90, 156),
        },
    });

    inv.setHeader(
        .{
            .name = "Acme Software LLC",
            .address_line1 = "123 Innovation Drive",
            .address_line2 = "San Francisco, CA 94105",
            .phone = "+1 (555) 012-3456",
            .email = "billing@acmesoftware.io",
            .logo_text = "ACME",
        },
        .{
            .name = "TechStart Inc.",
            .address_line1 = "789 Market Street, Suite 400",
            .address_line2 = "New York, NY 10001",
            .email = "accounts@techstart.com",
        },
    );

    try inv.addItem(.{
        .description = "Web Application Development",
        .quantity = 80,
        .unit_price = 95.00,
        .tax_rate = 8.25,
    });
    try inv.addItem(.{
        .description = "UI/UX Design",
        .quantity = 24,
        .unit_price = 85.00,
        .tax_rate = 8.25,
    });
    try inv.addItem(.{
        .description = "Cloud Hosting (Annual)",
        .quantity = 1,
        .unit_price = 599.00,
        .discount = 15.0,
    });
    try inv.addItem(.{
        .description = "SSL Certificate",
        .quantity = 1,
        .unit_price = 49.99,
    });
    try inv.addItem(.{
        .description = "Technical Support (hours)",
        .quantity = 10,
        .unit_price = 60.00,
        .tax_rate = 8.25,
    });

    inv.setNotes("Thank you for choosing Acme Software! We appreciate your continued partnership.");
    inv.setTerms("Payment is due within 30 days of the invoice date. Late payments are subject to a 1.5% monthly finance charge.");

    const bytes = try inv.generate(allocator);
    defer allocator.free(bytes);

    const file = try std.fs.cwd().createFile("invoice.pdf", .{});
    defer file.close();
    try file.writeAll(bytes);

    std.debug.print("Created invoice.pdf ({d} bytes)\n", .{bytes.len});
}
