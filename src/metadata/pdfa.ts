import type { PdfRef, PdfDict, PdfObject } from '../core/types.js';
import { ObjectStore } from '../core/object-store.js';
import {
  pdfDict, pdfName, pdfStr, pdfArray, pdfNum, pdfBool, pdfStream,
} from '../core/objects.js';
import type { DocumentInfo } from './info-dict.js';
import { createXMPMetadata, embedXMPMetadata } from './xmp.js';

type PDFALevel = '1b' | '1a' | '2b' | '2a' | '2u' | '3b' | '3a' | '3u';

/**
 * Add PDF/A compliance elements to a PDF catalog.
 *
 * 1. Creates and embeds XMP metadata with PDF/A identification
 * 2. Adds /Metadata ref to catalog
 * 3. Creates an output intent for sRGB color space
 * 4. Adds /MarkInfo <<Marked true>> for 'a' conformance levels
 */
export function addPDFACompliance(
  store: ObjectStore,
  catalogRef: PdfRef,
  level: PDFALevel,
  info: DocumentInfo,
): void {
  const partNum = level[0]; // '1', '2', or '3'
  const conformance = level[1] as 'a' | 'b' | 'u'; // 'a', 'b', or 'u'

  // 1. Create XMP metadata with PDF/A identification
  const xmp = createXMPMetadataWithPart(info, parseInt(partNum, 10), conformance);
  const metadataRef = embedXMPMetadata(store, xmp);

  // 2 & 3. Get catalog, add metadata and output intent
  const catalog = store.get(catalogRef);
  if (!catalog || catalog.type !== 'dict') {
    throw new Error('Catalog not found or is not a dict');
  }

  const newEntries = new Map(catalog.entries);

  // Add /Metadata
  newEntries.set('Metadata', metadataRef);

  // Create sRGB output intent
  const outputIntentRef = createSRGBOutputIntent(store);
  newEntries.set('OutputIntents', pdfArray(outputIntentRef));

  // 4. Add /MarkInfo for 'a' conformance levels
  if (conformance === 'a') {
    newEntries.set('MarkInfo', pdfDict({ Marked: pdfBool(true) }));
  }

  store.set(catalogRef, { type: 'dict', entries: newEntries });
}

/**
 * Create XMP with specific part number for PDF/A.
 */
function createXMPMetadataWithPart(info: DocumentInfo, part: number, conformance: 'a' | 'b' | 'u'): string {
  const parts: string[] = [];

  parts.push('<?xpacket begin="\uFEFF" id="W5M0MpCehiHzreSzNTczkc9d"?>');
  parts.push('<x:xmpmeta xmlns:x="adobe:ns:meta/">');
  parts.push('<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">');
  parts.push('<rdf:Description rdf:about=""');
  parts.push('  xmlns:dc="http://purl.org/dc/elements/1.1/"');
  parts.push('  xmlns:xmp="http://ns.adobe.com/xap/1.0/"');
  parts.push('  xmlns:pdf="http://ns.adobe.com/pdf/1.3/"');
  parts.push('  xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/"');
  parts.push('>');

  const esc = (s: string) => s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');

  if (info.title) {
    parts.push(`<dc:title><rdf:Alt><rdf:li xml:lang="x-default">${esc(info.title)}</rdf:li></rdf:Alt></dc:title>`);
  }
  if (info.author) {
    parts.push(`<dc:creator><rdf:Seq><rdf:li>${esc(info.author)}</rdf:li></rdf:Seq></dc:creator>`);
  }
  if (info.subject) {
    parts.push(`<dc:description><rdf:Alt><rdf:li xml:lang="x-default">${esc(info.subject)}</rdf:li></rdf:Alt></dc:description>`);
  }
  if (info.keywords && info.keywords.length > 0) {
    parts.push('<dc:subject><rdf:Bag>');
    for (const kw of info.keywords) parts.push(`<rdf:li>${esc(kw)}</rdf:li>`);
    parts.push('</rdf:Bag></dc:subject>');
  }
  if (info.creationDate) {
    parts.push(`<xmp:CreateDate>${info.creationDate.toISOString()}</xmp:CreateDate>`);
  }
  if (info.modDate) {
    parts.push(`<xmp:ModifyDate>${info.modDate.toISOString()}</xmp:ModifyDate>`);
  }
  if (info.creator) {
    parts.push(`<xmp:CreatorTool>${esc(info.creator)}</xmp:CreatorTool>`);
  }
  if (info.producer) {
    parts.push(`<pdf:Producer>${esc(info.producer)}</pdf:Producer>`);
  }

  parts.push(`<pdfaid:part>${part}</pdfaid:part>`);
  parts.push(`<pdfaid:conformance>${conformance.toUpperCase()}</pdfaid:conformance>`);

  parts.push('</rdf:Description>');
  parts.push('</rdf:RDF>');
  parts.push('</x:xmpmeta>');

  // Padding for in-place editing
  for (let i = 0; i < 20; i++) {
    parts.push('                                                                                ');
  }
  parts.push('<?xpacket end="w"?>');

  return parts.join('\n');
}

/**
 * Create an sRGB output intent for PDF/A compliance.
 */
