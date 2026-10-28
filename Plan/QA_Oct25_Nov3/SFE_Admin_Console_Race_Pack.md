# SFE admin console race pack: 26 Oct to 8 Nov 2026

Every admin console module is tested by the SFE who will own it after go-live. Each SFE uses their own login. They then use **Login As** to open salesforceoffline.com as a rep on their lines and check that the setup reaches the field.

Org: `zetapharma.my.salesforce.com` · App: SFE Co-pilot → Admin Console · Evidence run 25 Oct: [docs/admin-console-test-2026-10-25/notes.md](../../../docs/admin-console-test-2026-10-25/notes.md)

Rules from [README.md](README.md) apply. In production, exports run for real and imports stop at the preview step.

---

## 1. Who tests what

All five SFEs are on the **System Administrator** profile and hold `Pharma_Admin` and `Pharma_SFE_App` (checked 26 Oct). Those two sets grant every custom permission the console checks: `Manage_Meeting_Workflows`, `Meeting_Super_User`, `Merge_Account_Duplicates` and `Edit_Visit_Date`.

| SFE | Username | Lines (SFE Approvers) | Last login | Gap |
|---|---|---|---|---|
| Dr. Ahmed Abdullah (SFE Manager) | ahmed.abdullah@zeta-pharma.com | — | 26 Oct | — |
| David Gerges | david.badie@zeta-pharma.com | All lines | 26 Oct | — |
| Hamsa Mahmoud | hamsa.diaaeldin@zeta-pharma.com | Diabetes, GIT | 26 Oct | — |
| Manar AbdelHakim | manar.saleh@zeta-pharma.com | CHC, Cluster | 26 Oct | No `Meeting_Finance`: cannot do the finance step on meetings (Wave I) |
| Aya Elhawary | aya.adel@zeta-pharma.com | All lines | **21 Oct** | Same as Manar. Also missing `Meeting_Setup_Admin`, `Field_App_Feature_Admin` and `Zeta_HCP_App_Manager` (works today through the System Administrator profile). Confirm she can sign in before her slot. |

All five also need the new **`Field_Login_As`** permission set (section 3).

## 2. Module matrix

Status is from the Cloudastick run on 25 Oct. **Owner** runs the module as themselves and signs the result. **Retest** is the Zeta day in [CALENDAR.md](CALENDAR.md).

