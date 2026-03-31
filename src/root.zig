//! zpdf - A comprehensive, zero-dependency PDF library for Zig
//!
//! zpdf provides complete capabilities for creating, parsing, modifying,
//! and manipulating PDF documents in pure Zig. No runtime dependencies.
//!
//! ## Quick Start
//!
//! ```zig
//! const std = @import("std");
//! const zpdf = @import("zpdf");
//!
//! pub fn main() !void {
//!     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//!     defer _ = gpa.deinit();
//!     const allocator = gpa.allocator();
//!
//!     var doc = zpdf.Document.init(allocator);
//!     defer doc.deinit();
//!
//!     doc.setTitle("Hello World");
//!     var page = try doc.addPage(.a4);
//!     try page.drawText("Hello, zpdf!", .{
//!         .x = 50, .y = 750,
//!         .font = .helvetica,
//!         .font_size = 24,
//!         .color = zpdf.rgb(0, 51, 153),
//!     });
//!
//!     const bytes = try doc.save(allocator);
//!     defer allocator.free(bytes);
//!
//!     const file = try std.fs.cwd().createFile("hello.pdf", .{});
//!     defer file.close();
//!     try file.writeAll(bytes);
//! }
//! ```

const std = @import("std");

// ── Document (high-level API) ────────────────────────────────────────
pub const document = struct {
    pub const doc = @import("document/document.zig");
    pub const page = @import("document/page.zig");
    pub const page_sizes = @import("document/page_sizes.zig");
};
pub const Document = document.doc.Document;
pub const Page = document.page.Page;
pub const PageSize = document.page_sizes.PageSize;
pub const ImageHandle = document.page.ImageHandle;
pub const PathBuilder = document.page.PathBuilder;
pub const EncryptionOptions = document.doc.EncryptionOptions;

// ── Core (low-level PDF objects) ─────────────────────────────────────
pub const core = struct {
    pub const types = @import("core/types.zig");
    pub const object_store = @import("core/object_store.zig");
    pub const catalog = @import("core/catalog.zig");
    pub const page_tree = @import("core/page_tree.zig");
};
pub const PdfObject = core.types.PdfObject;
pub const Ref = core.types.Ref;
pub const ObjectStore = core.object_store.ObjectStore;

// ── Color ────────────────────────────────────────────────────────────
pub const color = @import("color/color.zig");
pub const color_conversion = @import("color/conversion.zig");
pub const Color = color.Color;
pub const rgb = color.rgb;
pub const cmyk = color.cmyk;
pub const grayscale = color.grayscale;
pub const hexColor = color.hexColor;

// ── Font ─────────────────────────────────────────────────────────────
pub const standard_fonts = @import("font/standard_fonts.zig");
pub const font_manager = @import("font/font_manager.zig");
pub const StandardFont = standard_fonts.StandardFont;
pub const FontHandle = font_manager.FontHandle;

// ── Graphics ─────────────────────────────────────────────────────────
pub const graphics = struct {
    pub const path_builder = @import("graphics/path_builder.zig");
    pub const transform = @import("graphics/transform.zig");
    pub const state = @import("graphics/state.zig");
    pub const gradient_mod = @import("graphics/gradient.zig");
};
pub const GfxPathBuilder = graphics.path_builder.PathBuilder;
pub const Matrix = @import("utils/math.zig").Matrix;
pub const GraphicsState = graphics.state.GraphicsState;
pub const gradient = graphics.gradient_mod;
pub const LinearGradient = gradient.LinearGradient;
pub const RadialGradient = gradient.RadialGradient;
pub const ColorStop = gradient.ColorStop;
pub const ClipMode = graphics.state.ClipMode;

// ── Text ─────────────────────────────────────────────────────────────
pub const text = struct {
    pub const text_style = @import("text/text_style.zig");
    pub const text_layout = @import("text/text_layout.zig");
    pub const text_renderer = @import("text/text_renderer.zig");
    pub const rich_text = @import("text/rich_text.zig");
};
pub const TextStyle = text.text_style.TextStyle;
pub const Alignment = text.text_style.Alignment;
pub const TextSpan = text.rich_text.TextSpan;
pub const RichTextOptions = text.rich_text.RichTextOptions;
pub const RichTextAlignment = text.rich_text.RichTextAlignment;

// ── Image ────────────────────────────────────────────────────────────
pub const image = struct {
    pub const jpeg_handler = @import("image/jpeg_handler.zig");
    pub const png_handler = @import("image/png_handler.zig");
    pub const image_embedder = @import("image/image_embedder.zig");
};
pub const EmbedImageHandle = image.image_embedder.ImageHandle;
pub const ImageFormat = image.image_embedder.ImageFormat;

// ── Table ────────────────────────────────────────────────────────────
pub const table = struct {
    pub const Table = @import("table/table.zig");
    pub const table_renderer = @import("table/table_renderer.zig");
};

