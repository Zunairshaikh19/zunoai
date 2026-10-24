# Zuno AI: competitor research (Imagine Art) and fix plan

Date: 2026-10-09. Competitor studied: Imagine Art (Vyro), Android app com.vyroai.aiart (10M+ downloads, 4.0 stars, about 441K ratings) and its web product.

## Sample (stated honestly)
- Google Play: 620 unique user reviews (copied by the user from the Play page). Dates: 2023 = 325, 2024 = 145, 2025 = 54, 2026 = 96. Star ratings were NOT in the export, so low-star filtering was not possible.
- Trustpilot: 20 reviews, 1 to 3 stars only, 13 Sep to 8 Oct 2026.
- Total 640 reviews, 2 sources. Theme counts below are keyword tallies with hand-read samples, so treat them as approximate. Recent window = 2025 and 2026 (150 Play reviews) because the app changed a lot in late 2025.
- Not covered: App Store, G2, Reddit (blocked in the browser), Hacker News (almost nothing relevant).
- The Play export has no per-review links, so quotes are not linked; each row is in reviews_play_imagineart.csv with its date.

## 1. What they hate (recent Play window of 150, plus Trustpilot)
1. Credits and pricing (about 42 of 150 recent; about 27 of 60 earlier tally with Trustpilot). Subscriptions that quietly turned into a credit system, "unlimited" that stopped being unlimited, credits that run out after a few generations.
2. Generation fails or returns nothing (about 29 of 150), often after watching one or more ads or spending credits. About 22 mention ads with no result. Several say credits were taken on a failed job.
3. Ads (about 30 of 150): long, unskippable, plus pop-ups asking to rate or subscribe.
4. Refunds, billing tricks and support (22 of 150 mention refund or scam; Trustpilot about 10 of 20 on misleading pricing or ads, about 13 of 20 on refused refunds). Annual plans sold as monthly, trials that converted, hard-to-find cancel.
5. Broken lifetime or annual deals (8 recent; 34 all-time).
6. Moderation (51 all-time, only 4 recent): unclear why a prompt is blocked.
7. Crashes and slowness (32 all-time, 4 recent).

## 2. What is missing (asked for)
- A visible reason or highlight when a prompt is blocked.
- Daily free credits that carry over.
- Use your own photo as the starting image (a top-helpful 2025 review, 963 helpful votes).
- A plain image tool without the video suite.

## 3. What is unsolved
- Older image-first users who feel the product became a video and credits platform and left them behind (lifetime, annual and "used to be great" complaints).
- Users who just want predictable cost per image.

## Fix plan for Zuno AI (ordered by evidence times cost)
| # | Change | Size | Where | Evidence |
|---|---|---|---|---|
| 1 | Auto-refund coins when a generation fails or times out; add a sweeper for jobs stuck in `charged` | M | supabase functions, economy | theme 2, 6+ explicit |
| 2 | Show coin cost before generating and the balance after; never say "unlimited" | S | upload_screen, paywall | theme 1 |
| 3 | Paywall shows full price, billing period, renewal date and how to cancel | S | paywall_screen | theme 4 |
| 4 | Rewarded ad: pending/retry state so coins arrive or the user is told why not; shorter ads; no rating prompt before first result | M | ad_service, rewarded_flow | themes 2 and 3 |
| 5 | Show why a prompt or photo is blocked; add report and ban path for misuse | M | generation, support chat | theme 6 + HN founder post on NSFW abuse |
| 6 | Keep finished results in History even if the app crashes or is closed | M | history_screen | themes 2 and 7 |
| 7 | Do not sell lifetime; do not change terms for existing subscribers without honoring them | S | policy, settings/economy | theme 5 |
| 8 | Keep "start from my photo" as a core feature | S | upload_screen | missing list |

## Positioning options
1. "Pay only for results": coins come back if a generation fails. Evidence: failure and wasted credits, 2 sources. Recommended, because items 1, 4, 6 make it true.
2. "Honest pricing": full price and easy cancel. Evidence: credits and billing complaints, 2 sources.
3. "Photos only, no video bloat": image-first. Evidence: lifetime and "used to be great" complaints.
Do not use the competitor's name in the app name, ads or store listing.

## Caveats
- Play default ordering and review self-selection skew negative; 2023 reviews are older and predate the credit system.
- A review of a different product (Trustpilot covers the web product and video features) may not apply to a mobile photo app.
