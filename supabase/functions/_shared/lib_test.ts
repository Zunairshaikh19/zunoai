// Run with:  deno test --allow-env --allow-net=none _shared/lib_test.ts
// (no network: Firestore + OAuth are faked in-memory, with real optimistic-
// locking semantics so the concurrency tests are meaningful.)

// Tiny assertion helpers (no external test library needed).
function assert(cond: unknown, msg = "assertion failed"): asserts cond {
  if (!cond) throw new Error(msg);
}
function assertEquals(actual: unknown, expected: unknown): void {
  const norm = (v: unknown) => JSON.stringify(v, (_k, x) => (x instanceof Date ? `D:${x.toISOString()}` : x));
  if (norm(actual) !== norm(expected)) {
    throw new Error(`assertEquals failed\n  actual:   ${norm(actual)}\n  expected: ${norm(expected)}`);
  }
}
async function assertRejects(fn: () => Promise<unknown>): Promise<void> {
  try {
    await fn();
  } catch (_e) {
    return;
  }
  throw new Error("expected promise to reject");
}
import { b64ToBytes, derToRaw, signedMessage } from "./admob.ts";
import { sniffImageMime } from "./image.ts";

// ---- fake Google OAuth + Firestore REST -----------------------------------

async function makeServiceAccountJson(): Promise<string> {
  const kp = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", kp.privateKey));
  let bin = "";
  for (const b of pkcs8) bin += String.fromCharCode(b);
  const b64 = btoa(bin).replace(/(.{64})/g, "$1\n");
  return JSON.stringify({
    client_email: "test@zunoai.iam.gserviceaccount.com",
    private_key: `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----\n`,
  });
}

// deno-lint-ignore no-explicit-any
type Fields = Record<string, any>;
interface StoredDoc { fields: Fields; version: number }

class FakeFirestore {
  docs = new Map<string, StoredDoc>();
  txReads = new Map<string, Map<string, number>>();
  nextTx = 1;
  root = "projects/zunoai-b924f/databases/(default)/documents/";

