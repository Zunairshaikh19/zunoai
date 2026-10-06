// AdMob Server-Side Verification (SSV) callback for rewarded ads.
//
// Google calls this URL (GET) after a user *really* finishes a rewarded ad,
// signed with Google's private key. We verify the signature, de-duplicate on
// transaction_id, enforce the daily ad limit, and credit the coins in one
// Firestore transaction. The app never credits ad coins itself.
//
// Configure in AdMob console: Apps -> your app -> Ad units -> your rewarded
// unit -> Server-side verification -> Callback URL:
//   https://<project-ref>.supabase.co/functions/v1/admob-ssv
//
// Optional secret: ADMOB_REWARDED_AD_UNIT_IDS="1234567890,0987654321" (the
// numeric ids at the end of ca-app-pub-XXX/<id>). If set, callbacks from other
// ad units are ignored.

import { b64ToBytes, derToRaw, signedMessage } from "../_shared/admob.ts";
import {
  adLimitFor,
  applyLazyState,
  asInt,
  type Doc,
  loadEconomy,
  runTransaction,
} from "../_shared/lib.ts";

const KEYS_URL = "https://www.gstatic.com/admob/reward/verifier-keys.json";
const ALLOWED_UNITS = (Deno.env.get("ADMOB_REWARDED_AD_UNIT_IDS") ?? "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

let keyCache: { keys: Map<string, string>; fetchedAt: number } | null = null;

async function getVerifierKeys(forceRefresh = false): Promise<Map<string, string>> {
  if (!forceRefresh && keyCache && Date.now() - keyCache.fetchedAt < 6 * 60 * 60 * 1000) {
    return keyCache.keys;
  }
  const res = await fetch(KEYS_URL);
  if (!res.ok) throw new Error("Could not fetch AdMob verifier keys");
  const body = await res.json();
  const keys = new Map<string, string>();
  for (const k of body.keys ?? []) keys.set(String(k.keyId), k.base64 as string);
  keyCache = { keys, fetchedAt: Date.now() };
  return keys;
}

async function verifySignature(message: string, signatureB64: string, keyId: string): Promise<boolean> {
  let keys = await getVerifierKeys();
  if (!keys.has(keyId)) keys = await getVerifierKeys(true);
  const spki = keys.get(keyId);
  if (!spki) return false;

  const key = await crypto.subtle.importKey(
    "spki",
    b64ToBytes(spki) as BufferSource,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  return await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    derToRaw(b64ToBytes(signatureB64)) as BufferSource,
    new TextEncoder().encode(message),
  );
}

Deno.serve(async (req) => {
  // AdMob's "verify URL" button in the console sends a plain GET without
  // params; answer 200 so the console accepts the URL.
  const url = new URL(req.url);
  const rawQuery = url.search.startsWith("?") ? url.search.slice(1) : url.search;
  if (!url.searchParams.has("signature")) return new Response("ok", { status: 200 });

  try {
    const signature = url.searchParams.get("signature")!;
    const keyId = url.searchParams.get("key_id") ?? "";
    const valid = await verifySignature(signedMessage(rawQuery), signature, keyId);
    if (!valid) return new Response("invalid signature", { status: 403 });

    const uid = url.searchParams.get("user_id") ?? "";
    const transactionId = url.searchParams.get("transaction_id") ?? "";
    const adUnit = url.searchParams.get("ad_unit") ?? "";
    if (!uid || !/^[A-Za-z0-9_-]{6,128}$/.test(transactionId) || !/^[A-Za-z0-9]{6,128}$/.test(uid)) {
      return new Response("bad params", { status: 400 });
    }
    if (ALLOWED_UNITS.length > 0 && !ALLOWED_UNITS.includes(adUnit)) {
      return new Response("ignored", { status: 200 });
    }

    const outcome = await runTransaction(async (tx) => {
      const eco = await loadEconomy(tx);
      const logPath = `adRewards/${transactionId}`;
      if ((await tx.get(logPath)) !== null) return "duplicate";

      const user = await tx.get(`users/${uid}`);
      if (!user || user.isBlocked === true) {
        tx.create(logPath, { uid, status: "rejected", adUnit, createdAt: new Date() });
        return "rejected";
      }

      const now = new Date();
      const patch: Doc = applyLazyState(user, eco, now);
      const watched = "dailyAdsWatched" in patch ? asInt(patch.dailyAdsWatched) : asInt(user.dailyAdsWatched);
      const coins = "coins" in patch ? asInt(patch.coins) : asInt(user.coins);
      const merged: Doc = { ...user, ...patch };

      if (watched >= adLimitFor(merged, eco, now)) {
        if (Object.keys(patch).length > 0) tx.update(`users/${uid}`, patch);
        tx.create(logPath, { uid, status: "limit", adUnit, createdAt: now });
        return "limit";
      }

      tx.update(`users/${uid}`, {
        ...patch,
        coins: coins + eco.adRewardAmount,
        dailyAdsWatched: watched + 1,
      });
      tx.create(logPath, { uid, status: "credited", amount: eco.adRewardAmount, adUnit, createdAt: now });
      return "credited";
    });

    return new Response(outcome, { status: 200 });
  } catch (e) {
    console.error(`admob-ssv error: ${e instanceof Error ? e.message : e}`);
    // 500 makes AdMob retry the callback later.
    return new Response("error", { status: 500 });
  }
});
