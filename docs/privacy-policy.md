# Regimen — Privacy Policy

**Last updated: August 30, 2026**

> **Before you publish this:** replace `support@example.com` below with a real
> address you monitor, and host this page at a public URL (GitHub Pages works:
> push this repo, then Settings → Pages → deploy from `/docs`). App Store
> Connect requires that URL before you can submit, and App Review will open it.
> This is a plain-language description of what the app actually does — it is
> not legal advice, and if you take payment in the EU/UK or expand what the app
> collects, have a lawyer review it.

Regimen ("the app") helps you track your skincare routine, predict when
products will run out, and follow changes in your skin over time. This policy
explains what the app collects, why, and what happens to it.

## What we collect

**Account information.** When you create an account we store your email
address and display name. Your password is handled by our authentication
provider (Supabase) and is stored only as a salted hash — we never see or store
your actual password.

**Your skincare data.** The products you add, when you use them, their sizes and
opened dates, and the usage history you create by checking products off.

**Progress photos.** Photos you choose to add, either from your camera or your
photo library. These are stored in a private, access-controlled bucket and are
only ever retrievable through short-lived signed links tied to your account.

**Skin analysis results.** If you run a skin scan, we store the resulting 0–100
score and a per-zone summary of what was detected. We do **not** store the
analyzed image separately — the scan reads the photo you already added.

**Subscription status.** Whether your account has an active premium
subscription. Payments themselves are processed entirely by Apple; we never
receive or store your payment details.

## What we do not collect

- We do not use analytics, advertising, or tracking SDKs. The app has no
  third-party trackers of any kind.
- We do not collect your location, contacts, health records, or device
  identifiers for advertising.
- We do not sell, rent, or share your personal data with third parties for
  their own purposes.
- We do not use your photos or data to train machine-learning models.

## Skin analysis happens on your device

The skin scan runs entirely on your iPhone using on-device Core ML models. Your
photo is **not** uploaded anywhere to be analyzed, and it is not sent to us, to
Apple, or to any third party for scoring. Only the resulting score and per-zone
summary are saved to your account so the app can show your progress over time.

Skin scan results are an estimate produced by a statistical model. They are
**not** a medical diagnosis and should not be used as a substitute for advice
from a qualified dermatologist or physician.

## Where your data is stored

Your data is stored with [Supabase](https://supabase.com), our database and
file-storage provider, and is protected by row-level security rules that
restrict every record to the account that created it. Data is encrypted in
transit using HTTPS.

## Notifications

If you enable reminders, the app schedules **local** notifications on your
device (for example, when a product is predicted to run low, or when your
streak is at risk). These are generated on-device and are not push
notifications sent from a server.

## The home screen widget

If you add the Regimen widget, your current streak and most recent skin score
are written to a shared container on your own device so the widget can display
them. This data never leaves your device.

## Your rights and choices

**Delete your account.** You can permanently delete your account and all
associated data from inside the app: Cabinet → profile icon → **Delete
Account**. This removes your account, products, usage history, photos, and
scan results. It cannot be undone.

**Access and correction.** You can view and edit your products, photos, and
profile at any time in the app. To request a copy of your data, contact us at
the address below.

**Cancel a subscription.** Manage or cancel your subscription through your
Apple ID subscription settings, in the app under Cabinet → profile icon →
Premium → **Manage**, or in the iOS Settings app.

## Children

Regimen is not directed at children under 13, and we do not knowingly collect
personal information from children under 13. If you believe a child has created
an account, contact us and we will delete it.

## Changes to this policy

If this policy changes materially, we will update the "Last updated" date above
and, where appropriate, notify you in the app.

## Contact

Questions about this policy or your data: **support@example.com**
