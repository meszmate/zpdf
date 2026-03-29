/**
 * Marked content operators for tagged PDF accessibility.
 */

/**
 * Begin a marked-content sequence with the given tag.
 * Produces the BMC operator.
 */
export function beginMarkedContent(tag: string): string {
  return `/${tag} BMC\n`;
}

/**
 * Begin a marked-content sequence with a property dict containing an MCID.
 * Produces the BDC operator.
 */
export function beginMarkedContentWithDict(tag: string, mcid: number): string {
  return `/${tag} <</MCID ${mcid}>> BDC\n`;
}

/**
 * End a marked-content sequence.
 * Produces the EMC operator.
 */
export function endMarkedContent(): string {
  return `EMC\n`;
}
