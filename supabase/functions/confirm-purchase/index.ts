// Premium activation with REAL receipt verification against the Google Play
// Developer API. A made-up purchase token is rejected by Google, so nobody can
// get premium without a genuine, active Play subscription.
//
// POST { productId, purchaseToken }   -> verify + activate
// POST { refresh: true }              -> re-check the stored subscription
//                                        (renewals, cancellations, refunds)
//
// Requirements (see PRODUCTION_CHECKLIST.md):
//  * A service account invited to Play Console -> Setup -> API access with
//    "View financial data" + "Manage orders and subscriptions".
//  * Secret PLAY_SERVICE_ACCOUNT_KEY (falls back to FIREBASE_SERVICE_ACCOUNT_KEY
//    if that account was granted the Play permissions).

import {
  ANDROID_PACKAGE,
  applyLazyState,
  asInt,
  authenticate,
  corsHeaders,
  type Doc,
  errorResponse,
  getAccessToken,
  getDoc,
  HttpError,
  json,
  loadEconomy,
  premiumDailyCoins,
  requireBody,
  runTransaction,
  SCOPE_PLAY,
  sha256Hex,
} from "../_shared/lib.ts";

const PLAY_KEY = Deno.env.get("PLAY_SERVICE_ACCOUNT_KEY") ?? Deno.env.get("FIREBASE_SERVICE_ACCOUNT_KEY") ?? "";

// productId -> plan. Create these subscriptions in Play Console with the same ids.
const PRODUCTS: Record<string, { plan: "monthly" | "yearly" }> = {
  zuno_premium_monthly: { plan: "monthly" },
  zuno_premium_yearly: { plan: "yearly" },
};

const ENTITLED_STATES = new Set([
  "SUBSCRIPTION_STATE_ACTIVE",
  "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
  "SUBSCRIPTION_STATE_CANCELED", // cancelled but paid-through until expiry
]);

interface PlayResult {
  entitled: boolean;
  expiry: Date | null;
  productId: string;
  orderId: string;
  ackPending: boolean;
  state: string;
}

