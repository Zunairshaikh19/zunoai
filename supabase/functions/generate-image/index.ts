// Image generation. Everything that costs money is decided here, server-side:
//   * the prompt comes from Firestore (`promptId`), never from the client
//   * the coin charge is an atomic transaction (no parallel-request race)
//   * a failed generation refunds in a transaction (never overwrites newer coins)
//   * the history entry is written here, so a client timeout never loses a paid image
//
// POST { promptId, referenceImageBase64, referenceImageBase64_2? }

import {
  applyLazyState,
  asDate,
  asInt,
  authenticate,
  corsHeaders,
  type Doc,
  errorResponse,
  getDoc,
  HttpError,
  isPremium,
  json,
  loadEconomy,
  requireBody,
  requireVerifiedEmail,
  runTransaction,
  utcDay,
} from "../_shared/lib.ts";
import { sniffImageMime } from "../_shared/image.ts";

const IMGBB_API_KEY = Deno.env.get("IMGBB_API_KEY") ?? "";

// Used only if the admin hasn't picked a model in settings/config.generationModel.
const DEFAULT_MODEL = "google/gemini-3.1-flash-image";

const MAX_IMAGE_B64_CHARS = 4_000_000; // ~3 MB decoded
const MIN_GAP_MS = 4_000; // blocks parallel/burst requests from the same account
const OPENROUTER_TIMEOUT_MS = 100_000;

interface Reference {
  b64: string;
  mime: string;
}

