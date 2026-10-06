// Pure helpers for verifying AdMob SSV signatures (kept separate so they can be unit-tested).

export function b64ToBytes(b64: string): Uint8Array {
  const std = b64.replace(/-/g, "+").replace(/_/g, "/");
  const padded = std + "=".repeat((4 - (std.length % 4)) % 4);
  const bin = atob(padded);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

/** Converts an ASN.1 DER ECDSA signature into the raw r||s form WebCrypto expects. */
export function derToRaw(der: Uint8Array, size = 32): Uint8Array {
  let i = 0;
  if (der[i++] !== 0x30) throw new Error("Bad DER signature");
  let len = der[i++];
  if (len & 0x80) i += len & 0x7f; // long-form length
  const readInt = (): Uint8Array => {
    if (der[i++] !== 0x02) throw new Error("Bad DER integer");
    const l = der[i++];
    let v = der.slice(i, i + l);
    i += l;
    while (v.length > size && v[0] === 0) v = v.slice(1);
    if (v.length > size) throw new Error("Bad DER integer size");
    const out = new Uint8Array(size);
    out.set(v, size - v.length);
    return out;
  };
  const r = readInt();
  const s = readInt();
  const raw = new Uint8Array(size * 2);
  raw.set(r, 0);
  raw.set(s, size);
  return raw;
}

/** The signed message is the raw query string up to (not including) `&signature=`. */
export function signedMessage(rawQuery: string): string {
  const idx = rawQuery.indexOf("&signature=");
  return idx === -1 ? rawQuery : rawQuery.slice(0, idx);
}

