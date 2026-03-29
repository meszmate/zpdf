import type { Font } from '../font/metrics.js';
import type { Color } from '../color/color.js';
import type { BlendMode } from '../graphics/state.js';
import type { Matrix } from '../utils/math.js';
import type { TextOptions, RichTextRun, RichTextOptions } from '../text/text-style.js';
import type {
  LineOptions, RectOptions, CircleOptions, EllipseOptions,
  PolygonOptions, PathOptions, ImageDrawOptions, WatermarkOptions, ImageRef,
} from './types.js';
import { ResourceManager } from './resource-manager.js';
import { PathBuilder } from '../graphics/path-builder.js';
import { createExtGState } from '../graphics/state.js';
import { setFillColor, setStrokeColor } from '../color/operators.js';
import { layoutText, layoutRichText } from '../text/text-layout.js';
import * as ops from '../graphics/operators.js';
import { grayscale } from '../color/color.js';

function formatNum(n: number): string {
  const s = n.toFixed(6);
  if (s.indexOf('.') !== -1) {
    let end = s.length;
    while (end > 0 && s[end - 1] === '0') end--;
    if (s[end - 1] === '.') end--;
    return s.slice(0, end);
  }
  return s;
}

function escapeText(text: string): string {
  return text
    .replace(/\\/g, '\\\\')
    .replace(/\(/g, '\\(')
    .replace(/\)/g, '\\)');
}

export class ContentBuilder {
  private operators: string[] = [];
  private resourceManager: ResourceManager;

  constructor(resourceManager: ResourceManager) {
    this.resourceManager = resourceManager;
  }

  addRaw(operator: string): void {
    this.operators.push(operator);
  }

  saveState(): void {
    this.operators.push(ops.saveState());
  }

  restoreState(): void {
    this.operators.push(ops.restoreState());
  }

  setTransform(matrix: Matrix): void {
    this.operators.push(ops.concatMatrix(matrix));
  }

  setOpacity(fillOpacity: number, strokeOpacity?: number): void {
    const gsDict = createExtGState({
      fillOpacity,
      strokeOpacity: strokeOpacity ?? fillOpacity,
    });
    const gsName = this.resourceManager.registerExtGState(gsDict);
    this.operators.push(ops.setExtGState(gsName));
  }

  setBlendMode(mode: BlendMode): void {
    const gsDict = createExtGState({ blendMode: mode });
    const gsName = this.resourceManager.registerExtGState(gsDict);
    this.operators.push(ops.setExtGState(gsName));
  }

  drawLine(options: LineOptions): void {
    this.operators.push(ops.saveState());

    if (options.opacity !== undefined) {
      this.setOpacity(options.opacity);
    }
    if (options.lineWidth !== undefined) {
      this.operators.push(ops.setLineWidth(options.lineWidth));
    }
    if (options.dashPattern) {
      this.operators.push(ops.setDashPattern(options.dashPattern.array, options.dashPattern.phase));
    }
    if (options.color) {
      this.operators.push(setStrokeColor(options.color));
    }

    this.operators.push(ops.moveTo(options.x1, options.y1));
    this.operators.push(ops.lineTo(options.x2, options.y2));
    this.operators.push(ops.stroke());
    this.operators.push(ops.restoreState());
  }

  drawRect(options: RectOptions): void {
    this.operators.push(ops.saveState());

    if (options.opacity !== undefined) {
      this.setOpacity(options.opacity);
    }

    const hasFill = options.color !== undefined;
    const hasStroke = options.borderColor !== undefined;

    if (options.borderWidth !== undefined) {
      this.operators.push(ops.setLineWidth(options.borderWidth));
    }
    if (options.dashPattern) {
      this.operators.push(ops.setDashPattern(options.dashPattern.array, options.dashPattern.phase));
    }
    if (options.color) {
      this.operators.push(setFillColor(options.color));
    }
    if (options.borderColor) {
      this.operators.push(setStrokeColor(options.borderColor));
    }

    if (options.borderRadius && options.borderRadius > 0) {
      const pb = new PathBuilder();
      pb.roundRect(options.x, options.y, options.width, options.height, options.borderRadius);
      this.operators.push(pb.toOperators());
    } else {
      this.operators.push(ops.rect(options.x, options.y, options.width, options.height));
    }

    if (hasFill && hasStroke) {
      this.operators.push(ops.fillAndStroke());
    } else if (hasFill) {
      this.operators.push(ops.fill());
    } else if (hasStroke) {
      this.operators.push(ops.stroke());
    } else {
      // Default: fill with black if no color specified, just draw path
      this.operators.push(ops.fill());
    }

    this.operators.push(ops.restoreState());
  }

