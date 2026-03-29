import type { Color } from '../color/color.js';

/* ------------------------------------------------------------------ */
/*  Form field option types                                           */
/* ------------------------------------------------------------------ */

export interface TextFieldOptions {
  rect: [number, number, number, number];
  name: string;
  value?: string;
  defaultValue?: string;
  maxLength?: number;
  multiline?: boolean;
  password?: boolean;
  readOnly?: boolean;
  required?: boolean;
  fontSize?: number;
  fontColor?: Color;
  backgroundColor?: Color;
  borderColor?: Color;
  alignment?: 0 | 1 | 2;
}

export interface CheckboxOptions {
  rect: [number, number, number, number];
  name: string;
  checked?: boolean;
  readOnly?: boolean;
  required?: boolean;
  backgroundColor?: Color;
  borderColor?: Color;
}

export interface RadioGroupOptions {
  name: string;
  options: Array<{
    rect: [number, number, number, number];
    value: string;
    selected?: boolean;
  }>;
  readOnly?: boolean;
  required?: boolean;
}

export interface DropdownOptions {
  rect: [number, number, number, number];
  name: string;
  options: string[];
  value?: string;
  editable?: boolean;
  readOnly?: boolean;
  required?: boolean;
  fontSize?: number;
  backgroundColor?: Color;
  borderColor?: Color;
}

export interface ListboxOptions {
  rect: [number, number, number, number];
  name: string;
  options: string[];
  selected?: string[];
  multiSelect?: boolean;
  readOnly?: boolean;
  required?: boolean;
  fontSize?: number;
  backgroundColor?: Color;
  borderColor?: Color;
}

export interface ButtonOptions {
  rect: [number, number, number, number];
  name: string;
  label?: string;
  fontSize?: number;
  backgroundColor?: Color;
  borderColor?: Color;
}

export interface SignatureFieldOptions {
  rect: [number, number, number, number];
  name: string;
  reason?: string;
  location?: string;
  contactInfo?: string;
}
