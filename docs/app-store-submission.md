---
title: Regimen — App Store Submission
---

# Regimen — App Store Submission Checklist

Everything needed to get version 1.0 submitted, in the order it has to
happen. Items marked **BLOCKER** stop the submission; the rest can be
fixed in review feedback if you run out of time.

Current state of the build: Debug, Release and the widget extension all
compile clean, 81 tests pass, bundle `com.alecagayan.Regimen`, version
**1.0 (1)**, deployment target **iOS 17.0**, team `N92ZZ9Q2HJ`.

---

## 0. Before anything else — run the migrations

**BLOCKER.** The app has features whose tables don't exist yet in
production. Run these in the Supabase SQL Editor **in this order**. Each is
idempotent where it can be, but order matters because later ones alter
tables earlier ones create.

```
schema.sql
catalog.sql
layering.sql
dose.sql
skin_scores.sql
skin_score.sql
premium.sql
multi_tag_conflicts.sql
catalog_more_brands.sql
catalog_dermocosmetic_brands.sql
zone_findings.sql
delete_account.sql
streak_restores.sql
free_scan.sql
streak_restore_credits.sql
skin_profile.sql
scan_persistence.sql
indexes.sql
schedules_and_history.sql
product_ingredients.sql
analytics.sql
```

Not migrations — do **not** run these against production:
`seed_test_account.sql`, `seed_sample_analytics.sql`,
`simulate_streak_restore_a@a.a.sql`. They create synthetic accounts and
test data. Delete them from the repo before it goes public, or at minimum
never run them on the live project.

Verify afterwards:

```sql
select table_name from information_schema.tables
where table_schema = 'public' order by 1;
-- expect: analytics_events, catalog_products, product_empties, products,
--         profiles, progress_photos, skin_reactions, streak_restores,
--         usage_logs, zone_findings
```

---

## 1. Test on a real device

**BLOCKER — nothing below is trustworthy until this is done.**

Four features have never run on hardware and cannot be validated in the
Simulator at all:

| Feature | Why the Simulator can't tell you |
|---|---|
| Barcode scanning | Needs a real camera feeding real frames |
| Camera framing guide | Overlay sits on the live viewfinder |
| Siri phrases | Needs on-device intent donation and a real Siri request |
| Widget check-off taps | Cross-process App Group writes, real timeline reloads |

Also worth a pass on device, since they were verified by construction
rather than by touch: the check-off spring, button press feedback, and the
score count-up.

There is a standing environment problem on this Mac that blocks automated
device/simulator control:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

That needs your password, so it has to be run by hand.

---

## 2. App Store Connect — in-app purchases

Three products. The IDs must match **exactly**; the app looks them up by
string and silently finds nothing if they differ.

**Subscriptions** (one group, e.g. "Regimen Premium"):

| Field | Monthly | Yearly |
|---|---|---|
| Product ID | `com.alecagayan.Regimen.premium.monthly2` | `com.alecagayan.Regimen.premium.yearly` |
| Reference Name | Regimen Premium Monthly (2026) | Regimen Premium Yearly |
| Duration | 1 Month | 1 Year |
| Price | $1.99 | $19.99 |

> The monthly uses `monthly2` because the original ID was deleted, and
> Apple never releases a product ID or reference name for reuse.

**Consumable:**

| Field | Value |
|---|---|
| Product ID | `com.alecagayan.Regimen.streakrestore.single` |
| Reference Name | Extra Streak Restore |
| Price | $0.99 |

Each subscription needs its own **Review Screenshot** — a capture of
`PaywallView` showing price and billing period. The same image works for
both, but it must be uploaded to each one separately or "Add for Review"
stays blocked.

---

## 3. App Privacy questionnaire

The app collects more than it used to. Declare all four:

| Data type | Linked | Tracking | Purpose |
|---|---|---|---|
| Email Address | Yes | No | App Functionality |
| Photos or Videos | Yes | No | App Functionality |
| Health & Fitness | Yes | No | App Functionality |
| Product Interaction | Yes | No | App Functionality **and Analytics** |

Product Interaction is the analytics events, tied to `user_id`, so it is
**Linked to You**. There is no third-party collector and no tracking
across apps, so no ATT prompt is required.

`PrivacyInfo.xcprivacy` ships in both targets and already declares these.

> **Check before submitting:** the `NSPrivacyAccessedAPICategoryUserDefaults`
> reason codes (`CA92.1`, `C56D.1`) against Apple's current published list.
> The app reads and writes its own defaults *and* an App Group shared with
> the widget, and I'm not confident `C56D.1` is the right code for the
> latter — App Group access is usually `1C8F.1`. Worth five minutes on
> Apple's docs; a wrong code draws a rejection notice.

---

## 4. App Review Information

**Sign-In Required: Yes.** There is no guest mode.

**Demo account.** Create a dedicated one, then:

1. Add 2–3 products so Routine, conflicts and the widget have content.
2. `update public.profiles set is_premium = true where id = '<uuid>';`
3. Check **Supabase → Authentication → Settings → Confirm email.** If it's
   on, that account and any fresh signup by a reviewer will stall waiting
   for an email they can't receive. Either turn it off or mark that user
   confirmed by hand.

**Contact:** your name, phone, `alecagayan24@gmail.com`.

**Notes** (paste as-is, edit the account line):

> This app requires an account (email/password). The demo account above is
> pre-loaded with sample products and has premium enabled. To test the skin
> scan, use any front-facing photo — analysis runs entirely on-device and
> no photo is uploaded for scoring. To test the Home Screen widget, long-
> press the Home Screen, tap "+", and search "Regimen"; it is a premium
> feature and the demo account already has premium. In-app purchases
> (`com.alecagayan.Regimen.premium.monthly2`, `.yearly`,
> `.streakrestore.single`) can be tested in sandbox as normal.

The widget note matters — reviewers have marked features "not found" when
they require manually adding a widget.

---

## 5. Listing

- **Support URL** and **Privacy Policy URL**: the GitHub Pages site —
  `https://alecagayan.github.io/Regimen/` and
  `.../Regimen/privacy-policy.html`. Confirm both load before submitting;
  a dead privacy policy URL is an automatic rejection.
- **EULA**: leave blank, Apple's standard one applies.
- **Age rating**: 4+ is defensible. The app gives general skincare
  guidance, not medical advice, and says so in-app.
- **Screenshots**: 6.9" is the only mandatory size. Shot list and listing
  copy are in `docs/app-store-listing.md`.
- **Encryption**: `ITSAppUsesNonExemptEncryption` is already declared in
  both targets, so the export-compliance question is pre-answered.

---

## 6. Archive and upload

```
Xcode → Product → Archive → Distribute App → App Store Connect
```

Version **1.0**, build **1**. If you need to re-upload, bump
`CURRENT_PROJECT_VERSION` only — build numbers must be unique per version.

---

## Known gaps going in

Worth deciding about consciously rather than discovering in review:

- **The skin score is weak and framed honestly.** R² 0.28 against its
  lesion-count target, MAE 9.0 versus 10.6 for guessing the mean — about
  15% better than a constant. The UI never presents it as clinical, the
  scan disclaims being a diagnosis, and score movements under 9 points are
  deliberately not reported as progress. Keep that framing; it's what makes
  the feature defensible.
- **Localization**: English only, no String Catalog.
- **Accessibility**: 12 of 31 view files have explicit labels. The
  high-traffic ones are covered; the rest have never been audited.
- **Analytics has no dashboard.** Query it in the Supabase SQL Editor;
  saved queries pinned to a Report page work well (see `analytics.sql`).
