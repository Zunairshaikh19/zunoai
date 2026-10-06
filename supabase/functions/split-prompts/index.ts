// One-time (idempotent) admin migration: moves every prompt's `hiddenPrompt`
// text out of the publicly-readable `prompts/{id}` doc into the admin-only
// `promptSecrets/{id}` doc, so nobody can read the secret prompts through the
// open Firestore `prompts` collection any more.
//
// Call once, signed in as an admin:
//   POST /functions/v1/split-prompts   (Authorization: Bearer <admin Firebase ID token>)
// Safe to re-run; docs already migrated are skipped.
//
// IMPORTANT: after running it, update the admin panel so new prompts write the
// hidden text to `promptSecrets/{id}.hiddenPrompt` (not to `prompts`).

import {
  authenticate,
  corsHeaders,
  errorResponse,
  getDoc,
  HttpError,
  json,
  listDocs,
  runTransaction,
} from "../_shared/lib.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ success: false, error: "Method not allowed" }, 405);

  try {
    const auth = await authenticate(req);
    if ((await getDoc(`admins/${auth.uid}`)) === null) {
      throw new HttpError(403, "Admin access required", "FORBIDDEN");
    }

    let migrated = 0;
    let skipped = 0;
    let pageToken: string | undefined;
    do {
      const page = await listDocs("prompts", 50, pageToken);
      for (const d of page.docs) {
        const hidden = d.data.hiddenPrompt;
        if (typeof hidden !== "string" || hidden === "") {
          skipped++;
          continue;
        }
        await runTransaction(async (tx) => {
          tx.merge(`promptSecrets/${d.id}`, { hiddenPrompt: hidden, migratedAt: new Date() });
          tx.removeFields(`prompts/${d.id}`, ["hiddenPrompt"]);
        });
        migrated++;
      }
      pageToken = page.nextPageToken;
    } while (pageToken);

    return json({ success: true, migrated, skipped });
  } catch (err) {
    return errorResponse(err);
  }
});
