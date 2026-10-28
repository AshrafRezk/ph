# Account master + target reload — validation checklist

**Org:** zetapharma.my.salesforce.com  
**Reload date:** 22 Oct 2026  
**Sources:** `Organizations_FinalMaster_List_flagged.xlsx` + `Target List (All Team).xlsx`  
**Exception files:** `ph/scripts/tmp/account-reload/`

Use this after the wipe/reload. Mark each row Pass / Fail / N/A and note evidence (screenshot or record Id).

---

## 0. Access prerequisite (do this first)

| Role | Profile | Permission set group |
|---|---|---|
| Medical / Senior / Sales Rep | Standard User | `Pharma_Field_Rep_PSG` |
| District / Area / Field Force Supervisor / Line / Region / NSM | Standard User | `Pharma_District_Manager_PSG` |
| SFE / CRM admin | System Administrator | `Pharma_Admin` (+ `Pharma_SFE_App` where needed) |

**Status after reload (22 Oct):** seated active users audited; missing field PSGs assigned. Reps → Field Rep PSG; managers → District Manager PSG.

Before feature testing, confirm the test user below shows the expected PSG on their user record (Permission Set Group Assignments).

---

## 1. Suggested test users (real books)

Pick one from each row. Prefer users who can log in today.

### Field reps (have ATF on their territory)

| Emp # | Name | Title | Territory example | ATF on that seat | Username |
|---|---|---|---|---|---|
| 1770 | Abadir Esmat Tawfik Botros | Medical Representative | GIT-I ASSUIT-A | ~211 | abadir.esmat@zetapharma.net |
| 1033 | Abanob Bushra Abdelmessih Qudsy | Senior Medical Representative | GIT-I BEHIRA-A | ~182 | abanob.boshra@zetapharma.net |
| 1134 | Abdelrahman Mahmoud Abdelzaher Othman Fathullah | Medical Representative | GIT-I CAIRO WEST | ~151 | abdelrahman.mahmoud@zetapharma.net |
| 1052 | Abdelmonsef Galal Elshazly Esmail | Senior Medical Representative | ORTHO-I KAFR ELSHEIKH | ~92 | abdelmonsef.galal@zetapharma.net |
| 1432 | Abanob Alaa Eissa RezkAllah Haneen | Medical Representative | ORTHO-I FAYOUM | ~93 | abanob.alaa@zetapharma.net |

### Managers (DM / supervisor seats)

| Emp # | Name | Title | Territory example | Username |
|---|---|---|---|---|
| 1157 | Ahmed Magdy Elsayed Elmaghawry | District Sales Manager | GIT-I DM CAIRO B | ahmed.magdy@zeta-pharma.com |
| 1920 | Ahmed Gamal Mohamed Youssef | District Sales Manager | PED DM UE A | ahmed.youssef@zeta-pharma.com |
| 1329 | Ahmed Mohamed Aly Shaaban | District Sales Manager | PED DM CAIRO B | ahmed.shaaban@zeta-pharma.com |
| 460 | Ahmed Mosaad Mostafa Ibrahim | Field Force Supervisor | DM DERMA DELTA B | ahmed.mosaad@zeta-pharma.com |

### Admin / SFE

Use a known SFE or System Admin with `Pharma_Admin` for console / master-list checks.

---

## 2. Data perspective

Expected org totals after reload (spot-check with reports or SOQL):

| Check | Expected | How to validate | Result |
|---|---|---|---|
| Total Accounts | **135,183** | Accounts list count / report | |
| Pharmacies | **50,858** | Filter Pharmacy RT | |
| Clinics (`CLINIC-*`) | **42,331** | External Id starts with CLINIC- | |
| Doctors (`DOC-*`) | **39,519** | External Id starts with DOC- (3 workplace names skipped) | |
| Hospitals | **1,507** | Institution_HCO + Hospital | |
| Contracts | **758** | Institution_HCO + Contract | |
| Distributors | **210** | Distributor RT | |
| Doctor–clinic affiliations | **42,328** | Account Affiliation count | |
| Active call-plan rows (ATF) | **64,151** | Account Territory Fields, Is Active | |
| Bricks unchanged | **920** | Brick count still present | |
| Territories unchanged | **997** | Territory2 count | |
| Call history wiped | **0** visits/samples tied to old accounts | Confirm no pre-reload calls remain | |
| Account sales facts wiped | **0** pharmacy sales withdrawals | | |
| Company sales plans kept | Brick / Item / SOB targets still exist | Spot-check Sales Brick Share / Item Target | |