async function verifyWithPlay(purchaseToken: string): Promise<PlayResult> {
  const token = await getAccessToken(SCOPE_PLAY, PLAY_KEY);
  const res = await fetch(
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${ANDROID_PACKAGE}` +
      `/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`,
    { headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(20_000) },
  );
  if (res.status === 400 || res.status === 404 || res.status === 410) {
    await res.body?.cancel();
    throw new HttpError(400, "This purchase could not be verified.", "INVALID_PURCHASE");
  }
  if (!res.ok) {
    const detail = (await res.text()).slice(0, 300);
    console.error(`Play API error ${res.status}: ${detail}`);
    throw new HttpError(503, "Purchase verification is temporarily unavailable. Please try again.", "PLAY_UNAVAILABLE");
  }
  const data = await res.json();
  const item = (data.lineItems ?? [])[0] ?? {};
  const expiry = item.expiryTime ? new Date(item.expiryTime) : null;
  const state = String(data.subscriptionState ?? "");
  const entitled = ENTITLED_STATES.has(state) && expiry !== null && expiry.getTime() > Date.now();
  return {
    entitled,
    expiry,
    productId: String(item.productId ?? ""),
    orderId: String(data.latestOrderId ?? ""),
    ackPending: data.acknowledgementState === "ACKNOWLEDGEMENT_STATE_PENDING",
    state,
  };
}

async function acknowledge(productId: string, purchaseToken: string): Promise<void> {
  try {
    const token = await getAccessToken(SCOPE_PLAY, PLAY_KEY);
    const res = await fetch(
      `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${ANDROID_PACKAGE}` +
        `/purchases/subscriptions/${productId}/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`,
      {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: "{}",
        signal: AbortSignal.timeout(20_000),
      },
    );
    await res.body?.cancel();
    if (!res.ok) console.error(`Acknowledge failed (${res.status}) for ${productId}`);
  } catch (e) {
    console.error(`Acknowledge error: ${e instanceof Error ? e.message : e}`);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ success: false, error: "Method not allowed" }, 405);

  try {
    const auth = await authenticate(req);
    const uid = auth.uid;
    const body = requireBody<Record<string, unknown>>(await req.json().catch(() => null));

    if (body.platform === "ios") {
      throw new HttpError(501, "iOS purchases are not available yet.", "UNSUPPORTED_PLATFORM");
    }

    // ---- Refresh the stored subscription (renewal / cancel / refund) ----
    if (body.refresh === true) {
      const sub = await getDoc(`subscriptions/${uid}`);
      const storedToken = typeof sub?.purchaseToken === "string" ? sub.purchaseToken : "";
      if (!storedToken) return json({ success: true, premium: false });

      const verified = await verifyWithPlay(storedToken);
      await runTransaction(async (tx) => {
        const user = await tx.get(`users/${uid}`);
        if (!user) return;
        if (verified.entitled && verified.expiry) {
          tx.update(`users/${uid}`, { tier: "paid", premiumExpiresAt: verified.expiry });
        } else {
          tx.update(`users/${uid}`, { tier: "free", premiumExpiresAt: null });
        }
      });
      return json({
        success: true,
        premium: verified.entitled,
        premiumExpiresAt: verified.expiry?.toISOString() ?? null,
      });
    }

    // ---- Activate a new purchase ----
    const productId = String(body.productId ?? "");
    const purchaseToken = String(body.purchaseToken ?? "");
    const plan = PRODUCTS[productId];
    if (!plan) throw new HttpError(400, "Unknown product", "UNKNOWN_PRODUCT");
    if (purchaseToken.length < 20 || purchaseToken.length > 2048) {
      throw new HttpError(400, "Missing purchase token", "BAD_REQUEST");
    }

    const verified = await verifyWithPlay(purchaseToken);
    if (verified.productId !== productId) {
      throw new HttpError(400, "This purchase does not match the selected plan.", "PRODUCT_MISMATCH");
    }
    if (!verified.entitled || !verified.expiry) {
      throw new HttpError(402, "This subscription is not active.", "NOT_ACTIVE");
    }
    const expiry = verified.expiry;

    const tokenHash = await sha256Hex(purchaseToken);
    await runTransaction(async (tx) => {
      const eco = await loadEconomy(tx);
      const tokenDoc: Doc | null = await tx.get(`purchaseTokens/${tokenHash}`);
      if (tokenDoc && tokenDoc.uid !== uid) {
        throw new HttpError(409, "This purchase is already linked to another account.", "TOKEN_LINKED");
      }
      const user = await tx.get(`users/${uid}`);
      if (!user) throw new HttpError(404, "Profile not found", "NO_PROFILE");

      const now = new Date();
      const patch = applyLazyState(user, eco, now);
      let coins = "coins" in patch ? asInt(patch.coins) : asInt(user.coins);
      const userUpdate: Doc = { ...patch, tier: "paid", premiumExpiresAt: expiry, premiumPlan: plan.plan };

      // First activation of this purchase: hand over today's premium allowance
      // right away (once). Re-syncs/restores of the same token grant nothing.
      if (!tokenDoc) {
        coins += premiumDailyCoins({ premiumPlan: plan.plan }, eco);
        userUpdate.lastDailyReset = now;
        userUpdate.dailyAdsWatched = 0;
      }
      userUpdate.coins = coins;
      tx.update(`users/${uid}`, userUpdate);

      tx.merge(`purchaseTokens/${tokenHash}`, {
        uid,
        productId,
        orderId: verified.orderId,
        updatedAt: now,
        ...(tokenDoc ? {} : { createdAt: now }),
      });
      tx.merge(`subscriptions/${uid}`, {
        purchaseToken,
        productId,
        plan: plan.plan,
        updatedAt: now,
      });
    });

    if (verified.ackPending) await acknowledge(productId, purchaseToken);

    return json({ success: true, premiumExpiresAt: expiry.toISOString(), plan: plan.plan });
  } catch (err) {
    return errorResponse(err);
  }
});