  handle = async (input: Request | URL | string, init?: RequestInit): Promise<Response> => {
    const url = new URL(typeof input === "string" ? input : input instanceof URL ? input.href : input.url);
    const method = init?.method ?? "GET";
    if (url.hostname === "oauth2.googleapis.com") {
      return Response.json({ access_token: "tok", expires_in: 3600 });
    }
    const path = decodeURIComponent(url.pathname.replace("/v1/projects/zunoai-b924f/databases/(default)/documents", ""));
    if (path === ":beginTransaction") {
      const id = `tx${this.nextTx++}`;
      this.txReads.set(id, new Map());
      return Response.json({ transaction: id });
    }
    if (path === ":rollback") {
      return Response.json({});
    }
    if (path === ":commit") {
      const body = JSON.parse(String(init?.body));
      const reads = this.txReads.get(body.transaction) ?? new Map();
      for (const [p, v] of reads) {
        if ((this.docs.get(p)?.version ?? 0) !== v) {
          return Response.json({ error: { status: "ABORTED" } }, { status: 409 });
        }
      }
      // validate preconditions first
      for (const w of body.writes) {
        const p = (w.update?.name ?? w.delete).replace(this.root, "");
        const exists = this.docs.has(p);
        if (w.currentDocument?.exists === false && exists) {
          return Response.json({ error: { status: "ALREADY_EXISTS" } }, { status: 409 });
        }
        if (w.currentDocument?.exists === true && !exists) {
          return Response.json({ error: { status: "NOT_FOUND" } }, { status: 404 });
        }
      }
      for (const w of body.writes) {
        if (w.delete) {
          this.docs.delete(w.delete.replace(this.root, ""));
          continue;
        }
        const p = w.update.name.replace(this.root, "");
        const cur = this.docs.get(p) ?? { fields: {}, version: 0 };
        let fields: Fields;
        if (w.updateMask) {
          fields = { ...cur.fields };
          for (const k of w.updateMask.fieldPaths) {
            if (k in w.update.fields) fields[k] = w.update.fields[k];
            else delete fields[k];
          }
        } else {
          fields = w.update.fields;
        }
        this.docs.set(p, { fields, version: cur.version + 1 });
      }
      return Response.json({});
    }
    if (method === "GET") {
      const p = path.replace(/^\//, "");
      const doc = this.docs.get(p);
      const tx = url.searchParams.get("transaction");
      if (tx) this.txReads.get(tx)?.set(p, doc?.version ?? 0);
      if (!doc) return Response.json({ error: { status: "NOT_FOUND" } }, { status: 404 });
      return Response.json({ name: this.root + p, fields: doc.fields });
    }
    return Response.json({}, { status: 500 });
  };
}

const fake = new FakeFirestore();
globalThis.fetch = ((i: Request | URL | string, init?: RequestInit) => fake.handle(i, init)) as typeof fetch;
Deno.env.set("FIREBASE_SERVICE_ACCOUNT_KEY", await makeServiceAccountJson());
const lib = await import("./lib.ts");
const { runTransaction, encodeFields, decodeFields, applyLazyState, parseEconomy, DEFAULT_ECONOMY, getDoc } = lib;

function seed(path: string, data: Record<string, unknown>) {
  fake.docs.set(path, { fields: encodeFields(data), version: 1 });
}
function coinsOf(path: string): number {
  return Number(decodeFields(fake.docs.get(path)!.fields).coins);
}

// ---- tests ----------------------------------------------------------------

Deno.test("codec round-trips all supported types", () => {
  const now = new Date("2026-10-06T10:00:00Z");
  const doc = { a: "x", b: 5, c: 1.5, d: true, e: null, f: now, g: [1, "y"], h: { n: 1 } };
  const back = decodeFields(encodeFields(doc));
  assertEquals(back, doc);
});

Deno.test("parseEconomy: falls back to defaults, accepts 0, ignores junk", () => {
  assertEquals(parseEconomy(null).generationCost, 40);
  assertEquals(parseEconomy({ generationCost: 0 }).generationCost, 0);
  assertEquals(parseEconomy({ generationCost: "abc" }).generationCost, 40);
  assertEquals(parseEconomy({ adRewardAmount: 12.0 }).adRewardAmount, 12);
  assertEquals(parseEconomy({ streakRewards: [1, 2, 3] }).streakRewards, [1, 2, 3]);
  assertEquals(parseEconomy({ streakRewards: [] }).streakRewards, DEFAULT_ECONOMY.streakRewards);
});

Deno.test("applyLazyState: daily bonus granted once per UTC day, by tier", () => {
  const eco = DEFAULT_ECONOMY;
  const now = new Date("2026-10-06T12:00:00Z");
  const yesterday = new Date("2026-10-05T23:59:00Z");
  const free = applyLazyState({ coins: 10, tier: "free", lastDailyReset: yesterday, dailyAdsWatched: 3 }, eco, now);
  assertEquals(free.coins, 10 + eco.dailyBonusFree);
  assertEquals(free.dailyAdsWatched, 0);

  const sameDay = applyLazyState({ coins: 10, tier: "free", lastDailyReset: new Date("2026-10-06T00:00:01Z") }, eco, now);
  assertEquals(Object.keys(sameDay).length, 0);

  const monthly = applyLazyState(
    { coins: 0, tier: "paid", premiumPlan: "monthly", premiumExpiresAt: new Date("2026-11-01T00:00:00Z"), lastDailyReset: yesterday },
    eco, now,
  );
  assertEquals(monthly.coins, eco.dailyBonusPremium);

  const yearly = applyLazyState(
    { coins: 0, tier: "paid", premiumPlan: "yearly", premiumExpiresAt: new Date("2027-10-01T00:00:00Z"), lastDailyReset: yesterday },
    eco, now,
  );
  assertEquals(yearly.coins, eco.dailyBonusPremiumYearly);
});

Deno.test("applyLazyState: expired premium drops to free and gets the FREE bonus", () => {
  const now = new Date("2026-10-06T12:00:00Z");
  const patch = applyLazyState(
    { coins: 0, tier: "paid", premiumPlan: "monthly", premiumExpiresAt: new Date("2026-10-05T00:00:00Z"), lastDailyReset: new Date("2026-10-05T01:00:00Z") },
    DEFAULT_ECONOMY, now,
  );
  assertEquals(patch.tier, "free");
  assertEquals(patch.coins, DEFAULT_ECONOMY.dailyBonusFree);
});

Deno.test("changing the clock backwards cannot re-trigger a daily bonus", () => {
  const now = new Date("2026-10-06T12:00:00Z");
  const patch = applyLazyState({ coins: 5, tier: "free", lastDailyReset: new Date("2026-10-06T08:00:00Z") }, DEFAULT_ECONOMY, now);
  assertEquals(Object.keys(patch).length, 0);
});

Deno.test("runTransaction: 20 parallel debits of the same balance never overspend", async () => {
  seed("users/u1", { coins: 40 });
  let successes = 0;
  const results = await Promise.allSettled(
    Array.from({ length: 20 }, () =>
      runTransaction(async (tx) => {
        const u = await tx.get("users/u1");
        const coins = Number(u!.coins);
        if (coins < 40) throw new Error("INSUFFICIENT");
        tx.update("users/u1", { coins: coins - 40 });
        successes++;
      }, 30)
    ),
  );
  assertEquals(coinsOf("users/u1"), 0);
  assertEquals(results.filter((r) => r.status === "fulfilled").length, 1);
  assertEquals(successes >= 1, true);
});

Deno.test("runTransaction: parallel credits all land (no lost updates)", async () => {
  seed("users/u2", { coins: 0 });
  await Promise.all(
    Array.from({ length: 15 }, () =>
      runTransaction(async (tx) => {
        const u = await tx.get("users/u2");
        tx.update("users/u2", { coins: Number(u!.coins) + 10 });
      }, 40)
    ),
  );
  assertEquals(coinsOf("users/u2"), 150);
});

Deno.test("runTransaction: create() fails if the doc already exists (dedupe guard)", async () => {
  seed("adRewards/t1", { status: "credited" });
  await assertRejects(() =>
    runTransaction(async (tx) => {
      tx.create("adRewards/t1", { status: "again" });
    }, 2)
  );
});

Deno.test("getDoc returns null for missing docs", async () => {
  assertEquals(await getDoc("users/nope"), null);
});

Deno.test("AdMob SSV: DER signature converts to raw and verifies with WebCrypto", async () => {
  const kp = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const msg = "ad_network=5450213213286189855&ad_unit=123&reward_amount=1&timestamp=1&transaction_id=abc&user_id=u1";
  const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, kp.privateKey, new TextEncoder().encode(msg)));
  // raw r||s -> DER
  const enc = (v: Uint8Array) => {
    let i = 0;
    while (i < v.length - 1 && v[i] === 0) i++;
    let x = v.slice(i);
    if (x[0] & 0x80) x = new Uint8Array([0, ...x]);
    return [0x02, x.length, ...x];
  };
  const body = [...enc(raw.slice(0, 32)), ...enc(raw.slice(32))];
  const der = new Uint8Array([0x30, body.length, ...body]);
  const back = derToRaw(der);
  assertEquals(Array.from(back), Array.from(raw));
  assert(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, kp.publicKey, back as BufferSource, new TextEncoder().encode(msg)));
  // base64url helper
  assertEquals(Array.from(b64ToBytes("-_8")), [251, 255]);
});

Deno.test("AdMob SSV: signed message excludes signature and key_id suffix", () => {
  assertEquals(signedMessage("a=1&b=2&signature=XYZ&key_id=9"), "a=1&b=2");
  assertEquals(signedMessage("a=1&b=2"), "a=1&b=2");
});

Deno.test("sniffImageMime", () => {
  const jpeg = btoa(String.fromCharCode(0xff, 0xd8, 0xff, 0xe0, 0, 0x10, 0x4a, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1));
  const png = btoa(String.fromCharCode(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0));
  const webp = btoa("RIFF\u0000\u0000\u0000\u0000WEBPVP8 \u0000\u0000");
  const exe = btoa("MZ\u0090\u0000\u0003\u0000\u0000\u0000\u0004\u0000\u0000\u0000ÿÿ\u0000\u0000");
  assertEquals(sniffImageMime(jpeg), "image/jpeg");
  assertEquals(sniffImageMime(png), "image/png");
  assertEquals(sniffImageMime(webp), "image/webp");
  assertEquals(sniffImageMime(exe), null);
  assertEquals(sniffImageMime("short"), null);
});

