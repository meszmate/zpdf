import type { PdfRef, PdfDict, PdfObject } from '../core/types.js';
import type { ObjectStore } from '../core/object-store.js';
import type { Font } from '../font/metrics.js';
import type { Color } from '../color/color.js';
import type { BlendMode } from '../graphics/state.js';
import type { Matrix, Rect } from '../utils/math.js';
import type { TextOptions, RichTextRun, RichTextOptions } from '../text/text-style.js';
import type {
  LineOptions, RectOptions, CircleOptions, EllipseOptions,
  PolygonOptions, PathOptions, ImageDrawOptions, WatermarkOptions,
  ImageRef, PageOptions, Margins,
} from './types.js';
import type { Table } from '../table/table.js';
import type { PathBuilder } from '../graphics/path-builder.js';
import { PageSizes, type PageSizeName } from './page-sizes.js';
import { ResourceManager } from './resource-manager.js';
import { ContentBuilder } from './content-builder.js';
import { layoutTable, type TableLayout } from '../table/table-layout.js';
import { renderTableRows } from '../table/table-renderer.js';
import { pdfName, pdfNum, pdfArray, pdfStream, pdfDict } from '../core/objects.js';
import { createPageNode } from '../core/page-tree.js';

export interface TableDrawOptions {
  x: number;
  y: number;
  width?: number;
  defaultFont: Font;
  defaultFontSize?: number;
}

export class PDFPage {
  private width: number;
  private height: number;
  private rotation: 0 | 90 | 180 | 270 = 0;
  private contentBuilder: ContentBuilder;
  private resourceManager: ResourceManager;
  private margins: Margins;
  private annotations: PdfObject[] = [];

  // Reference to the document for multi-page table support
  private addPageCallback?: (options?: PageOptions) => PDFPage;

  constructor(
    private store: ObjectStore,
    options?: PageOptions,
    addPageCallback?: (options?: PageOptions) => PDFPage,
  ) {
    this.addPageCallback = addPageCallback;
    this.resourceManager = new ResourceManager(store);
    this.contentBuilder = new ContentBuilder(this.resourceManager);

    // Determine page size
    let w: number;
    let h: number;
    if (options?.size) {
      if (Array.isArray(options.size)) {
        [w, h] = options.size;
      } else {
        const sz = PageSizes[options.size as PageSizeName];
        [w, h] = sz;
      }
    } else {
      [w, h] = PageSizes.A4;
    }

    // Handle orientation
    if (options?.orientation === 'landscape') {
      if (w < h) {
        [w, h] = [h, w];
      }
    } else if (options?.orientation === 'portrait') {
      if (w > h) {
        [w, h] = [h, w];
      }
    }

    this.width = w;
    this.height = h;
    this.margins = options?.margins ?? {};
  }

  getSize(): { width: number; height: number } {
    return { width: this.width, height: this.height };
  }

  setSize(width: number, height: number): void {
    this.width = width;
    this.height = height;
  }

  setRotation(degrees: 0 | 90 | 180 | 270): void {
    this.rotation = degrees;
  }

  getRotation(): number {
    return this.rotation;
  }

  getMargins(): Margins {
    return this.margins;
  }

  getContentBuilder(): ContentBuilder {
    return this.contentBuilder;
  }

  getResourceManager(): ResourceManager {
    return this.resourceManager;
  }

  // --- Drawing methods ---

  drawText(text: string, options: TextOptions): void {
    this.contentBuilder.drawText(text, options);
  }

  drawRichText(runs: RichTextRun[], options: RichTextOptions, defaultFont: Font, defaultFontSize: number): void {
    this.contentBuilder.drawRichText(runs, options, defaultFont, defaultFontSize);
  }

  drawLine(options: LineOptions): void {
    this.contentBuilder.drawLine(options);
  }

  drawRect(options: RectOptions): void {
    this.contentBuilder.drawRect(options);
  }

  drawCircle(options: CircleOptions): void {
    this.contentBuilder.drawCircle(options);
  }

  drawEllipse(options: EllipseOptions): void {
    this.contentBuilder.drawEllipse(options);
  }

