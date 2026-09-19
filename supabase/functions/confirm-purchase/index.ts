import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { importPKCS8, SignJWT, createRemoteJWKSet, jwtVerify } from "npm:jose@5";

const FIREBASE_PROJECT_ID = "zunoai-b924f";
const SERVICE_ACCOUNT_KEY = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_KEY") ?? "";

// Known store product IDs -> what they grant. Extend this as new SKUs are added.
const PRODUCTS: Record<string, { days: number; bonusCoins: number }> = {
  zuno_premium_monthly: { days: 30, bonusCoins: 100 },
};

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
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) return cachedToken.token;
  if (!SERVICE_ACCOUNT_KEY) throw new Error("Server misconfigured: FIREBASE_SERVICE_ACCOUNT_KEY is not set");
  const creds = JSON.parse(SERVICE_ACCOUNT_KEY);
  const privateKey = await importPKCS8(creds.private_key, "RS256");
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/datastore" })
    .setProtectedHeader({ alg: "RS256" })
    .setIssuer(creds.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(privateKey);

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  const data = await res.json();
  if (!res.ok || !data.access_token) throw new Error("Failed to obtain service account access token");
  cachedToken = { token: data.access_token, expiresAt: Date.now() + data.expires_in * 1000 };
  return data.access_token;
}

async function firestoreFetch(path: string, init: RequestInit = {}) {
  const token = await getServiceAccountAccessToken();
  return fetch(
    `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/${path}`,
    { ...init, headers: { ...(init.headers ?? {}), Authorization: `Bearer ${token}`, "Content-Type": "application/json" } }
  );
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return json({ success: false, error: "Missing or invalid authorization token" }, 401);
    }

    let uid: string;
    try {
      uid = await verifyFirebaseIdToken(authHeader.split("Bearer ")[1]);
    } catch {
      return json({ success: false, error: "Invalid or expired Firebase token" }, 401);
    }

    const { productId, purchaseToken } = await req.json();
    const plan = PRODUCTS[productId];
    if (!plan) return json({ success: false, error: "Unknown product" }, 400);
    if (!purchaseToken) return json({ success: false, error: "Missing purchase token" }, 400);

    // NOTE: This does not yet perform server-side receipt validation against
    // the Google Play Developer API / Apple App Store Server API — that
    // requires store credentials that aren't configured yet. Add that check
    // here before shipping to production; for now this trusts that the
    // client only calls this endpoint after the store SDK reports a
    // successful purchase.

    // Idempotency guard: a given purchase token can only grant premium once,
    // so replaying the same purchase (e.g. a retried network call) can't
    // stack extra coins or extend the expiry twice.
    const dedupeRes = await firestoreFetch(`processedPurchases/${encodeURIComponent(purchaseToken)}`);
    if (dedupeRes.status === 200) {
      return json({ success: false, error: "This purchase was already processed" }, 409);
    }

    const userRes = await firestoreFetch(`users/${uid}`);
    const userData = await userRes.json();
    const currentCoins = parseInt(userData?.fields?.coins?.integerValue || "0", 10);
    const now = Date.now();
    const existingExpiry = userData?.fields?.premiumExpiresAt?.timestampValue
      ? new Date(userData.fields.premiumExpiresAt.timestampValue).getTime()
      : 0;
    const newExpiry = new Date(Math.max(now, existingExpiry) + plan.days * 24 * 60 * 60 * 1000);

    await firestoreFetch(`users/${uid}?updateMask.fieldPaths=tier&updateMask.fieldPaths=premiumExpiresAt&updateMask.fieldPaths=coins`, {
      method: "PATCH",
      body: JSON.stringify({
        fields: {
          tier: { stringValue: "paid" },
          premiumExpiresAt: { timestampValue: newExpiry.toISOString() },
          coins: { integerValue: (currentCoins + plan.bonusCoins).toString() },
        },
      }),
    });

    await firestoreFetch(`processedPurchases/${encodeURIComponent(purchaseToken)}`, {
      method: "PATCH",
      body: JSON.stringify({
        fields: {
          uid: { stringValue: uid },
          productId: { stringValue: productId },
          processedAt: { timestampValue: new Date().toISOString() },
        },
      }),
    });

    return json({ success: true, premiumExpiresAt: newExpiry.toISOString() });
  } catch (err: any) {
    return json({ success: false, error: err.message || "Internal server error" }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}
