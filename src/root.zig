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
    pub const attachments = @import("document/attachments.zig");
    pub const destinations = @import("document/destinations.zig");
    pub const builder_mod = @import("document/builder.zig");
};
pub const Document = document.doc.Document;
pub const DocumentBuilder = document.builder_mod.DocumentBuilder;
pub const PageBuilder = document.builder_mod.PageBuilder;

/// Create a DocumentBuilder for fluent/chainable PDF construction.
pub fn build(allocator: std.mem.Allocator) DocumentBuilder {
    return DocumentBuilder.init(allocator);
}
pub const Page = document.page.Page;
pub const PageSize = document.page_sizes.PageSize;
pub const ImageHandle = document.page.ImageHandle;
pub const PathBuilder = document.page.PathBuilder;
pub const EncryptionOptions = document.doc.EncryptionOptions;
pub const Attachment = document.doc.Attachment;
pub const AttachmentBuilder = document.attachments.AttachmentBuilder;
pub const Destination = document.doc.Destination;
pub const DestinationType = document.doc.DestinationType;
pub const InternalLink = document.doc.InternalLink;
pub const TocEntry = document.doc.TocEntry;
pub const TocOptions = document.doc.TocOptions;

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
pub const truetype = @import("font/truetype.zig");
pub const font_subsetter = @import("font/font_subsetter.zig");
pub const font_embedder = @import("font/font_embedder.zig");
pub const StandardFont = standard_fonts.StandardFont;
pub const FontHandle = font_manager.FontHandle;
pub const TrueTypeFont = truetype.TrueTypeFont;
pub const TrueTypeFontHandle = document.doc.TrueTypeFontHandle;

// ── Graphics ─────────────────────────────────────────────────────────
pub const graphics = struct {
    pub const path_builder = @import("graphics/path_builder.zig");
    pub const transform = @import("graphics/transform.zig");
    pub const state = @import("graphics/state.zig");
    pub const gradient_mod = @import("graphics/gradient.zig");
    pub const soft_mask_mod = @import("graphics/soft_mask.zig");
    pub const tiling_pattern_mod = @import("graphics/tiling_pattern.zig");
    pub const transparency_mod = @import("graphics/transparency.zig");
};
pub const GfxPathBuilder = graphics.path_builder.PathBuilder;
pub const Matrix = @import("utils/math.zig").Matrix;
pub const GraphicsState = graphics.state.GraphicsState;
pub const gradient = graphics.gradient_mod;
pub const LinearGradient = gradient.LinearGradient;
pub const RadialGradient = gradient.RadialGradient;
pub const ColorStop = gradient.ColorStop;
pub const ClipMode = graphics.state.ClipMode;
pub const soft_mask = graphics.soft_mask_mod;
pub const SoftMask = soft_mask.SoftMask;
pub const SoftMaskType = soft_mask.SoftMaskType;
pub const GradientMask = soft_mask.GradientMask;
pub const tiling_pattern = graphics.tiling_pattern_mod;
pub const TilingPattern = tiling_pattern.TilingPattern;
pub const TilingType = tiling_pattern.TilingType;
pub const PaintType = tiling_pattern.PaintType;
pub const TilingPatternBuilder = tiling_pattern.PatternBuilder;
pub const transparency = graphics.transparency_mod;
pub const BlendMode = transparency.BlendMode;
pub const TransparencyOptions = transparency.TransparencyOptions;

// ── Text ─────────────────────────────────────────────────────────────
pub const text = struct {
    pub const text_style = @import("text/text_style.zig");
    pub const text_layout = @import("text/text_layout.zig");
    pub const text_renderer = @import("text/text_renderer.zig");
    pub const rich_text = @import("text/rich_text.zig");
    pub const hyphenation = @import("text/hyphenation.zig");
};
pub const TextStyle = text.text_style.TextStyle;
pub const Alignment = text.text_style.Alignment;
pub const TextSpan = text.rich_text.TextSpan;
pub const RichTextOptions = text.rich_text.RichTextOptions;
pub const RichTextAlignment = text.rich_text.RichTextAlignment;
pub const Hyphenator = text.hyphenation.Hyphenator;
pub const HyphenationLanguage = text.hyphenation.Language;
pub const LayoutOptions = text.text_layout.LayoutOptions;
pub const layoutTextWithOptions = text.text_layout.layoutTextWithOptions;
pub const freeTextLines = text.text_layout.freeTextLines;

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
    pub const form_filler = @import("form/form_filler.zig");
    pub const fdf = @import("form/fdf.zig");
};
pub const FormBuilder = form.form_builder.FormBuilder;
pub const fillForm = form.form_filler.fillForm;
pub const flattenForm = form.form_filler.flattenForm;
pub const fillAndFlatten = form.form_filler.fillAndFlatten;
pub const FieldValue = form.form_filler.FieldValue;
pub const FlattenOptions = form.form_filler.FlattenOptions;
pub const exportFdf = form.fdf.exportFdf;
pub const exportXfdf = form.fdf.exportXfdf;
pub const importFdf = form.fdf.importFdf;
pub const importXfdf = form.fdf.importXfdf;
pub const parseFdf = form.fdf.parseFdf;
pub const parseXfdf = form.fdf.parseXfdf;

