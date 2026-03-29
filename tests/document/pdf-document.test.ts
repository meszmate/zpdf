import { describe, it, expect } from 'vitest';
import { PDFDocument } from '../../src/document/pdf-document.js';

describe('PDFDocument', () => {
  it('creates an empty document', () => {
    const doc = PDFDocument.create();
    expect(doc.getPageCount()).toBe(0);
  });

  it('creates a document with options', () => {
    const doc = PDFDocument.create({
      title: 'Test',
      author: 'Author',
    });
    expect(doc.getTitle()).toBe('Test');
    expect(doc.getAuthor()).toBe('Author');
  });

  it('adds pages', () => {
    const doc = PDFDocument.create();
    const page = doc.addPage();
    expect(doc.getPageCount()).toBe(1);
    expect(page).toBeDefined();
  });

  it('gets page by index', () => {
    const doc = PDFDocument.create();
    const page = doc.addPage();
    expect(doc.getPage(0)).toBe(page);
  });

  it('throws on invalid page index', () => {
    const doc = PDFDocument.create();
    expect(() => doc.getPage(0)).toThrow('out of bounds');
    expect(() => doc.getPage(-1)).toThrow('out of bounds');
  });

  it('removes a page', () => {
    const doc = PDFDocument.create();
    doc.addPage();
    doc.addPage();
    expect(doc.getPageCount()).toBe(2);
    doc.removePage(0);
    expect(doc.getPageCount()).toBe(1);
  });

  it('inserts a page at index', () => {
    const doc = PDFDocument.create();
    doc.addPage();
    doc.addPage();
    const inserted = doc.insertPage(1);
    expect(doc.getPageCount()).toBe(3);
    expect(doc.getPage(1)).toBe(inserted);
  });

  it('throws on invalid insert index', () => {
    const doc = PDFDocument.create();
    expect(() => doc.insertPage(5)).toThrow('out of bounds');
  });

  describe('metadata', () => {
    it('sets and gets title', () => {
      const doc = PDFDocument.create();
      doc.setTitle('My PDF');
      expect(doc.getTitle()).toBe('My PDF');
    });

    it('sets and gets author', () => {
      const doc = PDFDocument.create();
      doc.setAuthor('John');
      expect(doc.getAuthor()).toBe('John');
    });

    it('sets and gets subject', () => {
      const doc = PDFDocument.create();
      doc.setSubject('Test Subject');
      expect(doc.getSubject()).toBe('Test Subject');
    });

    it('sets and gets keywords', () => {
      const doc = PDFDocument.create();
      doc.setKeywords(['pdf', 'test']);
      expect(doc.getKeywords()).toEqual(['pdf', 'test']);
    });
  });

  describe('page options', () => {
    it('default page size is A4', () => {
      const doc = PDFDocument.create();
      const page = doc.addPage();
      const size = page.getSize();
      expect(size.width).toBeCloseTo(595.28, 0);
      expect(size.height).toBeCloseTo(841.89, 0);
    });

    it('supports letter size', () => {
      const doc = PDFDocument.create();
      const page = doc.addPage({ size: 'Letter' });
      const size = page.getSize();
      expect(size.width).toBe(612);
      expect(size.height).toBe(792);
    });

    it('supports landscape orientation', () => {
      const doc = PDFDocument.create();
      const page = doc.addPage({ size: 'A4', orientation: 'landscape' });
      const size = page.getSize();
      expect(size.width).toBeGreaterThan(size.height);
    });

    it('supports custom size', () => {
      const doc = PDFDocument.create();
      const page = doc.addPage({ size: [300, 400] });
      const size = page.getSize();
      expect(size.width).toBe(300);
      expect(size.height).toBe(400);
    });
  });

  describe('save', () => {
    it('saves an empty document', async () => {
      const doc = PDFDocument.create();
      doc.addPage();
      const bytes = await doc.save();
      expect(bytes).toBeInstanceOf(Uint8Array);
      expect(bytes.length).toBeGreaterThan(0);

      const text = new TextDecoder().decode(bytes);
      expect(text).toContain('%PDF-');
      expect(text).toContain('%%EOF');
    });

    it('saves with metadata', async () => {
      const doc = PDFDocument.create();
      doc.setTitle('Test PDF');
      doc.setAuthor('Test Author');
      doc.addPage();
      const bytes = await doc.save();
      const text = new TextDecoder().decode(bytes);
      expect(text).toContain('Test PDF');
      expect(text).toContain('Test Author');
    });

    it('saves with multiple pages', async () => {
      const doc = PDFDocument.create();
      doc.addPage();
      doc.addPage();
      doc.addPage();
      const bytes = await doc.save();
      const text = new TextDecoder().decode(bytes);
      expect(text).toContain('/Count 3');
    });

    it('respects version option', async () => {
      const doc = PDFDocument.create();
      doc.addPage();
      const bytes = await doc.save({ version: '2.0' });
      const text = new TextDecoder().decode(bytes.subarray(0, 20));
      expect(text).toContain('%PDF-2.0');
    });

    it('saves with compression option', async () => {
      const doc = PDFDocument.create();
      const page = doc.addPage();
      const font = doc.getStandardFont('Helvetica');
      page.drawText('Hello World', { x: 50, y: 700, font, fontSize: 12 });

      const uncompressed = await doc.save({ compress: false });
      const compressed = await doc.save({ compress: true });

      // Both should be valid PDFs
      expect(new TextDecoder().decode(uncompressed)).toContain('%PDF-');
      expect(new TextDecoder().decode(compressed)).toContain('%PDF-');
    });
  });

  describe('fonts', () => {
    it('gets a standard font', () => {
      const doc = PDFDocument.create();
      const font = doc.getStandardFont('Helvetica');
      expect(font).toBeDefined();
      expect(font.name).toBe('Helvetica');
      expect(font.ref).toBeDefined();
    });

    it('caches standard fonts', () => {
      const doc = PDFDocument.create();
      const f1 = doc.getStandardFont('Helvetica');
      const f2 = doc.getStandardFont('Helvetica');
      expect(f1).toBe(f2);
    });

    it('provides different font objects for different names', () => {
      const doc = PDFDocument.create();
      const f1 = doc.getStandardFont('Helvetica');
      const f2 = doc.getStandardFont('Courier');
      expect(f1).not.toBe(f2);
    });
  });

  describe('bookmarks', () => {
    it('adds a bookmark', () => {
      const doc = PDFDocument.create();
      doc.addPage();
      const bm = doc.addBookmark('Chapter 1', 0);
      expect(bm.title).toBe('Chapter 1');
      expect(bm.pageIndex).toBe(0);
      expect(bm.children).toEqual([]);
    });

    it('adds nested bookmarks', () => {
      const doc = PDFDocument.create();
      doc.addPage();
      const parent = doc.addBookmark('Parent', 0);
      const child = doc.addBookmark('Child', 0, { parent });
      expect(parent.children.length).toBe(1);
      expect(parent.children[0]).toBe(child);
    });

    it('saves document with bookmarks', async () => {
      const doc = PDFDocument.create();
      doc.addPage();
      doc.addBookmark('Test Bookmark', 0);
      const bytes = await doc.save();
      const text = new TextDecoder().decode(bytes);
      expect(text).toContain('/Outlines');
      expect(text).toContain('Test Bookmark');
    });
  });
});
