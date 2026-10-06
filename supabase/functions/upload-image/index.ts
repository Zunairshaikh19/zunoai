// Authenticated image upload proxy (profile pictures, support attachments).
// The ImgBB API key lives only on the server — it is no longer compiled into
// the mobile app — and uploads are size/type checked.
//
// POST { imageBase64 }  ->  { success, url }

import {
  authenticate,
  corsHeaders,
  errorResponse,
  HttpError,
  json,
  requireBody,
} from "../_shared/lib.ts";
import { sniffImageMime } from "../_shared/image.ts";

const IMGBB_API_KEY = Deno.env.get("IMGBB_API_KEY") ?? "";
const MAX_B64_CHARS = 3_000_000; // ~2.2 MB decoded

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ success: false, error: "Method not allowed" }, 405);

  try {
    await authenticate(req);
    const body = requireBody<Record<string, unknown>>(await req.json().catch(() => null));
    const image = body.imageBase64;
    if (typeof image !== "string" || image.length === 0) {
      throw new HttpError(400, "Image is required", "BAD_REQUEST");
    }
    if (image.length > MAX_B64_CHARS) {
      throw new HttpError(413, "Image is too large (max ~2 MB).", "IMAGE_TOO_LARGE");
    }
    if (!sniffImageMime(image)) {
      throw new HttpError(400, "Unsupported image format. Use JPG or PNG.", "BAD_IMAGE");
    }
    if (!IMGBB_API_KEY) throw new HttpError(503, "Uploads are temporarily unavailable.", "NOT_CONFIGURED");

    const form = new URLSearchParams();
    form.append("image", image);
    const res = await fetch(`https://api.imgbb.com/1/upload?key=${IMGBB_API_KEY}`, {
      method: "POST",
      body: form,
      signal: AbortSignal.timeout(30_000),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok || !data?.data?.url) {
      console.error(`upload-image failed: HTTP ${res.status}`);
      throw new HttpError(502, "Upload failed. Please try again.", "UPLOAD_FAILED");
    }
    return json({ success: true, url: data.data.url as string });
  } catch (err) {
    return errorResponse(err);
  }
});
