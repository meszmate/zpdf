const std = @import("std");
const Allocator = std.mem.Allocator;
const color_mod = @import("../color/color.zig");
const Color = color_mod.Color;
const StandardFont = @import("../font/standard_fonts.zig").StandardFont;
const Document = @import("../document/document.zig").Document;
const Page = @import("../document/page.zig").Page;
const PageSize = @import("../document/page_sizes.zig").PageSize;

/// A single line item on the invoice.
pub const InvoiceItem = struct {
    description: []const u8,
    quantity: f32,
    unit_price: f32,
    tax_rate: ?f32 = null,
    discount: ?f32 = null,
};

/// Contact/company information for seller or buyer.
pub const CompanyInfo = struct {
    name: []const u8,
    address_line1: []const u8 = "",
    address_line2: []const u8 = "",
    phone: []const u8 = "",
    email: []const u8 = "",
    logo_text: ?[]const u8 = null,
};

/// Color scheme for the invoice.
pub const InvoiceColors = struct {
    accent: Color = color_mod.rgb(41, 65, 122),
    text: Color = color_mod.rgb(50, 50, 50),
    background: Color = color_mod.rgb(255, 255, 255),
    light_accent: Color = color_mod.rgb(235, 241, 250),
};

/// Options for generating an invoice.
pub const InvoiceOptions = struct {
    invoice_number: []const u8 = "INV-001",
    date: []const u8 = "",
    due_date: []const u8 = "",
    currency_symbol: []const u8 = "$",
    notes: []const u8 = "",
    terms: []const u8 = "",
    colors: InvoiceColors = .{},
};

