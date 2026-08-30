# App Store Connect — listing copy & submission notes

Draft copy for the fields App Store Connect asks for. Edit freely — this is a
starting point, not final copy. Character limits noted are Apple's hard caps.

## App name (30 char max)

    Regimen — Skincare Tracker

(24 chars. If already taken, "Regimen: Skincare Routine" is 25.)

## Subtitle (30 char max)

    Track, build, and use your routine right

(30 chars exactly — trim if it clips on smaller devices in review.)

## Promotional text (170 char max, editable without a new build)

    Log your products, catch ingredient conflicts before they happen, and
    scan your skin's progress over time — all with your camera, on your
    phone, never uploaded.

## Description (4000 char max)

    Regimen is a skincare cabinet that actually understands what's in it.

    Add the products you own and Regimen tracks how much you have left,
    predicts when you'll run out, and tells you what order to use everything
    in — so a retinol serum never gets layered under something that cancels
    it out.

    WHAT REGIMEN DOES

    • Cabinet — Log every product you own, with size, open date, and how
    often you use it. Regimen predicts when each one will run low.

    • Conflict checking — Regimen knows which active ingredients shouldn't be
    layered together (retinoids, exfoliating acids, vitamin C, benzoyl
    peroxide, and more) and flags real conflicts across your actual cabinet,
    not just a single product's label.

    • Routine builder — Answer a short quiz about your skin type, sensitivity,
    and how much time you want to spend, and Regimen builds a morning and
    evening routine from your own products — in the right order.

    • Progress photos & skin scan — Track your skin with photos over time.
    Run an on-device skin scan for a 0–100 score and a breakdown by area
    (forehead, cheeks, nose, chin) — the photo never leaves your phone.

    • Your Plan — After a scan, get a plain-language summary of where things
    are showing up, how to adjust your routine, and what to expect and when.

    • Streaks — Build a streak by logging your routine, with a calendar view
    of every day you kept it.

    • Home Screen widget — See your streak and score, and check off today's
    routine, without opening the app.

    Regimen doesn't diagnose anything and isn't a substitute for a
    dermatologist — it's a tool for keeping track of what you're doing and
    catching mistakes before they happen.

    PRIVACY

    Your skin scan runs entirely on your device using on-device machine
    learning. Your photos are never uploaded for analysis, sold, or used to
    train anything. No ads, no trackers, no analytics SDKs.

    PREMIUM

    Regimen is free to use for cabinet tracking, conflict checking, and the
    routine builder. Regimen Premium adds the interactive Home Screen widget,
    streak restores, and [list any other premium-gated features here].
    Subscriptions renew automatically; manage or cancel anytime in Settings.

(~1850 chars — well under the limit; there's room to expand.)

## Keywords (100 char max, comma-separated, no spaces needed but keep under 100)

    skincare,routine,tracker,ingredients,retinol,acne,skin,acids,cabinet,streak,dermatology

(~92 chars — swap words to taste; App Store Connect doesn't show these to
users, only its search indexer.)

## Category

Primary: **Health & Fitness**. Secondary (optional): **Lifestyle**.

## Age rating

Run the questionnaire in App Store Connect — nothing in Regimen should trip
any content flags (no user-generated content shown to others, no
unrestricted web access, no gambling/violence/mature themes). Expect **4+**.

## App Privacy questionnaire (Data Types)

Maps to what's actually collected — see `docs/privacy-policy.md` for the
full explanation. Answer each as **linked to identity**, **not used for
tracking**:

| Data type | Collected? | Used for |
|---|---|---|
| Email Address | Yes | App Functionality (account) |
| Photos or Videos | Yes | App Functionality (progress photos, on-device scan) |
| Health & Fitness (skin scan score/findings) | Yes | App Functionality |
| Product Interaction (usage logs, streak) | Yes | App Functionality |
| Purchase History | Yes (via StoreKit) | App Functionality |
| Contacts, Location, Browsing History, Identifiers, Usage Data for ads | No | — |

Answer **"Data Not Linked to Tracking"** / **App Tracking Transparency: not
required** — Regimen has no tracking SDKs and doesn't use IDFA.

## Privacy Policy URL

Publish `docs/privacy-policy.md` at a public URL before submitting (GitHub
Pages from this repo's `/docs` folder is the fastest path) and paste that URL
into App Store Connect's Privacy Policy field.

## Support URL

App Store Connect requires one. If there's no dedicated support page yet, a
GitHub Issues page on this repo, or a simple `mailto:` landing page, both
satisfy the requirement.

## EULA

Apple's Standard EULA (auto-applied if you leave this field blank in App
Store Connect) is sufficient for a subscription app like this — no need to
draft a custom one unless the subscription terms are unusual.