function createSRGBOutputIntent(store: ObjectStore): PdfRef {
  // Create a minimal sRGB ICC profile placeholder
  // A real implementation would embed the full sRGB ICC profile.
  // We create a minimal valid output intent dict.
  const destProfileRef = store.allocRef();

  // Minimal sRGB ICC profile header (128 bytes header + minimal tags)
  // This is a simplified profile - real PDF/A validators may require a full sRGB profile
  const profileData = createMinimalSRGBProfile();
  store.set(destProfileRef, pdfStream(
    {
      N: pdfNum(3),
    },
    profileData,
  ));

  const intentRef = store.allocRef();
  store.set(intentRef, pdfDict({
    Type: pdfName('OutputIntent'),
    S: pdfName('GTS_PDFA1'),
    OutputConditionIdentifier: pdfStr('sRGB IEC61966-2.1'),
    RegistryName: pdfStr('http://www.color.org'),
    Info: pdfStr('sRGB IEC61966-2.1'),
    DestOutputProfile: destProfileRef,
  }));

  return intentRef;
}

/**
 * Create a minimal sRGB ICC profile.
 * This generates a valid (though minimal) ICC profile header.
 */
function createMinimalSRGBProfile(): Uint8Array {
  // ICC profile structure:
  // 128-byte header + tag table + tag data
  const headerSize = 128;
  const tagCount = 3; // required minimum tags: desc, wtpt, cprt
  const tagTableSize = 4 + tagCount * 12; // count(4) + entries(12 each)

  const descData = encodeMLUC('sRGB IEC61966-2.1');
  const wtptData = encodeXYZ(0.9505, 1.0, 1.0890); // D65 white point
  const cprtData = encodeMLUC('Public Domain');

  // Calculate offsets
  const dataStart = headerSize + tagTableSize;
  const descOffset = dataStart;
  const wtptOffset = descOffset + descData.length;
  const cprtOffset = wtptOffset + wtptData.length;
  const totalSize = cprtOffset + cprtData.length;

  const profile = new Uint8Array(totalSize);
  const view = new DataView(profile.buffer);

  // === HEADER (128 bytes) ===
  view.setUint32(0, totalSize); // Profile size
  // Preferred CMM type (4 bytes) - zero
  profile.set([0x73, 0x63, 0x6E, 0x72], 12); // Device class: 'scnr' (input)
  profile.set([0x52, 0x47, 0x42, 0x20], 16); // Color space: 'RGB '
  profile.set([0x58, 0x59, 0x5A, 0x20], 20); // PCS: 'XYZ '
  // Version 2.1.0
  view.setUint8(8, 2); // major
  view.setUint8(9, 0x10); // minor.bugfix
  // Date/time (12 bytes at offset 24): 2000-01-01
  view.setUint16(24, 2000); // year
  view.setUint16(26, 1); // month
  view.setUint16(28, 1); // day
  // Profile signature 'acsp' at offset 36
  profile.set([0x61, 0x63, 0x73, 0x70], 36);
  // Primary platform: 'APPL' at offset 40
  profile.set([0x41, 0x50, 0x50, 0x4C], 40);
  // Illuminant D65 at offset 68 (XYZ): X=0.9642, Y=1.0, Z=0.8249 in s15Fixed16
  view.setInt32(68, Math.round(0.9642 * 65536));
  view.setInt32(72, Math.round(1.0 * 65536));
  view.setInt32(76, Math.round(0.8249 * 65536));

  // === TAG TABLE ===
  const tagTableStart = headerSize;
  view.setUint32(tagTableStart, tagCount);

  // desc tag
  profile.set([0x64, 0x65, 0x73, 0x63], tagTableStart + 4); // 'desc'
  view.setUint32(tagTableStart + 8, descOffset);
  view.setUint32(tagTableStart + 12, descData.length);

  // wtpt tag
  profile.set([0x77, 0x74, 0x70, 0x74], tagTableStart + 16); // 'wtpt'
  view.setUint32(tagTableStart + 20, wtptOffset);
  view.setUint32(tagTableStart + 24, wtptData.length);

  // cprt tag
  profile.set([0x63, 0x70, 0x72, 0x74], tagTableStart + 28); // 'cprt'
  view.setUint32(tagTableStart + 32, cprtOffset);
  view.setUint32(tagTableStart + 36, cprtData.length);

  // === TAG DATA ===
  profile.set(descData, descOffset);
  profile.set(wtptData, wtptOffset);
  profile.set(cprtData, cprtOffset);

  return profile;
}

function encodeMLUC(text: string): Uint8Array {
  // 'desc' type for ICC v2: textDescriptionType
  const ascii = new TextEncoder().encode(text);
  // 'desc' signature(4) + reserved(4) + ASCII count(4) + ASCII data + null
  const size = 12 + ascii.length + 1;
  // Pad to 4-byte alignment
  const padded = Math.ceil(size / 4) * 4;
  const data = new Uint8Array(padded);
  const view = new DataView(data.buffer);
  // Type signature: 'desc'
  data.set([0x64, 0x65, 0x73, 0x63], 0);
  // Reserved: 0
  view.setUint32(8, ascii.length + 1); // ASCII description length (including null)
  data.set(ascii, 12);
  // Null terminator is already zero
  return data;
}

function encodeXYZ(x: number, y: number, z: number): Uint8Array {
  // XYZType: signature(4) + reserved(4) + XYZ values (3 * s15Fixed16)
  const data = new Uint8Array(20);
  const view = new DataView(data.buffer);
  // Type signature: 'XYZ '
  data.set([0x58, 0x59, 0x5A, 0x20], 0);
  // Reserved: 0
  view.setInt32(8, Math.round(x * 65536));
  view.setInt32(12, Math.round(y * 65536));
  view.setInt32(16, Math.round(z * 65536));
  return data;
}
