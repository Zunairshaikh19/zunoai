// Server-authoritative economy actions. The client can no longer write
// `coins`, `tier`, `dailyAdsWatched`, `loginStreak`, referral fields etc.
// (see firestore.rules) — it asks this function to do it, and every action
// runs in a Firestore transaction.
//
// POST { action: "init-profile" | "claim-daily" | "claim-streak" |
//                "redeem-referral" | "unlock-watermark" | "delete-account", ... }

import {
  applyLazyState,
  asDate,
  asInt,
  authenticate,
  type AuthInfo,
  corsHeaders,
  deleteDoc,
  type Doc,
  errorResponse,
  generateReferralCode,
  getAccessToken,
  getDoc,
  HttpError,
  isPremium,
  json,
  listDocs,
  loadEconomy,
  previousUtcDay,
  requireBody,
  runTransaction,
  SCOPE_CLOUD,
  FIREBASE_PROJECT_ID,
  utcDay,
} from "../_shared/lib.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ success: false, error: "Method not allowed" }, 405);

  try {
    const auth = await authenticate(req);
    const body = requireBody<Record<string, unknown>>(await req.json().catch(() => null));
    const action = String(body.action ?? "");

    switch (action) {
      case "init-profile":
        return json(await initProfile(auth, String(body.referralCode ?? "")));
      case "claim-daily":
        return json(await claimDaily(auth.uid));
      case "claim-streak":
        return json(await claimStreak(auth.uid));
      case "redeem-referral":
        return json(await redeemReferral(auth.uid, String(body.code ?? "")));
      case "unlock-watermark":
        return json(await unlockWatermark(auth.uid, String(body.historyId ?? "")));
      case "delete-account":
        return json(await deleteAccount(auth.uid));
      default:
        throw new HttpError(400, "Unknown action", "BAD_REQUEST");
    }
  } catch (err) {
    return errorResponse(err);
  }
});

// ---------------------------------------------------------------------------

function normalizeCode(raw: string): string {
  return raw.trim().toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 16);
}

function assertNotBlocked(user: Doc) {
  if (user.isBlocked === true) throw new HttpError(403, "This account has been blocked.", "BLOCKED");
}

// --- init-profile ----------------------------------------------------------

async function initProfile(auth: AuthInfo, rawReferral: string) {
  const referralInput = normalizeCode(rawReferral);

  return await runTransaction(async (tx) => {
    const eco = await loadEconomy(tx);
    const userPath = `users/${auth.uid}`;
    const existing = await tx.get(userPath);

    if (existing && (existing.profileCreated === true || (typeof existing.email === "string" && existing.email !== ""))) {
      return { success: true, created: false, referralApplied: false, coins: asInt(existing.coins) };
    }

    // Pick a free referral code.
    let myCode = "";
    for (let i = 0; i < 6; i++) {
      const candidate = generateReferralCode();
      if ((await tx.get(`referralCodes/${candidate}`)) === null) {
        myCode = candidate;
        break;
      }
    }
    if (!myCode) throw new Error("Could not allocate a referral code");

    // Validate an optional referral code. An invalid/own/capped code is simply
    // ignored (no bonus) — it never grants anything.
    let coins = eco.signupBonus;
    let referredBy: string | null = null;
    let referralApplied = false;
    let inviterUid: string | null = null;
    let inviter: Doc | null = null;

    if (referralInput) {
      const codeDoc = await tx.get(`referralCodes/${referralInput}`);
      const candidateUid = typeof codeDoc?.uid === "string" ? codeDoc.uid : null;
      if (candidateUid && candidateUid !== auth.uid) {
        const inviterDoc = await tx.get(`users/${candidateUid}`);
        if (
          inviterDoc && inviterDoc.isBlocked !== true &&
          asInt(inviterDoc.referralCount) < eco.referralCap
        ) {
          inviterUid = candidateUid;
          inviter = inviterDoc;
          referredBy = referralInput;
          coins += eco.referralReward;
          referralApplied = true;
        }
      }
    }

    const now = new Date();
    tx.merge(userPath, {
      email: auth.email,
      displayName: auth.name ?? null,
      photoUrl: auth.picture ?? null,
      coins,
      tier: "free",
      premiumExpiresAt: null,
      premiumPlan: null,
      referralCode: myCode,
      referredBy,
      lastDailyReset: now,
      dailyAdsWatched: 0,
      referralCount: 0,
      isBlocked: false,
      lastActivity: now,
      loginStreak: 0,
      lastStreakClaim: null,
      gender: null,
      createdAt: now,
      profileCreated: true,
    });
    tx.create(`referralCodes/${myCode}`, { uid: auth.uid, createdAt: now });

    if (referralApplied && inviterUid && inviter) {
      tx.merge(`users/${inviterUid}`, {
        coins: asInt(inviter.coins) + eco.referralReward,
        referralCount: asInt(inviter.referralCount) + 1,
      });
      tx.create(`users/${inviterUid}/notifications/ref_${auth.uid}`, {
        title: "Referral Successful!",
        message: `A friend joined using your code! ${eco.referralReward} coins added to your account.`,
        timestamp: now,
        isRead: false,
      });
    }

    return { success: true, created: true, referralApplied, coins };
  });
}

