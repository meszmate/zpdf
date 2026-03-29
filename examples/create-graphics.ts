/**
 * create-graphics.ts
 *
 * Demonstrates vector graphics capabilities of zpdf:
 *  - Lines with different widths, colors, and dash patterns
 *  - Rectangles (filled, stroked, rounded corners)
 *  - Circles and ellipses
 *  - Polygons (triangle, pentagon, star)
 *  - Custom paths with PathBuilder (curves, arcs)
 *  - Transformations (rotate, scale)
 *  - Opacity / transparency
 *  - Clipping paths
 */

import { writeFileSync } from 'node:fs';
import {
  PDFDocument,
  rgb,
  hexColor,
  grayscale,
  cmyk,
} from '../src/index';

async function main() {
  const doc = PDFDocument.create();
  doc.setTitle('zpdf Graphics Example');

  const helvetica = doc.getStandardFont('Helvetica');
  const helveticaBold = doc.getStandardFont('Helvetica-Bold');

  // Helper to draw a section heading
  function sectionTitle(page: ReturnType<typeof doc.addPage>, text: string, y: number) {
    page.drawText(text, {
      x: 40,
      y,
      font: helveticaBold,
      fontSize: 16,
      color: rgb(0, 51, 153),
    });
  }

  // Helper to draw a small caption
  function caption(page: ReturnType<typeof doc.addPage>, text: string, x: number, y: number) {
    page.drawText(text, {
      x,
      y,
      font: helvetica,
      fontSize: 9,
      color: grayscale(0.4),
      alignment: 'center',
    });
  }

  // =================================================================
  // PAGE 1: Lines and Rectangles
  // =================================================================
  const page1 = doc.addPage({ size: 'A4' });
  const { width: w, height: h } = page1.getSize();

  sectionTitle(page1, 'Lines', h - 50);

  // Solid line
  page1.drawLine({ x1: 40, y1: h - 80, x2: 250, y2: h - 80, color: rgb(0, 0, 0), lineWidth: 1 });
  caption(page1, 'Solid, 1pt', 145, h - 92);

  // Thick line
  page1.drawLine({ x1: 40, y1: h - 110, x2: 250, y2: h - 110, color: rgb(200, 0, 0), lineWidth: 3 });
  caption(page1, 'Solid, 3pt, Red', 145, h - 124);

  // Dashed line
  page1.drawLine({
    x1: 40, y1: h - 145, x2: 250, y2: h - 145,
    color: rgb(0, 100, 0),
    lineWidth: 2,
    dashPattern: { array: [8, 4], phase: 0 },
  });
  caption(page1, 'Dashed [8,4]', 145, h - 158);

  // Dotted line
  page1.drawLine({
    x1: 40, y1: h - 180, x2: 250, y2: h - 180,
    color: rgb(0, 0, 200),
    lineWidth: 2,
    dashPattern: { array: [2, 4], phase: 0 },
  });
  caption(page1, 'Dotted [2,4]', 145, h - 193);

  // Dash-dot pattern
  page1.drawLine({
    x1: 40, y1: h - 215, x2: 250, y2: h - 215,
    color: hexColor('#FF6600'),
    lineWidth: 2,
    dashPattern: { array: [10, 3, 2, 3], phase: 0 },
  });
  caption(page1, 'Dash-dot [10,3,2,3]', 145, h - 228);

  // Semi-transparent line
  page1.drawLine({
    x1: 40, y1: h - 250, x2: 250, y2: h - 250,
    color: rgb(150, 0, 150),
    lineWidth: 4,
    opacity: 0.4,
  });
  caption(page1, '4pt, 40% opacity', 145, h - 266);

  // -- Rectangles --
  sectionTitle(page1, 'Rectangles', h - 300);

  // Filled rectangle
  page1.drawRect({
    x: 40, y: h - 400, width: 100, height: 70,
    color: rgb(70, 130, 180),
  });
  caption(page1, 'Filled', 90, h - 415);

  // Stroked rectangle
  page1.drawRect({
    x: 160, y: h - 400, width: 100, height: 70,
    borderColor: rgb(200, 0, 0),
    borderWidth: 2,
  });
  caption(page1, 'Stroked', 210, h - 415);

  // Filled + stroked
  page1.drawRect({
    x: 280, y: h - 400, width: 100, height: 70,
    color: rgb(255, 228, 181),
    borderColor: rgb(210, 105, 30),
    borderWidth: 2,
  });
  caption(page1, 'Fill + Stroke', 330, h - 415);

  // Rounded corners
  page1.drawRect({
    x: 400, y: h - 400, width: 100, height: 70,
    color: rgb(152, 251, 152),
    borderColor: rgb(34, 139, 34),
    borderWidth: 1.5,
    borderRadius: 12,
  });
  caption(page1, 'Rounded r=12', 450, h - 415);

  // Semi-transparent rectangle
  page1.drawRect({
    x: 40, y: h - 500, width: 100, height: 70,
    color: rgb(128, 0, 128),
    opacity: 0.3,
  });
  caption(page1, '30% opacity', 90, h - 515);

  // Dashed border rectangle
  page1.drawRect({
    x: 160, y: h - 500, width: 100, height: 70,
    borderColor: rgb(0, 0, 0),
    borderWidth: 1,
    dashPattern: { array: [5, 3], phase: 0 },
  });
  caption(page1, 'Dashed border', 210, h - 515);

  // CMYK colored rectangle
  page1.drawRect({
    x: 280, y: h - 500, width: 100, height: 70,
    color: cmyk(100, 0, 0, 0),
  });
  caption(page1, 'CMYK cyan', 330, h - 515);

  // =================================================================
  // PAGE 2: Circles, Ellipses, and Polygons
  // =================================================================
  const page2 = doc.addPage({ size: 'A4' });
  const { height: h2 } = page2.getSize();

  sectionTitle(page2, 'Circles', h2 - 50);

  // Filled circle
  page2.drawCircle({
    cx: 100, cy: h2 - 130, radius: 40,
    color: rgb(100, 149, 237),
  });
  caption(page2, 'Filled', 100, h2 - 185);

  // Stroked circle
  page2.drawCircle({
    cx: 220, cy: h2 - 130, radius: 40,
    borderColor: rgb(220, 20, 60),
    borderWidth: 2,
  });
  caption(page2, 'Stroked', 220, h2 - 185);

  // Filled + stroked with opacity
  page2.drawCircle({
    cx: 340, cy: h2 - 130, radius: 40,
    color: rgb(255, 215, 0),
    borderColor: rgb(184, 134, 11),
    borderWidth: 2,
    opacity: 0.6,
  });
  caption(page2, 'Fill+Stroke, 60%', 340, h2 - 185);

  // Overlapping circles to show transparency
  page2.drawCircle({ cx: 460, cy: h2 - 115, radius: 30, color: rgb(255, 0, 0), opacity: 0.4 });
  page2.drawCircle({ cx: 490, cy: h2 - 115, radius: 30, color: rgb(0, 255, 0), opacity: 0.4 });
  page2.drawCircle({ cx: 475, cy: h2 - 140, radius: 30, color: rgb(0, 0, 255), opacity: 0.4 });
  caption(page2, 'Overlapping RGB', 475, h2 - 185);

  // -- Ellipses --
  sectionTitle(page2, 'Ellipses', h2 - 210);

  page2.drawEllipse({
    cx: 120, cy: h2 - 280, rx: 70, ry: 35,
    color: rgb(176, 196, 222),
    borderColor: rgb(70, 130, 180),
    borderWidth: 1.5,
  });
  caption(page2, 'rx=70, ry=35', 120, h2 - 325);

  page2.drawEllipse({
    cx: 300, cy: h2 - 280, rx: 30, ry: 55,
    color: rgb(255, 182, 193),
    borderColor: rgb(199, 21, 133),
    borderWidth: 1.5,
  });
  caption(page2, 'rx=30, ry=55', 300, h2 - 345);

  // -- Polygons --
  sectionTitle(page2, 'Polygons', h2 - 370);

  // Triangle
  page2.drawPolygon({
    points: [
      { x: 80, y: h2 - 400 },
      { x: 140, y: h2 - 480 },
      { x: 20, y: h2 - 480 },
    ],
    color: rgb(255, 99, 71),
    borderColor: rgb(139, 0, 0),
    borderWidth: 1.5,
    closePath: true,
  });
  caption(page2, 'Triangle', 80, h2 - 498);

  // Pentagon
  const pentPoints = [];
  for (let i = 0; i < 5; i++) {
    const angle = (i * 2 * Math.PI) / 5 - Math.PI / 2;
    pentPoints.push({
      x: 230 + 45 * Math.cos(angle),
      y: h2 - 440 + 45 * Math.sin(angle),
    });
  }
  page2.drawPolygon({
    points: pentPoints,
    color: rgb(60, 179, 113),
    borderColor: rgb(0, 100, 0),
    borderWidth: 1.5,
    closePath: true,
  });
  caption(page2, 'Pentagon', 230, h2 - 498);

  // Star (5-pointed)
  const starPoints = [];
  for (let i = 0; i < 10; i++) {
    const angle = (i * Math.PI) / 5 - Math.PI / 2;
    const r = i % 2 === 0 ? 45 : 20;
    starPoints.push({
      x: 380 + r * Math.cos(angle),
      y: h2 - 440 + r * Math.sin(angle),
    });
  }
  page2.drawPolygon({
    points: starPoints,
    color: rgb(255, 215, 0),
    borderColor: rgb(184, 134, 11),
    borderWidth: 1,
    closePath: true,
  });
  caption(page2, 'Star', 380, h2 - 498);

  // Hexagon
  const hexPoints = [];
  for (let i = 0; i < 6; i++) {
    const angle = (i * Math.PI) / 3;
    hexPoints.push({
      x: 500 + 40 * Math.cos(angle),
      y: h2 - 440 + 40 * Math.sin(angle),
    });
  }
  page2.drawPolygon({
    points: hexPoints,
    color: rgb(147, 112, 219),
    borderColor: rgb(75, 0, 130),
    borderWidth: 1.5,
    closePath: true,
  });
  caption(page2, 'Hexagon', 500, h2 - 498);

  // =================================================================
  // PAGE 3: PathBuilder, Transformations, and Clipping
  // =================================================================
  const page3 = doc.addPage({ size: 'A4' });
  const { width: w3, height: h3 } = page3.getSize();

  sectionTitle(page3, 'Custom Paths (PathBuilder)', h3 - 50);

  // Heart shape using cubic bezier curves
  page3.drawPath(
    (path) => {
      const cx = 120;
      const cy = h3 - 140;
      path.moveTo(cx, cy - 20);
      // Left half of heart
      path.curveTo(cx - 50, cy + 20, cx - 50, cy + 50, cx, cy + 30);
      // Right half of heart
      path.curveTo(cx + 50, cy + 50, cx + 50, cy + 20, cx, cy - 20);
    },
    {
      color: rgb(220, 20, 60),
      borderColor: rgb(139, 0, 0),
      borderWidth: 1,
    },
  );
  caption(page3, 'Heart (Bezier)', 120, h3 - 185);

  // Rounded rectangle via PathBuilder
  page3.drawPath(
    (path) => {
      path.roundRect(240, h3 - 170, 120, 60, 15);
    },
    {
      color: rgb(135, 206, 250),
      borderColor: rgb(0, 0, 139),
      borderWidth: 1.5,
    },
  );
  caption(page3, 'roundRect()', 300, h3 - 185);

  // Arc path
  page3.drawPath(
    (path) => {
      path.arc(470, h3 - 130, 40, 0, Math.PI * 1.5);
      path.closePath();
    },
    {
      color: rgb(255, 165, 0),
      borderColor: rgb(139, 69, 19),
      borderWidth: 1.5,
    },
  );
  caption(page3, 'Arc (270 degrees)', 470, h3 - 185);

  // -- Transformations --
  sectionTitle(page3, 'Transformations', h3 - 220);

  // Rotated rectangle using pushState / setTransform / popState
  const rotCenterX = 120;
  const rotCenterY = h3 - 310;
  page3.pushState();
  // Translate to rotation center, rotate 30 degrees, translate back
  const angleRad = (30 * Math.PI) / 180;
  const cos30 = Math.cos(angleRad);
  const sin30 = Math.sin(angleRad);
  page3.setTransform([cos30, sin30, -sin30, cos30, rotCenterX, rotCenterY]);
  page3.drawRect({
    x: -40, y: -25,
    width: 80, height: 50,
    color: rgb(255, 160, 122),
    borderColor: rgb(178, 34, 34),
    borderWidth: 1,
  });
  page3.popState();
  caption(page3, 'Rotated 30 deg', rotCenterX, h3 - 360);

  // Scaled shapes
  const scaleX = 300;
  const scaleY = h3 - 310;
  page3.pushState();
  page3.setTransform([1.5, 0, 0, 0.75, scaleX, scaleY]);
  page3.drawCircle({
    cx: 0, cy: 0, radius: 30,
    color: rgb(152, 251, 152),
    borderColor: rgb(0, 128, 0),
    borderWidth: 1,
  });
  page3.popState();
  caption(page3, 'Scaled (1.5x, 0.75y)', scaleX, h3 - 360);

  // -- Clipping --
  sectionTitle(page3, 'Clipping Paths', h3 - 400);

  // Draw colorful content clipped to a circle
  page3.pushState();
  page3.setClipPath((path) => {
    path.circle(120, h3 - 500, 50);
  });
  // Draw several overlapping rectangles -- only the parts inside the circle are visible
  page3.drawRect({ x: 70, y: h3 - 550, width: 50, height: 100, color: rgb(255, 0, 0) });
  page3.drawRect({ x: 95, y: h3 - 550, width: 50, height: 100, color: rgb(0, 200, 0) });
  page3.drawRect({ x: 120, y: h3 - 550, width: 50, height: 100, color: rgb(0, 0, 255) });
  page3.popState();
  caption(page3, 'Circle clip', 120, h3 - 560);

  // Rectangular clip
  page3.pushState();
  page3.setClipRect(250, h3 - 540, 120, 80);
  // Draw a large circle that overflows the clip region
  page3.drawCircle({
    cx: 310, cy: h3 - 500, radius: 80,
    color: rgb(218, 112, 214),
  });
  page3.popState();
  caption(page3, 'Rect clip', 310, h3 - 560);

  // =================================================================
  // PAGE 4: Opacity showcase
  // =================================================================
  const page4 = doc.addPage({ size: 'A4' });
  const { width: w4, height: h4 } = page4.getSize();

  sectionTitle(page4, 'Opacity / Transparency', h4 - 50);

  // Draw a series of overlapping squares with decreasing opacity
  const opacities = [1.0, 0.8, 0.6, 0.4, 0.2];
  for (let i = 0; i < opacities.length; i++) {
    page4.drawRect({
      x: 40 + i * 50,
      y: h4 - 180 + i * 10,
      width: 80,
      height: 80,
      color: rgb(0, 100, 200),
      opacity: opacities[i],
    });
    caption(page4, `${Math.round(opacities[i] * 100)}%`, 80 + i * 50, h4 - 200);
  }

  // Gradient-like effect using thin semi-transparent rectangles
  sectionTitle(page4, 'Gradient Effect (via thin rects)', h4 - 240);
  const gradientWidth = w4 - 80;
  const steps = 60;
  const stepWidth = gradientWidth / steps;
  for (let i = 0; i < steps; i++) {
    const t = i / (steps - 1);
    // Transition from blue to red
    page4.drawRect({
      x: 40 + i * stepWidth,
      y: h4 - 310,
      width: stepWidth + 1, // +1 to avoid gaps
      height: 40,
      color: rgb(Math.round(t * 255), 0, Math.round((1 - t) * 255)),
    });
  }
  caption(page4, 'Blue-to-Red gradient simulation', w4 / 2, h4 - 360);

  // ---------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------
  const pdfBytes = await doc.save();
  writeFileSync('output/graphics.pdf', pdfBytes);
  console.log(`Created output/graphics.pdf (${pdfBytes.length} bytes, ${doc.getPageCount()} pages)`);
}

main().catch(console.error);