// ── Layout ──────────────────────────────────────────────────────────
pub const layout = struct {
    pub const header_footer = @import("layout/header_footer.zig");
    pub const columns_mod = @import("layout/columns.zig");
    pub const lists = @import("layout/lists.zig");
    pub const page_template_mod = @import("layout/page_template.zig");
};
pub const HeaderFooter = layout.header_footer.HeaderFooter;
pub const HFElement = layout.header_footer.HFElement;
pub const HFContent = layout.header_footer.HFContent;
pub const HFPosition = layout.header_footer.HFPosition;
pub const ColumnLayout = layout.columns_mod.ColumnLayout;
pub const ColumnContent = layout.columns_mod.ColumnContent;
pub const TextContent = layout.columns_mod.TextContent;
pub const RichTextContent = layout.columns_mod.RichTextContent;
pub const columnWidth = layout.columns_mod.columnWidth;
pub const ListStyle = layout.lists.ListStyle;
pub const ListItem = layout.lists.ListItem;
pub const ListOptions = layout.lists.ListOptions;
pub const drawList = layout.lists.drawList;
pub const PageTemplate = layout.page_template_mod.PageTemplate;
pub const TemplateElement = layout.page_template_mod.TemplateElement;
pub const Margins = layout.page_template_mod.Margins;
pub const ContentArea = layout.page_template_mod.ContentArea;

// ── Writer ───────────────────────────────────────────────────────────
pub const writer = struct {
    pub const pdf_writer = @import("writer/pdf_writer.zig");
    pub const object_serializer = @import("writer/object_serializer.zig");
    pub const xref_writer = @import("writer/xref_writer.zig");
    pub const stream_writer = @import("writer/stream_writer.zig");
    pub const linearizer = @import("writer/linearizer.zig");
};
pub const countingWriter = writer.stream_writer.countingWriter;
pub const CountingWriter = writer.stream_writer.CountingWriter;
pub const linearizePdf = writer.linearizer.linearizePdf;
pub const isLinearized = writer.linearizer.isLinearized;
pub const LinearizationOptions = writer.linearizer.LinearizationOptions;

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
    pub const ean8 = @import("barcode/ean8.zig");
    pub const upca = @import("barcode/upca.zig");
    pub const qr_code = @import("barcode/qr/qr_code.zig");
    pub const data_matrix = @import("barcode/data_matrix.zig");
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
    pub const stamper = @import("modify/stamper.zig");
    pub const incremental = @import("modify/incremental.zig");
    pub const redaction = @import("modify/redaction.zig");
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

// ── PDF/A (Archival Conformance) ────────────────────────────────────
pub const pdfa = @import("pdfa/pdfa.zig");
pub const PdfAConformanceLevel = pdfa.ConformanceLevel;
pub const PdfAOptions = pdfa.PdfAOptions;
pub const PdfAValidationResult = pdfa.ValidationResult;


// ── Generators ──────────────────────────────────────────────────────
pub const generators = struct {
    pub const mail_merge = @import("generators/mail_merge.zig");
    pub const report = @import("generators/report.zig");
    pub const invoice = @import("generators/invoice.zig");
};
pub const MailMerge = generators.mail_merge.MailMerge;
pub const MergeField = generators.mail_merge.MergeField;
pub const MergeRecord = generators.mail_merge.MergeRecord;
pub const MergeOptions = generators.mail_merge.MergeOptions;
pub const mergeWithBuilder = generators.mail_merge.mergeWithBuilder;
pub const replacePlaceholders = generators.mail_merge.replacePlaceholders;
pub const Report = generators.report.Report;
pub const ReportOptions = generators.report.ReportOptions;
pub const ReportSection = generators.report.ReportSection;
pub const Invoice = generators.invoice.Invoice;
pub const InvoiceItem = generators.invoice.InvoiceItem;
pub const CompanyInfo = generators.invoice.CompanyInfo;
pub const InvoiceOptions = generators.invoice.InvoiceOptions;
pub const InvoiceColors = generators.invoice.InvoiceColors;

// ── Parser ───────────────────────────────────────────────────────────
pub const parser = struct {
    pub const pdf_parser = @import("parser/pdf_parser.zig");
    pub const tokenizer = @import("parser/tokenizer.zig");
    pub const text_extractor = @import("parser/text_extractor.zig");
    pub const validator = @import("parser/validator.zig");
};
pub const parsePdf = parser.pdf_parser.parsePdf;
pub const ExtractedText = parser.text_extractor.ExtractedText;
pub const ExtractionOptions = parser.text_extractor.ExtractionOptions;
pub const validatePdf = parser.validator.validatePdf;
pub const ValidationResult = parser.validator.ValidationResult;
pub const ValidationOptions = parser.validator.ValidationOptions;
pub const ValidationIssue = parser.validator.ValidationIssue;
pub const Severity = parser.validator.Severity;
pub const IssueCode = parser.validator.IssueCode;

test {
    std.testing.refAllDeclsRecursive(@This());
}
