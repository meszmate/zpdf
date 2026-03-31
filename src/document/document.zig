const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const types = @import("../core/types.zig");
const Ref = types.Ref;
const ObjectStore = @import("../core/object_store.zig").ObjectStore;
const PageTree = @import("../core/page_tree.zig").PageTree;
const Catalog = @import("../core/catalog.zig").Catalog;
const Page = @import("page.zig").Page;
const PageSize = @import("page_sizes.zig").PageSize;
const StandardFont = @import("../font/standard_fonts.zig").StandardFont;
const TrueTypeFont = @import("../font/truetype.zig").TrueTypeFont;
const font_embedder = @import("../font/font_embedder.zig");
const EmbeddedFontData = font_embedder.EmbeddedFont;
const PdfWriter = @import("../writer/pdf_writer.zig").PdfWriter;
const stream_writer = @import("../writer/stream_writer.zig");
const HeaderFooter = @import("../layout/header_footer.zig").HeaderFooter;

/// Handle to a font resource within the document.
pub const FontHandle = struct {
    ref: Ref,
    font: StandardFont,
};

/// Handle to a TrueType font resource within the document.
pub const TrueTypeFontHandle = struct {
    ref: Ref,
    font: *TrueTypeFont,
    name: []const u8,
};

/// Encryption options for document security.
pub const EncryptionOptions = struct {
    user_password: []const u8,
    owner_password: []const u8,
    permissions: u32 = 0xFFFFFFFF,
    key_length: u16 = 128,
};

