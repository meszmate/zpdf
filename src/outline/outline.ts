import type { OutlineItemOptions } from './outline-item.js';

export class OutlineTree {
  private items: OutlineItemOptions[] = [];

  addItem(options: OutlineItemOptions): this {
    this.items.push(options);
    return this;
  }

  getItems(): OutlineItemOptions[] {
    return this.items;
  }
}
