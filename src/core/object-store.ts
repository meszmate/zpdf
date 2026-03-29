import type { PdfObject, PdfRef } from './types.js';

export class ObjectStore {
  private objects: Map<string, { ref: PdfRef; obj: PdfObject }> = new Map();
  private _nextObjectNumber: number = 1;

  private key(ref: PdfRef): string {
    return `${ref.objectNumber}:${ref.generation}`;
  }

  get nextObjectNumber(): number {
    return this._nextObjectNumber;
  }

  get size(): number {
    return this.objects.size;
  }

  allocRef(generation: number = 0): PdfRef {
    const objectNumber = this._nextObjectNumber++;
    return { type: 'ref', objectNumber, generation };
  }

  set(ref: PdfRef, obj: PdfObject): void {
    if (ref.objectNumber >= this._nextObjectNumber) {
      this._nextObjectNumber = ref.objectNumber + 1;
    }
    this.objects.set(this.key(ref), { ref, obj });
  }

  get(ref: PdfRef): PdfObject | undefined {
    const entry = this.objects.get(this.key(ref));
    return entry?.obj;
  }

  has(ref: PdfRef): boolean {
    return this.objects.has(this.key(ref));
  }

  delete(ref: PdfRef): void {
    this.objects.delete(this.key(ref));
  }

  *entries(): IterableIterator<[PdfRef, PdfObject]> {
    for (const { ref, obj } of this.objects.values()) {
      yield [ref, obj];
    }
  }
}