  drawCircle(options: CircleOptions): void {
    this.operators.push(ops.saveState());

    if (options.opacity !== undefined) {
      this.setOpacity(options.opacity);
    }

    const hasFill = options.color !== undefined;
    const hasStroke = options.borderColor !== undefined;

    if (options.borderWidth !== undefined) {
      this.operators.push(ops.setLineWidth(options.borderWidth));
    }
    if (options.color) {
      this.operators.push(setFillColor(options.color));
    }
    if (options.borderColor) {
      this.operators.push(setStrokeColor(options.borderColor));
    }

    const pb = new PathBuilder();
    pb.circle(options.cx, options.cy, options.radius);
    this.operators.push(pb.toOperators());

    if (hasFill && hasStroke) {
      this.operators.push(ops.fillAndStroke());
    } else if (hasFill) {
      this.operators.push(ops.fill());
    } else if (hasStroke) {
      this.operators.push(ops.stroke());
    } else {
      this.operators.push(ops.fill());
    }

    this.operators.push(ops.restoreState());
  }

  drawEllipse(options: EllipseOptions): void {
    this.operators.push(ops.saveState());

    if (options.opacity !== undefined) {
      this.setOpacity(options.opacity);
    }

    const hasFill = options.color !== undefined;
    const hasStroke = options.borderColor !== undefined;

    if (options.borderWidth !== undefined) {
      this.operators.push(ops.setLineWidth(options.borderWidth));
    }
    if (options.color) {
      this.operators.push(setFillColor(options.color));
    }
    if (options.borderColor) {
      this.operators.push(setStrokeColor(options.borderColor));
    }

    const pb = new PathBuilder();
    pb.ellipse(options.cx, options.cy, options.rx, options.ry);
    this.operators.push(pb.toOperators());

    if (hasFill && hasStroke) {
      this.operators.push(ops.fillAndStroke());
    } else if (hasFill) {
      this.operators.push(ops.fill());
    } else if (hasStroke) {
      this.operators.push(ops.stroke());
    } else {
      this.operators.push(ops.fill());
    }

    this.operators.push(ops.restoreState());
  }

  drawPolygon(options: PolygonOptions): void {
    if (options.points.length < 2) return;

    this.operators.push(ops.saveState());

    if (options.opacity !== undefined) {
      this.setOpacity(options.opacity);
    }

    const hasFill = options.color !== undefined;
    const hasStroke = options.borderColor !== undefined;

    if (options.borderWidth !== undefined) {
      this.operators.push(ops.setLineWidth(options.borderWidth));
    }
    if (options.color) {
      this.operators.push(setFillColor(options.color));
    }
    if (options.borderColor) {
      this.operators.push(setStrokeColor(options.borderColor));
    }

    this.operators.push(ops.moveTo(options.points[0].x, options.points[0].y));
    for (let i = 1; i < options.points.length; i++) {
      this.operators.push(ops.lineTo(options.points[i].x, options.points[i].y));
    }
    if (options.closePath !== false) {
      this.operators.push(ops.closePath());
    }

    if (hasFill && hasStroke) {
      this.operators.push(ops.fillAndStroke());
    } else if (hasFill) {
      this.operators.push(ops.fill());
    } else if (hasStroke) {
      this.operators.push(ops.stroke());
    } else {
      this.operators.push(ops.stroke());
    }

    this.operators.push(ops.restoreState());
  }

  drawPath(builder: (path: PathBuilder) => void, options: PathOptions): void {
    this.operators.push(ops.saveState());

    if (options.opacity !== undefined) {
      this.setOpacity(options.opacity);
    }

    const hasFill = options.color !== undefined;
    const hasStroke = options.borderColor !== undefined;

    if (options.borderWidth !== undefined) {
      this.operators.push(ops.setLineWidth(options.borderWidth));
    }
    if (options.color) {
      this.operators.push(setFillColor(options.color));
    }
    if (options.borderColor) {
      this.operators.push(setStrokeColor(options.borderColor));
    }

    const pb = new PathBuilder();
    builder(pb);
    this.operators.push(pb.toOperators());

    if (hasFill && hasStroke) {
      if (options.evenOdd) {
        this.operators.push('B*');
      } else {
        this.operators.push(ops.fillAndStroke());
      }
    } else if (hasFill) {
      this.operators.push(options.evenOdd ? ops.fillEvenOdd() : ops.fill());
    } else if (hasStroke) {
      this.operators.push(ops.stroke());
    } else {
      this.operators.push(ops.fill());
    }

    this.operators.push(ops.restoreState());
  }

