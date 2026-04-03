const std = @import("std");
const Allocator = std.mem.Allocator;
const Document = @import("document.zig").Document;
const EncryptionOptions = @import("document.zig").EncryptionOptions;
const Page = @import("page.zig").Page;
const PageSize = @import("page_sizes.zig").PageSize;
const ImageHandle = @import("page.zig").ImageHandle;
const TextOptions = @import("page.zig").TextOptions;
const RectOptions = @import("page.zig").RectOptions;
const CircleOptions = @import("page.zig").CircleOptions;
const LineOptions = @import("page.zig").LineOptions;
const ImageOptions = @import("page.zig").ImageOptions;
const StandardFont = @import("../font/standard_fonts.zig").StandardFont;

/// A chainable builder for adding drawing operations to a single page.
/// Returned by `DocumentBuilder.page()` and `DocumentBuilder.pageCustom()`.
pub const PageBuilder = struct {
    doc_builder: *DocumentBuilder,
    pg: *Page,

    /// Draw text on this page.
    pub fn text(self: *PageBuilder, str: []const u8, options: TextOptions) *PageBuilder {
        if (self.doc_builder.err != null) return self;
        self.ensureFont(options.font) catch |e| {
            self.doc_builder.err = e;
            return self;
        };
        self.pg.drawText(str, options) catch |e| {
            self.doc_builder.err = e;
        };
        return self;
    }

    /// Draw a rectangle on this page.
    pub fn rect(self: *PageBuilder, options: RectOptions) *PageBuilder {
        if (self.doc_builder.err != null) return self;
        self.pg.drawRect(options) catch |e| {
            self.doc_builder.err = e;
        };
        return self;
    }

    /// Draw a circle on this page.
    pub fn circle(self: *PageBuilder, options: CircleOptions) *PageBuilder {
        if (self.doc_builder.err != null) return self;
        self.pg.drawCircle(options) catch |e| {
            self.doc_builder.err = e;
        };
        return self;
    }

    /// Draw a line on this page.
    pub fn line(self: *PageBuilder, options: LineOptions) *PageBuilder {
        if (self.doc_builder.err != null) return self;
        self.pg.drawLine(options) catch |e| {
            self.doc_builder.err = e;
        };
        return self;
    }

    /// Draw an image on this page.
    pub fn image(self: *PageBuilder, handle: ImageHandle, options: ImageOptions) *PageBuilder {
        if (self.doc_builder.err != null) return self;
        self.pg.drawImage(handle, options) catch |e| {
            self.doc_builder.err = e;
        };
        return self;
    }

    /// Finish this page and return to the DocumentBuilder for further chaining.
    pub fn done(self: *PageBuilder) *DocumentBuilder {
        return self.doc_builder;
    }

    /// Get a mutable reference to the underlying Page for advanced usage.
    pub fn getPage(self: *PageBuilder) *Page {
        return self.pg;
    }

    fn ensureFont(self: *PageBuilder, font: StandardFont) !void {
        const handle = try self.doc_builder.doc.getStandardFont(font);
        _ = try self.pg.addFont(handle.font.pdfName(), handle.ref);
    }
};

