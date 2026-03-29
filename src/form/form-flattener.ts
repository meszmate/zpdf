import type { PdfRef, PdfObject, PdfDict, PdfStream, PdfArray } from '../core/types.js';
import type { ObjectStore } from '../core/object-store.js';
import {
  pdfName, pdfNum, pdfStr, pdfDict, pdfArray, pdfStream, pdfNull,
  dictGet, dictGetName, dictGetRef, dictGetArray, isDict, isRef, isArray,
  isStream, isName,
} from '../core/objects.js';

/* ------------------------------------------------------------------ */
/*  flattenForm                                                       */
/* ------------------------------------------------------------------ */

/**
 * Flatten all form fields into page content streams.
 * This merges each field's appearance stream into its page's content,
 * then removes the AcroForm and field annotations.
 */
export function flattenForm(store: ObjectStore, catalogRef: PdfRef): void {
  const catalogObj = store.get(catalogRef);
  if (!catalogObj || catalogObj.type !== 'dict') {
    throw new Error('Catalog not found or not a dictionary');
  }

  const acroFormObj = catalogObj.entries.get('AcroForm');
  if (!acroFormObj) {
    // No form to flatten
    return;
  }

  // Resolve AcroForm (could be ref or inline dict)
  let acroForm: PdfDict;
  if (acroFormObj.type === 'ref') {
    const resolved = store.get(acroFormObj);
    if (!resolved || resolved.type !== 'dict') return;
    acroForm = resolved;
  } else if (acroFormObj.type === 'dict') {
    acroForm = acroFormObj;
  } else {
    return;
  }

  // Collect all field refs
  const fieldRefs = collectAllFieldRefs(store, acroForm);

  // Group fields by page
  const pageFieldMap = new Map<string, { pageRef: PdfRef; fields: PdfRef[] }>();

  for (const fieldRef of fieldRefs) {
    const fieldObj = store.get(fieldRef);
    if (!fieldObj || fieldObj.type !== 'dict') continue;

    const pageRefObj = fieldObj.entries.get('P');
    if (!pageRefObj || pageRefObj.type !== 'ref') continue;

    const key = `${pageRefObj.objectNumber}:${pageRefObj.generation}`;
    if (!pageFieldMap.has(key)) {
      pageFieldMap.set(key, { pageRef: pageRefObj, fields: [] });
    }
    pageFieldMap.get(key)!.fields.push(fieldRef);
  }

  // Process each page
  for (const [, { pageRef, fields }] of pageFieldMap) {
    flattenFieldsOnPage(store, pageRef, fields);
  }

  // Remove AcroForm from catalog
  const newCatalogEntries = new Map(catalogObj.entries);
  newCatalogEntries.delete('AcroForm');
  store.set(catalogRef, pdfDict(Object.fromEntries(newCatalogEntries)));

  // Clean up AcroForm ref
  if (acroFormObj.type === 'ref') {
    store.delete(acroFormObj);
  }
}

/* ------------------------------------------------------------------ */
/*  Collect all field references (recursive for Kids)                 */
/* ------------------------------------------------------------------ */

function collectAllFieldRefs(store: ObjectStore, acroForm: PdfDict): PdfRef[] {
  const fieldsObj = acroForm.entries.get('Fields');
  if (!fieldsObj || fieldsObj.type !== 'array') return [];

  const result: PdfRef[] = [];
  collectFieldRefsRecursive(store, fieldsObj.items, result);
  return result;
}

function collectFieldRefsRecursive(
  store: ObjectStore,
  items: PdfObject[],
  result: PdfRef[],
): void {
  for (const item of items) {
    if (item.type !== 'ref') continue;

    const obj = store.get(item);
    if (!obj || obj.type !== 'dict') continue;

    // Check if this is a terminal field (widget) or has kids
    const kidsObj = obj.entries.get('Kids');
    if (kidsObj && kidsObj.type === 'array') {
      // Non-terminal node: recurse into kids
      collectFieldRefsRecursive(store, kidsObj.items, result);
    }

    // If the field has a Rect (it's a widget annotation), add it
    if (obj.entries.has('Rect')) {
      result.push(item);
    }
  }
}

/* ------------------------------------------------------------------ */
/*  Flatten fields on a single page                                   */
/* ------------------------------------------------------------------ */