  drawPolygon(options: PolygonOptions): void {
    this.contentBuilder.drawPolygon(options);
  }

  drawPath(builder: (path: PathBuilder) => void, options: PathOptions): void {
    this.contentBuilder.drawPath(builder, options);
  }

  drawImage(image: ImageRef, options: ImageDrawOptions): void {
    this.contentBuilder.drawImage(image, options);
  }

  drawTable(table: Table, options: TableDrawOptions): { pagesUsed: number } {
    const defaultFont = options.defaultFont;
    const defaultFontSize = options.defaultFontSize ?? 10;
    const tableWidth = options.width ?? (this.width - (this.margins.left ?? 0) - (this.margins.right ?? 0));
    const marginTop = this.margins.top ?? 0;
    const marginBottom = this.margins.bottom ?? 0;
    const availableHeight = this.height - marginTop - marginBottom;

    // Compute full table layout
    const layout = layoutTable(
      table,
      options.x,
      options.y,
      tableWidth,
      availableHeight,
      defaultFont,
      defaultFontSize,
    );

    const headerRows = layout.headerRows;
    const headerHeight = layout.headerHeight;
    const bodyRows = layout.rows.slice(headerRows.length);

    if (layout.pageBreaks.length === 0) {
      // Entire table fits on one page
      const operatorStr = renderTableRows(layout.rows, this.resourceManager, defaultFont, defaultFontSize);
      this.contentBuilder.addRaw(operatorStr);
      return { pagesUsed: 1 };
    }

    // Multi-page table
    let pagesUsed = 1;

    // Render first page segment
    const firstPageBodyRows = bodyRows.slice(0, layout.pageBreaks[0]);
    const firstPageRows = [...headerRows, ...firstPageBodyRows];
    const firstPageOps = renderTableRows(firstPageRows, this.resourceManager, defaultFont, defaultFontSize);
    this.contentBuilder.addRaw(firstPageOps);

    // Render subsequent pages
    for (let breakIdx = 0; breakIdx < layout.pageBreaks.length; breakIdx++) {
      const startRow = layout.pageBreaks[breakIdx];
      const endRow = breakIdx + 1 < layout.pageBreaks.length
        ? layout.pageBreaks[breakIdx + 1]
        : bodyRows.length;

      const pageBodyRows = bodyRows.slice(startRow, endRow);
      if (pageBodyRows.length === 0) continue;

      // Create a new page with the same size
      if (!this.addPageCallback) {
        // If no callback, just render on the current page (overflow)
        const overflowOps = renderTableRows(pageBodyRows, this.resourceManager, defaultFont, defaultFontSize);
        this.contentBuilder.addRaw(overflowOps);
        continue;
      }

      const newPage = this.addPageCallback({
        size: [this.width, this.height],
        margins: this.margins,
      });
      pagesUsed++;

      // Reposition rows for the new page
      const newStartY = options.y;
      const repositioned = repositionRows(headerRows, pageBodyRows, newStartY);
      const newResourceManager = newPage.getResourceManager();

      // Re-register fonts used by the table
      // The renderer will register fonts as needed through the new resource manager
      const pageOps = renderTableRows(repositioned, newResourceManager, defaultFont, defaultFontSize);
      newPage.getContentBuilder().addRaw(pageOps);
    }

    return { pagesUsed };
  }

  pushState(): void {
    this.contentBuilder.saveState();
  }

  popState(): void {
    this.contentBuilder.restoreState();
  }

  setTransform(matrix: Matrix): void {
    this.contentBuilder.setTransform(matrix);
  }

  setClipRect(x: number, y: number, w: number, h: number): void {
    this.contentBuilder.setClipRect(x, y, w, h);
  }

  setClipPath(builder: (path: PathBuilder) => void, evenOdd?: boolean): void {
    this.contentBuilder.setClipPath(builder, evenOdd);
  }

  setOpacity(opacity: number): void {
    this.contentBuilder.setOpacity(opacity);
  }

  setBlendMode(mode: BlendMode): void {
    this.contentBuilder.setBlendMode(mode);
  }

  addWatermark(options: WatermarkOptions): void {
    this.contentBuilder.addWatermark(options, this.width, this.height);
  }

