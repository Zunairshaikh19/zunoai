// Shared helpers for all Zuno AI Edge Functions.
//
// Everything that touches coins, premium, ads or referrals runs through
// Firestore *transactions* here, using a service account (which bypasses
// security rules). The mobile client can never change those fields itself.

import { createRemoteJWKSet, importPKCS8, jwtVerify, SignJWT } from "npm:jose@5";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

export const FIREBASE_PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID") ?? "zunoai-b924f";
export const FIREBASE_PROJECT_NUMBER = Deno.env.get("FIREBASE_PROJECT_NUMBER") ?? "31792471355";
export const ANDROID_PACKAGE = Deno.env.get("ANDROID_PACKAGE") ?? "com.zunoai.app";

const SERVICE_ACCOUNT_KEY = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_KEY") ?? "";
const APP_CHECK_ENFORCE = (Deno.env.get("APP_CHECK_ENFORCE") ?? "false") === "true";
const REQUIRE_VERIFIED_EMAIL = (Deno.env.get("REQUIRE_VERIFIED_EMAIL") ?? "true") === "true";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-firebase-appcheck",
};

// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------

export class HttpError extends Error {
  status: number;
  code: string;
  constructor(status: number, message: string, code = "ERROR") {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function errorResponse(err: unknown): Response {
  if (err instanceof HttpError) {
    return json({ success: false, error: err.message, code: err.code }, err.status);
  }
  const message = err instanceof Error ? err.message : String(err);
  console.error(`Unhandled error: ${message}`);
  // Never leak internals to the client.
  return json({ success: false, error: "Something went wrong. Please try again.", code: "INTERNAL" }, 500);
}

// ---------------------------------------------------------------------------
// Auth: Firebase ID token (+ optional App Check)
// ---------------------------------------------------------------------------

const firebaseJwks = createRemoteJWKSet(
  new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"),
);
const appCheckJwks = createRemoteJWKSet(new URL("https://firebaseappcheck.googleapis.com/v1/jwks"));

export interface AuthInfo {
  uid: string;
  email: string;
  emailVerified: boolean;
  provider: string;
  name?: string;
  picture?: string;
}

export async function authenticate(req: Request): Promise<AuthInfo> {
  const header = req.headers.get("Authorization");
  if (!header || !header.startsWith("Bearer ")) {
    throw new HttpError(401, "Missing or invalid authorization token", "UNAUTHENTICATED");
  }
  const idToken = header.slice("Bearer ".length).trim();

  let payload: Record<string, unknown>;
  try {
    const res = await jwtVerify(idToken, firebaseJwks, {
      issuer: `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`,
      audience: FIREBASE_PROJECT_ID,
    });
    payload = res.payload as Record<string, unknown>;
  } catch (_e) {
    throw new HttpError(401, "Invalid or expired Firebase token", "UNAUTHENTICATED");
  }

  const uid = (payload.user_id as string) || (payload.sub as string);
  if (!uid) throw new HttpError(401, "Token missing uid", "UNAUTHENTICATED");

  await verifyAppCheck(req);

  const firebase = (payload.firebase ?? {}) as Record<string, unknown>;
  return {
    uid,
    email: (payload.email as string) ?? "",
    emailVerified: payload.email_verified === true,
    provider: (firebase.sign_in_provider as string) ?? "",
    name: payload.name as string | undefined,
    picture: payload.picture as string | undefined,
  };
}

async function verifyAppCheck(req: Request): Promise<void> {
  if (!APP_CHECK_ENFORCE) return;
  const token = req.headers.get("X-Firebase-AppCheck");
  if (!token) throw new HttpError(401, "App attestation missing", "APP_CHECK");
  try {
    await jwtVerify(token, appCheckJwks, {
      issuer: `https://firebaseappcheck.googleapis.com/${FIREBASE_PROJECT_NUMBER}`,
      audience: `projects/${FIREBASE_PROJECT_NUMBER}`,
    });
  } catch (_e) {
    throw new HttpError(401, "App attestation failed", "APP_CHECK");
  }
}

/** Email/password accounts must verify their email before spending real money. */
export function requireVerifiedEmail(auth: AuthInfo): void {
  if (!REQUIRE_VERIFIED_EMAIL) return;
  if (auth.provider === "password" && !auth.emailVerified) {
    throw new HttpError(403, "Please verify your email address first. Check your inbox.", "EMAIL_NOT_VERIFIED");
  }
}

// ---------------------------------------------------------------------------
// Service account access tokens (Firestore, Play, Identity Toolkit)
// ---------------------------------------------------------------------------

const tokenCache = new Map<string, { token: string; expiresAt: number }>();

export async function getAccessToken(
  scope: string,
  keyJson: string = SERVICE_ACCOUNT_KEY,
): Promise<string> {
  const cacheKey = `${scope}|${keyJson.length}`;
  const cached = tokenCache.get(cacheKey);
  if (cached && cached.expiresAt > Date.now() + 60_000) return cached.token;

  if (!keyJson) throw new HttpError(503, "Server is not configured yet", "NOT_CONFIGURED");
  const creds = JSON.parse(keyJson);
  const privateKey = await importPKCS8(creds.private_key, "RS256");
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({ scope })
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
  tokenCache.set(cacheKey, { token: data.access_token, expiresAt: Date.now() + data.expires_in * 1000 });
  return data.access_token;
}

export const SCOPE_DATASTORE = "https://www.googleapis.com/auth/datastore";
export const SCOPE_CLOUD = "https://www.googleapis.com/auth/cloud-platform";
export const SCOPE_PLAY = "https://www.googleapis.com/auth/androidpublisher";

// ---------------------------------------------------------------------------
// Firestore REST value codec
// ---------------------------------------------------------------------------

// deno-lint-ignore no-explicit-any
type FsValue = Record<string, any>;
export type Doc = Record<string, unknown>;

export function decodeValue(v: FsValue): unknown {
  if (v === undefined || v === null) return null;
  if ("nullValue" in v) return null;
  if ("stringValue" in v) return v.stringValue;
  if ("booleanValue" in v) return v.booleanValue;
  if ("integerValue" in v) return parseInt(v.integerValue, 10);
  if ("doubleValue" in v) return Number(v.doubleValue);
  if ("timestampValue" in v) return new Date(v.timestampValue);
  if ("referenceValue" in v) return v.referenceValue;
  if ("arrayValue" in v) return (v.arrayValue.values ?? []).map(decodeValue);
  if ("mapValue" in v) return decodeFields(v.mapValue.fields ?? {});
  return null;
}

export function decodeFields(fields: Record<string, FsValue>): Doc {
  const out: Doc = {};
  for (const [k, v] of Object.entries(fields)) out[k] = decodeValue(v);
  return out;
}

export function encodeValue(v: unknown): FsValue {
  if (v === null || v === undefined) return { nullValue: null };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === "string") return { stringValue: v };
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number") {
    return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  }
  if (Array.isArray(v)) return { arrayValue: { values: v.map(encodeValue) } };
  if (typeof v === "object") return { mapValue: { fields: encodeFields(v as Doc) } };
  throw new Error(`Cannot encode value of type ${typeof v}`);
}

