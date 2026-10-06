# Zuno AI - Production Checklist

## 1. Economy and pricing (sized for $0.04 per image, 80% net margin)

1 coin = $0.001, 1 image = 40 coins. Google Play fee assumed 15%.

| Plan | Price | Coins/day | Max images/month | Max cost | Net margin |
|---|---|---|---|---|---|
| Premium monthly | $9.99 | 52 (+ streak) | ~42 | ~$1.68 | ~80% |
| Premium yearly | $79.99 | 33 (+ streak) | ~28 | ~$1.34/mo | ~80% |

Free users: 40 coins at signup, 5/day, 3 rewarded ads x 10 coins, streak 2-10, referral 20 (cap 10).
Free users are profitable only if rewarded-ad eCPM is high enough (roughly >= $13 for 3 ads/day). Check real AdMob numbers after launch and adjust `adRewardAmount` / `freeAdLimitPerDay` in `settings/economy`.

Seed Firestore `settings/economy` from `economy-defaults.json` (the old doc may still hold old values, e.g. adRewardAmount 40).

## 2. Deploy order

1. Rotate the ImgBB key that was previously committed; set new secrets:
   `supabase secrets set FIREBASE_SERVICE_ACCOUNT_KEY='{...}' IMGBB_API_KEY=... PLAY_SERVICE_ACCOUNT_KEY='{...}' APP_CHECK_ENFORCE=false`
   Optional: `ADMOB_REWARDED_AD_UNIT_IDS=ca-app-pub-x/yyyy` (restricts SSV to your unit), `REQUIRE_VERIFIED_EMAIL=true` (default).
2. `supabase functions deploy economy generate-image confirm-purchase admob-ssv upload-image mirror-image split-prompts`
3. Deploy Firestore rules: `firebase deploy --only firestore:rules`
4. Admin panel: new prompts must write `hiddenPrompt` to `promptSecrets/{id}` (not `prompts`). Run `split-prompts` once (as admin) to migrate old prompts, then delete `hiddenPrompt` from `prompts`.
5. Release the app only after the above (old app versions cannot write coins any more).

## 3. Manual setup that code cannot do

- AdMob: real app id + rewarded/interstitial/native units. Enable Server-Side Verification on the rewarded unit with callback URL
  `https://<project>.supabase.co/functions/v1/admob-ssv`. Build with
  `--dart-define=ADMOB_REWARDED_ANDROID=... --dart-define=ADMOB_INTERSTITIAL_ANDROID=... --dart-define=ADMOB_NATIVE_ANDROID=... -PADMOB_APP_ID=...`.
  Without them Google test ids are used (earn nothing).
- Play Console: create subscriptions `zuno_premium_monthly` ($9.99) and `zuno_premium_yearly` ($79.99). Setup > API access: link a service account with "View financial data" and "Manage orders and subscriptions"; put its key in `PLAY_SERVICE_ACCOUNT_KEY`.
- Firebase App Check: register Play Integrity, add the debug token for dev builds, watch metrics, then set `APP_CHECK_ENFORCE=true`.
- Release signing: copy `android/key.properties.example` to `android/key.properties` (never commit), build `flutter build appbundle --release`.
- Add `android/key.properties` and `*.jks` to `.gitignore`.
- Privacy policy URL, Play Data safety form, and an account-deletion URL (in-app "Delete Account" exists in Profile).
- Cancel active Google Play subscription before deleting an account (deletion does not cancel it).
- Content: add a report/moderation path if you allow user photos (Play UGC policy).

## 4. Known limitations

- Dart code and Firestore rules were written without access to a Flutter SDK / emulator: run `flutter pub get && flutter analyze && flutter test`, and test rules + functions against the Firebase emulator / a staging project.
- Edge-function logic has unit tests (`deno test --allow-env --allow-net=none supabase/functions/_shared/lib_test.ts`) against an in-memory Firestore fake only.
- Premium renewals/cancels are refreshed at app launch (no Play RTDN yet). iOS purchases return 501.
- A generation job stuck in `charged` (server crash after charging) has no automatic sweeper.
- The un-watermarked image URL is public on ImgBB; watermark is a soft gate.
- Free-tier profitability depends on real rewarded eCPM.