### Matching / alignment (critical)

| Check | Expected | How | Result |
|---|---|---|---|
| Doctor targets land on `DOC-*`, not a pharmacy with the same numeric code | 0 doctor ATF on Pharmacy RT | SOQL / report: ATF where Account External Id like DOC-% and RT = Pharmacy | |
| Pharmacy / hospital / contract / distributor targets match **Code only** | Sample 10 pharmacy ATF External Ids = sheet Code | Pick from Target List → open Account | |
| Clinic ATF only when workplace HCP was skipped | Exactly **1** CLINIC-* ATF (`CLINIC-30182` مصنع سكر قوص) | Search ATF by CLINIC- | |
| Affiliations link DOC + CLINIC | Open a multi-clinic doctor; both clinics affiliated | e.g. doctor with 2 clinics on master | |
| Class + visits/month on ATF | Match Target List New Class / New Frequency (else Default) | Spot 10 rows across teams | |
| Account class/tier stamped from target | Account classification reflects ATF | Open same 10 accounts | |
| No Brick on accounts yet | Brick blank until a brick file exists | Map / brick reports will not place accounts | |

### Exception lists (do not “fix” by inventing data)

Review CSVs under `ph/scripts/tmp/account-reload/`:

| File | Meaning | Approx rows | Validate |
|---|---|---|---|
| `target_exceptions.csv` Reason=`no_account` | Target row not on master | **34** | Confirm codes absent from Sheet1 |
| Reason=`vacant` | vac-* employee codes | 5,945 | No ATF expected |
| Reason=`no_user` | Employee code not in org | 14,924 | User missing or inactive |
| Reason=`no_territory` | User has no active territory seat | 2,246 | Organogram gap |
| `team_vs_territory_mismatches.csv` | Sheet Team Name ≠ organogram territory line | **89** | Organogram seat wins; list only |
| `multi_clinic_same_rep.csv` | Same doctor + same rep + 2 clinics → one plan, higher frequency | **20** | One ATF per doctor/rep |
| `workplace_skipped.csv` | Fake workplace names not created as HCP | **3** | Targets pointed at clinic where applicable |
| `missing_employees.csv` / `employees_without_territory.csv` | Seat gaps | 133 / 26 | HR / organogram follow-up |

---

## 3. Feature perspective — functional scenarios (core)

Run on **one rep from §1** in Salesforce Lightning, then repeat the same path in **Salesforce Offline / PWA** where noted. Prefer a weekday with no prior draft noise for that user.

**Channel rule (remember while testing):** AM = hospital HCO; PM = HCP, clinic, pharmacy, and other non-hospital accounts.

### 3A. Visit creation + draft submit

| # | Scenario | Steps | Pass if | SF | Offline |
|---|---|---|---|---|---|
| V1 | Create planned draft visit | Planner → pick in-plan doctor → create visit → status Draft | Draft saves; appears on day | | |
| V2 | Create hospital (AM) draft | Same for a hospital account | Visit on hospital; counts toward AM planned | | |
| V3 | Create pharmacy (PM) draft | Same for a pharmacy | Counts toward PM planned | | |
| V4 | Submit single draft | Open draft → Submit | Status → Submitted (or pending approval); no FLS crash | | |
| V5 | Submit week drafts | Create 2–3 drafts same week → Submit week | All eligible drafts submit; conflicts listed if any | | |
| V6 | Home after planning | Home → Your Performance | **Planned** count rises; Visits Achievement still actual/target; Remaining Calls drops only after **submitted/completed** actuals | | |
| V7 | Home AM/PM after planning | Note AM / PM Attainment cards | Target unchanged; **planned AM/PM** labels update; actual stays until submitted work | | |

### 3B. TOT (time off / office) creation

