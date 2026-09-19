import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  importPKCS8,
  SignJWT,
  createRemoteJWKSet,
  jwtVerify,
} from "npm:jose@5";

const IMGBB_API_KEY = Deno.env.get("IMGBB_API_KEY") ?? "";
const FIREBASE_PROJECT_ID = "zunoai-b924f";
const DEFAULT_COIN_COST = 40;

// Used only if the admin hasn't picked a model in settings/config.generationModel.
const DEFAULT_MODEL = "google/gemini-3.1-flash-image";

// Service account JSON (Firebase Console -> Project Settings -> Service accounts -> Generate new private key)
// Set via: supabase secrets set FIREBASE_SERVICE_ACCOUNT_KEY='<paste full JSON here>'
const SERVICE_ACCOUNT_KEY = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_KEY") ?? "";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Verifies the Firebase ID token's signature against Google's public keys (not just decoding it).
const firebaseJwks = createRemoteJWKSet(
  new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com")
);

async function verifyFirebaseIdToken(idToken: string): Promise<string> {
  const { payload } = await jwtVerify(idToken, firebaseJwks, {
    issuer: `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`,
    audience: FIREBASE_PROJECT_ID,
  });
  const uid = (payload.user_id as string) || (payload.sub as string);
  if (!uid) throw new Error("Token missing uid");
  return uid;
}

// Exchanges the service account key for a short-lived Google OAuth access token,
// so the function can read/write Firestore server-side without going through client security rules.
let cachedToken: { token: string; expiresAt: number } | null = null;

async function getServiceAccountAccessToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) {
    return cachedToken.token;
  }
  if (!SERVICE_ACCOUNT_KEY) {
    throw new Error("Server misconfigured: FIREBASE_SERVICE_ACCOUNT_KEY is not set");
  }
  const creds = JSON.parse(SERVICE_ACCOUNT_KEY);
  const privateKey = await importPKCS8(creds.private_key, "RS256");

  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/datastore",
  })
    .setProtectedHeader({ alg: "RS256" })
    .setIssuer(creds.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(privateKey);

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const data = await res.json();
  if (!res.ok || !data.access_token) {
    throw new Error("Failed to obtain service account access token");
  }
  cachedToken = { token: data.access_token, expiresAt: Date.now() + data.expires_in * 1000 };
  return data.access_token;
}