  beginLayer(layerName: string): void {
    this.contentBuilder.beginLayer(layerName);
  }

  endLayer(): void {
    this.contentBuilder.endLayer();
  }

  beginTag(tag: string, mcid?: number): void {
    this.contentBuilder.beginTag(tag, mcid);
  }

  endTag(): void {
    this.contentBuilder.endTag();
  }

  addAnnotation(annotation: PdfObject): void {
    this.annotations.push(annotation);
  }

  addLink(rect: { x: number; y: number; width: number; height: number }, target: string | { page: number; x?: number; y?: number }): void {
    const annotEntries: Record<string, PdfObject> = {
      Type: pdfName('Annot'),
      Subtype: pdfName('Link'),
      Rect: pdfArray(
        pdfNum(rect.x),
        pdfNum(rect.y),
        pdfNum(rect.x + rect.width),
        pdfNum(rect.y + rect.height),
      ),
      Border: pdfArray(pdfNum(0), pdfNum(0), pdfNum(0)),
    };

    if (typeof target === 'string') {
      // URI link
      annotEntries['A'] = pdfDict({
        S: pdfName('URI'),
        URI: { type: 'string', value: new TextEncoder().encode(target), encoding: 'literal' as const },
      });
    } else {
      // Internal link - destination will be resolved during save
      annotEntries['Dest'] = pdfArray(
        pdfNum(target.page),
        pdfName('XYZ'),
        pdfNum(target.x ?? 0),
        pdfNum(target.y ?? 0),
        pdfNum(0),
      );
    }

    this.annotations.push(pdfDict(annotEntries));
  }

  /**
   * Build the page object, content stream, and resources.
   * Returns refs for the page and content stream objects.
   */
  _build(store: ObjectStore, pageTreeRef: PdfRef): { pageRef: PdfRef; contentRef: PdfRef } {
    // Build content stream
    const contentStr = this.contentBuilder.toOperatorString();
    const contentBytes = new TextEncoder().encode(contentStr);
    const contentStream = pdfStream(
      { Length: pdfNum(contentBytes.length) },
      contentBytes,
    );
    const contentRef = store.allocRef();
    store.set(contentRef, contentStream);

    // Build resources dict
    const resourceDict = this.resourceManager.buildResourceDict();
    const resourceRef = store.allocRef();
    store.set(resourceRef, resourceDict);

    // Build page dict
    const mediaBox = [0, 0, this.width, this.height];
    const pageDict = createPageNode(pageTreeRef, mediaBox, resourceRef, contentRef);

    // Add rotation if set
    if (this.rotation !== 0) {
      (pageDict as any).entries.set('Rotate', pdfNum(this.rotation));
    }

    // Add annotations if any
    if (this.annotations.length > 0) {
      const annotRefs: PdfRef[] = [];
      for (const annot of this.annotations) {
        const annotRef = store.allocRef();
        store.set(annotRef, annot);
        annotRefs.push(annotRef);
      }
      (pageDict as any).entries.set('Annots', pdfArray(...annotRefs));
    }

    const pageRef = store.allocRef();
    store.set(pageRef, pageDict);

    return { pageRef, contentRef };
  }
}

/**
 * Reposition header and body rows for a new page, adjusting y coordinates.
 */
function repositionRows(
  headerRows: import('../table/table-layout.js').LayoutRow[],
  bodyRows: import('../table/table-layout.js').LayoutRow[],
  startY: number,
): import('../table/table-layout.js').LayoutRow[] {
  const result: import('../table/table-layout.js').LayoutRow[] = [];
  let currentY = startY;

  // Reposition header rows
  for (const row of headerRows) {
    const newCells = row.cells.map(cell => ({
      ...cell,
      y: currentY,
    }));
    result.push({
      cells: newCells,
      y: currentY,
      height: row.height,
    });
    currentY -= row.height;
  }

  // Reposition body rows
  for (const row of bodyRows) {
    const newCells = row.cells.map(cell => ({
      ...cell,
      y: currentY,
    }));
    result.push({
      cells: newCells,
      y: currentY,
      height: row.height,
    });
    currentY -= row.height;
  }

  return result;
}