/// A bookmark (outline entry) in the document.
pub const Bookmark = struct {
    title: []const u8,
    page_index: usize,
    parent: ?usize,
    children: ArrayList(usize),
    allocator: Allocator,

    pub fn init(allocator: Allocator, title: []const u8, page_index: usize) Bookmark {
        return .{
            .title = title,
            .page_index = page_index,
            .parent = null,
            .children = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Bookmark) void {
        self.children.deinit(self.allocator);
    }
};

/// The main PDF document, providing a high-level API for creating pages,
/// adding content, setting metadata, and serializing to PDF bytes.
pub const Document = struct {
    allocator: Allocator,
    pages: ArrayList(*Page),
    object_store: ObjectStore,
    page_tree: PageTree,
    catalog: Catalog,
    font_refs: std.StringHashMapUnmanaged(Ref),

    // Metadata
    title: ?[]const u8,
    author: ?[]const u8,
    subject: ?[]const u8,
    keywords: ?[]const u8,
    creator: ?[]const u8,
    producer: ?[]const u8,

    encryption_options: ?EncryptionOptions,
    bookmarks: ArrayList(Bookmark),
    header: ?HeaderFooter,
    footer: ?HeaderFooter,
    tt_fonts: ArrayList(*TrueTypeFont),
    embedded_font_data: ArrayList(EmbeddedFontData),

    /// Creates a new empty PDF document.
    pub fn init(allocator: Allocator) Document {
        return .{
            .allocator = allocator,
            .pages = .{},
            .object_store = ObjectStore.init(allocator),
            .page_tree = PageTree.init(allocator),
            .catalog = Catalog.init(),
            .font_refs = .{},
            .title = null,
            .author = null,
            .subject = null,
            .keywords = null,
            .creator = null,
            .producer = null,
            .encryption_options = null,
            .bookmarks = .{},
            .header = null,
            .footer = null,
            .tt_fonts = .{},
            .embedded_font_data = .{},
        };
    }

    /// Frees all document resources including pages and stored objects.
    pub fn deinit(self: *Document) void {
        for (self.pages.items) |page| {
            page.deinit();
            self.allocator.destroy(page);
        }
        self.pages.deinit(self.allocator);
        self.object_store.deinit();
        self.page_tree.deinit();
        self.font_refs.deinit(self.allocator);
        for (self.bookmarks.items) |*bm| {
            bm.deinit();
        }
        self.bookmarks.deinit(self.allocator);
        for (self.embedded_font_data.items) |*efd| {
            @constCast(efd).deinit();
        }
        self.embedded_font_data.deinit(self.allocator);
        for (self.tt_fonts.items) |tt_font| {
            @constCast(tt_font).deinit();
            self.allocator.destroy(tt_font);
        }
        self.tt_fonts.deinit(self.allocator);
    }

    // -- Metadata setters --

    pub fn setTitle(self: *Document, title: []const u8) void {
        self.title = title;
    }

    pub fn setAuthor(self: *Document, author: []const u8) void {
        self.author = author;
    }

    pub fn setSubject(self: *Document, subject: []const u8) void {
        self.subject = subject;
    }

    pub fn setKeywords(self: *Document, keywords: []const u8) void {
        self.keywords = keywords;
    }

    pub fn setCreator(self: *Document, creator: []const u8) void {
        self.creator = creator;
    }

    /// Sets the header configuration to be applied to all pages on save.
    pub fn setHeader(self: *Document, header: HeaderFooter) void {
        self.header = header;
    }

    /// Sets the footer configuration to be applied to all pages on save.
    pub fn setFooter(self: *Document, footer: HeaderFooter) void {
        self.footer = footer;
    }

    // -- Page management --

    /// Adds a new page with a predefined page size (portrait).
    pub fn addPage(self: *Document, size: PageSize) !*Page {
        const dims = size.dimensions();
        return self.addPageWithDimensions(dims.width, dims.height);
    }

    /// Adds a new page with custom dimensions in points.
    pub fn addPageWithDimensions(self: *Document, width: f32, height: f32) !*Page {
        const page = try self.allocator.create(Page);
        page.* = Page.init(self.allocator, width, height);
        try self.pages.append(self.allocator, page);
        return page;
    }

    /// Returns the page at the given index, or null if out of bounds.
    pub fn getPage(self: *Document, index: usize) ?*Page {
        if (index >= self.pages.items.len) return null;
        return self.pages.items[index];
    }

    /// Returns the total number of pages.
    pub fn getPageCount(self: *const Document) usize {
        return self.pages.items.len;
    }

    /// Removes the page at the given index.
    pub fn removePage(self: *Document, index: usize) !void {
        if (index >= self.pages.items.len) return error.IndexOutOfBounds;
        const page = self.pages.orderedRemove(index);
        page.deinit();
        self.allocator.destroy(page);
    }

    /// Inserts a new page at the given index with a predefined page size.
    pub fn insertPage(self: *Document, index: usize, size: PageSize) !*Page {
        const dims = size.dimensions();
        const page = try self.allocator.create(Page);
        page.* = Page.init(self.allocator, dims.width, dims.height);
        try self.pages.insert(self.allocator, index, page);
        return page;
    }

    /// Returns a font handle for one of the 14 standard PDF fonts.
    /// The font object is registered in the object store if not already present.
    pub fn getStandardFont(self: *Document, font: StandardFont) !FontHandle {
        const pdf_name = font.pdfName();
        if (self.font_refs.get(pdf_name)) |ref| {
            return .{ .ref = ref, .font = font };
        }

        // Create font dictionary object
        const ref = try self.object_store.allocate();
        var dict = types.pdfDict(self.allocator);
        try dict.dict_obj.put(self.allocator,"Type", types.pdfName("Font"));
        try dict.dict_obj.put(self.allocator,"Subtype", types.pdfName("Type1"));
        try dict.dict_obj.put(self.allocator,"BaseFont", types.pdfName(pdf_name));
        self.object_store.put(ref, dict);

        try self.font_refs.put(self.allocator, pdf_name, ref);
        return .{ .ref = ref, .font = font };
    }

    /// Adds a bookmark (outline entry) pointing to the given page.
    pub fn addBookmark(self: *Document, title: []const u8, page_index: usize) !usize {
        const idx = self.bookmarks.items.len;
        try self.bookmarks.append(self.allocator, Bookmark.init(self.allocator, title, page_index));
        return idx;
    }

    /// Enables encryption with the given options.
    pub fn encrypt(self: *Document, options: EncryptionOptions) void {
        self.encryption_options = options;
    }

    /// Load and register a TrueType font from raw font data.
    /// The font is parsed and stored; it can be used on pages via the returned handle.
    pub fn loadTrueTypeFont(self: *Document, font_data: []const u8) !TrueTypeFontHandle {
        const tt_font = try self.allocator.create(TrueTypeFont);
        errdefer self.allocator.destroy(tt_font);

        tt_font.* = try TrueTypeFont.init(self.allocator, font_data);
        errdefer tt_font.deinit();

        // Embed the font (with no used chars initially; the full embedding
        // happens at save time, but we register the font object now)
        const used_chars = [_]u32{};
        var embedded = try font_embedder.embedFont(self.allocator, &self.object_store, tt_font, &used_chars);
        errdefer embedded.deinit();

        const pdf_name = tt_font.postscript_name;
        try self.font_refs.put(self.allocator, pdf_name, embedded.ref);
        try self.tt_fonts.append(self.allocator, tt_font);
        try self.embedded_font_data.append(self.allocator, embedded);

        return TrueTypeFontHandle{
            .ref = embedded.ref,
            .font = tt_font,
            .name = embedded.name,
        };
    }

    /// Serializes the entire document to PDF bytes.
    pub fn save(self: *Document, allocator: Allocator) ![]u8 {
        return PdfWriter.writePdf(allocator, self);
    }

    /// Stream the document directly to a writer without building the entire PDF in memory.
    pub fn saveTo(self: *Document, allocator: Allocator, wr: anytype) !void {
        return stream_writer.streamPdf(allocator, self, wr);
    }
};

// -- Tests --

test "document init and deinit" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    try std.testing.expectEqual(@as(usize, 0), doc.getPageCount());
}

