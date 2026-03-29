import type { Point } from '../utils/math.js';
import * as ops from './operators.js';

export class PathBuilder {
  private commands: string[] = [];

  moveTo(x: number, y: number): this {
    this.commands.push(ops.moveTo(x, y));
    return this;
  }

  lineTo(x: number, y: number): this {
    this.commands.push(ops.lineTo(x, y));
    return this;
  }

  curveTo(x1: number, y1: number, x2: number, y2: number, x3: number, y3: number): this {
    this.commands.push(ops.curveTo(x1, y1, x2, y2, x3, y3));
    return this;
  }

  quadraticCurveTo(x1: number, y1: number, x2: number, y2: number): this {
    // Convert quadratic bezier to cubic bezier.
    // We need the current point. Track it from previous commands.
    const cp = this.getCurrentPoint();
    const cx0 = cp.x;
    const cy0 = cp.y;
    // Cubic control points from quadratic: CP1 = P0 + 2/3*(P1-P0), CP2 = P2 + 2/3*(P1-P2)
    const cp1x = cx0 + (2 / 3) * (x1 - cx0);
    const cp1y = cy0 + (2 / 3) * (y1 - cy0);
    const cp2x = x2 + (2 / 3) * (x1 - x2);
    const cp2y = y2 + (2 / 3) * (y1 - y2);
    this.commands.push(ops.curveTo(cp1x, cp1y, cp2x, cp2y, x2, y2));
    return this;
  }

  arc(
    cx: number,
    cy: number,
    r: number,
    startAngle: number,
    endAngle: number,
    counterclockwise: boolean = false,
  ): this {
    return this.ellipseArc(cx, cy, r, r, startAngle, endAngle, counterclockwise);
  }

  private ellipseArc(
    cx: number,
    cy: number,
    rx: number,
    ry: number,
    startAngle: number,
    endAngle: number,
    counterclockwise: boolean,
  ): this {
    // Normalize angles
    let sa = startAngle;
    let ea = endAngle;

    if (counterclockwise) {
      // Swap direction: go from start backwards to end
      if (ea >= sa) {
        ea -= Math.PI * 2;
      }
    } else {
      if (ea <= sa) {
        ea += Math.PI * 2;
      }
    }

    const totalAngle = ea - sa;
    // Split into segments of at most PI/2
    const segCount = Math.max(1, Math.ceil(Math.abs(totalAngle) / (Math.PI / 2)));
    const segAngle = totalAngle / segCount;

    // Move to start point
    const startX = cx + rx * Math.cos(sa);
    const startY = cy + ry * Math.sin(sa);

    if (this.commands.length === 0) {
      this.commands.push(ops.moveTo(startX, startY));
    } else {
      this.commands.push(ops.lineTo(startX, startY));
    }

    for (let i = 0; i < segCount; i++) {
      const a1 = sa + i * segAngle;
      const a2 = a1 + segAngle;
      this.arcSegment(cx, cy, rx, ry, a1, a2);
    }

    return this;
  }

  private arcSegment(
    cx: number,
    cy: number,
    rx: number,
    ry: number,
    a1: number,
    a2: number,
  ): void {
    // Approximate a circular/elliptical arc segment (max ~PI/2) with a cubic bezier
    const halfAngle = (a2 - a1) / 2;
    const kappa = (4 / 3) * Math.tan(halfAngle);

    const cos1 = Math.cos(a1);
    const sin1 = Math.sin(a1);
    const cos2 = Math.cos(a2);
    const sin2 = Math.sin(a2);

    const x1 = cx + rx * cos1;
    const y1 = cy + ry * sin1;
    const x4 = cx + rx * cos2;
    const y4 = cy + ry * sin2;

    const cp1x = x1 - kappa * rx * sin1;
    const cp1y = y1 + kappa * ry * cos1;
    const cp2x = x4 + kappa * rx * sin2;
    const cp2y = y4 - kappa * ry * cos2;

    this.commands.push(ops.curveTo(cp1x, cp1y, cp2x, cp2y, x4, y4));
  }

