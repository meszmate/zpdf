/**
 * Build the PDF /Encrypt dictionary for various encryption algorithms.
 */

import type { PdfDict } from '../core/types.js';
import { pdfDict, pdfName, pdfNum, pdfHexStr, pdfBool } from '../core/objects.js';
import type { PDFPermissions } from './permissions.js';
import { permissionsToFlags } from './permissions.js';
import {
  computeOwnerKey,
  computeUserKey,
  computeUserKeyR6,
  computeOwnerKeyR6,
} from './password.js';
import { aesEncryptCBC, generateRandomBytes } from './aes.js';

export interface EncryptionOptions {
  userPassword?: string;
  ownerPassword: string;
  permissions?: PDFPermissions;
  algorithm: 'rc4-40' | 'rc4-128' | 'aes-128' | 'aes-256';
}

/**
 * Create the /Encrypt dictionary and compute the encryption key.
 *
 * @param options - Encryption configuration
 * @param fileId - The first element of the /ID array from the trailer
 * @returns The /Encrypt PdfDict and the computed encryption key
 */
export function createEncryptionDict(
  options: EncryptionOptions,
  fileId: Uint8Array,
): { encryptDict: PdfDict; encryptionKey: Uint8Array } {
  const userPassword = options.userPassword || '';
  const ownerPassword = options.ownerPassword;
  const permissions = options.permissions || {};
  const permFlags = permissionsToFlags(permissions);

  switch (options.algorithm) {
    case 'rc4-40':
      return createRC4Dict(userPassword, ownerPassword, permFlags, fileId, 2, 40);
    case 'rc4-128':
      return createRC4Dict(userPassword, ownerPassword, permFlags, fileId, 3, 128);
    case 'aes-128':
      return createAES128Dict(userPassword, ownerPassword, permFlags, fileId);
    case 'aes-256':
      return createAES256Dict(userPassword, ownerPassword, permFlags);
    default:
      throw new Error(`Unknown encryption algorithm: ${(options as EncryptionOptions).algorithm}`);
  }
}

function createRC4Dict(
  userPassword: string,
  ownerPassword: string,
  permFlags: number,
  fileId: Uint8Array,
  revision: number,
  keyLength: number,
): { encryptDict: PdfDict; encryptionKey: Uint8Array } {
  const { ownerEntry } = computeOwnerKey(ownerPassword, userPassword, revision, keyLength);
  const { userEntry, encryptionKey } = computeUserKey(
    userPassword, ownerEntry, permFlags, fileId, revision, keyLength, true,
  );

  const version = revision === 2 ? 1 : 2;

  const dict = pdfDict({
    Filter: pdfName('Standard'),
    V: pdfNum(version),
    R: pdfNum(revision),
    Length: pdfNum(keyLength),
    O: pdfHexStr(ownerEntry),
    U: pdfHexStr(userEntry),
    P: pdfNum(permFlags),
  });

  return { encryptDict: dict, encryptionKey };
}

function createAES128Dict(
  userPassword: string,
  ownerPassword: string,
  permFlags: number,
  fileId: Uint8Array,
): { encryptDict: PdfDict; encryptionKey: Uint8Array } {
  const revision = 4;
  const keyLength = 128;

  const { ownerEntry } = computeOwnerKey(ownerPassword, userPassword, revision, keyLength);
  const { userEntry, encryptionKey } = computeUserKey(
    userPassword, ownerEntry, permFlags, fileId, revision, keyLength, true,
  );

  const stdCF = pdfDict({
    AuthEvent: pdfName('DocOpen'),
    CFM: pdfName('AESV2'),
    Length: pdfNum(16),
  });

  const cf = pdfDict({
    StdCF: stdCF,
  });

  const dict = pdfDict({
    Filter: pdfName('Standard'),
    V: pdfNum(4),
    R: pdfNum(4),
    Length: pdfNum(128),
    CF: cf,
    StmF: pdfName('StdCF'),
    StrF: pdfName('StdCF'),
    O: pdfHexStr(ownerEntry),
    U: pdfHexStr(userEntry),
    P: pdfNum(permFlags),
    EncryptMetadata: pdfBool(true),
  });

  return { encryptDict: dict, encryptionKey };
}

function createAES256Dict(
  userPassword: string,
  ownerPassword: string,
  permFlags: number,
): { encryptDict: PdfDict; encryptionKey: Uint8Array } {
  // Rev 6 / AES-256 does not use fileId for key derivation
  const { userEntry, userKeyEncryption, encryptionKey } = computeUserKeyR6(userPassword);
  const { ownerEntry, ownerKeyEncryption } = computeOwnerKeyR6(ownerPassword, userEntry);

  const stdCF = pdfDict({
    AuthEvent: pdfName('DocOpen'),
    CFM: pdfName('AESV3'),
    Length: pdfNum(32),
  });

  const cf = pdfDict({
    StdCF: stdCF,
  });

  // Build /Perms entry per ISO 32000-2 section 7.6.4.4.13
  const permsBytes = new Uint8Array(16);
  permsBytes[0] = permFlags & 0xff;
  permsBytes[1] = (permFlags >>> 8) & 0xff;
  permsBytes[2] = (permFlags >>> 16) & 0xff;
  permsBytes[3] = (permFlags >>> 24) & 0xff;
  permsBytes[4] = 0xff;
  permsBytes[5] = 0xff;
  permsBytes[6] = 0xff;
  permsBytes[7] = 0xff;
  permsBytes[8] = 0x54; // 'T' for encrypt metadata = true
  permsBytes[9] = 0x61; // 'a'
  permsBytes[10] = 0x64; // 'd'
  permsBytes[11] = 0x62; // 'b'
  const randBytes = generateRandomBytes(4);
  permsBytes[12] = randBytes[0];
  permsBytes[13] = randBytes[1];
  permsBytes[14] = randBytes[2];
  permsBytes[15] = randBytes[3];

  const iv = new Uint8Array(16);
  const permsEncrypted = aesEncryptCBC(encryptionKey, permsBytes, iv);

  const dict = pdfDict({
    Filter: pdfName('Standard'),
    V: pdfNum(5),
    R: pdfNum(6),
    Length: pdfNum(256),
    CF: cf,
    StmF: pdfName('StdCF'),
    StrF: pdfName('StdCF'),
    O: pdfHexStr(ownerEntry),
    U: pdfHexStr(userEntry),
    OE: pdfHexStr(ownerKeyEncryption),
    UE: pdfHexStr(userKeyEncryption),
    P: pdfNum(permFlags),
    Perms: pdfHexStr(permsEncrypted),
    EncryptMetadata: pdfBool(true),
  });

  return { encryptDict: dict, encryptionKey };
}
