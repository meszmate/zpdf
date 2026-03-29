import type { PdfRef, PdfObject } from '../core/types.js';
import { ObjectStore } from '../core/object-store.js';
import { pdfDict, pdfName, pdfStr, pdfArray } from '../core/objects.js';

export interface LayerInfo {
  ref: PdfRef;
  name: string;
  visible: boolean;
}

/**
 * Create the /OCProperties dictionary for the document catalog.
 * This defines all optional content groups and their default configuration.
 */
export function createOCProperties(
  store: ObjectStore,
  layers: LayerInfo[],
): PdfRef {
  // /OCGs: array of all OCG refs
  const allRefs: PdfObject[] = layers.map(l => l.ref);

  // /D default configuration
  const onRefs: PdfObject[] = [];
  const offRefs: PdfObject[] = [];
  const orderItems: PdfObject[] = [];

  for (const layer of layers) {
    if (layer.visible) {
      onRefs.push(layer.ref);
    } else {
      offRefs.push(layer.ref);
    }
    orderItems.push(layer.ref);
  }

  const defaultConfig: Record<string, PdfObject> = {
    BaseState: pdfName('ON'),
    Order: pdfArray(...orderItems),
  };

  // Only include /ON if there are visible layers
  if (onRefs.length > 0) {
    defaultConfig['ON'] = pdfArray(...onRefs);
  }

  // Only include /OFF if there are hidden layers
  if (offRefs.length > 0) {
    defaultConfig['OFF'] = pdfArray(...offRefs);
  }

  const ref = store.allocRef();
  store.set(ref, pdfDict({
    OCGs: pdfArray(...allRefs),
    D: pdfDict(defaultConfig),
  }));

  return ref;
}
