// Pure helpers for validating uploaded images (unit-testable).

/** Detects JPEG / PNG / WebP from the first bytes of a base64 string. Returns null for anything else. */
export function sniffImageMime(b64: string): string | null {
  if (typeof b64 !== "string" || b64.length < 24) return null;
  let head: string;
  try {
    head = atob(b64.slice(0, 24));
  } catch (_e) {
    return null;
  }
  const b = Array.from(head, (c) => c.charCodeAt(0));
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "image/jpeg";
  if (
    b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47 &&
    b[4] === 0x0d && b[5] === 0x0a && b[6] === 0x1a && b[7] === 0x0a
  ) return "image/png";
  if (
    head.slice(0, 4) === "RIFF" && head.slice(8, 12) === "WEBP"
  ) return "image/webp";
  return null;
}
