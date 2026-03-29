/**
 * PDF permission flags (Table 22 in PDF 1.7 spec).
 *
 * Permission bits (1-indexed):
 * Bit 3:  Print
 * Bit 4:  Modify contents
 * Bit 5:  Copy/extract text and graphics
 * Bit 6:  Add or modify annotations, fill forms
 * Bit 9:  Fill forms only (even if bit 6 is clear)
 * Bit 10: Extract for accessibility
 * Bit 11: Assemble (insert, rotate, delete pages, bookmarks)
 * Bit 12: High-quality print
 *
 * Bits 1-2, 7-8 must be 0. Bits 13-32 must be 1.
 */

export interface PDFPermissions {
  printing?: boolean | 'lowResolution';
  modifying?: boolean;
  copying?: boolean;
  annotating?: boolean;
  fillingForms?: boolean;
  contentAccessibility?: boolean;
  assembling?: boolean;
}

// Bits 13-32 set, bits 7-8 set (reserved must be 1 per spec for rev 2 and 3)
const RESERVED_HIGH = 0xfffff000;
const RESERVED_LOW  = 0x000000c0;
const BASE_FLAGS    = (RESERVED_HIGH | RESERVED_LOW) >>> 0;

export function permissionsToFlags(perms: PDFPermissions): number {
  let flags = BASE_FLAGS;

  // Default: if not specified, permission is granted
  const printing = perms.printing !== undefined ? perms.printing : true;
  const modifying = perms.modifying !== undefined ? perms.modifying : true;
  const copying = perms.copying !== undefined ? perms.copying : true;
  const annotating = perms.annotating !== undefined ? perms.annotating : true;
  const fillingForms = perms.fillingForms !== undefined ? perms.fillingForms : true;
  const contentAccessibility = perms.contentAccessibility !== undefined ? perms.contentAccessibility : true;
  const assembling = perms.assembling !== undefined ? perms.assembling : true;

  // Bit 3 (value 4): Print
  if (printing === true || printing === 'lowResolution') {
    flags |= (1 << 2);
  }

  // Bit 4 (value 8): Modify
  if (modifying) {
    flags |= (1 << 3);
  }

  // Bit 5 (value 16): Copy/extract
  if (copying) {
    flags |= (1 << 4);
  }

  // Bit 6 (value 32): Annotate
  if (annotating) {
    flags |= (1 << 5);
  }

  // Bit 9 (value 256): Fill forms
  if (fillingForms) {
    flags |= (1 << 8);
  }

  // Bit 10 (value 512): Content accessibility
  if (contentAccessibility) {
    flags |= (1 << 9);
  }

  // Bit 11 (value 1024): Assemble
  if (assembling) {
    flags |= (1 << 10);
  }

  // Bit 12 (value 2048): High-quality print
  if (printing === true) {
    flags |= (1 << 11);
  }

  return flags | 0; // Convert to signed 32-bit integer as PDF spec expects
}

export function flagsToPermissions(flags: number): PDFPermissions {
  const perms: PDFPermissions = {};

  const canPrint = !!(flags & (1 << 2));
  const highQualityPrint = !!(flags & (1 << 11));

  if (!canPrint) {
    perms.printing = false;
  } else if (!highQualityPrint) {
    perms.printing = 'lowResolution';
  } else {
    perms.printing = true;
  }

  perms.modifying = !!(flags & (1 << 3));
  perms.copying = !!(flags & (1 << 4));
  perms.annotating = !!(flags & (1 << 5));
  perms.fillingForms = !!(flags & (1 << 8));
  perms.contentAccessibility = !!(flags & (1 << 9));
  perms.assembling = !!(flags & (1 << 10));

  return perms;
}
