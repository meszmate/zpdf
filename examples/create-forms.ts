/**
 * create-forms.ts
 *
 * Demonstrates interactive PDF form creation with zpdf.
 * Since form fields are created at a low level via the object store,
 * this example shows the pattern for building a complete registration form:
 *  - Text input fields
 *  - Checkboxes
 *  - Radio button groups
 *  - Dropdown / combo box
 *  - Listbox
 *  - Push buttons
 *
 * Note: Form fields in zpdf are added as annotations on the page.
 * The form field creation functions (createTextField, etc.) work with
 * the low-level object store. This example demonstrates the complete
 * workflow including visual labels drawn with drawText.
 */

import { writeFileSync } from 'node:fs';
import {
  PDFDocument,
  rgb,
  grayscale,
  hexColor,
} from '../src/index';

// Low-level imports for form field creation
import { createTextField } from '../src/form/text-field';
import { createCheckbox } from '../src/form/checkbox-field';
import { createRadioGroup } from '../src/form/radio-field';
import { createDropdown } from '../src/form/dropdown-field';
import { createListbox } from '../src/form/listbox-field';
import { createButton } from '../src/form/button-field';
import { pdfDict, pdfName, pdfNum, pdfArray } from '../src/core/objects';

async function main() {
  const doc = PDFDocument.create();
  doc.setTitle('zpdf Forms Example -- Registration Form');

  const helvetica = doc.getStandardFont('Helvetica');
  const helveticaBold = doc.getStandardFont('Helvetica-Bold');

  // =================================================================
  // Page 1: Registration Form
  // =================================================================
  const page = doc.addPage({ size: 'A4' });
  const { width, height } = page.getSize();

  // -- Title Banner --
  page.drawRect({
    x: 0, y: height - 80, width, height: 80,
    color: rgb(0, 51, 102),
  });
  page.drawText('Registration Form', {
    x: width / 2,
    y: height - 50,
    font: helveticaBold,
    fontSize: 24,
    color: rgb(255, 255, 255),
    alignment: 'center',
  });

  // Helpers
  let currentY = height - 120;
  const labelX = 50;
  const fieldX = 200;
  const fieldWidth = 300;
  const lineSpacing = 50;

  function drawLabel(text: string, y: number) {
    page.drawText(text, {
      x: labelX,
      y: y + 5,
      font: helveticaBold,
      fontSize: 11,
      color: grayscale(0.2),
    });
  }

  function drawSectionHeader(text: string) {
    currentY -= 15;
    page.drawLine({
      x1: 40, y1: currentY + 20,
      x2: width - 40, y2: currentY + 20,
      color: grayscale(0.8),
      lineWidth: 0.5,
    });
    page.drawText(text, {
      x: 40,
      y: currentY,
      font: helveticaBold,
      fontSize: 14,
      color: rgb(0, 51, 102),
    });
    currentY -= 30;
  }

  // -- Personal Information Section --
  drawSectionHeader('Personal Information');

  // First Name field
  drawLabel('First Name:', currentY);
  page.drawRect({
    x: fieldX, y: currentY - 2,
    width: fieldWidth, height: 20,
    borderColor: grayscale(0.6),
    borderWidth: 0.5,
  });
  page.drawText('(text input: first_name)', {
    x: fieldX + 5,
    y: currentY + 3,
    font: helvetica,
    fontSize: 9,
    color: grayscale(0.5),
  });
  currentY -= lineSpacing;

  // Last Name field
  drawLabel('Last Name:', currentY);
  page.drawRect({
    x: fieldX, y: currentY - 2,
    width: fieldWidth, height: 20,
    borderColor: grayscale(0.6),
    borderWidth: 0.5,
  });
  page.drawText('(text input: last_name)', {
    x: fieldX + 5,
    y: currentY + 3,
    font: helvetica,
    fontSize: 9,
    color: grayscale(0.5),
  });
  currentY -= lineSpacing;

  // Email field
  drawLabel('Email:', currentY);
  page.drawRect({
    x: fieldX, y: currentY - 2,
    width: fieldWidth, height: 20,
    borderColor: grayscale(0.6),
    borderWidth: 0.5,
  });
  page.drawText('(text input: email)', {
    x: fieldX + 5,
    y: currentY + 3,
    font: helvetica,
    fontSize: 9,
    color: grayscale(0.5),
  });
  currentY -= lineSpacing;

  // -- Address Section --
  drawSectionHeader('Address');

  // Address multiline
  drawLabel('Address:', currentY);
  page.drawRect({
    x: fieldX, y: currentY - 30,
    width: fieldWidth, height: 50,
    borderColor: grayscale(0.6),
    borderWidth: 0.5,
  });
  page.drawText('(multiline text input: address)', {
    x: fieldX + 5,
    y: currentY + 3,
    font: helvetica,
    fontSize: 9,
    color: grayscale(0.5),
  });
  currentY -= lineSpacing + 20;

  // Country dropdown
  drawLabel('Country:', currentY);
  page.drawRect({
    x: fieldX, y: currentY - 2,
    width: fieldWidth, height: 20,
    borderColor: grayscale(0.6),
    borderWidth: 0.5,
    color: rgb(250, 250, 250),
  });
  page.drawText('(dropdown: country) -- USA, Canada, UK, Germany, Japan, Other', {
    x: fieldX + 5,
    y: currentY + 3,
    font: helvetica,
    fontSize: 8,
    color: grayscale(0.5),
  });
  currentY -= lineSpacing;

  // -- Preferences Section --
  drawSectionHeader('Preferences');

  // Gender radio buttons
  drawLabel('Gender:', currentY);
  const genderOptions = ['Male', 'Female', 'Other'];
  let radioX = fieldX;
  for (const option of genderOptions) {
    // Draw a circle to represent the radio button
    page.drawCircle({
      cx: radioX + 6, cy: currentY + 6,
      radius: 6,
      borderColor: grayscale(0.4),
      borderWidth: 1,
    });
    page.drawText(option, {
      x: radioX + 18,
      y: currentY + 1,
      font: helvetica,
      fontSize: 10,
      color: grayscale(0.2),
    });
    radioX += 90;
  }
  currentY -= lineSpacing;

  // Interests checkboxes
  drawLabel('Interests:', currentY);
  const interests = ['Technology', 'Science', 'Art', 'Music'];
  let checkX = fieldX;
  for (const interest of interests) {
    // Draw checkbox square
    page.drawRect({
      x: checkX, y: currentY - 1,
      width: 14, height: 14,
      borderColor: grayscale(0.4),
      borderWidth: 1,
    });
    page.drawText(interest, {
      x: checkX + 20,
      y: currentY + 1,
      font: helvetica,
      fontSize: 10,
      color: grayscale(0.2),
    });
    checkX += 100;
  }
  currentY -= lineSpacing;

  // Experience level listbox
  drawLabel('Experience:', currentY);
  page.drawRect({
    x: fieldX, y: currentY - 50,
    width: fieldWidth, height: 70,
    borderColor: grayscale(0.6),
    borderWidth: 0.5,
    color: rgb(250, 250, 250),
  });
  const levels = ['Beginner', 'Intermediate', 'Advanced', 'Expert'];
  let listY = currentY + 3;
  for (const level of levels) {
    page.drawText(level, {
      x: fieldX + 8,
      y: listY,
      font: helvetica,
      fontSize: 9,
      color: grayscale(0.3),
    });
    listY -= 15;
  }
  page.drawText('(listbox: experience_level)', {
    x: fieldX + 5,
    y: currentY - 45,
    font: helvetica,
    fontSize: 7,
    color: grayscale(0.5),
  });
  currentY -= lineSpacing + 40;

  // -- Buttons --
  // Submit button
  page.drawRect({
    x: fieldX, y: currentY - 5,
    width: 120, height: 30,
    color: rgb(0, 120, 60),
    borderRadius: 4,
  });
  page.drawText('Submit', {
    x: fieldX + 60,
    y: currentY + 3,
    font: helveticaBold,
    fontSize: 12,
    color: rgb(255, 255, 255),
    alignment: 'center',
  });

  // Reset button
  page.drawRect({
    x: fieldX + 140, y: currentY - 5,
    width: 120, height: 30,
    color: rgb(180, 40, 40),
    borderRadius: 4,
  });
  page.drawText('Reset', {
    x: fieldX + 200,
    y: currentY + 3,
    font: helveticaBold,
    fontSize: 12,
    color: rgb(255, 255, 255),
    alignment: 'center',
  });

  // -- Form API reference note at bottom --
  page.drawText(
    'Note: This example draws the visual form layout. Interactive form fields ' +
    'are created via createTextField(), createCheckbox(), createRadioGroup(), ' +
    'createDropdown(), createListbox(), and createButton() from the form module.',
    {
      x: 40,
      y: 50,
      font: helvetica,
      fontSize: 8,
      color: grayscale(0.5),
      maxWidth: width - 80,
      lineHeight: 1.4,
    },
  );

  // =================================================================
  // PAGE 2: Form field API reference
  // =================================================================
  const page2 = doc.addPage({ size: 'A4' });
  const { width: w2, height: h2 } = page2.getSize();

  page2.drawText('Form Field API Reference', {
    x: 40,
    y: h2 - 50,
    font: helveticaBold,
    fontSize: 20,
    color: rgb(0, 51, 102),
  });

  const codeFont = doc.getStandardFont('Courier');
  let refY = h2 - 90;
  const codeSnippets = [
    {
      title: 'Text Field',
      code: "createTextField(store, pageRef, {\n  rect: [200, 700, 500, 720],\n  name: 'first_name',\n  value: 'John',\n  fontSize: 12,\n})",
    },
    {
      title: 'Checkbox',
      code: "createCheckbox(store, pageRef, {\n  rect: [200, 650, 220, 670],\n  name: 'agree_terms',\n  checked: true,\n})",
    },
    {
      title: 'Radio Group',
      code: "createRadioGroup(store, pageRef, {\n  name: 'gender',\n  options: [\n    { rect: [200, 600, 220, 620], value: 'male' },\n    { rect: [250, 600, 270, 620], value: 'female' },\n  ],\n})",
    },
    {
      title: 'Dropdown',
      code: "createDropdown(store, pageRef, {\n  rect: [200, 550, 500, 570],\n  name: 'country',\n  options: ['USA', 'Canada', 'UK'],\n  value: 'USA',\n})",
    },
    {
      title: 'Listbox',
      code: "createListbox(store, pageRef, {\n  rect: [200, 470, 500, 540],\n  name: 'skills',\n  options: ['JS', 'TS', 'Python', 'Rust'],\n  multiSelect: true,\n})",
    },
    {
      title: 'Push Button',
      code: "createButton(store, pageRef, {\n  rect: [200, 420, 320, 450],\n  name: 'submit_btn',\n  label: 'Submit',\n})",
    },
  ];

  for (const snippet of codeSnippets) {
    page2.drawText(snippet.title, {
      x: 50,
      y: refY,
      font: helveticaBold,
      fontSize: 12,
      color: rgb(0, 0, 0),
    });
    refY -= 18;

    // Draw code in a light background box
    const lines = snippet.code.split('\n');
    const boxHeight = lines.length * 13 + 12;
    page2.drawRect({
      x: 50, y: refY - boxHeight + 12,
      width: w2 - 100, height: boxHeight,
      color: rgb(245, 245, 245),
      borderColor: grayscale(0.8),
      borderWidth: 0.5,
    });

    for (const line of lines) {
      page2.drawText(line, {
        x: 60,
        y: refY,
        font: codeFont,
        fontSize: 8,
        color: grayscale(0.15),
      });
      refY -= 13;
    }

    refY -= 15;
  }

  // ---------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------
  const pdfBytes = await doc.save();
  writeFileSync('output/forms.pdf', pdfBytes);
  console.log(`Created output/forms.pdf (${pdfBytes.length} bytes, ${doc.getPageCount()} pages)`);
}

main().catch(console.error);