/// A high-level invoice/receipt builder that generates a professional PDF invoice.
pub const Invoice = struct {
    allocator: Allocator,
    seller: ?CompanyInfo,
    buyer: ?CompanyInfo,
    items: std.ArrayListUnmanaged(InvoiceItem),
    options: InvoiceOptions,

    /// Create a new invoice builder.
    pub fn init(allocator: Allocator) Invoice {
        return .{
            .allocator = allocator,
            .seller = null,
            .buyer = null,
            .items = .{},
            .options = .{},
        };
    }

    /// Free resources owned by this invoice builder.
    pub fn deinit(self: *Invoice) void {
        self.items.deinit(self.allocator);
    }

    /// Set invoice options (number, dates, currency, colors, etc.).
    pub fn setOptions(self: *Invoice, options: InvoiceOptions) void {
        self.options = options;
    }

    /// Set the seller (from) and buyer (to) company information.
    pub fn setHeader(self: *Invoice, seller: CompanyInfo, buyer: CompanyInfo) void {
        self.seller = seller;
        self.buyer = buyer;
    }

    /// Add a line item to the invoice.
    pub fn addItem(self: *Invoice, item: InvoiceItem) !void {
        try self.items.append(self.allocator, item);
    }

    /// Set notes text (displayed at the bottom of the invoice).
    pub fn setNotes(self: *Invoice, notes: []const u8) void {
        self.options.notes = notes;
    }

    /// Set terms/conditions text (displayed at the bottom of the invoice).
    pub fn setTerms(self: *Invoice, terms: []const u8) void {
        self.options.terms = terms;
    }

    /// Generate the invoice and return the PDF bytes. Caller owns the returned slice.
    pub fn generate(self: *const Invoice, allocator: Allocator) ![]u8 {
        var doc = Document.init(allocator);
        defer doc.deinit();

        doc.setTitle("Invoice");
        doc.setCreator("zpdf Invoice Generator");

        const page = try doc.addPage(.a4);
        const page_width: f32 = 595.28;

        // Register fonts
        const helv = try doc.getStandardFont(.helvetica);
        _ = try page.addFont(helv.font.pdfName(), helv.ref);
        const helv_bold = try doc.getStandardFont(.helvetica_bold);
        _ = try page.addFont(helv_bold.font.pdfName(), helv_bold.ref);

        const margin: f32 = 50.0;
        const content_width: f32 = page_width - margin * 2.0;
        var y: f32 = 790.0;

        const colors = self.options.colors;

        // ── Header accent bar ──────────────────────────────────────────
        try page.drawRect(.{
            .x = 0,
            .y = 800,
            .width = page_width,
            .height = 42,
            .color = colors.accent,
        });

        // ── Invoice title ──────────────────────────────────────────────
        try page.drawText("INVOICE", .{
            .x = margin,
            .y = 810,
            .font = .helvetica_bold,
            .font_size = 22,
            .color = color_mod.rgb(255, 255, 255),
        });

        // ── Invoice meta (number, date, due date) on the right ────────
        const meta_x: f32 = page_width - margin - 200;
        try drawLabelValue(page, "Invoice #:", self.options.invoice_number, meta_x, 810, colors.text);

        y = 780.0;
        if (self.options.date.len > 0) {
            try drawLabelValue(page, "Date:", self.options.date, meta_x, y, colors.text);
            y -= 14.0;
        }
        if (self.options.due_date.len > 0) {
            try drawLabelValue(page, "Due Date:", self.options.due_date, meta_x, y, colors.text);
            y -= 14.0;
        }

        // ── Seller / Buyer info side by side ───────────────────────────
        y = 740.0;
        if (self.seller) |seller| {
            try drawCompanyBlock(page, "From:", seller, margin, y, colors);
        }
        if (self.buyer) |buyer| {
            try drawCompanyBlock(page, "Bill To:", buyer, margin + content_width / 2.0, y, colors);
        }

        // ── Line items table ───────────────────────────────────────────
        y = 620.0;

        // Column layout: #(30) | Description(200) | Qty(60) | Unit Price(80) | Tax(60) | Total(65)
        const col_x = [_]f32{ margin, margin + 30, margin + 230, margin + 290, margin + 370, margin + 430 };
        const table_right = margin + content_width;

        // Table header background
        const header_height: f32 = 22.0;
        try page.drawRect(.{
            .x = margin,
            .y = y - header_height,
            .width = content_width,
            .height = header_height,
            .color = colors.accent,
        });

        // Table header text
        const header_y = y - 15.0;
        const hdr_color = color_mod.rgb(255, 255, 255);
        try page.drawText("#", .{ .x = col_x[0] + 4, .y = header_y, .font = .helvetica_bold, .font_size = 9, .color = hdr_color });
        try page.drawText("Description", .{ .x = col_x[1] + 4, .y = header_y, .font = .helvetica_bold, .font_size = 9, .color = hdr_color });
        try page.drawText("Qty", .{ .x = col_x[2] + 4, .y = header_y, .font = .helvetica_bold, .font_size = 9, .color = hdr_color });
        try page.drawText("Unit Price", .{ .x = col_x[3] + 4, .y = header_y, .font = .helvetica_bold, .font_size = 9, .color = hdr_color });
        try page.drawText("Tax", .{ .x = col_x[4] + 4, .y = header_y, .font = .helvetica_bold, .font_size = 9, .color = hdr_color });
        try page.drawText("Total", .{ .x = col_x[5] + 4, .y = header_y, .font = .helvetica_bold, .font_size = 9, .color = hdr_color });

        y -= header_height;

        // Table rows
        const row_height: f32 = 20.0;
        var subtotal: f32 = 0.0;
        var tax_total: f32 = 0.0;
        var discount_total: f32 = 0.0;

        for (self.items.items, 0..) |item, idx| {
            // Alternating row color
            if (idx % 2 == 0) {
                try page.drawRect(.{
                    .x = margin,
                    .y = y - row_height,
                    .width = content_width,
                    .height = row_height,
                    .color = colors.light_accent,
                });
            }

            const line_total_before_discount = item.quantity * item.unit_price;
            const item_discount = if (item.discount) |d| line_total_before_discount * d / 100.0 else 0.0;
            const after_discount = line_total_before_discount - item_discount;
            const item_tax = if (item.tax_rate) |r| after_discount * r / 100.0 else 0.0;
            const line_total = after_discount + item_tax;

            subtotal += after_discount;
            tax_total += item_tax;
            discount_total += item_discount;

            const text_y = y - 14.0;

            // Row number
            var num_buf: [8]u8 = undefined;
            const num_str = formatInt(idx + 1, &num_buf);
            try page.drawText(num_str, .{ .x = col_x[0] + 4, .y = text_y, .font = .helvetica, .font_size = 9, .color = colors.text });

            // Description
            try page.drawText(item.description, .{ .x = col_x[1] + 4, .y = text_y, .font = .helvetica, .font_size = 9, .color = colors.text });

            // Qty
            var qty_buf: [32]u8 = undefined;
            const qty_str = formatFloat(item.quantity, &qty_buf);
            try page.drawText(qty_str, .{ .x = col_x[2] + 4, .y = text_y, .font = .helvetica, .font_size = 9, .color = colors.text });

            // Unit Price
            var up_buf: [32]u8 = undefined;
            const up_str = formatCurrency(item.unit_price, self.options.currency_symbol, &up_buf);
            try page.drawText(up_str, .{ .x = col_x[3] + 4, .y = text_y, .font = .helvetica, .font_size = 9, .color = colors.text });

            // Tax
            if (item.tax_rate) |rate| {
                var tax_buf: [32]u8 = undefined;
                const tax_str = formatPercent(rate, &tax_buf);
                try page.drawText(tax_str, .{ .x = col_x[4] + 4, .y = text_y, .font = .helvetica, .font_size = 9, .color = colors.text });
            } else {
                try page.drawText("-", .{ .x = col_x[4] + 4, .y = text_y, .font = .helvetica, .font_size = 9, .color = colors.text });
            }

            // Total
            var tot_buf: [32]u8 = undefined;
            const tot_str = formatCurrency(line_total, self.options.currency_symbol, &tot_buf);
            try page.drawText(tot_str, .{ .x = col_x[5] + 4, .y = text_y, .font = .helvetica, .font_size = 9, .color = colors.text });

            y -= row_height;
        }

        // Table bottom border
        try page.drawLine(.{
            .x1 = margin,
            .y1 = y,
            .x2 = table_right,
            .y2 = y,
            .color = colors.accent,
            .line_width = 0.5,
        });

        // ── Totals section ─────────────────────────────────────────────
        y -= 20.0;
        const totals_label_x: f32 = margin + content_width - 170;
        const totals_value_x: f32 = margin + content_width - 70;

        try page.drawText("Subtotal:", .{ .x = totals_label_x, .y = y, .font = .helvetica, .font_size = 10, .color = colors.text });
        var sub_buf: [32]u8 = undefined;
        const sub_str = formatCurrency(subtotal, self.options.currency_symbol, &sub_buf);
        try page.drawText(sub_str, .{ .x = totals_value_x, .y = y, .font = .helvetica, .font_size = 10, .color = colors.text });

        if (discount_total > 0) {
            y -= 16.0;
            try page.drawText("Discount:", .{ .x = totals_label_x, .y = y, .font = .helvetica, .font_size = 10, .color = colors.text });
            var disc_buf: [32]u8 = undefined;
            const disc_str = formatCurrency(discount_total, self.options.currency_symbol, &disc_buf);
            // Prefix with minus
            var disc_neg_buf: [34]u8 = undefined;
            const disc_neg = formatNegCurrency(disc_str, &disc_neg_buf);
            try page.drawText(disc_neg, .{ .x = totals_value_x, .y = y, .font = .helvetica, .font_size = 10, .color = colors.text });
        }

        if (tax_total > 0) {
            y -= 16.0;
            try page.drawText("Tax:", .{ .x = totals_label_x, .y = y, .font = .helvetica, .font_size = 10, .color = colors.text });
            var tax_buf: [32]u8 = undefined;
            const tax_str = formatCurrency(tax_total, self.options.currency_symbol, &tax_buf);
            try page.drawText(tax_str, .{ .x = totals_value_x, .y = y, .font = .helvetica, .font_size = 10, .color = colors.text });
        }

        // Grand total
        y -= 20.0;
        const grand_total = subtotal + tax_total;
        try page.drawLine(.{
            .x1 = totals_label_x,
            .y1 = y + 12,
            .x2 = margin + content_width,
            .y2 = y + 12,
            .color = colors.accent,
            .line_width = 1.0,
        });
        try page.drawText("Grand Total:", .{ .x = totals_label_x, .y = y, .font = .helvetica_bold, .font_size = 12, .color = colors.accent });
        var grand_buf: [32]u8 = undefined;
        const grand_str = formatCurrency(grand_total, self.options.currency_symbol, &grand_buf);
        try page.drawText(grand_str, .{ .x = totals_value_x, .y = y, .font = .helvetica_bold, .font_size = 12, .color = colors.accent });

        // ── Notes section ──────────────────────────────────────────────
        y -= 40.0;
        if (self.options.notes.len > 0) {
            try page.drawText("Notes:", .{ .x = margin, .y = y, .font = .helvetica_bold, .font_size = 10, .color = colors.text });
            y -= 14.0;
            try page.drawText(self.options.notes, .{
                .x = margin,
                .y = y,
                .font = .helvetica,
                .font_size = 9,
                .color = colors.text,
                .max_width = content_width,
                .line_height = 12.0,
            });
            y -= 24.0;
        }

        // ── Terms section ──────────────────────────────────────────────
        if (self.options.terms.len > 0) {
            try page.drawText("Terms & Conditions:", .{ .x = margin, .y = y, .font = .helvetica_bold, .font_size = 10, .color = colors.text });
            y -= 14.0;
            try page.drawText(self.options.terms, .{
                .x = margin,
                .y = y,
                .font = .helvetica,
                .font_size = 9,
                .color = colors.text,
                .max_width = content_width,
                .line_height = 12.0,
            });
        }

        return doc.save(allocator);
    }
};