| # | Scenario | Steps | Pass if | SF | Offline |
|---|---|---|---|---|---|
| T1 | Create TOT block | Planner → add Time Off / Office Work for a field day | Block saves; day shows TOT | | |
| T2 | Submit TOT with week | Include TOT in week submit | TOT submitted per planner rules | | |
| T3 | Approved vacation impact | Create leave ≥ adjustment threshold (default **7** weekday days) as **Approved** `Time_Off_Request__c` (or via leave UI) → wait for target recalculation / run reapply if admin | Per-account **Target Visit Frequency** drops by rule step; home **target visits** lower; call rate measured vs reduced target | | |
| T4 | Short leave (grace) | Leave under threshold (e.g. 2–3 days) | Targets **not** stepped down (grace); coverage may still scale with field days | | |
| T5 | Long-term leave | Leave ≥ long-term threshold (default **40**) if rule enabled | Targets go to configured floor / zero per Call Target Rule | | |

Admin reference: Admin Console → Call Target Rules (`callTargetRuleManager`). Confirm adjustment is **on** before T3–T5.

### 3C. Overlaps (must not silently double-book)

Use Planner Rules (Allow / Warn / Block). Prefer **Block** for this validation.

| # | Scenario | Steps | Pass if | SF | Offline |
|---|---|---|---|---|---|
| O1 | Visit ↔ Visit overlap | Two visits same rep overlapping times | Second save/submit blocked or warned per rule; no silent overlap | | |
| O2 | Visit ↔ TOT overlap | Draft visit during an existing TOT block | Blocked/warned; message clear | | |
| O3 | Visit ↔ Meeting overlap | Visit during a meeting block (if meetings used) | Same policy applied | | |
| O4 | Weekend / non-working | Plan visit on weekend | Blocked/warned via working calendar | | |
| O5 | Reschedule into conflict | Move an existing draft onto a busy slot | Conflict service fires on reschedule | | |

### 3D. Vacations → target calls (end-to-end story)

| # | Check | How | Pass if | Result |
|---|---|---|---|---|
| L1 | Baseline | Note home: Target visits, Remaining, AM/PM targets, Call Rate strip | Screenshot / numbers recorded | |
| L2 | Book vacation | Approved leave covering ≥7 field weekdays in current month | Leave visible on time card / planner | |
| L3 | Targets recalculate | Refresh home / account targets | Monthly target calls **down**; Remaining down; attainment % may rise for same actuals | |
| L4 | Call rate vs reduced target | Open RF / account gaps | Frequency status uses **reduced** target (call rate path) | |
| L5 | Cancel / reverse leave | Cancel leave or reduce days below threshold → reapply | Targets restore toward class frequency | |

### 3E. AM / PM — target, planned, actual

| # | Check | Where | Pass if | Result |
|---|---|---|---|---|
| P1 | Territory rates configured | Territory Management → edit MR seat | **Call Rate**, **AM Call Rate**, **PM Call Rate** editable and saved | |
| P2 | Home rate strip | Field home (SF + Offline) | Shows Call / AM / PM **target** from territory and **actual** rates from time card (visits ÷ activity days) | |
| P3 | AM attainment | Home AM card | actual/target hospitals only | |
| P4 | PM attainment | Home PM card | actual/target non-hospital | |
| P5 | After planning only | Plan AM + PM drafts, do **not** submit | Planned totals up; actuals unchanged; attainment % unchanged | |
| P6 | After submit/complete | Submit then complete visits (or sync offline) | Actuals and AM/PM attainment move; time-card AM/PM visit rates move | |
| P7 | Drill | Click AM / PM KPI | Drill list is hospitals vs HCP/clinic/pharmacy | |

### 3F. Offline-specific

| # | Check | Pass if | Result |
|---|---|---|---|
| Off1 | Sync book after reload | Account count ≈ ATF book | |
| Off2 | Draft visit offline → sync | Appears in SF as Draft | |
| Off3 | Home metrics offline | Cached home shows same rate strip + AM/PM after prior online load | |
| Off4 | Conflict offline | Overlap attempt queues or rejects consistently | |

---

## 4. Feature perspective — persona smoke

### A. Field rep