function readReference(value: unknown, label: string): Reference | null {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value !== "string") throw new HttpError(400, `Invalid ${label}`, "BAD_REQUEST");
  if (value.length > MAX_IMAGE_B64_CHARS) {
    throw new HttpError(413, "Photo is too large. Please pick a smaller one.", "IMAGE_TOO_LARGE");
  }
  const mime = sniffImageMime(value);
  if (!mime) throw new HttpError(400, "Unsupported photo format. Use JPG or PNG.", "BAD_IMAGE");
  return { b64: value, mime };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ success: false, error: "Method not allowed" }, 405);

  const startedAt = Date.now();
  let uid = "";
  let jobId = "";
  let cost = 0;

  try {
    const auth = await authenticate(req);
    uid = auth.uid;
    requireVerifiedEmail(auth);

    const body = requireBody<Record<string, unknown>>(await req.json().catch(() => null));
    const promptId = String(body.promptId ?? "");
    if (!/^[A-Za-z0-9_-]{1,128}$/.test(promptId)) {
      throw new HttpError(400, "Prompt is required", "BAD_REQUEST");
    }
    const ref1 = readReference(body.referenceImageBase64, "photo");
    const ref2 = readReference(body.referenceImageBase64_2, "second photo");
    if (!ref1) throw new HttpError(400, "A reference photo is required", "BAD_REQUEST");

    // Prompt + secret prompt text (prompts live in Firestore; the hidden text
    // may be in `promptSecrets` so it is never readable by clients).
    const promptDoc = await getDoc(`prompts/${promptId}`);
    if (!promptDoc || promptDoc.isPublished === false) {
      throw new HttpError(404, "This style is no longer available.", "PROMPT_NOT_FOUND");
    }
    const secret = await getDoc(`promptSecrets/${promptId}`);
    const category = String(promptDoc.category ?? "General");
    const hiddenPrompt = String(secret?.hiddenPrompt ?? promptDoc.hiddenPrompt ?? "").trim() || category;
    const templateImageUrl = typeof promptDoc.imageUrl === "string" && promptDoc.imageUrl.startsWith("https://")
      ? promptDoc.imageUrl
      : undefined;

    // Provider key + model (admin-only doc, read with the service account).
    const config = await getDoc("settings/config");
    const apiKey = typeof config?.openRouterApiKey === "string" ? config.openRouterApiKey : "";
    const model = typeof config?.generationModel === "string" && config.generationModel
      ? config.generationModel
      : DEFAULT_MODEL;
    if (!apiKey) throw new HttpError(503, "Image generation is temporarily unavailable.", "NOT_CONFIGURED");

    // ---- 1. Atomic charge ------------------------------------------------
    jobId = crypto.randomUUID().replaceAll("-", "");
    const charge = await runTransaction(async (tx) => {
      const eco = await loadEconomy(tx);
      const user = await tx.get(`users/${uid}`);
      if (!user) throw new HttpError(404, "Profile not found", "NO_PROFILE");
      if (user.isBlocked === true) throw new HttpError(403, "This account has been blocked.", "BLOCKED");

      const now = new Date();
      const patch = applyLazyState(user, eco, now);
      const merged: Doc = { ...user, ...patch };
      let coins = asInt(merged.coins);

      if (promptDoc.isPremium === true && !isPremium(merged, now)) {
        throw new HttpError(403, "This is a Premium style. Upgrade to use it.", "PREMIUM_ONLY");
      }

      const lastStart = asDate(user.lastGenerationStartedAt);
      if (lastStart && now.getTime() - lastStart.getTime() < MIN_GAP_MS) {
        throw new HttpError(429, "Please wait a few seconds before generating again.", "TOO_FAST");
      }

      const today = utcDay(now);
      const countToday = user.genDay === today ? asInt(user.genCountToday) : 0;
      if (countToday >= eco.maxGenerationsPerDay) {
        throw new HttpError(429, "Daily generation limit reached. Try again tomorrow.", "DAILY_CAP");
      }

      if (coins < eco.generationCost) {
        throw new HttpError(402, `Insufficient coins. You need at least ${eco.generationCost} coins.`, "INSUFFICIENT_COINS");
      }
      coins -= eco.generationCost;

      tx.update(`users/${uid}`, {
        ...patch,
        coins,
        lastGenerationStartedAt: now,
        genDay: today,
        genCountToday: countToday + 1,
      });
      tx.create(`generationJobs/${jobId}`, {
        uid,
        status: "charged",
        cost: eco.generationCost,
        promptId,
        model,
        createdAt: now,
      });
      return { cost: eco.generationCost, coins };
    });
    cost = charge.cost;

    // ---- 2. Generate -----------------------------------------------------
    let imageUrl: string | null = null;
    let lastError: string | null = null;
    for (let attempt = 0; attempt < 2 && !imageUrl; attempt++) {
      // Only retry if there is comfortably time left inside the function's wall-clock limit.
      if (attempt > 0 && Date.now() - startedAt > 45_000) break;
      const result = await tryGenerateViaOpenRouter({
        model,
        prompt: hiddenPrompt,
        apiKey,
        ref1,
        ref2,
        templateImageUrl,
      });
      imageUrl = result.imageUrl;
      lastError = result.error;
    }

    // ---- 3a. Failure: refund atomically ---------------------------------
    if (!imageUrl) {
      console.error(`Generation failed uid=${uid} job=${jobId} model=${model}: ${lastError}`);
      const refunded = await refund(uid, jobId, cost);
      throw new HttpError(
        502,
        refunded
          ? `We couldn't generate this image. ${cost} coins were refunded. Try a different photo.`
          : "We couldn't generate this image. Please contact support.",
        "GENERATION_FAILED",
      );
    }

    // ---- 3b. Success: save history server-side ---------------------------
    try {
      await runTransaction(async (tx) => {
        const now = new Date();
        tx.create(`users/${uid}/history/${jobId}`, {
          outputUrl: imageUrl,
          promptCategory: category,
          timestamp: now,
          status: "success",
          watermarkUnlocked: false,
        });
        tx.update(`generationJobs/${jobId}`, { status: "done", completedAt: now });
      });
    } catch (e) {
      // The user already has the image URL in this response; don't fail the request.
      console.error(`History write failed uid=${uid} job=${jobId}: ${e instanceof Error ? e.message : e}`);
    }

    return json({ success: true, imageUrl, historyId: jobId, coins: charge.coins });
  } catch (err) {
    // Anything thrown after the charge but before success must refund.
    if (jobId && cost > 0 && !(err instanceof HttpError && err.code === "GENERATION_FAILED")) {
      await refund(uid, jobId, cost);
    }
    return errorResponse(err);
  }
});

/** Refunds a charged job exactly once, relative to the *current* balance. */
async function refund(uid: string, jobId: string, cost: number): Promise<boolean> {
  try {
    return await runTransaction(async (tx) => {
      const job = await tx.get(`generationJobs/${jobId}`);
      if (!job || job.status !== "charged") return false; // already done/refunded
      const user = await tx.get(`users/${uid}`);
      if (!user) return false;
      tx.update(`users/${uid}`, { coins: asInt(user.coins) + cost });
      tx.update(`generationJobs/${jobId}`, { status: "refunded", completedAt: new Date() });
      return true;
    });
  } catch (e) {
    console.error(`REFUND FAILED uid=${uid} job=${jobId}: ${e instanceof Error ? e.message : e}`);
    return false;
  }
}

