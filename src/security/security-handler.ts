/**
 * Main security handler that ties together encryption/decryption for PDF documents.
 */

import type { PdfObject, PdfRef, PdfDict } from '../core/types.js';
import { dictGetNumber, dictGetName, dictGetBool, dictGetDict } from '../core/objects.js';
import type { EncryptionOptions } from './encryption-dict.js';
import { createEncryptionDict } from './encryption-dict.js';
import { encryptObject } from './encrypt-stream.js';
import { decryptObject } from './decrypt-stream.js';
import {
  padPassword,
  PDF_PASSWORD_PADDING,
  computeOwnerKey,
  computeUserKey,
  validateUserPasswordR6,
  validateOwnerPasswordR6,
  recoverFileKeyFromUserR6,
  recoverFileKeyFromOwnerR6,
} from './password.js';
import { md5 } from './md5.js';
import { rc4 } from './rc4.js';

/**
 * SecurityHandler manages encryption and decryption for a PDF document.
 */
export class SecurityHandler {
  private encryptionKey: Uint8Array;
  private algorithm: string;
  private revision: number;

  private constructor(encryptionKey: Uint8Array, algorithm: string, revision: number) {
    this.encryptionKey = encryptionKey;
    this.algorithm = algorithm;
    this.revision = revision;
  }

  /**
   * Create a new security handler for encrypting a PDF document.
   *
   * @param options - Encryption options (algorithm, passwords, permissions)
   * @param fileId - The first element of the /ID array
   * @returns The security handler and the /Encrypt dictionary
   */
  static create(
    options: EncryptionOptions,
    fileId: Uint8Array,
  ): { handler: SecurityHandler; encryptDict: PdfDict } {
    const { encryptDict, encryptionKey } = createEncryptionDict(options, fileId);

    let revision: number;
    switch (options.algorithm) {
      case 'rc4-40': revision = 2; break;
      case 'rc4-128': revision = 3; break;
      case 'aes-128': revision = 4; break;
      case 'aes-256': revision = 6; break;
      default: throw new Error(`Unknown algorithm: ${options.algorithm}`);
    }

    const handler = new SecurityHandler(encryptionKey, options.algorithm, revision);
    return { handler, encryptDict };
  }

  /**
   * Create a security handler from an existing /Encrypt dictionary (for decryption).
   * Validates the password and derives the encryption key.
   *
   * @param encryptDict - The parsed /Encrypt dictionary
   * @param password - The password to try (tested as user password first, then owner)
   * @param fileId - The first element of the /ID array
   * @returns The security handler ready for decryption
   * @throws Error if the password is invalid
   */
  static fromEncryptDict(
    encryptDict: PdfDict,
    password: string,
    fileId: Uint8Array,
  ): SecurityHandler {
    const V = dictGetNumber(encryptDict, 'V') ?? 0;
    const R = dictGetNumber(encryptDict, 'R') ?? 0;
    const lengthBits = dictGetNumber(encryptDict, 'Length') ?? 40;
    const P = dictGetNumber(encryptDict, 'P') ?? 0;
    const encryptMetadata = dictGetBool(encryptDict, 'EncryptMetadata') ?? true;

    // Extract /O and /U entries as raw bytes
    const oEntry = extractStringBytes(encryptDict, 'O');
    const uEntry = extractStringBytes(encryptDict, 'U');

    if (!oEntry || !uEntry) {
      throw new Error('Missing /O or /U entry in encryption dictionary');
    }

    // Determine algorithm from V and R
    let algorithm: string;
    if (R === 6) {
      algorithm = 'aes-256';
    } else if (R === 4) {
      // Check CF for AESV2
      const cf = dictGetDict(encryptDict, 'CF');
      if (cf) {
        const stdCF = dictGetDict(cf, 'StdCF');
        if (stdCF) {
          const cfm = dictGetName(stdCF, 'CFM');
          algorithm = cfm === 'AESV2' ? 'aes-128' : 'rc4-128';
        } else {
          algorithm = 'rc4-128';
        }
      } else {
        algorithm = 'rc4-128';
      }
    } else if (V === 2) {
      algorithm = 'rc4-128';
    } else {
      algorithm = 'rc4-40';
    }

    // Rev 6: AES-256
    if (R === 6) {
      return SecurityHandler.fromEncryptDictR6(encryptDict, password, uEntry, oEntry);
    }

    // Rev 2-4: try as user password first
    const keyLength = lengthBits;
    const { userEntry: computedU, encryptionKey } = computeUserKey(
      password, oEntry, P, fileId, R, keyLength, encryptMetadata,
    );

    // Validate user password
    if (validateUserPassword(computedU, uEntry, R)) {
      return new SecurityHandler(encryptionKey, algorithm, R);
    }

    // Try as owner password
    const ownerKey = deriveOwnerDecryptionKey(password, oEntry, R, keyLength);
    const userPassword = recoverUserPasswordFromOwner(ownerKey, oEntry, R, keyLength);

    const { userEntry: computedU2, encryptionKey: encKey2 } = computeUserKey(
      userPassword, oEntry, P, fileId, R, keyLength, encryptMetadata,
    );

    if (validateUserPassword(computedU2, uEntry, R)) {
      return new SecurityHandler(encKey2, algorithm, R);
    }

    throw new Error('Invalid password');
  }

