/**
 * Remap object references when copying between PDF documents.
 * Handles deep cloning of PdfObject graphs with circular reference detection.
 */

import type { PdfObject, PdfRef, PdfDict, PdfArray, PdfStream } from '../core/types.js';
import { ObjectStore } from '../core/object-store.js';
import { pdfDict, pdfArray, pdfStream, pdfRef } from '../core/objects.js';

export class RefRemapper {
  private mapping: Map<string, PdfRef> = new Map();
  private inProgress: Set<string> = new Set(); // circular reference detection

  constructor(private targetStore: ObjectStore) {}

  /**
   * Get the string key for a ref.
   */
  private refKey(ref: PdfRef): string {
    return `${ref.objectNumber}:${ref.generation}`;
  }

  /**
   * Get or create a mapping for a source ref in the target store.
   */
  getMapping(ref: PdfRef): PdfRef {
    const key = this.refKey(ref);
    let mapped = this.mapping.get(key);
    if (!mapped) {
      mapped = this.targetStore.allocRef();
      this.mapping.set(key, mapped);
    }
    return mapped;
  }

  /**
   * Check if a ref has already been mapped.
   */
  hasMapping(ref: PdfRef): boolean {
    return this.mapping.has(this.refKey(ref));
  }

  /**
   * Deep clone a PdfObject, remapping all PdfRef values to new refs in the target store.
   * Recursively handles dicts, arrays, and streams.
   */
  remapObject(obj: PdfObject, sourceStore: ObjectStore): PdfObject {
    switch (obj.type) {
      case 'ref': {
        // Map to a new ref and copy the referenced object
        return this.copyObjectGraph(obj, sourceStore);
      }
      case 'dict': {
        return this.remapDict(obj, sourceStore);
      }
      case 'array': {
        return this.remapArray(obj, sourceStore);
      }
      case 'stream': {
        return this.remapStream(obj, sourceStore);
      }
      // Primitive types are immutable, return as-is
      case 'bool':
      case 'number':
      case 'string':
      case 'name':
      case 'null':
        return obj;
      default:
        return obj;
    }
  }

  /**
   * Deep clone a PdfDict, remapping all refs inside it.
   */
  private remapDict(dict: PdfDict, sourceStore: ObjectStore): PdfDict {
    const newEntries = new Map<string, PdfObject>();
    for (const [key, value] of dict.entries) {
      newEntries.set(key, this.remapObject(value, sourceStore));
    }
    return { type: 'dict', entries: newEntries };
  }

  /**
   * Deep clone a PdfArray, remapping all refs inside it.
   */
  private remapArray(arr: PdfArray, sourceStore: ObjectStore): PdfArray {
    const newItems = arr.items.map(item => this.remapObject(item, sourceStore));
    return { type: 'array', items: newItems };
  }

  /**
   * Deep clone a PdfStream, remapping refs in the stream dict and copying data.
   */
  private remapStream(stream: PdfStream, sourceStore: ObjectStore): PdfStream {
    const newDict = new Map<string, PdfObject>();
    for (const [key, value] of stream.dict) {
      newDict.set(key, this.remapObject(value, sourceStore));
    }
    // Copy stream data
    const newData = new Uint8Array(stream.data.length);
    newData.set(stream.data);
    return { type: 'stream', dict: newDict, data: newData };
  }

  /**
   * Copy an entire object graph rooted at ref from source to target store.
   * Returns the new ref in the target store.
   */
  copyObjectGraph(ref: PdfRef, sourceStore: ObjectStore): PdfRef {
    const key = this.refKey(ref);

    // Return existing mapping if already processed
    if (this.mapping.has(key)) {
      return this.mapping.get(key)!;
    }

    // Allocate new ref before recursing to handle circular references
    const newRef = this.targetStore.allocRef();
    this.mapping.set(key, newRef);

    // Check for circular reference
    if (this.inProgress.has(key)) {
      return newRef;
    }
    this.inProgress.add(key);

    // Get the source object
    const sourceObj = sourceStore.get(ref);
    if (sourceObj === undefined) {
      // Object not found in source, store a null placeholder
      this.targetStore.set(newRef, { type: 'null' });
      this.inProgress.delete(key);
      return newRef;
    }

    // Deep clone the object, remapping all refs
    const clonedObj = this.remapObjectInner(sourceObj, sourceStore);
    this.targetStore.set(newRef, clonedObj);

    this.inProgress.delete(key);
    return newRef;
  }

  /**
   * Inner remap that handles the object directly (not following refs).
   */
  private remapObjectInner(obj: PdfObject, sourceStore: ObjectStore): PdfObject {
    switch (obj.type) {
      case 'ref':
        return this.copyObjectGraph(obj, sourceStore);
      case 'dict':
        return this.remapDict(obj, sourceStore);
      case 'array':
        return this.remapArray(obj, sourceStore);
      case 'stream':
        return this.remapStream(obj, sourceStore);
      default:
        return obj;
    }
  }
}