  ellipse(cx: number, cy: number, rx: number, ry: number): this {
    // Draw full ellipse using 4 bezier curves
    // Kappa for quarter circle: 4*(sqrt(2)-1)/3
    const k = 0.5522847498;

    this.commands.push(ops.moveTo(cx + rx, cy));
    this.commands.push(ops.curveTo(cx + rx, cy + ry * k, cx + rx * k, cy + ry, cx, cy + ry));
    this.commands.push(ops.curveTo(cx - rx * k, cy + ry, cx - rx, cy + ry * k, cx - rx, cy));
    this.commands.push(ops.curveTo(cx - rx, cy - ry * k, cx - rx * k, cy - ry, cx, cy - ry));
    this.commands.push(ops.curveTo(cx + rx * k, cy - ry, cx + rx, cy - ry * k, cx + rx, cy));
    this.commands.push(ops.closePath());

    return this;
  }

  circle(cx: number, cy: number, r: number): this {
    return this.ellipse(cx, cy, r, r);
  }

  rect(x: number, y: number, w: number, h: number): this {
    this.commands.push(ops.rect(x, y, w, h));
    return this;
  }

  roundRect(x: number, y: number, w: number, h: number, radius: number): this {
    const r = Math.min(radius, w / 2, h / 2);
    const k = 0.5522847498 * r;

    this.commands.push(ops.moveTo(x + r, y));
    this.commands.push(ops.lineTo(x + w - r, y));
    this.commands.push(ops.curveTo(x + w - r + k, y, x + w, y + r - k, x + w, y + r));
    this.commands.push(ops.lineTo(x + w, y + h - r));
    this.commands.push(ops.curveTo(x + w, y + h - r + k, x + w - r + k, y + h, x + w - r, y + h));
    this.commands.push(ops.lineTo(x + r, y + h));
    this.commands.push(ops.curveTo(x + r - k, y + h, x, y + h - r + k, x, y + h - r));
    this.commands.push(ops.lineTo(x, y + r));
    this.commands.push(ops.curveTo(x, y + r - k, x + r - k, y, x + r, y));
    this.commands.push(ops.closePath());

    return this;
  }

  polygon(points: Point[]): this {
    if (points.length < 2) return this;
    this.commands.push(ops.moveTo(points[0].x, points[0].y));
    for (let i = 1; i < points.length; i++) {
      this.commands.push(ops.lineTo(points[i].x, points[i].y));
    }
    this.commands.push(ops.closePath());
    return this;
  }

  closePath(): this {
    this.commands.push(ops.closePath());
    return this;
  }

  toOperators(): string {
    return this.commands.join('\n');
  }

  private getCurrentPoint(): Point {
    // Parse the last command to get the current point
    for (let i = this.commands.length - 1; i >= 0; i--) {
      const cmd = this.commands[i];
      const parts = cmd.trim().split(/\s+/);
      const op = parts[parts.length - 1];

      if (op === 'm' || op === 'l') {
        return { x: parseFloat(parts[0]), y: parseFloat(parts[1]) };
      }
      if (op === 'c') {
        return { x: parseFloat(parts[4]), y: parseFloat(parts[5]) };
      }
      if (op === 'v') {
        return { x: parseFloat(parts[2]), y: parseFloat(parts[3]) };
      }
      if (op === 'y') {
        return { x: parseFloat(parts[2]), y: parseFloat(parts[3]) };
      }
      if (op === 're') {
        // rect: x y w h re - current point is (x, y)
        return { x: parseFloat(parts[0]), y: parseFloat(parts[1]) };
      }
      if (op === 'h') {
        // closePath - need to find the moveTo
        continue;
      }
    }
    return { x: 0, y: 0 };
  }
}
