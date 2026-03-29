export interface PdfBool { readonly type: 'bool'; readonly value: boolean }
export interface PdfNumber { readonly type: 'number'; readonly value: number }
export interface PdfString { readonly type: 'string'; readonly value: Uint8Array; readonly encoding: 'literal' | 'hex' }
export interface PdfName { readonly type: 'name'; readonly value: string }
export interface PdfArray { readonly type: 'array'; readonly items: PdfObject[] }
export interface PdfDict { readonly type: 'dict'; readonly entries: Map<string, PdfObject> }
export interface PdfStream { readonly type: 'stream'; readonly dict: Map<string, PdfObject>; readonly data: Uint8Array }
export interface PdfNull { readonly type: 'null' }
export interface PdfRef { readonly type: 'ref'; readonly objectNumber: number; readonly generation: number }
export type PdfObject = PdfBool | PdfNumber | PdfString | PdfName | PdfArray | PdfDict | PdfStream | PdfNull | PdfRef
