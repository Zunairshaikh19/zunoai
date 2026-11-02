// Admin-only, idempotent: moves every prompt's template image (`prompts/{id}.imageUrl`)
// from ImgBB (or any other host) to our own Cloudflare R2 bucket and rewrites the
// URL. The old URL is kept in `legacyImageUrl`.
//
// Works one Firestore page (PAGE_SIZE docs) per call so it always finishes well
// inside the function time limit, and every doc is read exactly once per run:
//   POST { pageToken? }  ->  { success, migrated, skipped, failed, failures[], nextPageToken? }
// The admin panel keeps calling with `nextPageToken` until it is absent.
//
// Safe to re-run: docs already on R2 are skipped. A prompt whose image cannot be
// fetched keeps its old URL and is flagged `needsCleanup: true` so it shows up in
// the admin "Needs Cleanup" filter.

import {
  authenticate,
  corsHeaders,
  errorResponse,
  getDoc,
  HttpError,
  json,
  listDocs,
  runTransaction,
} from "../_shared/lib.ts";
import { sniffImageMime } from "../_shared/image.ts";
import { bytesToB64, extFor, isR2Url, r2Configured, storeImageR2 } from "../_shared/storage.ts";

const PAGE_SIZE = 20;
const CONCURRENCY = 5;
const MAX_BYTES = 8 * 1024 * 1024;
const MIN_BYTES = 2 * 1024; // smaller than this is almost certainly an error placeholder, not a template

/** Only public https URLs: never internal addresses (SSRF guard). */
function assertPublicHttps(raw: string): URL {
  let url: URL;
  try {
    url = new URL(raw);
  } catch (_e) {
    throw new Error("not a valid URL");
  }
  const host = url.hostname.toLowerCase();
  const isPrivate = host === "localhost" || host.endsWith(".local") || host.endsWith(".internal") ||
    /^(127\.|10\.|192\.168\.|169\.254\.|0\.)/.test(host) || /^172\.(1[6-9]|2\d|3[01])\./.test(host) ||
    host === "[::1]" || host.startsWith("[");
  if (url.protocol !== "https:" || isPrivate) throw new Error("only public https URLs are allowed");
  return url;
}

type Outcome = { kind: "migrated" } | { kind: "skipped" } | { kind: "failed"; reason: string };

async function migrateOne(id: string, imageUrl: unknown): Promise<Outcome> {
  if (typeof imageUrl !== "string" || imageUrl.trim() === "") return { kind: "skipped" };
  if (isR2Url(imageUrl)) return { kind: "skipped" };

  try {
    const url = assertPublicHttps(imageUrl);
    const res = await fetch(url, { redirect: "error", signal: AbortSignal.timeout(25_000) });
    if (!res.ok) {
      await res.body?.cancel();
      throw new Error(`source HTTP ${res.status}`);
    }
    const bytes = new Uint8Array(await res.arrayBuffer());
    if (bytes.length > MAX_BYTES) throw new Error("source image too large");
    if (bytes.length < MIN_BYTES) throw new Error("source image suspiciously small (placeholder?)");
    const mime = sniffImageMime(bytesToB64(bytes.subarray(0, 24)));
    if (!mime) throw new Error("source is not a JPG/PNG/WebP image");

    const newUrl = await storeImageR2(bytes, mime, `prompts/${id}.${extFor(mime)}`);
    if (!newUrl) throw new Error("R2 upload failed");

    await runTransaction(async (tx) => {
      tx.update(`prompts/${id}`, { imageUrl: newUrl, legacyImageUrl: imageUrl });
    });
    return { kind: "migrated" };
  } catch (e) {
    const reason = e instanceof Error ? e.message : String(e);
    console.error(`migrate ${id} failed: ${reason} | ${String(imageUrl).slice(0, 120)}`);
    try {
      await runTransaction(async (tx) => {
        tx.update(`prompts/${id}`, { imageFailed: true });
      });
    } catch (_e) {
      // flagging is best-effort
    }
    return { kind: "failed", reason };
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ success: false, error: "Method not allowed" }, 405);

  try {
    const auth = await authenticate(req);
    if ((await getDoc(`admins/${auth.uid}`)) === null) {
      throw new HttpError(403, "Admin access required", "FORBIDDEN");
    }
    if (!r2Configured()) {
      throw new HttpError(503, "R2 is not configured (check the R2_* secrets).", "NOT_CONFIGURED");
    }

    const body = await req.json().catch(() => ({})) as Record<string, unknown>;
    const pageToken = typeof body?.pageToken === "string" && body.pageToken ? body.pageToken : undefined;

    const page = await listDocs("prompts", PAGE_SIZE, pageToken);

    let migrated = 0;
    let skipped = 0;
    let failed = 0;
    const failures: { id: string; reason: string }[] = [];

    const queue = [...page.docs];
    const workers = Array.from({ length: Math.min(CONCURRENCY, queue.length) }, async () => {
      for (let d = queue.shift(); d; d = queue.shift()) {
        const out = await migrateOne(d.id, d.data.imageUrl);
        if (out.kind === "migrated") migrated++;
        else if (out.kind === "skipped") skipped++;
        else {
          failed++;
          if (failures.length < 20) failures.push({ id: d.id, reason: out.reason });
        }
      }
    });
    await Promise.all(workers);

    return json({ success: true, migrated, skipped, failed, failures, nextPageToken: page.nextPageToken ?? null });
  } catch (err) {
    return errorResponse(err);
  }
});