// ── Form ─────────────────────────────────────────────────────────────
pub const form = struct {
    pub const Form = @import("form/form.zig");
    pub const form_builder = @import("form/form_builder.zig");
};
pub const FormBuilder = form.form_builder.FormBuilder;

// ── Layout ──────────────────────────────────────────────────────────
pub const layout = struct {
    pub const header_footer = @import("layout/header_footer.zig");
};
pub const HeaderFooter = layout.header_footer.HeaderFooter;
pub const HFElement = layout.header_footer.HFElement;
pub const HFContent = layout.header_footer.HFContent;
pub const HFPosition = layout.header_footer.HFPosition;

// ── Writer ───────────────────────────────────────────────────────────
pub const writer = struct {
    pub const pdf_writer = @import("writer/pdf_writer.zig");
    pub const object_serializer = @import("writer/object_serializer.zig");
    pub const xref_writer = @import("writer/xref_writer.zig");
    pub const stream_writer = @import("writer/stream_writer.zig");
};
pub const countingWriter = writer.stream_writer.countingWriter;
pub const CountingWriter = writer.stream_writer.CountingWriter;

// ── Compress ─────────────────────────────────────────────────────────
pub const compress = struct {
    pub const deflate_mod = @import("compress/deflate.zig");
    pub const inflate_mod = @import("compress/inflate.zig");
    pub const ascii85 = @import("compress/ascii85.zig");
    pub const ascii_hex = @import("compress/ascii_hex.zig");
    pub const run_length = @import("compress/run_length.zig");
    pub const predictor = @import("compress/predictor.zig");
};

// ── Utils ────────────────────────────────────────────────────────────
pub const utils = struct {
    pub const buffer = @import("utils/buffer.zig");
    pub const encoding = @import("utils/encoding.zig");
    pub const math = @import("utils/math.zig");
    pub const string_utils = @import("utils/string_utils.zig");
    pub const crc32 = @import("utils/crc32.zig");
};
pub const ByteBuffer = utils.buffer.ByteBuffer;

// ── Security ─────────────────────────────────────────────────────────
pub const security = struct {
    pub const rc4 = @import("security/rc4.zig");
    pub const md5 = @import("security/md5.zig");
    pub const aes = @import("security/aes.zig");
    pub const security_handler = @import("security/security_handler.zig");
    pub const signature = @import("security/signature.zig");
    pub const sha256 = @import("security/sha256.zig");
    pub const pkcs7 = @import("security/pkcs7.zig");
};
pub const SecurityEncryptionOptions = security.security_handler.EncryptionOptions;
pub const SignatureOptions = security.signature.SignatureOptions;
pub const SignatureAppearance = security.signature.SignatureAppearance;
pub const PreparedSignature = security.signature.PreparedSignature;
pub const Sha256 = security.sha256.Sha256;

// ── Barcode ──────────────────────────────────────────────────────────
pub const barcode = struct {
    pub const barcode_api = @import("barcode/barcode.zig");
    pub const code128 = @import("barcode/code128.zig");
    pub const code39 = @import("barcode/code39.zig");
    pub const ean13 = @import("barcode/ean13.zig");
    pub const qr_code = @import("barcode/qr/qr_code.zig");
};
pub const drawBarcode = barcode.barcode_api.drawBarcode;

// ── Annotation ───────────────────────────────────────────────────────
pub const annotation = @import("annotation/annotation.zig");
pub const Annotation = annotation.Annotation;

// ── Outline (Bookmarks) ─────────────────────────────────────────────
pub const outline = @import("outline/outline.zig");
pub const OutlineTree = outline.OutlineTree;

// ── Metadata ─────────────────────────────────────────────────────────
pub const metadata = struct {
    pub const info_dict = @import("metadata/info_dict.zig");
    pub const xmp = @import("metadata/xmp.zig");
};
pub const DocumentInfo = metadata.info_dict.DocumentInfo;

// ── Modify ───────────────────────────────────────────────────────────
pub const modify = struct {
    pub const merger = @import("modify/merger.zig");
    pub const splitter = @import("modify/splitter.zig");
    pub const watermarker = @import("modify/watermarker.zig");
    pub const incremental = @import("modify/incremental.zig");
};
pub const PdfMerger = modify.merger.PdfMerger;
pub const IncrementalUpdate = modify.incremental.IncrementalUpdate;
pub const MetadataUpdate = modify.incremental.MetadataUpdate;

// ── Layers (Optional Content) ───────────────────────────────────────
pub const layers = @import("layers/layer_builder.zig");
pub const LayerBuilder = layers.LayerBuilder;

// ── Structure (Tagged PDF / Accessibility) ──────────────────────────
pub const structure = @import("structure/structure_tree.zig");
pub const StructureTree = structure.StructureTree;

// ── Parser ───────────────────────────────────────────────────────────
pub const parser = struct {
    pub const pdf_parser = @import("parser/pdf_parser.zig");
    pub const tokenizer = @import("parser/tokenizer.zig");
};
pub const parsePdf = parser.pdf_parser.parsePdf;

test {
    std.testing.refAllDeclsRecursive(@This());
}