// --- claim-daily -----------------------------------------------------------

async function claimDaily(uid: string) {
  return await runTransaction(async (tx) => {
    const eco = await loadEconomy(tx);
    const user = await tx.get(`users/${uid}`);
    if (!user) throw new HttpError(404, "Profile not found", "NO_PROFILE");
    assertNotBlocked(user);

    const now = new Date();
    const patch = applyLazyState(user, eco, now);
    const granted = "coins" in patch ? asInt(patch.coins) - asInt(user.coins) : 0;
    if (Object.keys(patch).length > 0) tx.update(`users/${uid}`, patch);
    return {
      success: true,
      granted,
      coins: "coins" in patch ? asInt(patch.coins) : asInt(user.coins),
    };
  });
}

// --- claim-streak ----------------------------------------------------------

async function claimStreak(uid: string) {
  return await runTransaction(async (tx) => {
    const eco = await loadEconomy(tx);
    const user = await tx.get(`users/${uid}`);
    if (!user) throw new HttpError(404, "Profile not found", "NO_PROFILE");
    assertNotBlocked(user);

    const now = new Date();
    const patch = applyLazyState(user, eco, now);
    let coins = "coins" in patch ? asInt(patch.coins) : asInt(user.coins);

    const last = asDate(user.lastStreakClaim);
    if (last && utcDay(last) === utcDay(now)) {
      throw new HttpError(409, "You already claimed today's streak.", "ALREADY_CLAIMED");
    }
    const continues = last !== null && utcDay(last) === previousUtcDay(now);
    const streak = continues ? asInt(user.loginStreak) + 1 : 1;
    const reward = eco.streakRewards[(streak - 1) % eco.streakRewards.length];
    coins += reward;

    tx.update(`users/${uid}`, { ...patch, coins, loginStreak: streak, lastStreakClaim: now });
    return { success: true, streak, reward, coins };
  });
}

// --- redeem-referral -------------------------------------------------------

