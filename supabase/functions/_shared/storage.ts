// Image storage for Zuno AI.
//
// Primary: Cloudflare R2 (S3-compatible, zero egress fees). It is used as soon
// as these Supabase secrets exist:
//   R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET,
//   R2_PUBLIC_BASE_URL   (e.g. https://pub-xxxx.r2.dev, later https://img.yourdomain.com)
//
// Fallback: ImgBB (IMGBB_API_KEY). Used only while R2 is not configured yet, or
// if an R2 upload fails, so a generation is never lost to a storage hiccup.
//
// Object keys are built by the server from trusted ids only (uid from the
// verified token, random UUIDs) - never from client-supplied names.

import { AwsClient } from "npm:aws4fetch@1.0.20";

const R2_ACCOUNT_ID = Deno.env.get("R2_ACCOUNT_ID") ?? "";
const R2_ACCESS_KEY_ID = Deno.env.get("R2_ACCESS_KEY_ID") ?? "";
const R2_SECRET_ACCESS_KEY = Deno.env.get("R2_SECRET_ACCESS_KEY") ?? "";
const R2_BUCKET = Deno.env.get("R2_BUCKET") ?? "";
const R2_PUBLIC_BASE_URL = (Deno.env.get("R2_PUBLIC_BASE_URL") ?? "").replace(/\/+$/, "");
const IMGBB_API_KEY = Deno.env.get("IMGBB_API_KEY") ?? "";

// A Cloudflare account id is exactly 32 hex characters. Anything else means a
// secret was set in the wrong slot; refuse to use it (and never log its value).
const ACCOUNT_ID_OK = /^[0-9a-f]{32}$/i.test(R2_ACCOUNT_ID);
let _warned = false;

export function r2Configured(): boolean {
  if (R2_ACCOUNT_ID && !ACCOUNT_ID_OK) {
    if (!_warned) {
      _warned = true;
      console.error("R2_ACCOUNT_ID is invalid: it must be the 32-character Cloudflare account id. R2 is disabled until it is fixed.");
    }
    return false;
  }
  return !!(R2_ACCOUNT_ID && R2_ACCESS_KEY_ID && R2_SECRET_ACCESS_KEY && R2_BUCKET && R2_PUBLIC_BASE_URL);
}

/** True if `url` is one of our own R2 public URLs (already migrated). */
export function isR2Url(url: string): boolean {
  return r2Configured() && url.startsWith(`${R2_PUBLIC_BASE_URL}/`);
}

/** True if at least one storage backend is available. */
export function storageConfigured(): boolean {
  return r2Configured() || !!IMGBB_API_KEY;
}

export function extFor(mime: string): string {
  if (mime === "image/png") return "png";
  if (mime === "image/webp") return "webp";
  return "jpg";
}

export function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function bytesToB64(bytes: Uint8Array): string {
  let s = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    s += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(s);
}

let _client: AwsClient | null = null;
function r2Client(): AwsClient {
  _client ??= new AwsClient({
    accessKeyId: R2_ACCESS_KEY_ID,
    secretAccessKey: R2_SECRET_ACCESS_KEY,
    service: "s3",
    region: "auto",
  });
  return _client;
}

async function putR2(bytes: Uint8Array, mime: string, key: string): Promise<string | null> {
  try {
    const url = `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com/${R2_BUCKET}/${key}`;
    const res = await r2Client().fetch(url, {
      method: "PUT",
      headers: {
        "Content-Type": mime,
        "Cache-Control": "public, max-age=31536000, immutable",
      },
      body: bytes,
      signal: AbortSignal.timeout(30_000),
    });
    if (!res.ok) {
      console.error(`R2 upload failed: HTTP ${res.status} ${(await res.text()).slice(0, 300)}`);
      return null;
    }
    return `${R2_PUBLIC_BASE_URL}/${key}`;
  } catch (e) {
    console.error(`R2 upload error: ${e instanceof Error ? e.message : e}`);
    return null;
  }
}

async function putImgBB(bytes: Uint8Array): Promise<string | null> {
  if (!IMGBB_API_KEY) return null;
  try {
    const body = new URLSearchParams();
    body.append("image", bytesToB64(bytes));
    const res = await fetch(`https://api.imgbb.com/1/upload?key=${IMGBB_API_KEY}`, {
      method: "POST",
      body,
      signal: AbortSignal.timeout(30_000),
    });
    const data = await res.json().catch(() => ({}));
    if (res.ok && data?.data?.url) return data.data.url as string;
  } catch (_e) {
    // fall through
  }
  return null;
}

/** R2 only (no ImgBB fallback). Used by the template migration. */
export async function storeImageR2(bytes: Uint8Array, mime: string, key: string): Promise<string | null> {
  if (!r2Configured()) return null;
  return await putR2(bytes, mime, key);
}

/**
 * Stores image bytes and returns a public https URL, or null on failure.
 * `key` is the object path inside the bucket, e.g. "generations/<uid>/<job>.png".
 */
export async function storeImage(bytes: Uint8Array, mime: string, key: string): Promise<string | null> {
  if (r2Configured()) {
    const url = await putR2(bytes, mime, key);
    if (url) return url;
  }
  return await putImgBB(bytes);
}