| # | Module | BRD | Owner | Retest | 25 Oct | What the owner must confirm / open item |
|---|---|---|---|---|---|---|
| 01 | Field App Manager | 5.14, 5.17 | Aya | Mon 26 | Pass | Home widgets, rings, planner tools and requests match what Zeta wants live. Toggle one and check it with Login As. |
| 02 | HCP Portal | 5.4.5 | Aya | Mon 26 | Pass | Tabs for the /meet guest app. |
| 03 | Co-pilot app tabs | 5.18 | Aya | Mon 26 | Pass | Field tabs on/off. **Meetings, Speakers are off** — confirm intended. |
| 04 | Visit Tabs | 5.4.1 | Aya | Mon 26 | Pass + note | 'Person Account' row appears twice (two record types share the label). |
| 05 | CLM | 5.12, C4 | Aya | Wed 28 | Pass (preview) | Product column shows a placeholder image on every deck. CLM publish is Aya's approval (BRD §6). Don't publish to every territory. |
| 06 | Rating Layouts | 5.3 | Hamsa | Wed 28 | Pass | HCO + HCP layouts deployed. |
| 07 | Learning Module Mgmt | 5.6 | Manar | Wed 28 | Pass + note | CHC shows '2 assigned' but 0 territories selected. Confirm whether courses are assigned to users or to territories. |
| 08 | Quiz Management | 5.6 | Manar | Wed 28 | Pass + UX | Question editor opens below the list with no scroll. |
| 09 | Coaching Management | 5.5, C6 | Manar | Wed 28 | Pass + note | 'Visit Check (Copy)' looks like a leftover. Deactivate or keep? |
| 10 | Territory Management | 5.8, 5.11 | Hamsa | Mon 26 | Pass + notes | Organogram export truncates 'Assigned User'. One-off buttons still live ('Apply October line assignments', 'Apply CHC/GIT/CVM mirrors', 'Seat Brand Managers'). CHC BU code TERR_BU_338. **Login As starts here** (section 3). |
| 11 | SFE Approvers | 5.8, §6 | Dr. Ahmed | Mon 26 | Pass + UX | 'New accounts' column clipped at 1024 px. |
| 12 | Bricks Manager | 5.11 | Hamsa | Mon 26 | Pass | 702/702 bricks, 148 regions. **Do not** click 'Apply regions to sales'. |
| 13 | Products Manager | 5.7 | Hamsa | Mon 26 | Pass + notes | 'CHC DM DELTA' appears twice. Training territories show here. |
| 14 | Promo Grid | 5.11 | Hamsa | Mon 26 | **Fixed 25 Oct** (retest) | Round-trip fix is in production (test `previewJson_keepsLineNamesFromTheWorkbook` passes). Hamsa: export a line, import the same file, preview must show Ready, not '(unnamed)'. |
| 15 | Sample Logistics | 5.13, C3 | David | Wed 28 | Pass + notes | Lot 2010 expired 30 Sep but still on hand with no flag. Test request SR-00000 from Cloudastick is still in the queue. |
| 16 | Plan Manager | 5.15 | Dr. Ahmed | Thu 29 | Pass / **RISK** | Only 19 of 694 (3%) have an October plan. Wave E (Thu 29) needs plans for the test reps. |
| 17 | Call Target Rules | 5.15 | Dr. Ahmed | Tue 27 | Pass + UX | Hide the 'Calls to subtract (no longer used)' field. |
| 18 | KPI Targets | 5.15 | Dr. Ahmed | Wed 28 | Pass + note | 42 metrics. Confirm 'Reset to framework' asks before it resets. |
| 19 | Sales Policy | 5.9 | Dr. Ahmed | Wed 28 | Pass | Cap 200, tender excluded, 'Zeta Colest' exception. |
| 20 | Monthly data pack | 5.9, C9 | David | Wed 28 | Pass (preview) | Import preview read the file correctly. |
| 21 | Export month | 5.9 | David | Wed 28 | **Data loaded 25 Oct** (retest) | 121,551 withdrawal rows now: Sep 120,770 · Aug 519 · Jun 262. Retest with a September date. |
| 22 | Distributors Mgmt | 5.9 | David | Wed 28 | Screens pass / **RISK** | Every withdrawal row has a brick and product, but **0 are linked to a pharmacy account**: brick-level sales work, per-pharmacy sales don't. 'Max rows (pilot) 200' is still the default. |
| 23 | Target Governance | 5.11 | Dr. Ahmed | Tue 27 | Fixed 25 Oct | Retest: loads, thresholds 10/10. |
| 24 | Account Management | 5.1, C1 | David | Tue 27 | **Fixed 25 Oct** (retest) | Opens on Export now (checked in production code). Import/Modify still has no preview step. |
| 25 | Account data quality | 5.1 | David | Tue 27 | Pass | Scans not run (they create proposals). |
| 26 | Target & Master Lists | 5.11 | David | Tue 27 | Pass | 64,151 targets and 135,183 masters round-trip exactly. |
| 27 | Public Holidays | 5.4.2 | Aya | Mon 26 | Pass + **data** | 10 active (Coptic Christmas and Christmas Eve added 26 Oct). Still missing Sham El-Nessim, Islamic New Year, Prophet's Birthday. Each Eid is a single day. One-off Eids need 2027 dates. |
| 28 | Planner Rules | 5.4.1–2 | Aya | Mon 26 | Pass | Sat–Wed working week. Overlap matrix is set. |
| 29 | Meetings Setup | 5.4.5, §6 | Manar | Thu 5 | Pass + UX | Raw keys 'Tab:overview'. Banner shows 'Meeting__c' and training text. |
| 30 | Service Request Types | 5.4.5 | Manar | Thu 5 | Pass + notes | Typo 'Accomodation'. Seed button 'Load Marketing and Medical services' still visible. |
| 31 | Integrations | §7, 5.10 | David | Thu 5 | Status page | IQVIA catalog only, with 0 accounts carrying `Brick__c`. Mendix pending. |
| 32 | Chrome & Data Tools | — | Manar | Mon 26 | Pass | Reference only. |
| 33 | Help | — | Manar | Mon 26 | Pass + minor | Search ranking is minor. |

### Must fix before the SFE retests

| Priority | Item | Blocks |
|---|---|---|
| ~~1~~ | ~~**24** Wipe & Load default tab~~ fixed 25 Oct | — |
| ~~2~~ | ~~**14** Promo grid round trip~~ fixed 25 Oct (2 test-only failures fixed 26 Oct, validated) | — |
| 3 | **22** Withdrawals not linked to pharmacy accounts (21 now has data) | Per-pharmacy sales, Wave J reports |
| 4 | **16** Only 3% of October plans exist | Wave E (Thu 29) |
| 5 | **27** Holidays incomplete (SFE data entry, not code) | Planner rules from Wave E onward |
| 6 | Aya / Manar `Meeting_Finance` | Wave I (Wed 4) |