/// A chainable builder for constructing PDF documents ergonomically.
///
/// Usage:
/// ```
/// const pdf = try zpdf.build(allocator)
///     .title("My Document")
///     .author("John Doe")
///     .page(.a4)
///         .text("Hello World", .{ .x = 50, .y = 750, .font_size = 24 })
///         .rect(.{ .x = 50, .y = 700, .width = 200, .height = 50 })
///     .done()
///     .save();
/// defer allocator.free(pdf);
/// ```
pub const DocumentBuilder = struct {
    doc: Document,
    err: ?anyerror,
    page_builders: std.ArrayListUnmanaged(PageBuilder),

    /// Create a new DocumentBuilder wrapping a fresh Document.
    pub fn init(allocator: Allocator) DocumentBuilder {
        return .{
            .doc = Document.init(allocator),
            .err = null,
            .page_builders = .{},
        };
    }

    /// Free all resources held by the underlying document and page builders.
    pub fn deinit(self: *DocumentBuilder) void {
        self.page_builders.deinit(self.doc.allocator);
        self.doc.deinit();
    }

    /// Set the document title.
    pub fn title(self: *DocumentBuilder, value: []const u8) *DocumentBuilder {
        self.doc.setTitle(value);
        return self;
    }

    /// Set the document author.
    pub fn author(self: *DocumentBuilder, value: []const u8) *DocumentBuilder {
        self.doc.setAuthor(value);
        return self;
    }

    /// Set the document subject.
    pub fn subject(self: *DocumentBuilder, value: []const u8) *DocumentBuilder {
        self.doc.setSubject(value);
        return self;
    }

    /// Set the document keywords.
    pub fn keywords(self: *DocumentBuilder, value: []const u8) *DocumentBuilder {
        self.doc.setKeywords(value);
        return self;
    }

    /// Set the document creator.
    pub fn creator(self: *DocumentBuilder, value: []const u8) *DocumentBuilder {
        self.doc.setCreator(value);
        return self;
    }

    /// Enable encryption with the given options.
    pub fn encrypt(self: *DocumentBuilder, options: EncryptionOptions) *DocumentBuilder {
        self.doc.encrypt(options);
        return self;
    }

    /// Add a page with a predefined size and return a PageBuilder for it.
    pub fn page(self: *DocumentBuilder, size: PageSize) *PageBuilder {
        if (self.err != null) {
            return self.dummyPageBuilder();
        }
        const pg = self.doc.addPage(size) catch |e| {
            self.err = e;
            return self.dummyPageBuilder();
        };
        return self.createPageBuilder(pg);
    }

    /// Add a page with custom dimensions (in points) and return a PageBuilder for it.
    pub fn pageCustom(self: *DocumentBuilder, width: f32, height: f32) *PageBuilder {
        if (self.err != null) {
            return self.dummyPageBuilder();
        }
        const pg = self.doc.addPageWithDimensions(width, height) catch |e| {
            self.err = e;
            return self.dummyPageBuilder();
        };
        return self.createPageBuilder(pg);
    }

    /// Serialize the document to PDF bytes. Returns an error if any prior
    /// builder operation failed, or if serialization itself fails.
    pub fn save(self: *DocumentBuilder) ![]u8 {
        if (self.err) |e| return e;
        return self.doc.save(self.doc.allocator);
    }

    /// Get a mutable reference to the underlying Document for advanced usage.
    pub fn getDocument(self: *DocumentBuilder) *Document {
        return &self.doc;
    }

    fn createPageBuilder(self: *DocumentBuilder, pg: *Page) *PageBuilder {
        self.page_builders.append(self.doc.allocator, .{
            .doc_builder = self,
            .pg = pg,
        }) catch |e| {
            self.err = e;
            return self.dummyPageBuilder();
        };
        return &self.page_builders.items[self.page_builders.items.len - 1];
    }

    fn dummyPageBuilder(self: *DocumentBuilder) *PageBuilder {
        // When an error has already occurred, we need a valid pointer to return
        // so the chain can continue (all subsequent ops will be no-ops due to err).
        // We append a dummy entry; if this allocation also fails we have a problem,
        // but the pattern requires returning a pointer.
        self.page_builders.append(self.doc.allocator, .{
            .doc_builder = self,
            .pg = undefined,
        }) catch {
            // Last resort: return pointer to last item if available, otherwise
            // this is truly unrecoverable (OOM while already in error state).
            if (self.page_builders.items.len > 0) {
                return &self.page_builders.items[self.page_builders.items.len - 1];
            }
            // This should not happen in practice since we already failed once.
            @panic("DocumentBuilder: out of memory during error handling");
        };
        return &self.page_builders.items[self.page_builders.items.len - 1];
    }
};

