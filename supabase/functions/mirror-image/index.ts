import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  importPKCS8,
  SignJWT,
  createRemoteJWKSet,
  jwtVerify,
} from "npm:jose@5";

// Server-side proxy so the admin panel's "Bulk Upload JSON" can mirror
// third-party prompt images to ImgBB without hitting browser CORS.
//
// Why this exists: the admin panel is Flutter Web, and a browser tab can
// display an <img> from almost any host, but it can't *read* that image's
// bytes with fetch()/XHR unless the host sends Access-Control-Allow-Origin
// headers — most image buckets (like the R2 bucket this prompt dataset's
// images live on) don't. Downloading here instead is a plain server-to-
// server fetch with no CORS involved at all, so it always works regardless
// of what the source host does or doesn't send.
//
// Admin-only: verifies the caller's Firebase ID token and requires an
// `admins/{uid}` doc to exist, same as the app's generate-image function
// requires a signed-in user.

const IMGBB_API_KEY = Deno.env.get("IMGBB_API_KEY") ?? "";
const FIREBASE_PROJECT_ID = "zunoai-b924f";
const SERVICE_ACCOUNT_KEY = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_KEY") ?? "";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

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

async function isAdmin(uid: string): Promise<boolean> {
  const token = await getServiceAccountAccessToken();
  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/admins/${uid}`,
    { headers: { Authorization: `Bearer ${token}` } }
  );
  return res.status === 200;
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

    if (!(await isAdmin(uid))) {
      return new Response(
        JSON.stringify({ success: false, error: "Admin access required" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { imageUrl } = await req.json();
    if (!imageUrl || typeof imageUrl !== "string") {
      return new Response(
        JSON.stringify({ success: false, error: "imageUrl is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Plain server-to-server fetch — no browser, no CORS involved.
    const imgRes = await fetch(imageUrl);
    if (!imgRes.ok) {
      return new Response(
        JSON.stringify({ success: false, error: `Source image fetch failed: HTTP ${imgRes.status}` }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    const imgBytes = new Uint8Array(await imgRes.arrayBuffer());

    const form = new FormData();
    form.append("image", new Blob([imgBytes]), "prompt.jpg");

    const uploadRes = await fetch(`https://api.imgbb.com/1/upload?key=${IMGBB_API_KEY}`, {
      method: "POST",
      body: form,
    });
    const uploadData = await uploadRes.json();

    if (!uploadRes.ok || !uploadData?.data?.url) {
      return new Response(
        JSON.stringify({ success: false, error: `ImgBB upload failed: ${JSON.stringify(uploadData).slice(0, 300)}` }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ success: true, imageUrl: uploadData.data.url }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: any) {
    console.error(`Unhandled error in mirror-image: ${err.message}`);
    return new Response(
      JSON.stringify({ success: false, error: err.message || "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