## 3. Login As into salesforceoffline.com

**Where:** Admin Console → Territory Management → **Users** tab → the **⋯** menu on a user → **Open field app as user**.

**What happens:** the SFE types a reason (e.g. "Wave E retest, issue 42") and clicks **Start session**, then **Open field app**. salesforceoffline.com opens signed in as that rep, with an orange bar: *Signed in as Abadir … by Aya …* and an **Exit** button.

| Rule | Detail |
|---|---|
| Who can use it | Only users with the `Field_Login_As` permission set (the five SFEs). |
| Who can be opened | Active field users only. Administrators and the SFE's own user are refused. |
| What the SFE can do | Everything the rep can. Plans, visits, samples and orders are **saved as the rep** (decided 26 Oct). |
| How long | Until the org session timeout. There is no refresh token, so the session cannot run on as the SFE. When it ends, the app shows a message and returns to sign-in. |
| Audit | Every start, refusal and failure is a **Field Login As Log** record (`FLA-#####`). Created By is the SFE; the record holds the target user, reason and status. |
| Device | The browser becomes the rep's device until **Exit**. If the device has unsynced changes, Login As refuses to start. Exit warns if the rep's changes haven't synced yet. |
| Limit | Salesforce only issues the session if the rep has signed in to salesforceoffline.com **at least once**. Otherwise the SFE sees: *"… has not signed in to the field app yet …"* |

### One-time setup (in order)

1. **pharma-prod org** (`admin@pharma.eg`): Setup → App Manager → **Pharma Field Offline** → Edit → tick **Use digital signatures** → upload [login-as/Zeta_SelfSignedCert_04Aug2026.crt](login-as/Zeta_SelfSignedCert_04Aug2026.crt) → Save. This only adds the JWT flow; the PKCE sign-in reps use today is unchanged. Wait about 10 minutes for it to take effect.
2. ~~**Zeta org**: deploy the package~~ **Done 26 Oct**, deploy `0Afiv0000005gBVCAY` (6/6 tests).
3. ~~**Zeta org**: assign `Field_Login_As`~~ **Done 26 Oct**: the five SFEs + `cloudastick@zetapharma.com`.
3b. **Zeta org, so Login As works for every rep**: as of 26 Oct only 18 users have ever signed in to the field app, and none of the QA seats (Abadir, Abdelmonsef, Ahmed Magdy, Ahmed Mosaad) are among them. Setup → Connected Apps OAuth Usage → **Pharma Field Offline** → Manage → Edit Policies → Permitted Users = **Admin approved users are pre-authorized** → Save → Manage Profiles → tick **Standard User** and **System Administrator**. Those two profiles cover all 797 active people, so no one who signs in today gets locked out.
4. **salesforceoffline.com**: push `ph/offline` (`src/loginAs.js`, `src/main.js`, `src/apex/restHelper.js`, `src/shell.css`) to `AshrafRezk/ph` main. Netlify deploys it.
5. Smoke test (works before step 3b): Hamsa → **Nada Wael** or **Gasem Gamal** (both signed in to the field app on 22 Oct). After 3b: Aya → Abadir (GIT-I ASSUIT-A) → the orange bar shows → Planner shows his 211 targets → Exit → the log row shows Status = Started.

### Login As journeys per SFE

Run after the setup above, on the same reps the QA days use, so records stay comparable.

| SFE | Rep to open | Check in the field app | QA wave |
|---|---|---|---|
| Hamsa | Abadir Esmat (GIT-I ASSUIT-A) | Products, promo grid weights and bricks she set appear in Planner and visit | D–E (Wed 28 – Thu 29) |
| Manar | A CHC rep on her lines | Learning course and quiz show in My Learning. The coaching template shows for the DM. | D, G |
| Aya | Abdelmonsef Galal (ORTHO-I KAFR ELSHEIKH) | Field App Manager toggles, visit tabs and holidays block the planner | A, E |
| David | Abadir (pharmacy accounts) | Sample allocation shows in rep inventory. Target list matches. | B, F |
| Dr. Ahmed | Ahmed Magdy (GIT-I DM CAIRO B), manager | Team home shows KPIs. Approves the plan the rep submitted. | H (Tue 3) |

Log every Login As result in the issue log with the `FLA-` number as evidence.
