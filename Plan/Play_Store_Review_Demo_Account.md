# Google Play review: demo account

**Build with demo mode:** version 1.1.6 (version code 20), signed with the upload key: `ph/offline/store/release/Zeta-Co-Pilot-1.1.6-vc20.aab`. Upload it to the track under review (Play Console → Test and release → Production → Create new release), then send the changes for review. The demo is also live at https://www.salesforceoffline.com.

Replace the old "Reviewer Salesforce account" (`play.review@zetapharma.com`). That is a real user in the Zeta production org: its password changed on 15 Oct, so every Google sign-in since 16 Oct failed.

Paste into Play Console → App content → **App access** → "All or some functionality is restricted" → Add instructions.

| Field | Value |
|---|---|
| Username | `review.demo@zeta-copilot.app` |
| Password | `Zc-CdvAR3-H6WSWY-Nlsbbw` |

**Instructions for the reviewer (paste as-is):**

> Open the app. On the Welcome screen, under "How do you sign in?", choose **Demo account (app review)**. Enter the username and password above and tap **Sign in**. The demo runs on sample data only (fictional doctors, pharmacies and products) and needs no company Salesforce login. All screens can be explored. Changes you make are kept on the device only.

The app ships only a SHA-256 hash of `username + newline + password` (`src/demo/demoMode.js`). To rotate: pick a new password, recompute the hash, update `DEMO_CREDENTIAL_SHA256`, rebuild and redeploy, then update Play Console.

Hash: `b27c8bfe238cba60f38730394c5aa0cf52fe2f370f1ab24e4a00fcf9309500c5`