  drawText(text: string, options: TextOptions): void {
    const fontName = this.resourceManager.registerFont(options.font);
    const layout = layoutText(text, options, options.maxWidth, options.maxLines);

    this.operators.push(ops.saveState());

    if (options.color) {
      this.operators.push(setFillColor(options.color));
    }

    this.operators.push(ops.beginText());
    this.operators.push(ops.setFont(fontName, options.fontSize));

    if (options.letterSpacing !== undefined && options.letterSpacing !== 0) {
      this.operators.push(ops.setCharSpacing(options.letterSpacing));
    }
    if (options.wordSpacing !== undefined && options.wordSpacing !== 0) {
      this.operators.push(ops.setWordSpacing(options.wordSpacing));
    }

    for (let i = 0; i < layout.lines.length; i++) {
      const line = layout.lines[i];
      const tx = options.x + line.x;
      const ty = options.y + line.y;

      this.operators.push(ops.moveText(tx, ty));
      this.operators.push(`(${escapeText(line.text)}) Tj`);

      // Draw underline
      if (options.underline) {
        this.operators.push(ops.endText());
        const descent = options.font.metrics.descent * options.fontSize / options.font.metrics.unitsPerEm;
        const lineY = ty + descent * 0.5;
        this.operators.push(ops.setLineWidth(options.fontSize * 0.05));
        if (options.color) {
          this.operators.push(setStrokeColor(options.color));
        }
        this.operators.push(ops.moveTo(tx, lineY));
        this.operators.push(ops.lineTo(tx + line.width, lineY));
        this.operators.push(ops.stroke());
        this.operators.push(ops.beginText());
        this.operators.push(ops.setFont(fontName, options.fontSize));
      }

      // Draw strikethrough
      if (options.strikethrough) {
        this.operators.push(ops.endText());
        const xHeight = options.font.metrics.xHeight * options.fontSize / options.font.metrics.unitsPerEm;
        const lineY = ty + xHeight * 0.5;
        this.operators.push(ops.setLineWidth(options.fontSize * 0.05));
        if (options.color) {
          this.operators.push(setStrokeColor(options.color));
        }
        this.operators.push(ops.moveTo(tx, lineY));
        this.operators.push(ops.lineTo(tx + line.width, lineY));
        this.operators.push(ops.stroke());
        this.operators.push(ops.beginText());
        this.operators.push(ops.setFont(fontName, options.fontSize));
      }
    }

    this.operators.push(ops.endText());
    this.operators.push(ops.restoreState());
  }

  drawRichText(runs: RichTextRun[], options: RichTextOptions, defaultFont: Font, defaultFontSize: number): void {
    const layout = layoutRichText(runs, options, defaultFont, defaultFontSize);

    this.operators.push(ops.saveState());

    for (const line of layout.lines) {
      for (const run of line.runs) {
        const font = run.font;
        const fontName = this.resourceManager.registerFont(font);

        this.operators.push(ops.beginText());
        this.operators.push(ops.setFont(fontName, run.fontSize));

        if (run.color) {
          this.operators.push(setFillColor(run.color));
        }

        const tx = options.x + line.x + run.x;
        const ty = options.y + line.y;
        this.operators.push(ops.moveText(tx, ty));
        this.operators.push(`(${escapeText(run.text)}) Tj`);
        this.operators.push(ops.endText());

        // Draw underline
        if (run.underline) {
          const descent = font.metrics.descent * run.fontSize / font.metrics.unitsPerEm;
          const lineY = ty + descent * 0.5;
          this.operators.push(ops.setLineWidth(run.fontSize * 0.05));
          if (run.color) {
            this.operators.push(setStrokeColor(run.color));
          }
          this.operators.push(ops.moveTo(tx, lineY));
          this.operators.push(ops.lineTo(tx + run.width, lineY));
          this.operators.push(ops.stroke());
        }

        // Draw strikethrough
        if (run.strikethrough) {
          const xHeight = font.metrics.xHeight * run.fontSize / font.metrics.unitsPerEm;
          const lineY = ty + xHeight * 0.5;
          this.operators.push(ops.setLineWidth(run.fontSize * 0.05));
          if (run.color) {
            this.operators.push(setStrokeColor(run.color));
          }
          this.operators.push(ops.moveTo(tx, lineY));
          this.operators.push(ops.lineTo(tx + run.width, lineY));
          this.operators.push(ops.stroke());
        }
      }
    }

    this.operators.push(ops.restoreState());
  }

