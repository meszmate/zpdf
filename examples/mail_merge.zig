const std = @import("std");
const zpdf = @import("zpdf");

/// Builder function that creates a personalized letter for each record.
fn buildLetter(allocator: std.mem.Allocator, doc: *zpdf.Document, record: zpdf.MergeRecord) anyerror!void {
    _ = allocator;
    const page = try doc.addPage(.a4);

    const name = record.get("name") orelse "Valued Customer";
    const company = record.get("company") orelse "Unknown Corp";
    const amount = record.get("amount") orelse "$0.00";

    const font_handle = try doc.getStandardFont(.helvetica);
    _ = try page.addFont(font_handle.font.pdfName(), font_handle.ref);

    const bold_handle = try doc.getStandardFont(.helvetica_bold);
    _ = try page.addFont(bold_handle.font.pdfName(), bold_handle.ref);

    // Header
    try page.drawText("INVOICE", .{
        .x = 72,
        .y = 750,
        .font = .helvetica_bold,
        .font_size = 28,
        .color = zpdf.rgb(0, 51, 153),
    });

    try page.drawLine(.{
        .x1 = 72,
        .y1 = 740,
        .x2 = 523,
        .y2 = 740,
        .color = zpdf.rgb(0, 51, 153),
        .line_width = 2,
    });

    // Recipient
    try page.drawText("Bill To:", .{
        .x = 72,
        .y = 700,
        .font = .helvetica_bold,
        .font_size = 12,
    });

    try page.drawText(name, .{
        .x = 72,
        .y = 682,
        .font = .helvetica,
        .font_size = 12,
    });

    try page.drawText(company, .{
        .x = 72,
        .y = 664,
        .font = .helvetica,
        .font_size = 12,
        .color = zpdf.rgb(100, 100, 100),
    });

    // Amount box
    try page.drawRect(.{
        .x = 72,
        .y = 580,
        .width = 451,
        .height = 50,
        .color = zpdf.rgb(240, 240, 250),
        .border_color = zpdf.rgb(0, 51, 153),
        .border_width = 1,
        .corner_radius = 4,
    });

    try page.drawText("Amount Due:", .{
        .x = 82,
        .y = 600,
        .font = .helvetica,
        .font_size = 14,
    });

    try page.drawText(amount, .{
        .x = 400,
        .y = 600,
        .font = .helvetica_bold,
        .font_size = 18,
        .color = zpdf.rgb(0, 102, 0),
    });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // -- Approach 1: Builder-based mail merge using MailMerge struct --
    {
        var mm = zpdf.MailMerge.init(allocator);
        defer mm.deinit();

        mm.setBuilder(buildLetter);

        const fields1 = [_]zpdf.MergeField{
            .{ .name = "name", .value = "Alice Johnson" },
            .{ .name = "company", .value = "Acme Corp" },
            .{ .name = "amount", .value = "$1,250.00" },
        };
        const fields2 = [_]zpdf.MergeField{
            .{ .name = "name", .value = "Bob Smith" },
            .{ .name = "company", .value = "Widgets Inc" },
            .{ .name = "amount", .value = "$3,800.00" },
        };
        const fields3 = [_]zpdf.MergeField{
            .{ .name = "name", .value = "Carol Davis" },
            .{ .name = "company", .value = "Tech Solutions" },
            .{ .name = "amount", .value = "$950.00" },
        };

        try mm.addRecord(&fields1);
        try mm.addRecord(&fields2);
        try mm.addRecord(&fields3);

        // Generate a single PDF with all invoices
        const merged = try mm.generate(allocator);
        defer allocator.free(merged);

        const file = try std.fs.cwd().createFile("mail_merge_invoices.pdf", .{});
        defer file.close();
        try file.writeAll(merged);

        std.debug.print("Created mail_merge_invoices.pdf ({d} bytes) with 3 invoices\n", .{merged.len});
    }

    // -- Approach 2: Simple functional merge with mergeWithBuilder --
    {
        const f1 = [_]zpdf.MergeField{
            .{ .name = "name", .value = "Dave Wilson" },
            .{ .name = "company", .value = "Global Ltd" },
            .{ .name = "amount", .value = "$2,100.00" },
        };
        const f2 = [_]zpdf.MergeField{
            .{ .name = "name", .value = "Eve Taylor" },
            .{ .name = "company", .value = "StartupXYZ" },
            .{ .name = "amount", .value = "$750.00" },
        };
        const records = [_]zpdf.MergeRecord{
            .{ .fields = &f1 },
            .{ .fields = &f2 },
        };

        const result = try zpdf.mergeWithBuilder(allocator, &records, buildLetter);
        defer allocator.free(result);

        const file = try std.fs.cwd().createFile("mail_merge_functional.pdf", .{});
        defer file.close();
        try file.writeAll(result);

        std.debug.print("Created mail_merge_functional.pdf ({d} bytes) with 2 invoices\n", .{result.len});
    }
}