test "add and get page" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    const page = try doc.addPage(.a4);
    try std.testing.expectEqual(@as(usize, 1), doc.getPageCount());
    try std.testing.expectApproxEqAbs(@as(f32, 595.28), page.getWidth(), 0.01);

    const fetched = doc.getPage(0);
    try std.testing.expect(fetched != null);
    try std.testing.expect(doc.getPage(1) == null);
}

test "remove page" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    _ = try doc.addPage(.a4);
    _ = try doc.addPage(.letter);
    try std.testing.expectEqual(@as(usize, 2), doc.getPageCount());

    try doc.removePage(0);
    try std.testing.expectEqual(@as(usize, 1), doc.getPageCount());
}

test "insert page" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    _ = try doc.addPage(.a4);
    _ = try doc.addPage(.a4);
    const inserted = try doc.insertPage(1, .letter);
    try std.testing.expectEqual(@as(usize, 3), doc.getPageCount());
    try std.testing.expectApproxEqAbs(@as(f32, 612.0), inserted.getWidth(), 0.01);
}

test "set metadata" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    doc.setTitle("Test PDF");
    doc.setAuthor("zpdf");
    try std.testing.expectEqualStrings("Test PDF", doc.title.?);
    try std.testing.expectEqualStrings("zpdf", doc.author.?);
}

test "get standard font" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    const handle = try doc.getStandardFont(.helvetica);
    try std.testing.expectEqual(@as(u32, 1), handle.ref.obj_num);

    // Getting same font again should return same ref
    const handle2 = try doc.getStandardFont(.helvetica);
    try std.testing.expect(handle.ref.eql(handle2.ref));
}

test "add bookmark" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    _ = try doc.addPage(.a4);
    const idx = try doc.addBookmark("Chapter 1", 0);
    try std.testing.expectEqual(@as(usize, 0), idx);
    try std.testing.expectEqual(@as(usize, 1), doc.bookmarks.items.len);
}
