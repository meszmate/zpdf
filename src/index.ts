/**
 * zpdf - A pure TypeScript PDF library.
 *
 * Main barrel export file exposing the public API.
 */

// ============================================================================
// Document
// ============================================================================

export { PDFDocument } from './document/pdf-document.js';
export { PDFPage } from './document/page.js';
export { PageSizes } from './document/page-sizes.js';
export type { PageSizeName, Orientation } from './document/page-sizes.js';
export type {
  DocumentOptions,
  LoadOptions,
  SaveOptions,
  PageOptions,
  Margins,
  LineOptions,
  RectOptions,
  CircleOptions,
  EllipseOptions,
  PolygonOptions,
  PathOptions,
  ImageDrawOptions,
  WatermarkOptions,
  HeaderFooterContext,
  ImageRef,
} from './document/types.js';
export type { TableDrawOptions } from './document/page.js';

// ============================================================================
// Table
// ============================================================================

export { Table } from './table/table.js';
export { TableCell } from './table/cell.js';
export type { TableStyle, CellStyle } from './table/table-style.js';

// ============================================================================
// Font
// ============================================================================

export { FontManager } from './font/font-manager.js';
export type { EmbeddedFont } from './font/font-manager.js';
export { StandardFonts, getStandardFont, STANDARD_FONT_NAMES } from './font/standard-fonts.js';
export type { StandardFontName } from './font/standard-fonts.js';
export type { Font, FontMetrics } from './font/metrics.js';

// ============================================================================
// Color
// ============================================================================

export { rgb, cmyk, grayscale, hexColor } from './color/color.js';
export type { RGB, CMYK, Grayscale, Color } from './color/color.js';
export { NAMED_COLORS } from './color/named-colors.js';
export { rgbToCmyk, cmykToRgb, rgbToGrayscale, grayscaleToRgb } from './color/conversion.js';

// ============================================================================
// Graphics
// ============================================================================

export { PathBuilder } from './graphics/path-builder.js';
export type { BlendMode, GraphicsState } from './graphics/state.js';
export type { Point, Rect, Matrix } from './utils/math.js';

// ============================================================================
// Text
// ============================================================================

export type {
  Alignment,
  TextStyle,
  TextOptions,
  RichTextRun,
  RichTextOptions,
} from './text/text-style.js';

// ============================================================================
// Image
// ============================================================================

export type { EmbeddedImage } from './image/image-embedder.js';

// ============================================================================
// Parser
// ============================================================================

export { parsePdf } from './parser/pdf-parser.js';
export type {
  ParsedDocument,
  ParsedPage,
  OutlineNode,
  FormFieldInfo,
} from './parser/pdf-parser.js';
export type { ExtractedTextItem } from './parser/text-extractor.js';
export type { ExtractedImage } from './parser/image-extractor.js';

// ============================================================================
// Modify (Merge / Split / Watermark)
// ============================================================================

export { PDFMerger } from './modify/merger.js';
export { PDFSplitter } from './modify/splitter.js';
export { addWatermark } from './modify/watermarker.js';
export type { WatermarkConfig } from './modify/watermarker.js';

// ============================================================================
// Outline (Bookmarks)
// ============================================================================

export { OutlineTree } from './outline/outline.js';
export type { OutlineItemOptions } from './outline/outline-item.js';

// ============================================================================
// Layers (Optional Content)
// ============================================================================

export { LayerBuilder } from './layers/layer-builder.js';

// ============================================================================
// Structure (Tagged PDF / Accessibility)
// ============================================================================

export { StructureTree } from './structure/structure-tree.js';
export type { StructureElement } from './structure/structure-tree.js';
export { StructureTags } from './structure/tags.js';
export type { StructureTag } from './structure/tags.js';

// ============================================================================
// Security / Encryption
// ============================================================================

export { SecurityHandler } from './security/security-handler.js';
export type { EncryptionOptions } from './security/encryption-dict.js';
export type { PDFPermissions } from './security/permissions.js';

// ============================================================================
// Form Fields
// ============================================================================

export { FieldFlags } from './form/field-flags.js';
export type {
  TextFieldOptions,
  CheckboxOptions,
  RadioGroupOptions,
  DropdownOptions,
  ListboxOptions,
  ButtonOptions,
  SignatureFieldOptions,
} from './form/form.js';

// ============================================================================
// Annotations
// ============================================================================

export type {
  Annotation,
  AnnotationBase,
  TextAnnotation,
  LinkAnnotation,
  HighlightAnnotation,
  UnderlineAnnotation,
  StrikeoutAnnotation,
  StampAnnotation,
  FreeTextAnnotation,
  InkAnnotation,
} from './annotation/annotation.js';

// ============================================================================
// Barcode
// ============================================================================

export { drawBarcode } from './barcode/barcode.js';
export type { BarcodeType, BarcodeOptions } from './barcode/barcode.js';

// ============================================================================
// Metadata
// ============================================================================

export type { DocumentInfo } from './metadata/info-dict.js';

// ============================================================================
// Core Types (low-level, for advanced usage)
// ============================================================================

export type {
  PdfObject,
  PdfBool,
  PdfNumber,
  PdfString,
  PdfName,
  PdfArray,
  PdfDict,
  PdfStream,
  PdfNull,
  PdfRef,
} from './core/types.js';