async function redeemReferral(uid: string, rawCode: string) {
  const code = normalizeCode(rawCode);
  if (!code) throw new HttpError(400, "Enter a referral code.", "BAD_REQUEST");

  return await runTransaction(async (tx) => {
    const eco = await loadEconomy(tx);
    const user = await tx.get(`users/${uid}`);
    if (!user) throw new HttpError(404, "Profile not found", "NO_PROFILE");
    assertNotBlocked(user);

    if (user.referredBy) throw new HttpError(409, "You have already used a referral code.", "ALREADY_REFERRED");
    if (user.referralCode === code) throw new HttpError(400, "You cannot use your own referral code.", "OWN_CODE");

    const codeDoc = await tx.get(`referralCodes/${code}`);
    const inviterUid = typeof codeDoc?.uid === "string" ? codeDoc.uid : null;
    if (!inviterUid) throw new HttpError(404, "Invalid referral code.", "INVALID_CODE");
    if (inviterUid === uid) throw new HttpError(400, "You cannot use your own referral code.", "OWN_CODE");

    const inviter = await tx.get(`users/${inviterUid}`);
    if (!inviter || inviter.isBlocked === true) throw new HttpError(404, "Invalid referral code.", "INVALID_CODE");
    if (asInt(inviter.referralCount) >= eco.referralCap) {
      throw new HttpError(409, "This referral code has reached its limit.", "CODE_LIMIT");
    }

    const now = new Date();
    const patch = applyLazyState(user, eco, now);
    const baseCoins = "coins" in patch ? asInt(patch.coins) : asInt(user.coins);
    const coins = baseCoins + eco.referralReward;

    tx.update(`users/${uid}`, { ...patch, coins, referredBy: code });
    tx.update(`users/${inviterUid}`, {
      coins: asInt(inviter.coins) + eco.referralReward,
      referralCount: asInt(inviter.referralCount) + 1,
    });
    tx.create(`users/${inviterUid}/notifications/ref_${uid}`, {
      title: "Referral Successful!",
      message: `A friend joined using your code! ${eco.referralReward} coins added to your account.`,
      timestamp: now,
      isRead: false,
    });
    return { success: true, reward: eco.referralReward, coins };
  });
}

// --- unlock-watermark ------------------------------------------------------

async function unlockWatermark(uid: string, historyId: string) {
  if (!/^[A-Za-z0-9_-]{6,64}$/.test(historyId)) {
    throw new HttpError(400, "Invalid image id", "BAD_REQUEST");
  }
  return await runTransaction(async (tx) => {
    const eco = await loadEconomy(tx);
    const user = await tx.get(`users/${uid}`);
    if (!user) throw new HttpError(404, "Profile not found", "NO_PROFILE");
    assertNotBlocked(user);

    const histPath = `users/${uid}/history/${historyId}`;
    const item = await tx.get(histPath);
    if (!item) throw new HttpError(404, "Image not found", "NOT_FOUND");

    const now = new Date();
    const patch = applyLazyState(user, eco, now);
    let coins = "coins" in patch ? asInt(patch.coins) : asInt(user.coins);

    const free = isPremium(user, now) || item.watermarkUnlocked === true;
    if (!free) {
      if (coins < eco.watermarkRemovalCost) {
        throw new HttpError(402, `You need ${eco.watermarkRemovalCost} coins to remove the watermark.`, "INSUFFICIENT_COINS");
      }
      coins -= eco.watermarkRemovalCost;
    }
    if (item.watermarkUnlocked !== true) tx.update(histPath, { watermarkUnlocked: true });
    if (Object.keys(patch).length > 0 || !free) tx.update(`users/${uid}`, { ...patch, coins });
    return { success: true, coins, charged: free ? 0 : eco.watermarkRemovalCost };
  });
}

// --- delete-account --------------------------------------------------------

async function deleteSubcollection(path: string) {
  let token: string | undefined;
  do {
    const page = await listDocs(path, 100, token);
    for (const d of page.docs) await deleteDoc(`${path}/${d.id}`);
    token = page.nextPageToken;
  } while (token);
}

async function deleteAccount(uid: string) {
  const user = await getDoc(`users/${uid}`);

  await deleteSubcollection(`users/${uid}/history`);
  await deleteSubcollection(`users/${uid}/notifications`);
  await deleteSubcollection(`support_tickets/${uid}/messages`);
  await deleteDoc(`support_tickets/${uid}`);
  await deleteDoc(`subscriptions/${uid}`);
  if (user && typeof user.referralCode === "string" && user.referralCode) {
    await deleteDoc(`referralCodes/${user.referralCode}`);
  }
  await deleteDoc(`users/${uid}`);

  // Finally remove the Firebase Auth account itself.
  const token = await getAccessToken(SCOPE_CLOUD);
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/accounts:delete`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ localId: uid }),
    },
  );
  if (!res.ok) {
    const detail = (await res.text()).slice(0, 200);
    if (!detail.includes("USER_NOT_FOUND")) {
      throw new Error(`Auth account deletion failed (${res.status}): ${detail}`);
    }
  } else {
    await res.body?.cancel();
  }
  return { success: true };
}