// ── Helper rendering functions ─────────────────────────────────────────

fn drawLabelValue(page: *Page, label: []const u8, value: []const u8, x: f32, y: f32, text_color: Color) !void {
    try page.drawText(label, .{
        .x = x,
        .y = y,
        .font = .helvetica_bold,
        .font_size = 9,
        .color = text_color,
    });
    const label_width = StandardFont.helvetica_bold.textWidth(label, 9);
    try page.drawText(value, .{
        .x = x + label_width + 4,
        .y = y,
        .font = .helvetica,
        .font_size = 9,
        .color = text_color,
    });
}

fn drawCompanyBlock(page: *Page, title: []const u8, info: CompanyInfo, x: f32, start_y: f32, colors: InvoiceColors) !void {
    var y = start_y;

    try page.drawText(title, .{
        .x = x,
        .y = y,
        .font = .helvetica_bold,
        .font_size = 10,
        .color = colors.accent,
    });
    y -= 16.0;

    // Logo text or company name
    if (info.logo_text) |logo| {
        try page.drawText(logo, .{
            .x = x,
            .y = y,
            .font = .helvetica_bold,
            .font_size = 14,
            .color = colors.accent,
        });
        y -= 16.0;
    }

    try page.drawText(info.name, .{
        .x = x,
        .y = y,
        .font = .helvetica_bold,
        .font_size = 10,
        .color = colors.text,
    });
    y -= 13.0;

    if (info.address_line1.len > 0) {
        try page.drawText(info.address_line1, .{ .x = x, .y = y, .font = .helvetica, .font_size = 9, .color = colors.text });
        y -= 12.0;
    }
    if (info.address_line2.len > 0) {
        try page.drawText(info.address_line2, .{ .x = x, .y = y, .font = .helvetica, .font_size = 9, .color = colors.text });
        y -= 12.0;
    }
    if (info.phone.len > 0) {
        try page.drawText(info.phone, .{ .x = x, .y = y, .font = .helvetica, .font_size = 9, .color = colors.text });
        y -= 12.0;
    }
    if (info.email.len > 0) {
        try page.drawText(info.email, .{ .x = x, .y = y, .font = .helvetica, .font_size = 9, .color = colors.text });
    }
}

