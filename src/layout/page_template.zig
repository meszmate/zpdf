const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const Page = @import("../document/page.zig").Page;
const PageSize = @import("../document/page_sizes.zig").PageSize;
const Color = @import("../color/color.zig").Color;
const StandardFont = @import("../font/standard_fonts.zig").StandardFont;

/// Page margins in points.
pub const Margins = struct {
    top: f32 = 72,
    bottom: f32 = 72,
    left: f32 = 72,
    right: f32 = 72,

    /// One-inch margins on all sides.
    pub const one_inch: Margins = .{ .top = 72, .bottom = 72, .left = 72, .right = 72 };

    /// Half-inch margins on all sides.
    pub const half_inch: Margins = .{ .top = 36, .bottom = 36, .left = 36, .right = 36 };

    /// Symmetric margins with the same value on all sides.
    pub fn symmetric(value: f32) Margins {
        return .{ .top = value, .bottom = value, .left = value, .right = value };
    }
};

/// Describes the usable content area within a page after margins are applied.
pub const ContentArea = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

/// A single element that can be placed on a template.
pub const TemplateElement = union(enum) {
    text: TextElement,
    rect: RectElement,
    line: LineElement,

    pub const TextElement = struct {
        content: []const u8,
        x: f32,
        y: f32,
        font: StandardFont = .helvetica,
        font_size: f32 = 12,
        color: Color = .{ .named = .black },
        /// If true, {page} placeholder in content is replaced with the page number.
        use_page_number: bool = false,
    };

    pub const RectElement = struct {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
        color: ?Color = null,
        border_color: ?Color = null,
        border_width: f32 = 1.0,
    };

    pub const LineElement = struct {
        x1: f32,
        y1: f32,
        x2: f32,
        y2: f32,
        color: Color = .{ .named = .black },
        line_width: f32 = 1.0,
    };
};

/// A reusable page template that defines margins and a set of elements
/// to be drawn on every page created from it.
pub const PageTemplate = struct {
    allocator: Allocator,
    page_size: PageSize,
    margins: Margins,
    elements: ArrayList(TemplateElement),

    /// Creates a new page template with the given page size and margins.
    pub fn init(allocator: Allocator, page_size: PageSize, margins: Margins) PageTemplate {
        return .{
            .allocator = allocator,
            .page_size = page_size,
            .margins = margins,
            .elements = .{},
        };
    }

    /// Frees all resources held by this template.
    pub fn deinit(self: *PageTemplate) void {
        self.elements.deinit(self.allocator);
    }

    /// Adds a text element to the template.
    pub fn addText(self: *PageTemplate, elem: TemplateElement.TextElement) !void {
        try self.elements.append(self.allocator, .{ .text = elem });
    }

    /// Adds a rectangle element to the template.
    pub fn addRect(self: *PageTemplate, elem: TemplateElement.RectElement) !void {
        try self.elements.append(self.allocator, .{ .rect = elem });
    }

    /// Adds a line element to the template.
    pub fn addLine(self: *PageTemplate, elem: TemplateElement.LineElement) !void {
        try self.elements.append(self.allocator, .{ .line = elem });
    }

    /// Returns the content area available after margins are applied.
    pub fn contentArea(self: *const PageTemplate) ContentArea {
        const dims = self.page_size.dimensions();
        return .{
            .x = self.margins.left,
            .y = self.margins.bottom,
            .width = dims.width - self.margins.left - self.margins.right,
            .height = dims.height - self.margins.top - self.margins.bottom,
        };
    }

    /// Applies all template elements to a page, substituting page_number where requested.
    pub fn apply(self: *const PageTemplate, page: *Page, page_number: usize) !void {
        for (self.elements.items) |elem| {
            switch (elem) {
                .text => |t| {
                    if (t.use_page_number) {
                        const resolved = try std.fmt.allocPrint(page.allocator, "{d}", .{page_number});
                        defer page.allocator.free(resolved);
                        // Replace {page} in content with the page number
                        const text_out = try replacePage(page.allocator, t.content, resolved);
                        defer page.allocator.free(text_out);
                        try page.drawText(text_out, .{
                            .x = t.x,
                            .y = t.y,
                            .font = t.font,
                            .font_size = t.font_size,
                            .color = t.color,
                        });
                    } else {
                        try page.drawText(t.content, .{
                            .x = t.x,
                            .y = t.y,
                            .font = t.font,
                            .font_size = t.font_size,
                            .color = t.color,
                        });
                    }
                },
                .rect => |r| {
                    try page.drawRect(.{
                        .x = r.x,
                        .y = r.y,
                        .width = r.width,
                        .height = r.height,
                        .color = r.color,
                        .border_color = r.border_color,
                        .border_width = r.border_width,
                    });
                },
                .line => |l| {
                    try page.drawLine(.{
                        .x1 = l.x1,
                        .y1 = l.y1,
                        .x2 = l.x2,
                        .y2 = l.y2,
                        .color = l.color,
                        .line_width = l.line_width,
                    });
                },
            }
        }
    }
};