// -- Tests --

test "document builder basic chain" {
    const allocator = std.testing.allocator;

    var builder = DocumentBuilder.init(allocator);
    defer builder.deinit();

    const pdf = try builder
        .title("Test Doc")
        .author("Test Author")
        .subject("Test Subject")
        .keywords("test, builder")
        .creator("builder test")
        .page(.a4)
        .text("Hello World", .{ .x = 50, .y = 750, .font_size = 24 })
        .rect(.{ .x = 50, .y = 700, .width = 200, .height = 50 })
        .done()
        .save();
    defer allocator.free(pdf);

    // Verify PDF was produced
    try std.testing.expect(pdf.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, pdf, "%PDF"));
}

test "document builder multiple pages" {
    const allocator = std.testing.allocator;

    var builder = DocumentBuilder.init(allocator);
    defer builder.deinit();

    const pdf = try builder
        .title("Multi Page")
        .page(.a4)
        .text("Page 1", .{ .x = 50, .y = 750 })
        .done()
        .page(.letter)
        .text("Page 2", .{ .x = 50, .y = 750 })
        .done()
        .save();
    defer allocator.free(pdf);

    try std.testing.expect(pdf.len > 0);
    try std.testing.expectEqual(@as(usize, 2), builder.doc.getPageCount());
}

test "document builder custom page size" {
    const allocator = std.testing.allocator;

    var builder = DocumentBuilder.init(allocator);
    defer builder.deinit();

    const pdf = try builder
        .pageCustom(300, 400)
        .text("Custom size", .{ .x = 10, .y = 380 })
        .done()
        .save();
    defer allocator.free(pdf);

    try std.testing.expect(pdf.len > 0);
}

test "document builder drawing operations" {
    const allocator = std.testing.allocator;

    var builder = DocumentBuilder.init(allocator);
    defer builder.deinit();

    const pdf = try builder
        .page(.a4)
        .text("Test", .{ .x = 50, .y = 750 })
        .rect(.{ .x = 50, .y = 700, .width = 100, .height = 50 })
        .circle(.{ .cx = 200, .cy = 600, .r = 30 })
        .line(.{ .x1 = 50, .y1 = 500, .x2 = 200, .y2 = 500 })
        .done()
        .save();
    defer allocator.free(pdf);

    try std.testing.expect(pdf.len > 0);
}

test "document builder metadata" {
    const allocator = std.testing.allocator;

    var builder = DocumentBuilder.init(allocator);
    defer builder.deinit();

    _ = builder
        .title("Title")
        .author("Author")
        .subject("Subject")
        .keywords("a, b")
        .creator("Creator");

    try std.testing.expectEqualStrings("Title", builder.doc.title.?);
    try std.testing.expectEqualStrings("Author", builder.doc.author.?);
    try std.testing.expectEqualStrings("Subject", builder.doc.subject.?);
    try std.testing.expectEqualStrings("a, b", builder.doc.keywords.?);
    try std.testing.expectEqualStrings("Creator", builder.doc.creator.?);
}

test "document builder encrypt" {
    const allocator = std.testing.allocator;

    var builder = DocumentBuilder.init(allocator);
    defer builder.deinit();

    _ = builder.encrypt(.{
        .user_password = "user",
        .owner_password = "owner",
    });

    try std.testing.expect(builder.doc.encryption_options != null);
}

test "document builder get document" {
    const allocator = std.testing.allocator;

    var builder = DocumentBuilder.init(allocator);
    defer builder.deinit();

    const doc = builder.getDocument();
    try std.testing.expectEqual(@as(usize, 0), doc.getPageCount());
}

test "page builder get page" {
    const allocator = std.testing.allocator;

    var builder = DocumentBuilder.init(allocator);
    defer builder.deinit();

    const pb = builder.page(.a4);
    const pg = pb.getPage();
    try std.testing.expectApproxEqAbs(@as(f32, 595.28), pg.getWidth(), 0.01);
}
