/**
 * create-tables.ts
 *
 * Demonstrates table creation features of zpdf:
 *  - Simple table with headers
 *  - Styled table with colors and fonts
 *  - Column width control (fixed, auto, percentage)
 *  - Cell styling (backgrounds, borders, alignment)
 *  - Alternating row colors
 *  - Multi-line cell content
 *  - Complex data table
 */

import { writeFileSync } from 'node:fs';
import {
  PDFDocument,
  Table,
  TableCell,
  rgb,
  hexColor,
  grayscale,
} from '../src/index';

async function main() {
  const doc = PDFDocument.create();
  doc.setTitle('zpdf Tables Example');

  const helvetica = doc.getStandardFont('Helvetica');
  const helveticaBold = doc.getStandardFont('Helvetica-Bold');
  const courier = doc.getStandardFont('Courier');

  // =================================================================
  // PAGE 1: Simple table
  // =================================================================
  const page1 = doc.addPage({ size: 'A4' });
  const { width: w1, height: h1 } = page1.getSize();

  page1.drawText('Simple Table', {
    x: 40,
    y: h1 - 50,
    font: helveticaBold,
    fontSize: 20,
    color: rgb(0, 0, 0),
  });

  // Create a basic table with default styling
  const simpleTable = new Table({
    borderColor: grayscale(0.3),
    borderWidth: 0.5,
  });

  simpleTable.addHeaderRow(['Name', 'Age', 'City', 'Occupation']);
  simpleTable.addRow(['Alice Johnson', '29', 'New York', 'Engineer']);
  simpleTable.addRow(['Bob Smith', '35', 'London', 'Designer']);
  simpleTable.addRow(['Carol White', '42', 'Tokyo', 'Manager']);
  simpleTable.addRow(['David Brown', '28', 'Berlin', 'Developer']);
  simpleTable.addRow(['Eve Davis', '31', 'Paris', 'Analyst']);

  page1.drawTable(simpleTable, {
    x: 40,
    y: h1 - 80,
    width: w1 - 80,
    defaultFont: helvetica,
    defaultFontSize: 10,
  });

  // =================================================================
  // Styled table with custom colors and fonts
  // =================================================================
  page1.drawText('Styled Table with Custom Colors', {
    x: 40,
    y: h1 - 250,
    font: helveticaBold,
    fontSize: 20,
    color: rgb(0, 0, 0),
  });

  const styledTable = new Table({
    borderColor: rgb(255, 255, 255),
    borderWidth: 1,
    headerStyle: {
      backgroundColor: rgb(0, 51, 102),
      textColor: rgb(255, 255, 255),
      font: helveticaBold,
      fontSize: 11,
      padding: 8,
      alignment: 'center',
    },
    cellStyle: {
      padding: 6,
      fontSize: 10,
      textColor: grayscale(0.1),
    },
    alternateRowColor: rgb(230, 240, 250),
  });

  styledTable.addHeaderRow(['Product', 'Category', 'Price', 'Stock', 'Rating']);
  styledTable.addRow(['Laptop Pro', 'Electronics', '$1,299.00', '45', '4.8/5']);
  styledTable.addRow(['Wireless Mouse', 'Accessories', '$29.99', '320', '4.5/5']);
  styledTable.addRow(['USB-C Hub', 'Accessories', '$49.99', '180', '4.3/5']);
  styledTable.addRow(['Monitor 27"', 'Electronics', '$449.00', '62', '4.7/5']);
  styledTable.addRow(['Keyboard', 'Accessories', '$79.99', '215', '4.6/5']);
  styledTable.addRow(['Webcam HD', 'Electronics', '$69.99', '88', '4.2/5']);

  page1.drawTable(styledTable, {
    x: 40,
    y: h1 - 280,
    width: w1 - 80,
    defaultFont: helvetica,
    defaultFontSize: 10,
  });

  // =================================================================
  // PAGE 2: Column widths and cell alignment
  // =================================================================
  const page2 = doc.addPage({ size: 'A4' });
  const { width: w2, height: h2 } = page2.getSize();

  page2.drawText('Column Width Control', {
    x: 40,
    y: h2 - 50,
    font: helveticaBold,
    fontSize: 20,
    color: rgb(0, 0, 0),
  });

  // Fixed pixel widths
  const fixedWidthTable = new Table({
    borderColor: grayscale(0.5),
    borderWidth: 0.5,
    headerStyle: {
      backgroundColor: rgb(60, 60, 60),
      textColor: rgb(255, 255, 255),
      font: helveticaBold,
      padding: 6,
    },
  });

  // Set explicit column widths in points
  fixedWidthTable.setColumnWidths([80, 200, 100, 'auto']);
  fixedWidthTable.addHeaderRow(['ID', 'Description', 'Status', 'Notes']);
  fixedWidthTable.addRow(['001', 'Initial setup and configuration', 'Complete', 'Done on time']);
  fixedWidthTable.addRow(['002', 'Database migration', 'In Progress', 'ETA: next week']);
  fixedWidthTable.addRow(['003', 'API integration testing', 'Pending', 'Blocked by #002']);

  page2.drawTable(fixedWidthTable, {
    x: 40,
    y: h2 - 80,
    width: w2 - 80,
    defaultFont: helvetica,
    defaultFontSize: 10,
  });

  // =================================================================
  // Cell alignment variations
  // =================================================================
  page2.drawText('Cell Styling and Alignment', {
    x: 40,
    y: h2 - 220,
    font: helveticaBold,
    fontSize: 20,
    color: rgb(0, 0, 0),
  });

  const alignTable = new Table({
    borderColor: grayscale(0.4),
    borderWidth: 0.5,
  });

  alignTable.addHeaderRow([
    new TableCell('Left Aligned', {
      style: { alignment: 'left', backgroundColor: rgb(200, 220, 240), font: helveticaBold, padding: 8 },
    }),
    new TableCell('Center Aligned', {
      style: { alignment: 'center', backgroundColor: rgb(200, 220, 240), font: helveticaBold, padding: 8 },
    }),
    new TableCell('Right Aligned', {
      style: { alignment: 'right', backgroundColor: rgb(200, 220, 240), font: helveticaBold, padding: 8 },
    }),
  ]);

  alignTable.addRow([
    new TableCell('This text is left-aligned.', { style: { alignment: 'left', padding: 8 } }),
    new TableCell('This text is centered.', { style: { alignment: 'center', padding: 8 } }),
    new TableCell('This text is right-aligned.', { style: { alignment: 'right', padding: 8 } }),
  ]);

  alignTable.addRow([
    new TableCell('$1,000.00', { style: { alignment: 'left', padding: 8 } }),
    new TableCell('$2,500.00', { style: { alignment: 'center', padding: 8 } }),
    new TableCell('$3,750.00', { style: { alignment: 'right', padding: 8 } }),
  ]);

  page2.drawTable(alignTable, {
    x: 40,
    y: h2 - 250,
    width: w2 - 80,
    defaultFont: helvetica,
    defaultFontSize: 10,
  });

  // =================================================================
  // Individual cell backgrounds
  // =================================================================
  page2.drawText('Individual Cell Backgrounds', {
    x: 40,
    y: h2 - 400,
    font: helveticaBold,
    fontSize: 20,
    color: rgb(0, 0, 0),
  });

  const colorTable = new Table({
    borderColor: rgb(255, 255, 255),
    borderWidth: 1,
  });

  colorTable.addRow([
    new TableCell('Red Background', {
      style: { backgroundColor: rgb(255, 200, 200), padding: 10, alignment: 'center' },
    }),
    new TableCell('Green Background', {
      style: { backgroundColor: rgb(200, 255, 200), padding: 10, alignment: 'center' },
    }),
    new TableCell('Blue Background', {
      style: { backgroundColor: rgb(200, 200, 255), padding: 10, alignment: 'center' },
    }),
  ]);

  colorTable.addRow([
    new TableCell('Yellow', {
      style: { backgroundColor: rgb(255, 255, 200), padding: 10, alignment: 'center' },
    }),
    new TableCell('Cyan', {
      style: { backgroundColor: rgb(200, 255, 255), padding: 10, alignment: 'center' },
    }),
    new TableCell('Magenta', {
      style: { backgroundColor: rgb(255, 200, 255), padding: 10, alignment: 'center' },
    }),
  ]);

  page2.drawTable(colorTable, {
    x: 40,
    y: h2 - 430,
    width: w2 - 80,
    defaultFont: helvetica,
    defaultFontSize: 11,
  });

  // =================================================================
  // PAGE 3: Multi-line content and complex data table
  // =================================================================
  const page3 = doc.addPage({ size: 'A4' });
  const { width: w3, height: h3 } = page3.getSize();

  page3.drawText('Multi-line Cell Content', {
    x: 40,
    y: h3 - 50,
    font: helveticaBold,
    fontSize: 20,
    color: rgb(0, 0, 0),
  });

  const multiLineTable = new Table({
    borderColor: grayscale(0.4),
    borderWidth: 0.5,
    headerStyle: {
      backgroundColor: hexColor('#2C3E50'),
      textColor: rgb(255, 255, 255),
      font: helveticaBold,
      fontSize: 10,
      padding: 8,
    },
    cellStyle: {
      padding: 8,
      fontSize: 9,
    },
  });

  multiLineTable.setColumnWidths([120, 'auto', 80]);
  multiLineTable.addHeaderRow(['Feature', 'Description', 'Status']);
  multiLineTable.addRow([
    'PDF Creation',
    'Create PDF documents from scratch with\ntext, graphics, images, and tables.\nSupports all 14 standard PDF fonts.',
    'Stable',
  ]);
  multiLineTable.addRow([
    'PDF Parsing',
    'Parse existing PDF files to extract\ntext content, metadata, and structure.',
    'Stable',
  ]);
  multiLineTable.addRow([
    'Forms',
    'Create interactive form fields including\ntext inputs, checkboxes, radio buttons,\ndropdowns, and signature fields.',
    'Beta',
  ]);
  multiLineTable.addRow([
    'Security',
    'Encrypt PDFs with RC4 or AES algorithms.\nSupport for password protection and\npermission control.',
    'Stable',
  ]);

  page3.drawTable(multiLineTable, {
    x: 40,
    y: h3 - 80,
    width: w3 - 80,
    defaultFont: helvetica,
    defaultFontSize: 9,
  });

  // =================================================================
  // Complex data table (financial report style)
  // =================================================================
  page3.drawText('Financial Report Table', {
    x: 40,
    y: h3 - 340,
    font: helveticaBold,
    fontSize: 20,
    color: rgb(0, 0, 0),
  });

  const finTable = new Table({
    borderColor: grayscale(0.6),
    borderWidth: 0.5,
    headerStyle: {
      backgroundColor: rgb(44, 62, 80),
      textColor: rgb(255, 255, 255),
      font: helveticaBold,
      fontSize: 9,
      padding: 6,
      alignment: 'center',
    },
    cellStyle: {
      padding: 5,
      fontSize: 9,
    },
    alternateRowColor: rgb(245, 245, 245),
  });

  finTable.addHeaderRow(['Quarter', 'Revenue', 'Expenses', 'Profit', 'Margin']);

  const financialData = [
    ['Q1 2025', '$2,450,000', '$1,820,000', '$630,000', '25.7%'],
    ['Q2 2025', '$2,780,000', '$1,950,000', '$830,000', '29.9%'],
    ['Q3 2025', '$3,120,000', '$2,100,000', '$1,020,000', '32.7%'],
    ['Q4 2025', '$3,450,000', '$2,280,000', '$1,170,000', '33.9%'],
  ];

  for (const row of financialData) {
    finTable.addRow([
      new TableCell(row[0], { style: { font: helveticaBold, alignment: 'center' } }),
      new TableCell(row[1], { style: { alignment: 'right' } }),
      new TableCell(row[2], { style: { alignment: 'right' } }),
      new TableCell(row[3], {
        style: { alignment: 'right', textColor: rgb(0, 128, 0) },
      }),
      new TableCell(row[4], { style: { alignment: 'center' } }),
    ]);
  }

  // Total row
  finTable.addRow([
    new TableCell('Total', {
      style: { font: helveticaBold, alignment: 'center', backgroundColor: rgb(230, 230, 230) },
    }),
    new TableCell('$11,800,000', {
      style: { font: helveticaBold, alignment: 'right', backgroundColor: rgb(230, 230, 230) },
    }),
    new TableCell('$8,150,000', {
      style: { font: helveticaBold, alignment: 'right', backgroundColor: rgb(230, 230, 230) },
    }),
    new TableCell('$3,650,000', {
      style: {
        font: helveticaBold, alignment: 'right', textColor: rgb(0, 128, 0),
        backgroundColor: rgb(230, 230, 230),
      },
    }),
    new TableCell('30.9%', {
      style: { font: helveticaBold, alignment: 'center', backgroundColor: rgb(230, 230, 230) },
    }),
  ]);

  page3.drawTable(finTable, {
    x: 40,
    y: h3 - 370,
    width: w3 - 80,
    defaultFont: helvetica,
    defaultFontSize: 9,
  });

  // =================================================================
  // Monospaced code table
  // =================================================================
  page3.drawText('Code Listing Table', {
    x: 40,
    y: h3 - 560,
    font: helveticaBold,
    fontSize: 20,
    color: rgb(0, 0, 0),
  });

  const codeTable = new Table({
    borderColor: grayscale(0.6),
    borderWidth: 0.5,
    headerStyle: {
      backgroundColor: rgb(40, 40, 40),
      textColor: rgb(0, 255, 100),
      font: courierBold,
      fontSize: 9,
      padding: 6,
    },
    cellStyle: {
      font: courier,
      fontSize: 8,
      padding: 5,
      backgroundColor: rgb(245, 245, 245),
    },
  });

  const courierBold = doc.getStandardFont('Courier-Bold');

  codeTable.addHeaderRow(['Line', 'Code']);
  codeTable.setColumnWidths([50, 'auto']);
  codeTable.addRow(['1', "import { PDFDocument } from 'zpdf';"]);
  codeTable.addRow(['2', '']);
  codeTable.addRow(['3', 'const doc = PDFDocument.create();']);
  codeTable.addRow(['4', "const page = doc.addPage({ size: 'A4' });"]);
  codeTable.addRow(['5', 'const bytes = await doc.save();']);

  page3.drawTable(codeTable, {
    x: 40,
    y: h3 - 590,
    width: w3 - 80,
    defaultFont: courier,
    defaultFontSize: 8,
  });

  // ---------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------
  const pdfBytes = await doc.save();
  writeFileSync('output/tables.pdf', pdfBytes);
  console.log(`Created output/tables.pdf (${pdfBytes.length} bytes, ${doc.getPageCount()} pages)`);
}

main().catch(console.error);
