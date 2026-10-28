# Field APK push notifications (Salesforce → FCM)

**One Firebase account. One Field APK. Many Salesforce orgs.**

You do **not** create a Firebase project (or account) per customer org.  
You do **not** invent a separate “Firebase org id” per Salesforce org to decide who gets a push.

Do **not** put Firebase Admin / FCM secrets in `VITE_*` or git.

---

## How Salesforce knows which devices / which app

| Question | Answer |
| --- | --- |
| Which **app** receives the push? | The Field APK package `com.zetapharma.fieldpwa`, backed by the shared Firebase project **`salesforceoffline`**. Each Salesforce org’s External Client App (`OSR_Offline_Runtime`) is wired to that **same** FCM project. |
| Which **users/devices** get a push from Org A? | Devices that registered `MobilePushServiceDevice` **inside Org A** after login. Org B has its own registrations. Salesforce looks up recipients in **the org that sent the notification**. |
| Do orgs need different Firebase project IDs? | **No.** Every org pastes the **identical** shared id (`salesforceoffline`) + service account into its ECA push settings. |

```text
                    ┌──────────────────────────────────┐
                    │  ONE Firebase project            │
                    │  salesforceoffline (umbrella)    │
                    └─────────────┬────────────────────┘
                                  │ FCM
           ┌──────────────────────┼──────────────────────┐
           ▼                      ▼                      ▼
     [Salesforce Org A]     [Salesforce Org B]     [Salesforce Org N]
     ECA + same FCM creds   ECA + same FCM creds   ECA + same FCM creds
     MobilePushServiceDevice MobilePushServiceDevice ...
     (users who logged in)  (users who logged in)
```

The “which apps” link is: **ECA push settings → `salesforceoffline` FCM → package `com.zetapharma.fieldpwa`**.  
The “which devices” link is: **notification recipient User Id → that org’s `MobilePushServiceDevice` rows**.

---

## Manual steps

### A. Once (Salesforce Offline product — you)

1. Create **one** Firebase project under the **Salesforce Offline** umbrella.  
   Prefer project name / ID: **`salesforceoffline`** (not a customer brand like Zeta Pharma).  
   That project owns push for every org that uses this APK/website.
2. Add **one** Android app registered to the existing Cap package: `com.zetapharma.fieldpwa`  
   (package id is the installed app identity; Firebase **project** branding is Salesforce Offline).
3. Download `google-services.json` →  
   `ph/offline/android/app/google-services.json`  
   Rebuild and ship the **same** APK to all customers.
4. Generate **one** Admin SDK service account JSON (FCM HTTP v1).
5. Keep a small ops note for every org admin (same values everywhere):
   - Firebase **project ID**: `salesforceoffline` (or whatever id Firebase assigned — shared)
   - Base64(Admin SDK JSON)  
   Secure channel; never commit.

### B. Every Salesforce org (repeat — no new Firebase)

1. Confirm Field login uses External Client App **`OSR_Offline_Runtime`** (PKCE).  
   Push registration only works on sessions from the push-enabled ECA.
2. Setup → that ECA → enable **Push** + **Notification** plugins.
3. Paste the **same** shared credentials from step A5 (project ID + Base64 service account).  
   This is how **this org** knows to send through the Field APK’s Firebase app — not a unique Firebase id per org.
4. Deploy the push metadata pack:  
   [`force-app/main/default/manifests/field-apk-push-package.xml`](../../force-app/main/default/manifests/field-apk-push-package.xml)  
   (custom notification types + ECA subscriptions; **no** secrets in git).
5. After credentials save, set `pushByDefault` = **true** on the four custom types  
   (Visit Plan, Time Off, Coaching, Brick Sales). Salesforce blocks `true` until step 3 is done.
6. Optional: enable standard types (approvals, mentions, …) for this ECA in Setup → Notification Builder.

**New org checklist:** same FCM paste + deploy pack + `pushByDefault`. **No new Firebase project. No new APK.**

### C. Automatic (APK — no admin work)

On Capacitor Android after login to **that** org:

1. Permission → FCM token  
2. `POST MobilePushServiceDevice` on **that** org (storage keyed by instance host)  
3. Logout → delete that org’s registration  

Browser/website: no OS push; in-app bell only.

### D. Verify (any org)

1. Install the shared APK, sign into that org.  
2. User → **Mobile Push Registrations** present.  
3. Background app → custom notification or ECA “Send Test Notification”.  
4. Tap → approval inbox (no Welcome flash if session exists).

---

## What not to do

- Do **not** create Firebase projects per Salesforce org.  
- Do **not** put different FCM credentials per org (unless you intentionally ship multiple APKs).  
- Do **not** expect a per-org “Firebase org id” to route pushes — Salesforce org + `MobilePushServiceDevice` already does that.  
- Do **not** store the Admin SDK JSON in Custom Metadata / `VITE_*` / git.
