/**
 * Unicode to glyph mapping and CMap generation for PDF text extraction.
 */

/**
 * Generate a ToUnicode CMap stream that maps CID values to Unicode code points.
 * This is required for text extraction from PDFs using embedded fonts.
 *
 * @param mapping - Map of CID values to Unicode code points
 * @returns CMap stream content as a string
 */
export function generateToUnicodeCMap(mapping: Map<number, number>): string {
  // Sort entries by CID
  const entries = Array.from(mapping.entries()).sort((a, b) => a[0] - b[0]);
  if (entries.length === 0) {
    return buildCMapWrapper('', '');
  }

  // Separate into ranges and individual chars
  const ranges: { startCID: number; endCID: number; startUnicode: number }[] = [];
  const singles: { cid: number; unicode: number }[] = [];

  let i = 0;
  while (i < entries.length) {
    const [startCID, startUnicode] = entries[i];

    // Try to find a consecutive range
    let endIdx = i;
    while (
      endIdx + 1 < entries.length &&
      entries[endIdx + 1][0] === entries[endIdx][0] + 1 &&
      entries[endIdx + 1][1] === entries[endIdx][1] + 1
    ) {
      endIdx++;
    }

    if (endIdx > i) {
      // We have a range of at least 2
      ranges.push({
        startCID: startCID,
        endCID: entries[endIdx][0],
        startUnicode: startUnicode,
      });
      i = endIdx + 1;
    } else {
      singles.push({ cid: startCID, unicode: startUnicode });
      i++;
    }
  }

  // Build bfchar and bfrange sections
  let bfcharSections = '';
  let bfrangeSections = '';

  // bfchar: max 100 entries per section
  for (let j = 0; j < singles.length; j += 100) {
    const chunk = singles.slice(j, j + 100);
    bfcharSections += `${chunk.length} beginbfchar\n`;
    for (const { cid, unicode } of chunk) {
      bfcharSections += `<${toHex16(cid)}> <${unicodeToHex(unicode)}>\n`;
    }
    bfcharSections += 'endbfchar\n';
  }

  // bfrange: max 100 entries per section
  for (let j = 0; j < ranges.length; j += 100) {
    const chunk = ranges.slice(j, j + 100);
    bfrangeSections += `${chunk.length} beginbfrange\n`;
    for (const { startCID, endCID, startUnicode } of chunk) {
      bfrangeSections += `<${toHex16(startCID)}> <${toHex16(endCID)}> <${unicodeToHex(startUnicode)}>\n`;
    }
    bfrangeSections += 'endbfrange\n';
  }

  return buildCMapWrapper(bfcharSections, bfrangeSections);
}

function toHex16(n: number): string {
  return n.toString(16).toUpperCase().padStart(4, '0');
}

function unicodeToHex(codePoint: number): string {
  if (codePoint <= 0xFFFF) {
    return codePoint.toString(16).toUpperCase().padStart(4, '0');
  }
  // For supplementary plane characters, encode as surrogate pair
  const hi = Math.floor((codePoint - 0x10000) / 0x400) + 0xD800;
  const lo = ((codePoint - 0x10000) % 0x400) + 0xDC00;
  return hi.toString(16).toUpperCase().padStart(4, '0') +
         lo.toString(16).toUpperCase().padStart(4, '0');
}

function buildCMapWrapper(bfcharSection: string, bfrangeSection: string): string {
  return `/CIDInit /ProcSet findresource begin
12 dict begin
begincmap
/CIDSystemInfo
<< /Registry (Adobe)
/Ordering (UCS)
/Supplement 0
>> def
/CMapName /Adobe-Identity-UCS def
/CMapType 2 def
1 begincodespacerange
<0000> <FFFF>
endcodespacerange
${bfcharSection}${bfrangeSection}endcmap
CMapName currentdict /CMap defineresource pop
end
end`;
}