// ── Number formatting helpers ──────────────────────────────────────────

fn formatInt(value: usize, buf: []u8) []const u8 {
    const result = std.fmt.bufPrint(buf, "{d}", .{value}) catch return "?";
    return result;
}

fn formatFloat(value: f32, buf: []u8) []const u8 {
    // Show 2 decimal places
    const result = std.fmt.bufPrint(buf, "{d:.2}", .{value}) catch return "?";
    return result;
}

fn formatCurrency(value: f32, symbol: []const u8, buf: []u8) []const u8 {
    const result = std.fmt.bufPrint(buf, "{s}{d:.2}", .{ symbol, value }) catch return "?";
    return result;
}

fn formatPercent(value: f32, buf: []u8) []const u8 {
    const result = std.fmt.bufPrint(buf, "{d:.1}%", .{value}) catch return "?";
    return result;
}

fn formatNegCurrency(positive: []const u8, buf: []u8) []const u8 {
    const result = std.fmt.bufPrint(buf, "-{s}", .{positive}) catch return "?";
    return result;
}

// ── Tests ──────────────────────────────────────────────────────────────

test "Invoice: init and deinit" {
    var inv = Invoice.init(std.testing.allocator);
    defer inv.deinit();

    try std.testing.expect(inv.seller == null);
    try std.testing.expect(inv.buyer == null);
    try std.testing.expectEqual(@as(usize, 0), inv.items.items.len);
}

