// Admin-only proxy so the admin panel's "Bulk Upload JSON" can mirror
// third-party prompt images to our own storage (R2) without hitting browser CORS.
//
// Why this exists: the admin panel is Flutter Web, and a browser tab can
// display an <img> from almost any host, but it can't *read* that image's
// bytes with fetch()/XHR unless the host sends Access-Control-Allow-Origin
// headers. Downloading here is a plain server-to-server fetch with no CORS.
//
// Admin-only: verifies the caller's Firebase ID token and requires an
// `admins/{uid}` doc to exist.

import {
  authenticate,
  corsHeaders,
  errorResponse,
  getDoc,
  HttpError,
  json,
  requireBody,
} from "../_shared/lib.ts";
import { sniffImageMime } from "../_shared/image.ts";
import { bytesToB64, extFor, isR2Url, storageConfigured, storeImage } from "../_shared/storage.ts";

const MAX_BYTES = 8 * 1024 * 1024;

/** Only public https URLs — never internal addresses (SSRF guard). */
function assertPublicHttps(raw: string): URL {
  let url: URL;
  try {
    url = new URL(raw);
  } catch (_e) {
    throw new HttpError(400, "imageUrl is not a valid URL", "BAD_REQUEST");
  }
  const host = url.hostname.toLowerCase();
  const isPrivate = host === "localhost" || host.endsWith(".local") || host.endsWith(".internal") ||
    /^(127\.|10\.|192\.168\.|169\.254\.|0\.)/.test(host) || /^172\.(1[6-9]|2\d|3[01])\./.test(host) ||
    host === "[::1]" || host.startsWith("[");
  if (url.protocol !== "https:" || isPrivate) {
    throw new HttpError(400, "Only public https image URLs are allowed", "BAD_REQUEST");
  }
  return url;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ success: false, error: "Method not allowed" }, 405);

  try {
    const auth = await authenticate(req);
    if ((await getDoc(`admins/${auth.uid}`)) === null) {
      throw new HttpError(403, "Admin access required", "FORBIDDEN");
    }

    const body = requireBody<Record<string, unknown>>(await req.json().catch(() => null));
    if (typeof body.imageUrl !== "string" || !body.imageUrl) {
      throw new HttpError(400, "imageUrl is required", "BAD_REQUEST");
    }
    const url = assertPublicHttps(body.imageUrl);
    if (!storageConfigured()) throw new HttpError(503, "Storage is not configured", "NOT_CONFIGURED");
    // Already on our own storage: nothing to mirror.
    if (isR2Url(body.imageUrl)) return json({ success: true, imageUrl: body.imageUrl });

    const imgRes = await fetch(url, { redirect: "error", signal: AbortSignal.timeout(30_000) });
    if (!imgRes.ok) throw new HttpError(502, `Source image fetch failed: HTTP ${imgRes.status}`, "FETCH_FAILED");
    const imgBytes = new Uint8Array(await imgRes.arrayBuffer());
    if (imgBytes.length > MAX_BYTES) throw new HttpError(413, "Source image is too large", "IMAGE_TOO_LARGE");

    const mime = sniffImageMime(bytesToB64(imgBytes.subarray(0, 24)));
    if (!mime) throw new HttpError(400, "Source is not a JPG, PNG or WebP image", "BAD_IMAGE");

    const stored = await storeImage(imgBytes, mime, `prompts/${crypto.randomUUID()}.${extFor(mime)}`);
    if (!stored) throw new HttpError(502, "Image upload failed", "UPLOAD_FAILED");
    return json({ success: true, imageUrl: stored });
  } catch (err) {
    return errorResponse(err);
  }
});