  drawImage(imageRef: ImageRef, options: ImageDrawOptions): void {
    const imgName = this.resourceManager.registerImage(imageRef.ref);

    this.operators.push(ops.saveState());

    if (options.opacity !== undefined) {
      this.setOpacity(options.opacity);
    }

    // Calculate display dimensions
    let drawWidth = options.width ?? imageRef.width;
    let drawHeight = options.height ?? imageRef.height;

    // If only one dimension given, maintain aspect ratio
    if (options.width !== undefined && options.height === undefined) {
      drawHeight = (imageRef.height / imageRef.width) * options.width;
    } else if (options.height !== undefined && options.width === undefined) {
      drawWidth = (imageRef.width / imageRef.height) * options.height;
    }

    // Image placement: translate to (x, y), then scale
    // PDF images are drawn in a 1x1 unit square, so we scale them
    this.operators.push(ops.concatMatrix([drawWidth, 0, 0, drawHeight, options.x, options.y]));
    this.operators.push(ops.drawXObject(imgName));
    this.operators.push(ops.restoreState());
  }

  addWatermark(options: WatermarkOptions, pageWidth: number, pageHeight: number): void {
    const font = options.font;
    const fontSize = options.fontSize ?? 48;
    const color = options.color ?? grayscale(0.75);
    const opacity = options.opacity ?? 0.3;
    const rotation = options.rotation ?? -45;

    this.operators.push(ops.saveState());
    this.setOpacity(opacity);

    if (font) {
      const fontName = this.resourceManager.registerFont(font);

      // Position at center of page
      const cx = pageWidth / 2;
      const cy = pageHeight / 2;

      // Calculate text width for centering
      const textWidth = font.measureWidth(options.text, fontSize);

      this.operators.push(setFillColor(color));
      this.operators.push(ops.beginText());
      this.operators.push(ops.setFont(fontName, fontSize));

      // Apply rotation around center
      const rad = (rotation * Math.PI) / 180;
      const cos = Math.cos(rad);
      const sin = Math.sin(rad);

      // Text matrix: rotation + translation to center
      const tx = cx - (textWidth / 2) * cos + (fontSize / 2) * sin;
      const ty = cy - (textWidth / 2) * sin - (fontSize / 2) * cos;

      this.operators.push(`${formatNum(cos)} ${formatNum(sin)} ${formatNum(-sin)} ${formatNum(cos)} ${formatNum(tx)} ${formatNum(ty)} Tm`);
      this.operators.push(`(${escapeText(options.text)}) Tj`);
      this.operators.push(ops.endText());
    }

    this.operators.push(ops.restoreState());
  }

  setClipRect(x: number, y: number, w: number, h: number): void {
    this.operators.push(ops.rect(x, y, w, h));
    this.operators.push('W n');
  }

  setClipPath(builder: (path: PathBuilder) => void, evenOdd?: boolean): void {
    const pb = new PathBuilder();
    builder(pb);
    this.operators.push(pb.toOperators());
    this.operators.push(evenOdd ? 'W* n' : 'W n');
  }

  beginLayer(layerName: string): void {
    this.operators.push(`/OC /${layerName} BDC`);
  }

  endLayer(): void {
    this.operators.push('EMC');
  }

  beginTag(tag: string, mcid?: number): void {
    if (mcid !== undefined) {
      this.operators.push(`/${tag} <</MCID ${mcid}>> BDC`);
    } else {
      this.operators.push(`/${tag} BMC`);
    }
  }

  endTag(): void {
    this.operators.push('EMC');
  }

  toOperatorString(): string {
    return this.operators.join('\n');
  }

  getResourceManager(): ResourceManager {
    return this.resourceManager;
  }
}