test "Invoice: setHeader" {
    var inv = Invoice.init(std.testing.allocator);
    defer inv.deinit();

    inv.setHeader(
        .{ .name = "Seller Inc." },
        .{ .name = "Buyer LLC" },
    );
    try std.testing.expectEqualStrings("Seller Inc.", inv.seller.?.name);
    try std.testing.expectEqualStrings("Buyer LLC", inv.buyer.?.name);
}

test "Invoice: addItem" {
    var inv = Invoice.init(std.testing.allocator);
    defer inv.deinit();

    try inv.addItem(.{ .description = "Widget", .quantity = 2, .unit_price = 9.99 });
    try inv.addItem(.{ .description = "Gadget", .quantity = 1, .unit_price = 29.99, .tax_rate = 10.0 });
    try std.testing.expectEqual(@as(usize, 2), inv.items.items.len);
    try std.testing.expectEqualStrings("Widget", inv.items.items[0].description);
}

test "Invoice: setNotes and setTerms" {
    var inv = Invoice.init(std.testing.allocator);
    defer inv.deinit();

    inv.setNotes("Thank you for your business!");
    inv.setTerms("Payment due within 30 days.");
    try std.testing.expectEqualStrings("Thank you for your business!", inv.options.notes);
    try std.testing.expectEqualStrings("Payment due within 30 days.", inv.options.terms);
}

test "Invoice: generate produces valid PDF" {
    var inv = Invoice.init(std.testing.allocator);
    defer inv.deinit();

    inv.setOptions(.{
        .invoice_number = "INV-1001",
        .date = "2026-01-15",
        .due_date = "2026-02-15",
        .currency_symbol = "$",
    });

    inv.setHeader(
        .{
            .name = "Acme Corp",
            .address_line1 = "123 Main St",
            .address_line2 = "Springfield, IL 62701",
            .phone = "+1 555-0100",
            .email = "billing@acme.com",
        },
        .{
            .name = "Widget Co",
            .address_line1 = "456 Oak Ave",
            .email = "orders@widget.co",
        },
    );

    try inv.addItem(.{ .description = "Web Development", .quantity = 40, .unit_price = 75.00, .tax_rate = 8.5 });
    try inv.addItem(.{ .description = "Hosting", .quantity = 1, .unit_price = 29.99 });
    try inv.addItem(.{ .description = "Domain Name", .quantity = 1, .unit_price = 12.00, .discount = 10.0 });

    inv.setNotes("Thank you for your business!");
    inv.setTerms("Net 30. Late payments subject to 1.5% monthly interest.");

    const bytes = try inv.generate(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    // Check it starts with PDF header
    try std.testing.expect(bytes.len > 100);
    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-"));
}

test "Invoice: generate with no items" {
    var inv = Invoice.init(std.testing.allocator);
    defer inv.deinit();

    inv.setOptions(.{ .invoice_number = "INV-0000" });

    const bytes = try inv.generate(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    try std.testing.expect(std.mem.startsWith(u8, bytes, "%PDF-"));
}

test "Invoice: generate with discount" {
    var inv = Invoice.init(std.testing.allocator);
    defer inv.deinit();

    try inv.addItem(.{ .description = "Service", .quantity = 1, .unit_price = 100.00, .discount = 20.0, .tax_rate = 10.0 });

    const bytes = try inv.generate(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    try std.testing.expect(bytes.len > 100);
}

test "InvoiceColors: defaults" {
    const colors = InvoiceColors{};
    const accent_rgb = colors.accent.toRgb();
    try std.testing.expectEqual(@as(u8, 41), accent_rgb.r);
    try std.testing.expectEqual(@as(u8, 65), accent_rgb.g);
    try std.testing.expectEqual(@as(u8, 122), accent_rgb.b);
}

test "InvoiceItem: defaults" {
    const item = InvoiceItem{ .description = "Test", .quantity = 1, .unit_price = 10.0 };
    try std.testing.expect(item.tax_rate == null);
    try std.testing.expect(item.discount == null);
}

test "formatCurrency helper" {
    var buf: [32]u8 = undefined;
    const result = formatCurrency(99.50, "$", &buf);
    try std.testing.expectEqualStrings("$99.50", result);
}

test "formatPercent helper" {
    var buf: [32]u8 = undefined;
    const result = formatPercent(8.5, &buf);
    try std.testing.expectEqualStrings("8.5%", result);
}