/// Replace all occurrences of "{page}" in text with the replacement string.
fn replacePage(allocator: Allocator, text: []const u8, replacement: []const u8) ![]u8 {
    var result = ArrayList(u8){};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < text.len) {
        if (i + 6 <= text.len and std.mem.eql(u8, text[i .. i + 6], "{page}")) {
            try result.appendSlice(allocator, replacement);
            i += 6;
        } else {
            try result.append(allocator, text[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}

// -- Tests --

test "margins symmetric" {
    const m = Margins.symmetric(50);
    try std.testing.expectApproxEqAbs(@as(f32, 50), m.top, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 50), m.left, 0.01);
}

test "template init and deinit" {
    var tmpl = PageTemplate.init(std.testing.allocator, .a4, Margins.one_inch);
    defer tmpl.deinit();
    try std.testing.expectEqual(@as(usize, 0), tmpl.elements.items.len);
}

test "template add elements" {
    var tmpl = PageTemplate.init(std.testing.allocator, .a4, Margins.one_inch);
    defer tmpl.deinit();

    try tmpl.addText(.{ .content = "Header", .x = 72, .y = 770 });
    try tmpl.addRect(.{ .x = 50, .y = 50, .width = 495, .height = 2 });
    try tmpl.addLine(.{ .x1 = 50, .y1 = 800, .x2 = 545, .y2 = 800 });

    try std.testing.expectEqual(@as(usize, 3), tmpl.elements.items.len);
}

test "content area calculation" {
    var tmpl = PageTemplate.init(std.testing.allocator, .a4, .{
        .top = 72,
        .bottom = 72,
        .left = 50,
        .right = 50,
    });
    defer tmpl.deinit();

    const area = tmpl.contentArea();
    const dims = PageSize.a4.dimensions();
    try std.testing.expectApproxEqAbs(@as(f32, 50), area.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 72), area.y, 0.01);
    try std.testing.expectApproxEqAbs(dims.width - 100, area.width, 0.01);
    try std.testing.expectApproxEqAbs(dims.height - 144, area.height, 0.01);
}

test "template apply draws elements" {
    var tmpl = PageTemplate.init(std.testing.allocator, .a4, Margins.one_inch);
    defer tmpl.deinit();

    try tmpl.addText(.{ .content = "Test", .x = 72, .y = 770 });
    try tmpl.addRect(.{ .x = 50, .y = 50, .width = 100, .height = 50, .color = .{ .named = .blue } });
    try tmpl.addLine(.{ .x1 = 50, .y1 = 800, .x2 = 545, .y2 = 800 });

    var page = Page.init(std.testing.allocator, 595.28, 841.89);
    defer page.deinit();

    try tmpl.apply(&page, 1);
    try std.testing.expect(page.content.items.len > 0);
}

test "template apply with page number" {
    var tmpl = PageTemplate.init(std.testing.allocator, .a4, Margins.one_inch);
    defer tmpl.deinit();

    try tmpl.addText(.{
        .content = "Page {page}",
        .x = 500,
        .y = 30,
        .use_page_number = true,
    });

    var page = Page.init(std.testing.allocator, 595.28, 841.89);
    defer page.deinit();

    try tmpl.apply(&page, 5);
    try std.testing.expect(page.content.items.len > 0);
}

test "replacePage" {
    const allocator = std.testing.allocator;
    const result = try replacePage(allocator, "Page {page} footer", "3");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Page 3 footer", result);
}