async function firestoreFetch(path: string, init: RequestInit = {}) {
  const token = await getServiceAccountAccessToken();
  return fetch(
    `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/${path}`,
    {
      ...init,
      headers: {
        ...(init.headers ?? {}),
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
    }
  );
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ success: false, error: "Missing or invalid authorization token" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const idToken = authHeader.split("Bearer ")[1];

    let uid: string;
    try {
      uid = await verifyFirebaseIdToken(idToken);
    } catch (_e) {
      return new Response(
        JSON.stringify({ success: false, error: "Invalid or expired Firebase token" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { prompt, referenceImageBase64, referenceImageBase64_2, templateImageUrl } = await req.json();
    if (!prompt) {
      return new Response(
        JSON.stringify({ success: false, error: "Prompt is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 1. Read the OpenRouter key + which model the admin picked (service-account authenticated)
    const configRes = await firestoreFetch("settings/config");
    const configData = await configRes.json();
    const apiKey = configData?.fields?.openRouterApiKey?.stringValue;
    const model = configData?.fields?.generationModel?.stringValue || DEFAULT_MODEL;

    if (!apiKey) {
      return new Response(
        JSON.stringify({ success: false, error: "Server API Key config missing" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 2. Read the admin-configurable generation cost (falls back if unset)
    const economyRes = await firestoreFetch("settings/economy");
    const economyData = await economyRes.json();
    const coinCost = parseInt(economyData?.fields?.generationCost?.integerValue || "", 10) || DEFAULT_COIN_COST;

    // 3. Read user coins from Firestore (service-account authenticated)
    const userRes = await firestoreFetch(`users/${uid}`);
    const userData = await userRes.json();
    const currentCoins = parseInt(userData?.fields?.coins?.integerValue || "0", 10);
    const isBlocked = userData?.fields?.isBlocked?.booleanValue === true;

    if (isBlocked) {
      return new Response(
        JSON.stringify({ success: false, error: "This account has been blocked." }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (currentCoins < coinCost) {
      return new Response(
        JSON.stringify({ success: false, error: `Insufficient coins. You need at least ${coinCost} coins.` }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 4. Deduct coins
    const newCoins = currentCoins - coinCost;
    await updateFirestoreCoins(uid, newCoins);

    // 5. Generate the image via OpenRouter — the reference photo (if any) is
    // sent alongside the prompt so the model conditions on the user's actual
    // face/photo instead of generating something generic. When the gallery
    // template's own image is available (templateImageUrl), it's sent too so
    // the model copies its exact pose/clothing/background/composition instead
    // of freely reinterpreting the text prompt — this is what keeps a user's
    // result looking like the template they picked, not a different render
    // each time. The model itself is whatever the admin picked in
    // settings/config.generationModel, so switching providers/models never
    // needs a redeploy.
    let imageUrl: string | null = null;
    let lastError: string | null = null;

    for (let attempt = 0; attempt < 2 && !imageUrl; attempt++) {
      const result = await tryGenerateViaOpenRouter(
        model,
        prompt,
        apiKey,
        referenceImageBase64,
        referenceImageBase64_2,
        templateImageUrl
      );
      imageUrl = result.imageUrl;
      lastError = result.error;
    }

    // 6. If image generation failed, refund coins
    if (!imageUrl) {
      // Full reason goes to the server console only — end users get a clean
      // generic message; use `supabase functions deploy` logs / dashboard to
      // see `lastError` for real debugging.
      console.error(`Generation failed for uid=${uid}, model=${model}: ${lastError}`);
      await updateFirestoreCoins(uid, currentCoins);
      return new Response(
        JSON.stringify({
          success: false,
          error: `Image generation failed. ${coinCost} coins refunded.`,
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ success: true, imageUrl }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: any) {
    console.error(`Unhandled error: ${err.message}`);
    return new Response(
      JSON.stringify({ success: false, error: err.message || "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

async function updateFirestoreCoins(uid: string, coins: number) {
  await firestoreFetch(`users/${uid}?updateMask.fieldPaths=coins`, {
    method: "PATCH",
    body: JSON.stringify({
      fields: {
        coins: { integerValue: coins.toString() },
      },
    }),
  });
}

async function tryGenerateViaOpenRouter(
  model: string,
  prompt: string,
  apiKey: string,
  referenceImageBase64?: string,
  referenceImageBase64_2?: string,
  templateImageUrl?: string
): Promise<{ imageUrl: string | null; error: string | null }> {
  try {
    const content: Record<string, unknown>[] = [];
    const hasTemplate = !!templateImageUrl;
    const hasImage1 = !!referenceImageBase64;
    const hasImage2 = !!referenceImageBase64_2;

    // Build the instruction text first, tailored to exactly which images are
    // being sent, then push the images in the same order the text refers to
    // them by ("the template image", "the first/second photo").
    let text: string;
    if (hasTemplate && hasImage1 && hasImage2) {
      // Couple prompt, two separate photos: swap two faces into the template
      // while keeping the template's own pose/clothing/background/composition.
      text =
        `Image 1 is a reference template showing two people together. Image 2 and Image 3 are real photos of two different people. ` +
        `Recreate Image 1 exactly — same pose, clothing style, background, lighting, composition and framing — but replace the two subjects' faces and identities: ` +
        `the person in Image 2 becomes the first/left subject, and the person in Image 3 becomes the second/right subject. ` +
        `Preserve each person's real facial features, skin tone, and apparent gender exactly as shown in their own photo — do not swap, blend, or alter their gender presentation. ` +
        `Style notes: ${prompt}`;
    } else if (hasTemplate && hasImage1) {
      // Single subject (or a couple already together in one photo) matched
      // against a template image.
      text =
        `Image 1 is a reference template image. Image 2 is a real photo of the actual person (or people) to feature. ` +
        `Recreate Image 1 exactly — same pose, clothing style, background, lighting, composition and framing — but replace the subject's face and identity with the person shown in Image 2. ` +
        `If Image 2 shows two people together, replace both subjects in Image 1 with those same two people, matching them left-to-right as they appear. ` +
        `Preserve their real facial features, skin tone, and apparent gender exactly as shown in Image 2 — do not alter their gender presentation. ` +
        `Style notes: ${prompt}`;
    } else if (hasImage1) {
      // No template available — fall back to the original text-driven look.
      text = `Using the person in the provided image as the subject, transform them into: ${prompt}. Keep the person's identity, facial features, and apparent gender recognizable and unchanged.`;
    } else {
      text = `Generate an image: ${prompt}`;
    }
    content.push({ type: "text", text });

    if (hasTemplate) {
      content.push({ type: "image_url", image_url: { url: templateImageUrl } });
    }
    if (hasImage1) {
      content.push({
        type: "image_url",
        image_url: { url: `data:image/jpeg;base64,${referenceImageBase64}` },
      });
    }
    if (hasImage2) {
      content.push({
        type: "image_url",
        image_url: { url: `data:image/jpeg;base64,${referenceImageBase64_2}` },
      });
    }

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
  } catch (e: any) {
    return { imageUrl: null, error: e.message };
  }
}

async function uploadToImgBB(base64Image: string): Promise<string | null> {
  try {
    const body = new URLSearchParams();
    body.append("image", base64Image);

    const res = await fetch(`https://api.imgbb.com/1/upload?key=${IMGBB_API_KEY}`, {
      method: "POST",
      body,
    });
    const data = await res.json();
    if (res.ok && data.data?.url) {
      return data.data.url;
    }
  } catch (_e) {
    // upload failed
  }
  return null;
}
