import type { PdfRef, PdfDict, PdfObject } from '../core/types.js';
import type { ObjectStore } from '../core/object-store.js';
import type { Font } from '../font/metrics.js';
import { pdfDict, pdfName, pdfRef } from '../core/objects.js';

type ResourceType = 'font' | 'image' | 'extgstate' | 'pattern' | 'shading' | 'xobject';

interface ResourceEntry {
  name: string;
  ref: PdfRef;
}

export class ResourceManager {
  private fonts: Map<string, ResourceEntry> = new Map();
  private images: Map<string, ResourceEntry> = new Map();
  private extGStates: Map<string, ResourceEntry> = new Map();
  private patterns: Map<string, ResourceEntry> = new Map();
  private shadings: Map<string, ResourceEntry> = new Map();
  private xobjects: Map<string, ResourceEntry> = new Map();

  private fontCounter = 0;
  private imageCounter = 0;
  private gsCounter = 0;
  private patternCounter = 0;
  private shadingCounter = 0;
  private xobjectCounter = 0;

  // Store ext-gstate dicts keyed by their resource name for inline objects
  private extGStateDicts: Map<string, PdfDict> = new Map();

  constructor(private store: ObjectStore) {}

  private refKey(ref: PdfRef): string {
    return `${ref.objectNumber}:${ref.generation}`;
  }

  registerFont(font: Font): string {
    if (!font.ref) {
      throw new Error(`Font "${font.name}" does not have a ref assigned`);
    }
    const key = this.refKey(font.ref);
    const existing = this.fonts.get(key);
    if (existing) return existing.name;

    this.fontCounter++;
    const name = `F${this.fontCounter}`;
    this.fonts.set(key, { name, ref: font.ref });
    return name;
  }

  registerImage(imageRef: PdfRef): string {
    const key = this.refKey(imageRef);
    const existing = this.images.get(key);
    if (existing) return existing.name;

    this.imageCounter++;
    const name = `Im${this.imageCounter}`;
    this.images.set(key, { name, ref: imageRef });
    return name;
  }

  registerExtGState(state: PdfDict): string {
    // Serialize the dict entries to use as dedup key
    const serialized = this.serializeDictForKey(state);
    const existing = this.extGStates.get(serialized);
    if (existing) return existing.name;

    this.gsCounter++;
    const name = `GS${this.gsCounter}`;
    const ref = this.store.allocRef();
    this.store.set(ref, state);
    this.extGStates.set(serialized, { name, ref });
    this.extGStateDicts.set(name, state);
    return name;
  }

  registerPattern(patternRef: PdfRef): string {
    const key = this.refKey(patternRef);
    const existing = this.patterns.get(key);
    if (existing) return existing.name;

    this.patternCounter++;
    const name = `P${this.patternCounter}`;
    this.patterns.set(key, { name, ref: patternRef });
    return name;
  }

  registerShading(shadingRef: PdfRef): string {
    const key = this.refKey(shadingRef);
    const existing = this.shadings.get(key);
    if (existing) return existing.name;

    this.shadingCounter++;
    const name = `Sh${this.shadingCounter}`;
    this.shadings.set(key, { name, ref: shadingRef });
    return name;
  }

  registerXObject(ref: PdfRef): string {
    const key = this.refKey(ref);
    const existing = this.xobjects.get(key);
    if (existing) return existing.name;

    this.xobjectCounter++;
    const name = `X${this.xobjectCounter}`;
    this.xobjects.set(key, { name, ref });
    return name;
  }

  getResourceName(type: ResourceType, ref: PdfRef): string | undefined {
    const key = this.refKey(ref);
    switch (type) {
      case 'font': return this.fonts.get(key)?.name;
      case 'image': return this.images.get(key)?.name;
      case 'extgstate': return this.extGStates.get(key)?.name;
      case 'pattern': return this.patterns.get(key)?.name;
      case 'shading': return this.shadings.get(key)?.name;
      case 'xobject': return this.xobjects.get(key)?.name;
    }
  }

  buildResourceDict(): PdfDict {
    const entries: Record<string, PdfObject> = {};

    if (this.fonts.size > 0) {
      const fontEntries: Record<string, PdfObject> = {};
      for (const { name, ref } of this.fonts.values()) {
        fontEntries[name] = ref;
      }
      entries['Font'] = pdfDict(fontEntries);
    }

    // Merge images and xobjects into XObject dict
    const xobjEntries: Record<string, PdfObject> = {};
    for (const { name, ref } of this.images.values()) {
      xobjEntries[name] = ref;
    }
    for (const { name, ref } of this.xobjects.values()) {
      xobjEntries[name] = ref;
    }
    if (Object.keys(xobjEntries).length > 0) {
      entries['XObject'] = pdfDict(xobjEntries);
    }

    if (this.extGStates.size > 0) {
      const gsEntries: Record<string, PdfObject> = {};
      for (const { name, ref } of this.extGStates.values()) {
        gsEntries[name] = ref;
      }
      entries['ExtGState'] = pdfDict(gsEntries);
    }

    if (this.patterns.size > 0) {
      const patEntries: Record<string, PdfObject> = {};
      for (const { name, ref } of this.patterns.values()) {
        patEntries[name] = ref;
      }
      entries['Pattern'] = pdfDict(patEntries);
    }

    if (this.shadings.size > 0) {
      const shEntries: Record<string, PdfObject> = {};
      for (const { name, ref } of this.shadings.values()) {
        shEntries[name] = ref;
      }
      entries['Shading'] = pdfDict(shEntries);
    }

    return pdfDict(entries);
  }

  private serializeDictForKey(dict: PdfDict): string {
    const parts: string[] = [];
    for (const [k, v] of dict.entries) {
      parts.push(`${k}=${this.serializeValue(v)}`);
    }
    parts.sort();
    return parts.join(';');
  }

  private serializeValue(obj: PdfObject): string {
    switch (obj.type) {
      case 'name': return `/${obj.value}`;
      case 'number': return `${obj.value}`;
      case 'bool': return `${obj.value}`;
      case 'string': return `(${Array.from(obj.value).join(',')})`;
      case 'ref': return `${obj.objectNumber}:${obj.generation}`;
      case 'null': return 'null';
      case 'array': return `[${obj.items.map(i => this.serializeValue(i)).join(',')}]`;
      case 'dict': return `{${this.serializeDictForKey(obj)}}`;
      case 'stream': return `stream`;
    }
  }
}
