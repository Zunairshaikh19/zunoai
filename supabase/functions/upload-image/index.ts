// Authenticated image upload proxy (profile pictures, support attachments).
// Storage credentials (Cloudflare R2, ImgBB fallback) live only on the server —
// never in the mobile app — and uploads are size/type checked.
//
// POST { imageBase64 }  ->  { success, url }

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
import { b64ToBytes, extFor, storageConfigured, storeImage } from "../_shared/storage.ts";

const MAX_B64_CHARS = 3_000_000; // ~2.2 MB decoded (profile pictures, support attachments)
const MAX_B64_CHARS_ADMIN = 11_500_000; // ~8 MB decoded (admin template images)

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ success: false, error: "Method not allowed" }, 405);

  try {
    const auth = await authenticate(req);
    const body = requireBody<Record<string, unknown>>(await req.json().catch(() => null));
    const image = body.imageBase64;
    if (typeof image !== "string" || image.length === 0) {
      throw new HttpError(400, "Image is required", "BAD_REQUEST");
    }
    // Admin panel template uploads: { purpose: "prompt" } -> admin only, bigger limit, prompts/ prefix.
    const isPromptUpload = body.purpose === "prompt";
    if (isPromptUpload && (await getDoc(`admins/${auth.uid}`)) === null) {
      throw new HttpError(403, "Admin access required", "FORBIDDEN");
    }
    if (image.length > (isPromptUpload ? MAX_B64_CHARS_ADMIN : MAX_B64_CHARS)) {
      throw new HttpError(413, "Image is too large (max ~2 MB).", "IMAGE_TOO_LARGE");
    }
    const mime = sniffImageMime(image);
    if (!mime) {
      throw new HttpError(400, "Unsupported image format. Use JPG or PNG.", "BAD_IMAGE");
    }
    if (!storageConfigured()) throw new HttpError(503, "Uploads are temporarily unavailable.", "NOT_CONFIGURED");

    const url = await storeImage(
      b64ToBytes(image),
      mime,
      `${isPromptUpload ? "prompts" : `uploads/${auth.uid}`}/${crypto.randomUUID()}.${extFor(mime)}`,
    );
    if (!url) {
      console.error("upload-image: storage upload failed");
      throw new HttpError(502, "Upload failed. Please try again.", "UPLOAD_FAILED");
    }
    return json({ success: true, url });
  } catch (err) {
    return errorResponse(err);
  }
});