| # | Feature | Steps | Pass if |
|---|---|---|---|
| R1 | Login + home | Log in as rep | No permission errors; Pharma field apps visible |
| R2 | Planner / call book | Open Field Planner / My Accounts | Sees **only** accounts on their ATF (≈ territory book size), not full 135k |
| R3 | Doctor vs pharmacy | Filter HCP vs Pharmacy | Doctors are person accounts (`DOC-*`); pharmacies are Pharmacy RT |
| R4 | Class & frequency | Open 3 planned accounts | Class / visits-per-month match Target List for that emp code |
| R5 | Search Arabic / Latin | Search أحمد / Ahmed / a pharmacy brand | Hits via cognitive name search; no blank crash |
| R6 | Account detail | Open doctor with affiliation | Sees clinic affiliation(s); can open clinic |
| R7 | Map / brick placement | Open map for accounts | Expect **no brick pin** until brick file is loaded (known gap) |

### B. District manager / supervisor

| # | Feature | Steps | Pass if |
|---|---|---|---|
| M1 | Login + manager apps | Log in as DM | District Manager PSG; manager planner / coaching visible |
| M2 | Team visibility | Open team / subordinate planners | Sees reports’ books, not only own seat |
| M3 | Approve / coach path | Open a report’s planned week (if coaching live) | Can open without FLS / object errors |
| M4 | Account search across team | Search a doctor on a report’s book | Found when in team scope |
| M5 | No double book | Same doctor assigned to two clinics on one rep | Appears **once** in that rep’s plan |
| M6 | Team AM/PM rates | Management KPI / team dashboard | AM / PM visit rates visible for reports | |

### C. SFE / Admin

| # | Feature | Steps | Pass if |
|---|---|---|---|
| A1 | Account Management | Open admin account tools | Can search master; Flagged Only sheet ignored (as designed) |
| A2 | Target export / governance | Export or view target list for one team | Aligns with ATF for that territory |
| A3 | Duplicate rule | Create/edit account carefully | Standard Account duplicate rule **active** again |
| A4 | Organogram intact | Territory tree + brick alignments | Users/territories/bricks still there; only accounts were reloaded |
| A5 | Sales plans intact | Brick / item / SOB targets | Still populated (not wiped) |
| A6 | Exception follow-up | Review 34 `no_account` + 89 team mismatches | Logged for business; not silently “fixed” |
| A7 | Territory call rates | Set Call / AM / PM rates on a test MR territory | Values persist; appear on that rep’s home | |
| A8 | Call target rules | Confirm vacation adjustment rule on | Matches T3–T5 expectations | |

---

## 5. Smoke matrix (45–60 min sign-off)

On **one rep + one DM**:

1. Rep login → planner count ≈ ATF; home shows Call / AM / PM rate strip  
2. Set or confirm territory Call Rate / AM / PM Call Rate on that seat  
3. Create hospital draft + HCP/pharmacy draft → home planned AM/PM up  
4. Attempt overlapping visit/TOT → blocked or warned  
5. Submit drafts → actuals / attainment move  
6. (If leave available) Approved ≥7-day leave → targets drop; note home before/after  
7. DM login → open that rep’s book  
8. Offline: sync → create one draft → sync back  
9. Admin: Account count still 135,183; ATF still 64,151  

| Persona | Tester | Date | Overall |
|---|---|---|---|
| Rep (SF) | | | Pass / Fail |
| Rep (Offline) | | | Pass / Fail |
| DM | | | Pass / Fail |
| SFE | | | Pass / Fail |

---

## 6. Known non-issues (do not raise as bugs)

- **Call history** from before the wipe is gone and cannot be restored from these two files.  
- **Brick / map placement** empty until a brick assignment file is provided.  
- **Vacant / no_user / no_territory** target rows have no ATF by design.  
- **Team Name on sheet vs territory line** mismatches are reported only; organogram seat is source of truth.  
- **Flagged Only** sheet is a warning list; those orgs are still on Sheet1 and were imported.  
- **Territory Call / AM / PM rates** are capacity targets; they do not auto-populate from the master/target Excel (those files have no brick/call-rate columns). Admins set them on the organogram.