interface GenerateArgs {
  model: string;
  prompt: string;
  apiKey: string;
  ref1: Reference;
  ref2: Reference | null;
  templateImageUrl?: string;
}

async function tryGenerateViaOpenRouter(
  { model, prompt, apiKey, ref1, ref2, templateImageUrl }: GenerateArgs,
): Promise<{ imageUrl: string | null; error: string | null }> {
  try {
    const content: Record<string, unknown>[] = [];
    const hasTemplate = !!templateImageUrl;
    const hasImage2 = !!ref2;

    // Instruction text first, tailored to exactly which images are sent; then
    // the images in the same order the text refers to them by.
    let text: string;
    if (hasTemplate && hasImage2) {
      text =
        `Image 1 is a reference template showing two people together. Image 2 and Image 3 are real photos of two different people. ` +
        `Recreate Image 1 exactly — same pose, clothing style, background, lighting, composition and framing — but replace the two subjects' faces and identities: ` +
        `the person in Image 2 becomes the first/left subject, and the person in Image 3 becomes the second/right subject. ` +
        `Preserve each person's real facial features, skin tone, and apparent gender exactly as shown in their own photo — do not swap, blend, or alter their gender presentation. ` +
        `Style notes: ${prompt}`;
    } else if (hasTemplate) {
      text =
        `Image 1 is a reference template image. Image 2 is a real photo of the actual person (or people) to feature. ` +
        `Recreate Image 1 exactly — same pose, clothing style, background, lighting, composition and framing — but replace the subject's face and identity with the person shown in Image 2. ` +
        `If Image 2 shows two people together, replace both subjects in Image 1 with those same two people, matching them left-to-right as they appear. ` +
        `Preserve their real facial features, skin tone, and apparent gender exactly as shown in Image 2 — do not alter their gender presentation. ` +
        `Style notes: ${prompt}`;
    } else {
      text =
        `Using the person in the provided image as the subject, transform them into: ${prompt}. ` +
        `Keep the person's identity, facial features, and apparent gender recognizable and unchanged.`;
    }
    content.push({ type: "text", text });

    if (hasTemplate) content.push({ type: "image_url", image_url: { url: templateImageUrl } });
    content.push({ type: "image_url", image_url: { url: `data:${ref1.mime};base64,${ref1.b64}` } });
    if (ref2) content.push({ type: "image_url", image_url: { url: `data:${ref2.mime};base64,${ref2.b64}` } });

    const res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
        "HTTP-Referer": "https://zunoai.app",
        "X-Title": "Zuno AI",
      },
      body: JSON.stringify({
        model,
        messages: [{ role: "user", content }],
        modalities: ["image", "text"],
      }),
      signal: AbortSignal.timeout(OPENROUTER_TIMEOUT_MS),
    });
    const data = await res.json();

    if (!res.ok) {
      return { imageUrl: null, error: `HTTP ${res.status}: ${JSON.stringify(data).slice(0, 500)}` };
    }

    const images = data.choices?.[0]?.message?.images;
    if (Array.isArray(images) && images.length > 0) {
      const dataUrl: string | undefined = images[0]?.image_url?.url;
      const base64 = dataUrl?.split(",")[1];
      if (base64) {
        const imageUrl = await uploadToImgBB(base64);
        return { imageUrl, error: imageUrl ? null : "ImgBB upload failed" };
      }
    }
    return { imageUrl: null, error: `No image in response: ${JSON.stringify(data).slice(0, 500)}` };
  } catch (e) {
    return { imageUrl: null, error: e instanceof Error ? e.message : String(e) };
  }
}

async function uploadToImgBB(base64Image: string): Promise<string | null> {
  try {
    const body = new URLSearchParams();
    body.append("image", base64Image);
    const res = await fetch(`https://api.imgbb.com/1/upload?key=${IMGBB_API_KEY}`, {
      method: "POST",
      body,
      signal: AbortSignal.timeout(30_000),
    });
    const data = await res.json();
    if (res.ok && data.data?.url) return data.data.url as string;
  } catch (_e) {
    // upload failed
  }
  return null;
}
