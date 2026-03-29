import type { PdfRef } from '../core/types.js';
import { ObjectStore } from '../core/object-store.js';
import { createOCG } from './ocg.js';
import { createOCProperties, type LayerInfo } from './oc-properties.js';

/**
 * High-level API for building PDF layers (Optional Content Groups).
 */
export class LayerBuilder {
  private layers: Array<{ ref: PdfRef; name: string; visible: boolean }> = [];

  constructor(private store: ObjectStore) {}

  /**
   * Add a new layer (OCG) with the given name and default visibility.
   * Returns the layer info including the ref for use in content streams.
   */
  addLayer(name: string, visible: boolean = true): { ref: PdfRef; name: string } {
    const ref = createOCG(this.store, name, visible);
    const layer = { ref, name, visible };
    this.layers.push(layer);
    return { ref, name };
  }

  /**
   * Get all registered layers.
   */
  getLayers(): Array<{ ref: PdfRef; name: string; visible: boolean }> {
    return [...this.layers];
  }

  /**
   * Build the /OCProperties dict and store it. Returns the ref.
   * This should be added to the document catalog.
   */
  buildOCProperties(): PdfRef {
    return createOCProperties(this.store, this.layers);
  }

  /**
   * Returns PDF operators to begin optional content for a layer.
   * Use in a content stream to mark content as belonging to a layer.
   */
  beginLayerContent(layerRef: PdfRef): string {
    return `/OC /MC${layerRef.objectNumber} BDC\n`;
  }

  /**
   * Returns PDF operators to end optional content.
   */
  endLayerContent(): string {
    return `EMC\n`;
  }
}