  /**
   * Handle Rev 6 (AES-256) password validation and key recovery.
   */
  private static fromEncryptDictR6(
    encryptDict: PdfDict,
    password: string,
    uEntry: Uint8Array,
    oEntry: Uint8Array,
  ): SecurityHandler {
    const ueEntry = extractStringBytes(encryptDict, 'UE');
    const oeEntry = extractStringBytes(encryptDict, 'OE');

    if (!ueEntry || !oeEntry) {
      throw new Error('Missing /UE or /OE entry for Rev 6 encryption');
    }

    // Try as user password
    if (validateUserPasswordR6(password, uEntry)) {
      const encryptionKey = recoverFileKeyFromUserR6(password, uEntry, ueEntry);
      return new SecurityHandler(encryptionKey, 'aes-256', 6);
    }

    // Try as owner password
    if (validateOwnerPasswordR6(password, oEntry, uEntry)) {
      const encryptionKey = recoverFileKeyFromOwnerR6(password, oEntry, uEntry, oeEntry);
      return new SecurityHandler(encryptionKey, 'aes-256', 6);
    }

    throw new Error('Invalid password');
  }

  /**
   * Encrypt a PDF object.
   */
  encryptObject(obj: PdfObject, ref: PdfRef): PdfObject {
    return encryptObject(obj, ref, this.encryptionKey, this.algorithm, this.revision);
  }

  /**
   * Decrypt a PDF object.
   */
  decryptObject(obj: PdfObject, ref: PdfRef): PdfObject {
    return decryptObject(obj, ref, this.encryptionKey, this.algorithm, this.revision);
  }

  getEncryptionKey(): Uint8Array {
    return this.encryptionKey;
  }

  getAlgorithm(): string {
    return this.algorithm;
  }

  getRevision(): number {
    return this.revision;
  }
}

/**
 * Extract raw bytes from a string entry in a dict.
 */
function extractStringBytes(dict: PdfDict, key: string): Uint8Array | undefined {
  const obj = dict.entries.get(key);
  if (obj && obj.type === 'string') {
    return obj.value;
  }
  return undefined;
}

/**
 * Validate user password by comparing /U entries.
 * Rev 2: compare all 32 bytes.
 * Rev 3-4: compare first 16 bytes only (rest is arbitrary padding).
 */
function validateUserPassword(
  computedU: Uint8Array,
  storedU: Uint8Array,
  revision: number,
): boolean {
  const compareLen = revision === 2 ? 32 : 16;
  if (computedU.length < compareLen || storedU.length < compareLen) return false;
  for (let i = 0; i < compareLen; i++) {
    if (computedU[i] !== storedU[i]) return false;
  }
  return true;
}

/**
 * Derive the owner key for decrypting the /O value to recover the user password.
 */
function deriveOwnerDecryptionKey(
  ownerPassword: string,
  _ownerEntry: Uint8Array,
  revision: number,
  keyLength: number,
): Uint8Array {
  const keyBytes = keyLength / 8;
  const paddedOwner = padPassword(ownerPassword);
  let hash = md5(paddedOwner);

  if (revision >= 3) {
    for (let i = 0; i < 50; i++) {
      hash = md5(hash);
    }
  }

  return hash.subarray(0, keyBytes);
}

/**
 * Recover the user password from the /O entry using the owner key.
 * This is the reverse of the owner key computation (Algorithm 7 from PDF spec).
 */
function recoverUserPasswordFromOwner(
  ownerKey: Uint8Array,
  ownerEntry: Uint8Array,
  revision: number,
  keyLength: number,
): string {
  const keyBytes = keyLength / 8;
  let decrypted = ownerEntry;

  if (revision === 2) {
    decrypted = rc4(ownerKey, ownerEntry);
  } else {
    // Rev 3+: decrypt with keys from 19 down to 0
    decrypted = new Uint8Array(ownerEntry);
    for (let i = 19; i >= 0; i--) {
      const modKey = new Uint8Array(keyBytes);
      for (let j = 0; j < keyBytes; j++) {
        modKey[j] = ownerKey[j] ^ i;
      }
      decrypted = rc4(modKey, decrypted);
    }
  }

  // The decrypted value is the padded user password
  // Convert back to string (take bytes before padding starts)
  let len = 32;
  // Find where the padding constant starts
  for (let i = 0; i < 32; i++) {
    if (decrypted[i] === PDF_PASSWORD_PADDING[0]) {
      // Check if the rest matches the padding
      let match = true;
      for (let j = 0; j + i < 32 && j < 32; j++) {
        if (decrypted[i + j] !== PDF_PASSWORD_PADDING[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        len = i;
        break;
      }
    }
  }

  let result = '';
  for (let i = 0; i < len; i++) {
    result += String.fromCharCode(decrypted[i]);
  }
  return result;
}