function flattenFieldsOnPage(
  store: ObjectStore,
  pageRef: PdfRef,
  fieldRefs: PdfRef[],
): void {
  const pageObj = store.get(pageRef);
  if (!pageObj || pageObj.type !== 'dict') return;

  const pageEntries = new Map(pageObj.entries);

  // Collect appearance stream content for each field
  const extraContent: string[] = [];
  const xObjectEntries = new Map<string, PdfObject>();

  for (let i = 0; i < fieldRefs.length; i++) {
    const fieldRef = fieldRefs[i];
    const fieldObj = store.get(fieldRef);
    if (!fieldObj || fieldObj.type !== 'dict') continue;

    // Get the field's appearance stream
    const apRef = getAppearanceStreamRef(store, fieldObj);
    if (!apRef) continue;

    // Get the field rect for positioning
    const rect = getFieldRect(fieldObj);
    if (!rect) continue;

    // Create an XObject name for this appearance
    const xobjName = `FlatField${i}`;
    xObjectEntries.set(xobjName, apRef);

    // Generate content stream to place the appearance at the field's rect
    const [x1, y1, x2, y2] = rect;
    const width = Math.abs(x2 - x1);
    const height = Math.abs(y2 - y1);
    const x = Math.min(x1, x2);
    const y = Math.min(y1, y2);

    extraContent.push('q');
    extraContent.push(`${width} 0 0 ${height} ${x} ${y} cm`);
    extraContent.push(`/${xobjName} Do`);
    extraContent.push('Q');
  }

  if (extraContent.length === 0) return;

  // Merge XObjects into page resources
  let resources: PdfDict;
  const resourcesObj = pageEntries.get('Resources');
  if (resourcesObj && resourcesObj.type === 'dict') {
    resources = resourcesObj;
  } else if (resourcesObj && resourcesObj.type === 'ref') {
    const resolved = store.get(resourcesObj);
    if (resolved && resolved.type === 'dict') {
      resources = resolved;
    } else {
      resources = pdfDict({});
    }
  } else {
    resources = pdfDict({});
  }

  // Get or create XObject subdictionary
  const existingXObj = resources.entries.get('XObject');
  const xobjDict = new Map<string, PdfObject>();
  if (existingXObj && existingXObj.type === 'dict') {
    for (const [k, v] of existingXObj.entries) {
      xobjDict.set(k, v);
    }
  }
  for (const [k, v] of xObjectEntries) {
    xobjDict.set(k, v);
  }

  const newResourceEntries = new Map(resources.entries);
  newResourceEntries.set('XObject', pdfDict(Object.fromEntries(xobjDict)));
  const newResources = pdfDict(Object.fromEntries(newResourceEntries));

  // If resources was a ref, update in place; otherwise set inline
  if (resourcesObj && resourcesObj.type === 'ref') {
    store.set(resourcesObj, newResources);
  } else {
    pageEntries.set('Resources', newResources);
  }

  // Append extra content to page's content stream
  const extraData = textEncoder(extraContent.join('\n'));
  const extraStreamRef = store.allocRef();
  store.set(extraStreamRef, pdfStream(
    { Length: pdfNum(extraData.length) },
    extraData,
  ));

  // Append to existing Contents
  const existingContents = pageEntries.get('Contents');
  if (existingContents) {
    if (existingContents.type === 'array') {
      const newItems = [...existingContents.items, extraStreamRef];
      pageEntries.set('Contents', pdfArray(...newItems));
    } else if (existingContents.type === 'ref') {
      pageEntries.set('Contents', pdfArray(existingContents, extraStreamRef));
    } else {
      pageEntries.set('Contents', extraStreamRef);
    }
  } else {
    pageEntries.set('Contents', extraStreamRef);
  }

  // Remove field annotations from page's Annots array
  const annotsObj = pageEntries.get('Annots');
  if (annotsObj && annotsObj.type === 'array') {
    const fieldRefSet = new Set(
      fieldRefs.map(r => `${r.objectNumber}:${r.generation}`)
    );
    const filteredAnnots = annotsObj.items.filter(item => {
      if (item.type !== 'ref') return true;
      return !fieldRefSet.has(`${item.objectNumber}:${item.generation}`);
    });
    if (filteredAnnots.length > 0) {
      pageEntries.set('Annots', pdfArray(...filteredAnnots));
    } else {
      pageEntries.delete('Annots');
    }
  }

  // Write updated page
  store.set(pageRef, pdfDict(Object.fromEntries(pageEntries)));

  // Delete field objects
  for (const fieldRef of fieldRefs) {
    store.delete(fieldRef);
  }
}

/* ------------------------------------------------------------------ */
/*  Helpers                                                           */
/* ------------------------------------------------------------------ */

function getAppearanceStreamRef(store: ObjectStore, fieldDict: PdfDict): PdfRef | null {
  const apObj = fieldDict.entries.get('AP');
  if (!apObj || apObj.type !== 'dict') return null;

  // Get the /N (normal) appearance
  const nObj = apObj.entries.get('N');
  if (!nObj) return null;

  if (nObj.type === 'ref') {
    return nObj;
  }

  // If /N is a dict (e.g., checkbox with /Yes and /Off), get the current state
  if (nObj.type === 'dict') {
    const asObj = fieldDict.entries.get('AS');
    const stateName = asObj && asObj.type === 'name' ? asObj.value : 'Yes';
    const stateStream = nObj.entries.get(stateName);
    if (stateStream && stateStream.type === 'ref') {
      return stateStream;
    }
    // Fallback: try 'Off'
    const offStream = nObj.entries.get('Off');
    if (offStream && offStream.type === 'ref') {
      return offStream;
    }
  }

  return null;
}

function getFieldRect(fieldDict: PdfDict): [number, number, number, number] | null {
  const rectObj = fieldDict.entries.get('Rect');
  if (!rectObj || rectObj.type !== 'array' || rectObj.items.length < 4) return null;

  const nums = rectObj.items.map(item =>
    item.type === 'number' ? item.value : 0
  );
  return [nums[0], nums[1], nums[2], nums[3]];
}

function textEncoder(text: string): Uint8Array {
  const bytes: number[] = [];
  for (let i = 0; i < text.length; i++) {
    bytes.push(text.charCodeAt(i) & 0xff);
  }
  return new Uint8Array(bytes);
}