export function encodeFields(obj: Doc): Record<string, FsValue> {
  const out: Record<string, FsValue> = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v !== undefined) out[k] = encodeValue(v);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Firestore REST + transactions
// ---------------------------------------------------------------------------

const DB_ROOT = `projects/${FIREBASE_PROJECT_ID}/databases/(default)`;
const DOCS_URL = `https://firestore.googleapis.com/v1/${DB_ROOT}/documents`;

async function fsFetch(url: string, init: RequestInit = {}): Promise<Response> {
  const token = await getAccessToken(SCOPE_CLOUD);
  return fetch(url, {
    ...init,
    headers: {
      ...(init.headers ?? {}),
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
  });
}

/** Non-transactional read. Returns null when the doc does not exist. */
export async function getDoc(path: string): Promise<Doc | null> {
  const res = await fsFetch(`${DOCS_URL}/${path}`);
  if (res.status === 404) {
    await res.body?.cancel();
    return null;
  }
  if (!res.ok) throw new Error(`Firestore read failed (${res.status}) for ${path}`);
  const data = await res.json();
  return decodeFields(data.fields ?? {});
}

export async function listDocs(
  collectionPath: string,
  pageSize = 100,
  pageToken?: string,
): Promise<{ docs: { id: string; data: Doc }[]; nextPageToken?: string }> {
  const qs = new URLSearchParams({ pageSize: String(pageSize) });
  if (pageToken) qs.set("pageToken", pageToken);
  const res = await fsFetch(`${DOCS_URL}/${collectionPath}?${qs}`);
  if (!res.ok) throw new Error(`Firestore list failed (${res.status}) for ${collectionPath}`);
  const body = await res.json();
  const docs = (body.documents ?? []).map((d: { name: string; fields?: Record<string, FsValue> }) => ({
    id: d.name.split("/").pop() as string,
    data: decodeFields(d.fields ?? {}),
  }));
  return { docs, nextPageToken: body.nextPageToken };
}

export async function deleteDoc(path: string): Promise<void> {
  const res = await fsFetch(`${DOCS_URL}/${path}`, { method: "DELETE" });
  await res.body?.cancel();
  if (!res.ok && res.status !== 404) throw new Error(`Firestore delete failed (${res.status}) for ${path}`);
}

export interface TxWrite {
  // deno-lint-ignore no-explicit-any
  [key: string]: any;
}

export class Tx {
  id = "";
  writes: TxWrite[] = [];

  async get(path: string): Promise<Doc | null> {
    const res = await fsFetch(`${DOCS_URL}/${path}?transaction=${encodeURIComponent(this.id)}`);
    if (res.status === 404) {
      await res.body?.cancel();
      return null;
    }
    if (!res.ok) throw new Error(`Firestore tx read failed (${res.status}) for ${path}`);
    const data = await res.json();
    return decodeFields(data.fields ?? {});
  }

  /** Create a document; the commit fails (and the tx retries) if it already exists. */
  create(path: string, data: Doc): void {
    this.writes.push({
      update: { name: `${DB_ROOT}/documents/${path}`, fields: encodeFields(data) },
      currentDocument: { exists: false },
    });
  }

  /** Merge the given fields into an existing-or-new doc (only these fields are touched). */
  merge(path: string, data: Doc): void {
    const keys = Object.keys(data).filter((k) => data[k] !== undefined);
    this.writes.push({
      update: { name: `${DB_ROOT}/documents/${path}`, fields: encodeFields(data) },
      updateMask: { fieldPaths: keys },
    });
  }

  /** Merge into an existing doc; fails if it doesn't exist. */
  update(path: string, data: Doc): void {
    const keys = Object.keys(data).filter((k) => data[k] !== undefined);
    this.writes.push({
      update: { name: `${DB_ROOT}/documents/${path}`, fields: encodeFields(data) },
      updateMask: { fieldPaths: keys },
      currentDocument: { exists: true },
    });
  }

  /** Removes the given fields from an existing doc. */
  removeFields(path: string, fieldPaths: string[]): void {
    this.writes.push({
      update: { name: `${DB_ROOT}/documents/${path}`, fields: {} },
      updateMask: { fieldPaths },
      currentDocument: { exists: true },
    });
  }

  delete(path: string): void {
    this.writes.push({ delete: `${DB_ROOT}/documents/${path}` });
  }
}

/**
 * Runs `fn` inside a Firestore transaction (reads are locked, writes are
 * applied atomically on commit). Retries automatically on contention, so two
 * concurrent requests for the same user can never both spend/earn off the
 * same stale balance.
 */
export async function runTransaction<T>(fn: (tx: Tx) => Promise<T>, attempts = 6): Promise<T> {
  let lastError: unknown;
  for (let i = 0; i < attempts; i++) {
    const begin = await fsFetch(`${DOCS_URL}:beginTransaction`, {
      method: "POST",
      body: JSON.stringify({ options: { readWrite: {} } }),
    });
    if (!begin.ok) throw new Error(`Firestore beginTransaction failed (${begin.status})`);
    const { transaction } = await begin.json();

    const tx = new Tx();
    tx.id = transaction;

    let result: T;
    try {
      result = await fn(tx);
    } catch (e) {
      // Release the transaction; ignore rollback errors.
      try {
        const rb = await fsFetch(`${DOCS_URL}:rollback`, {
          method: "POST",
          body: JSON.stringify({ transaction }),
        });
        await rb.body?.cancel();
      } catch (_r) { /* ignore */ }
      throw e;
    }

    const commit = await fsFetch(`${DOCS_URL}:commit`, {
      method: "POST",
      body: JSON.stringify({ writes: tx.writes, transaction }),
    });
    if (commit.ok) {
      await commit.body?.cancel();
      return result;
    }
    const errBody = await commit.text();
    // 409 = ABORTED (contention); 400 FAILED_PRECONDITION on `exists:false` creates also lands here.
    if (commit.status === 409 || errBody.includes("ABORTED")) {
      lastError = new Error(`Transaction aborted: ${errBody.slice(0, 200)}`);
      await new Promise((r) => setTimeout(r, 50 * (i + 1) + Math.random() * 50));
      continue;
    }
    throw new Error(`Firestore commit failed (${commit.status}): ${errBody.slice(0, 300)}`);
  }
  throw lastError ?? new Error("Transaction failed");
}

// ---------------------------------------------------------------------------
// Economy
// ---------------------------------------------------------------------------

export interface Economy {
  signupBonus: number;
  referralReward: number;
  referralCap: number;
  generationCost: number;
  adRewardAmount: number;
  dailyBonusFree: number;
  dailyBonusPremium: number; // monthly plan, coins/day
  dailyBonusPremiumYearly: number; // yearly plan, coins/day
  freeAdLimitPerDay: number;
  premiumAdLimitPerDay: number;
  watermarkRemovalCost: number;
  maxGenerationsPerDay: number;
  streakRewards: number[];
}

// Keep in sync with lib/models/economy_config.dart and economy-defaults.json.
// Sized for: $0.04 per image, 40 coins per image, 80% net margin on premium
// after the 15% Google Play fee.
export const DEFAULT_ECONOMY: Economy = {
  signupBonus: 40,
  referralReward: 20,
  referralCap: 10,
  generationCost: 40,
  adRewardAmount: 10,
  dailyBonusFree: 5,
  dailyBonusPremium: 52,
  dailyBonusPremiumYearly: 33,
  freeAdLimitPerDay: 3,
  premiumAdLimitPerDay: 0,
  watermarkRemovalCost: 20,
  maxGenerationsPerDay: 60,
  streakRewards: [2, 2, 3, 3, 4, 5, 10],
};

function num(v: unknown, fallback: number): number {
  return typeof v === "number" && Number.isFinite(v) && v >= 0 ? Math.floor(v) : fallback;
}

export function parseEconomy(data: Doc | null): Economy {
  const d = DEFAULT_ECONOMY;
  if (!data) return { ...d, streakRewards: [...d.streakRewards] };
  const rewards = Array.isArray(data.streakRewards)
    ? (data.streakRewards as unknown[]).map((x) => num(x, 0)).filter((x) => x > 0)
    : [];
  return {
    signupBonus: num(data.signupBonus, d.signupBonus),
    referralReward: num(data.referralReward, d.referralReward),
    referralCap: num(data.referralCap, d.referralCap),
    // NOTE: 0 is a legitimate value here (free generations), so no `||` fallback.
    generationCost: num(data.generationCost, d.generationCost),
    adRewardAmount: num(data.adRewardAmount, d.adRewardAmount),
    dailyBonusFree: num(data.dailyBonusFree, d.dailyBonusFree),
    dailyBonusPremium: num(data.dailyBonusPremium, d.dailyBonusPremium),
    dailyBonusPremiumYearly: num(data.dailyBonusPremiumYearly, d.dailyBonusPremiumYearly),
    freeAdLimitPerDay: num(data.freeAdLimitPerDay, d.freeAdLimitPerDay),
    premiumAdLimitPerDay: num(data.premiumAdLimitPerDay, d.premiumAdLimitPerDay),
    watermarkRemovalCost: num(data.watermarkRemovalCost, d.watermarkRemovalCost),
    maxGenerationsPerDay: num(data.maxGenerationsPerDay, d.maxGenerationsPerDay),
    streakRewards: rewards.length > 0 ? rewards : [...d.streakRewards],
  };
}

export async function loadEconomy(tx?: Tx): Promise<Economy> {
  const doc = tx ? await tx.get("settings/economy") : await getDoc("settings/economy");
  return parseEconomy(doc);
}

// ---------------------------------------------------------------------------
// User state helpers
// ---------------------------------------------------------------------------

/** UTC calendar day, e.g. "2026-10-06". All daily limits reset at UTC midnight. */
export function utcDay(d: Date): string {
  return d.toISOString().slice(0, 10);
}

export function previousUtcDay(d: Date): string {
  return utcDay(new Date(d.getTime() - 24 * 60 * 60 * 1000));
}

export function asDate(v: unknown): Date | null {
  return v instanceof Date && !Number.isNaN(v.getTime()) ? v : null;
}

export function asInt(v: unknown, fallback = 0): number {
  return typeof v === "number" && Number.isFinite(v) ? Math.trunc(v) : fallback;
}

export function isPremium(user: Doc, now: Date): boolean {
  if (user.tier !== "paid") return false;
  const exp = asDate(user.premiumExpiresAt);
  return exp !== null && exp.getTime() > now.getTime();
}

export function premiumDailyCoins(user: Doc, eco: Economy): number {
  return user.premiumPlan === "yearly" ? eco.dailyBonusPremiumYearly : eco.dailyBonusPremium;
}

/**
 * Applies lazily-evaluated state changes to a user doc (premium expiry and
 * the once-per-UTC-day reset + daily bonus). Returns only the fields that
 * changed, so the caller merges them into its own write. Doing this inside
 * every economy transaction means a daily bonus can never be granted twice,
 * and changing the phone's clock has no effect.
 */
export function applyLazyState(user: Doc, eco: Economy, now: Date): Doc {
  const patch: Doc = {};
  let coins = asInt(user.coins);
  let tier = user.tier;

  if (user.tier === "paid") {
    const exp = asDate(user.premiumExpiresAt);
    if (!exp || exp.getTime() <= now.getTime()) {
      tier = "free";
      patch.tier = "free";
      patch.premiumExpiresAt = null;
    }
  }

  const last = asDate(user.lastDailyReset);
  if (!last || utcDay(last) !== utcDay(now)) {
    const bonus = tier === "paid" ? premiumDailyCoins(user, eco) : eco.dailyBonusFree;
    coins += bonus;
    patch.coins = coins;
    patch.dailyAdsWatched = 0;
    patch.lastDailyReset = now;
  }
  return patch;
}

export function adLimitFor(user: Doc, eco: Economy, now: Date): number {
  return isPremium(user, now) ? eco.premiumAdLimitPerDay : eco.freeAdLimitPerDay;
}

export function generateReferralCode(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no look-alike chars
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  return Array.from(bytes, (b) => alphabet[b % alphabet.length]).join("");
}

export async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, "0")).join("");
}

export function requireBody<T extends Record<string, unknown>>(body: unknown): T {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new HttpError(400, "Invalid request body", "BAD_REQUEST");
  }
  return body as T;
}
