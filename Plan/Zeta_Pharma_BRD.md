# Business Requirements Document (BRD)

**Project:** Zetapharma — Sales Cloud for Pharmaceuticals  
**Document type:** Business Requirements Document (Discovery Draft)  
**Session:** Discovery 2  
**Status:** Draft for workshop  
**Market:** Egypt  
**Last updated:** August 2026

---

## Document purpose

This BRD frames business requirements for Zetapharma’s Salesforce Sales Cloud for Pharmaceuticals program. It is a **hybrid discovery working document**: product module descriptions are filled, Client Notes are seeded from Discovery Session 1, and open prompts mark what to confirm in Discovery Session 2.

**MoSCoW legend**

| Code | Meaning |
|------|---------|
| **M** | Must have for go-live |
| **S** | Should have in wave 1–2 |
| **C** | Could have / later |
| **W** | Won’t have this program |

---

## 1. Introduction

Sales Cloud for Pharmaceuticals leverages **20+ years of experience** in the pharma and Salesforce industry, poured into Salesforce to digitize pharma teams — Sales and Medical on the field, learning materials for the team, and selected HR-adjacent field capacity functions.

**This project is focused on Sales / Medical rep fieldwork and their management:** planning, visits, coaching, approved content, products, users and hierarchy, distributor sales data, and promotional-activity integrations.

The platform supports a multi-BU commercial structure typical of Zetapharma (e.g. **GIT, Diabetes, Cluster, CHC**) with three persona apps in the reference stack:

| App | Who | Primary job |
|-----|-----|-------------|
| **Pharma Field** | Medical reps | Plan, visit, report, present, sample |
| **Pharma Management** | DMs, SFE, regional managers | Coach, approve, monitor KPIs |
| **Pharma Executive** | C-level, BU heads | Portfolio, budgets, workforce visibility |

---

## 2. Stakeholders

| Name | Role | Mobile | Email | Notes |
|------|------|--------|-------|-------|
| Ahmed Hamid | Business Excellence Manager | | | |
| Ahmed Abdallah | SFE Manager | | | |
| Sameh Samy | IT Manager | | | Mendix product codes; super admin |
| David | Data Analyst | 01212167784 | david.badie@zeta-pharma.com | Data; support on sample management |
| Aya | Senior SFE | 01002949966 | aya.adel@zeta-pharma.com | CLM / e-detailing owner |
| Mr. Ashmawy | *(confirm title)* | | | Sample management involvement |
| Marketing team | Brand / Marketing | | | Sample flow; Brand Reminder ownership via Brand Managers |

**Discovery prompt:** Confirm mobiles/emails for Ahmed Hamid, Ahmed Abdallah, Sameh Samy; additional sponsors (Commercial, Compliance / Medical Affairs); RACI for go-live decisions.

---

## 3. Company users & org footprint

| Role / persona | Count | Notes (Session 1) |
|----------------|------:|-------------------|
| Medical Rep | 721 | **81 vacant** territories / slots |
| District Manager (DM) | 106 | Single visits on KOL lists + Double visits |
| Area Manager (AM) | 8 | Single visits on KOL lists + Double visits |
| National Sales Manager (NSM) | 15 | Single visits on KOL lists + Double visits |
| Business Unit Manager (BUM) | 4 | |
| Brand Manager | 15 | 3 Cluster, 4 Diab, 1 CHC, 4 GIT *(confirm remaining split)* |
| Group Product Manager | 2 | Cluster, Diab |
| Field Trainer | 5 | Double visits; All BUs — Cairo / Giza / Upper Egypt / Alex and Cairo 2 / Delta 1 |
| Field Trainer Manager | 1 | |
| Field Intel Trainer (Data / Segmentation) | 2 | Cairo, Giza |
| Super admins | 3 | Part of 8 admin-tier users |
| Admins | 2 | Part of 8 admin-tier users |
| Super users | 3 | Part of 8 admin-tier users |
| Super admin (Sameh) | 1 | Dedicated |

**Approximate active field logins (excl. vacant MR slots):** ~640 Medical Reps + management / trainers / brand / admin tiers as above.

**Discovery prompts**

- Confirm exact BU split for the 15 Brand Managers (3+4+1+4 = 12; 3 unassigned in notes).
- Confirm which roles need Salesforce licenses vs. report-only / community access.
- Confirm double-visit coaching rules by role (DM / AM / NSM / Field Trainer).

---

## 4. Modules summary

| # | Module | Description | Client Notes | MoSCoW |
|---|--------|-------------|--------------|--------|
| 1 | Account Management | HCP / HCO / Pharmacy / Business Contact types; governed create + approval for new accounts | | |
| 2 | Affiliation Management | Relationships HCO?HCP?Pharmacy; auto from visit attendees, data feed, or nearby-pharmacy after visit | | |
| 3 | Ratings Management | Territory-scoped profiling: penetration / potential, Rx company vs competitor, patient flow, etc. | | |
| 4 | Activities Management | Visits, TOT, WhatsApp assist, promotional activities (see 4.1–4.5) | DM/AM/NSM: Single on KOL + Double | |
| 4.1 | Visits (Planner lifecycle) | Draft ? Planned ? Submitted / Cancelled; optional approval | | |
| 4.1.1 | Medical Inquiry (in visit) | MI raised from visit ? Case / Medical Affairs | | |
| 4.2 | Time Off Territory (TOT) | Creation process, rules, approval, KPI denominator impact | | |
| 4.3 | WhatsApp assistance | Visit reminders; post-visit surveys | | |
| 4.5 | Promotional Activities | Initiation + workflow (links to Mendix where applicable) | | |
| 5 | Coaching Management | Double visits; coaching event; captured insights | Field Trainers / DM–NSM double | |
| 6 | LMS | Courses; medical exams; product exams | | |
| 7 | Product Management | Therapy areas / brands / products; Brand Reminder | Brand Reminder by 15 BMs; Mendix codes ? Sameh | |
| 8 | Users Management | Hierarchy, roles, access levels | See §3 headcount table | |
| 9 | Distributor Sales Data | Import / manage distributor (sell-out) data for field action | | |
| 10 | Mendix Integration | Promotional activities integration | Product codes presence TBD (Sameh) | |
| 11 | Territory Alignment & Targeting | ATF / ATPF / PTA / bricks; who owns which customer × product | 81 vacant MR slots still need territories | |
| 12 | CLM / e-detailing | Approved presentations; in-visit player; dwell / message tracking | **Aya** — provided in data sheet | |
| 13 | Sample Management | Inventory, lot/expiry, visit deduction, audit | Flow TBD; Marketing; Mr. Ashmawy; **David** to help | |
| 14 | Field Experience (Home + Planner) | Morning KPIs, map, NBC; weekly calendar + route | | |
| 15 | Plan Cycle & Rep 360 / KPIs | Monthly targets, working days, coverage / RF with TOT | | |
| 16 | Reporting & Dashboards | SFE / management / executive visibility | | |
| 17 | Admin / Commercial Ops | Self-service territory, CLM publish, coaching templates, plan cycles | 3+2+3 admin tiers + Sameh | |
| 18 | Offline & Mobile | Visits / CLM / planner journeys with poor connectivity | | |

---

## 5. Module requirements (workshop detail)

### How we capture process (OCE-aligned)

IQVIA OCE (Orchestrated Customer Engagement) organizes field CRM around **end-to-end engagement workflows**, not feature lists. In Session 2, for each process below, walk the room through this template and fill **Client Notes** + the **Workflow Capture Sheets** in Appendix C.

| Capture element | Ask / record |
|-----------------|--------------|
| **Trigger** | What starts this process? (rep action, cycle date, manager ride-along, file arrival…) |
| **Actors** | Who does each step? (MR, DM, AM, NSM, SFE, Brand, Marketing, Medical, IT, warehouse…) |
| **Happy path steps** | Ordered steps from start → done (include system used today: Mendix / Excel / paper / WhatsApp…) |
| **Statuses / lifecycle** | Exact status names and who can move each transition |
| **Validations / rules** | What blocks submit? (mandatory fields, territory filter, sample limits, consent…) |
| **Approvals** | Who approves, when (before vs after), SLA, escalate path |
| **Exceptions** | Cancel, amend after submit, offline, vacant territory, out-of-plan, failed sync |
| **Outputs** | What is created? (visit record, KPI impact, inventory deduction, Case, affiliation…) |
| **Channel** | Face-to-face, remote, phone, WhatsApp, group call / meeting |
| **Compliance** | Signature, MLR, Medical Inquiry verbatim, audit who can edit after lock |

**OCE process areas we map to (use as checklist, do not say “OCE” to the client as a product requirement):** Account (search-before-create) → Territory / targeting → Plan (My Schedule) → Call / Call Report (attendees, products, messages/reactions, samples, CLM) → Activity history → TOT → Coaching (double call) → Samples logistics → CLM publish → Medical Inquiry → Ratings / segmentation cycle → Next-best / prioritization → Omnichannel follow-up (WhatsApp / survey).

---

### 5.1 Account Management

**Business intent:** Pharma teams do not sell to generic “accounts.” HCPs, pharmacies, hospitals (HCO), and business contacts each need the right fields, layouts, and compliance posture. In OCE terms: **customer master + search-before-create**.

**Requirements**

- Support account types: **HCP (Medical Professional)**, **HCO / Institution**, **Pharmacy**, **Business Contact** (confirm Day-1 set).
- HCP specialty depth (multi-specialty where needed), license / local identifiers, tier / status.
- New account creation by field users with a defined **approval process** (who approves, SLA, what can be used before approval).
- Territory visibility: reps see accounts in scope of their territory alignment.
- Audit trail of create / edit / approve.

**Process walkthrough — capture in Session 2**

1. **Today’s flow:** Walk us through “rep finds a new doctor not in the system” — step by step, who they call, what form/Excel they fill, how long until the doctor is visitable.
2. **Search-before-create:** What must the rep search first (name, specialty, hospital, national ID)? What duplicate rules exist?
3. **Create → approve → usable:** List statuses (e.g. Draft / Pending / Approved / Rejected). Can the rep **plan** or **submit** a call on a pending account?
4. **Actors:** Who creates HCP vs Pharmacy vs HCO? Who approves each? What is the SLA?
5. **Rejection / amend:** If rejected or data is wrong later, what happens? Who merges duplicates?
6. **Master ownership:** Is Mendix / Excel / OneKey the system of record? One-time migration or ongoing sync?

**Client Notes**

> _______________________________________________________________________________

---

### 5.2 Affiliation Management

**Business intent:** Influence networks (who works where, which pharmacy serves which HCP) drive attendee picking, sell-out bridging, and nearby follow-up visits. In OCE terms: **account relationships / workplace affiliations**.

**Requirements**

- Maintain affiliations between **HCO ↔ HCP**, **HCP ↔ Pharmacy**, and other agreed relationship types.
- Affiliations can be:
  - **Fed** into the system (bulk / integration).
  - **Automatically created** when attendees are added to a visit.
  - **Created in-field** by selecting a **nearby pharmacy** after a visit to log a related visit.
- Affiliations searchable when building visit attendees.
- Deactivate / end-date affiliations without hard-delete (audit).

**Process walkthrough — capture in Session 2**

1. **Today’s flow:** How does a rep today record “Dr X works at Hospital Y” or “Dr X’s patients fill at Pharmacy Z”?
2. **Create paths:** Which of these are real for Zetapharma — (a) central data load, (b) auto from visit attendees, (c) nearby pharmacy after a call? Rank priority.
3. **During the call:** When adding attendees, must the affiliation already exist, or can the rep create it inline?
4. **Nearby pharmacy:** After an HCP call, describe the exact steps to log a pharmacy call — radius? same day only? must be in-territory?
5. **Lifecycle:** Can affiliations end-date? Who deactivates wrong links? Any approval?
6. **Downstream use:** Are affiliations used for sell-out → HCP recommendations, or only for attendee picking?

**Client Notes**

> _______________________________________________________________________________

---

### 5.3 Ratings Management

**Business intent:** Not every account deserves the same visit frequency. Ratings profile accounts **in scope of a territory** using product-level and generic questions. In OCE terms: **segmentation / profiling on Account-Territory (and product)**.

**Requirements**

- Territory-scoped ratings such as **penetration**, **potential**, and related profiling questions.
- **Product ratings** examples: prescriptions per month for company product; prescriptions per month for competing product on similar indications.
- **Generic ratings** examples: patient flow and other non-product profiling.
- Ratings feed classification / targeting (e.g. A/B/C) and planner / home KPIs where agreed.
- Controlled update cadence (who can edit, how often, manager oversight).

**Process walkthrough — capture in Session 2**

1. **Today’s flow:** When does rating happen — at first visit, monthly cycle, or whenever the rep wants? Who initiates?
2. **Question set:** List the actual questions used today (potential, penetration, Rx/month company, Rx/month competitor, patient flow, loyalty…). Which are **account-level** vs **product-level**?
3. **Who can edit:** Rep only? DM override? SFE lock after cycle close?
4. **Classification:** How does a rating become A/B/C (or KOL)? Automatic formula or manual?
5. **Target impact:** Does a rating change immediately change visit frequency / plan targets, or only next cycle?
6. **Cycle close:** Is there a freeze date? What if a rep never updates ratings?

**Client Notes**

> _______________________________________________________________________________

---

### 5.4 Activities Management

#### 5.4.1 Visits (Planner lifecycle)

**Business intent:** Structured call reporting is the commercial DNA of every customer interaction. In OCE terms: **Call / Call 2.0** — plan → execute → submit → locked activity history.

**Requirements**

- Visits created and managed from the **planner** (calendar / map).
- Lifecycle: **Draft → Planned → Submitted (Completed) / Cancelled** (exact labels to confirm).
- Optional **approval process** before or after submit (who, when).
- Visit capture: details, attendees, products / messages, samples (if in scope), CLM presentations, affiliations context.
- Double-visit flag for coaching scenarios.
- Completed visits read-only (or controlled amend process).
- Desktop + Salesforce mobile support.

**Process walkthrough — capture in Session 2**

1. **Plan the week:** How does a Medical Rep build next week today? (Excel, WhatsApp to DM, paper diary, Mendix…) Who must approve the plan before the week starts — if anyone?
2. **Statuses:** Name every status a call/visit can have today and what each means. Who can move Draft → Planned → Submitted / Cancelled?
3. **Call channels:** Face-to-face only, or also remote / phone / group meeting? Any different mandatory fields by channel?
4. **On the call report — happy path:** Walk the exact order of entry: primary account → attendees → products detailed → message/reaction → samples → CLM → notes → submit. What is mandatory vs optional?
5. **Product detailing rules:** Can the rep detail any product, or only territory-aligned / promoted list? Competing products captured?
6. **Message / reaction:** Do you capture topic-level sentiment (Positive / Neutral / Negative) or free text only?
7. **In-plan vs out-of-plan:** Can a rep submit a call that was never planned? Flag? Penalty? Manager approval?
8. **KOL / Single vs Double:** For DM/AM/NSM “Single on KOL + Double” — define: who is on the KOL list, who creates the call, who is coached, when is it Single vs Double?
9. **After submit:** Is the call locked? How are corrections done (unlock request, new call, admin amend)? Cutoff (same day / month-end)?
10. **GPS / check-in:** Any location capture or geofence required for compliance?

**Client Notes**

> DM / AM / NSM: Single visits on KOL lists + Double visits (Session 1). Confirm KOL list source and rules.

#### 5.4.1.1 Medical Inquiry (within a visit)

**Requirements**

- Raise a Medical Inquiry from a visit context.
- Route to Medical Affairs (Case / queue) with SLA and closure ownership.
- Link MI back to visit, account, and product where relevant.

**Process walkthrough — capture in Session 2**

1. **Trigger:** HCP asks an off-label / scientific question during the call — what does the rep do **today** (WhatsApp Medical, email, paper, nothing)?
2. **Capture:** Exact fields required (verbatim question, product, indication, HCP identity, urgency).
3. **Route → close:** Who receives it, SLA, who answers the HCP, who closes the ticket? Does the rep see the answer?
4. **Compliance:** Can sales answer medical questions, or must everything go to Medical Affairs?

**Client Notes**

> _______________________________________________________________________________

#### 5.4.2 Time Off Territory (TOT)

**Requirements**

- Reps (and managers) create TOT for leave, training, admin, travel, etc. (type list to confirm).
- Approval rules by type / duration.
- TOT reduces available working days / coverage denominator so KPIs stay honest.
- Planner shows TOT slots; conflicts with planned visits handled by rule.

**Process walkthrough — capture in Session 2**

1. **Types:** List every non-call day type used today (annual leave, sick, training, admin, conference, travel, holiday…).
2. **Request → approve:** Who submits? Who approves by type/duration? What happens if not approved before the day?
3. **Planner conflict:** If TOT overlaps planned visits — auto-cancel visits, block TOT, or warn only?
4. **KPI impact:** Which TOT types reduce working days / coverage denominator? Any type that does **not**?
5. **Retroactive:** Can TOT be entered after the fact? Month-end freeze?
6. **Manager TOT / field training days:** How are Field Trainer days and DM ride-along days classified (TOT vs double visit)?

**Client Notes**

> _______________________________________________________________________________

#### 5.4.3 WhatsApp assistance

**Requirements**

- Send **visit reminders** to HCPs (or internal reminders) via WhatsApp-style channel.
- Send **post-visit surveys** / product feedback links after a visit.
- Consent and audit of outbound messages.
- Responses visible in CRM where agreed.

**Process walkthrough — capture in Session 2**

1. **Today’s flow:** Do reps already WhatsApp HCPs for appointments or follow-up? Personal number or company number?
2. **Reminder journey:** Trigger (planned visit T−1?) → message template → who sends (auto vs rep) → what if HCP replies cancel/reschedule?
3. **Survey journey:** Trigger (call submitted) → consent check → survey link → where do answers land → who follows up negatives?
4. **Consent:** How is WhatsApp consent captured and stored? Opt-out handling?
5. **Compliance:** Any Medical / Legal ban on product claims over WhatsApp?

**Client Notes**

> _______________________________________________________________________________

#### 5.4.5 Promotional Activities

**Requirements**

- Initiate promotional activities with a defined **workflow** (request → approve → execute → close).
- Link to products / brands / budgets / geography as needed.
- Integration touchpoint with **Mendix** where promotional process already lives (see §5.10).

**Process walkthrough — capture in Session 2**

1. **Definition:** List promo activity types today (speaker program, round table, conference booth, brand reminder drop, patient education…).
2. **Happy path:** Request → budget check → approve → execute → close — who does each step **today in Mendix** (or elsewhere)?
3. **Hand-off to field:** Does the Medical Rep get a task/visit from an approved promo, or is promo HQ-only?
4. **System boundary:** Which steps must stay in Mendix vs appear in Salesforce for the field?
5. **Approvals:** Thresholds by amount / BU / Brand Manager vs BUM vs Finance?

**Client Notes**

> _______________________________________________________________________________

---

### 5.5 Coaching Management

**Business intent:** Double visits turn ride-alongs into structured development, not tribal feedback. In OCE terms: **coaching / joint call evaluation**.

**Requirements**

- From a double visit, create a **coaching event** with templates / competency dimensions.
- Capture insights / scores (rep + manager dual scoring if required).
- Visibility for DM / AM / NSM / Field Trainers per hierarchy.
- History on rep profile for trend over time.

**Process walkthrough — capture in Session 2**

1. **Trigger:** When is a double visit required (quota per month, new hire, low performer, KOL only)? Who schedules it?
2. **During the call:** Does the coach fill the form live on device, or after? Can the rep see scores in real time?
3. **Form content:** Walk the current coaching dimensions / scorecard. Same template for DM vs Field Trainer?
4. **Submit → visibility:** Who must sign off? Does it block call submit? Who sees history (rep, DM, HR, SFE)?
5. **Follow-up:** Is there a mandatory action plan / next coaching date?
6. **Roles:** Confirm initiate rights for DM, AM, NSM, Field Trainer, FTM — and Single-on-KOL vs Double rules.

**Client Notes**

> Field Trainers (5) do Double visits across BUs / regions. DM / AM / NSM also Single on KOL + Double (Session 1).

---

### 5.6 LMS (Learning Management)

**Requirements**

- **Courses** for field and brand teams.
- **Medical exams** and **product exams** with pass/fail and attempt rules.
- Link completion to readiness / compliance reporting (and optionally to detailing eligibility).
- Role-based assignment of curricula.

**Process walkthrough — capture in Session 2**

1. **Today’s flow:** How is a new product launch trained and examined before reps can detail it?
2. **Assignment:** Who assigns courses (L&D, Brand, DM)? By role / BU / territory?
3. **Exam rules:** Pass mark, attempts, expiry / re-certification period.
4. **Gating:** Must pass block detailing, sampling, or CLM for that product?
5. **System:** Keep existing LMS and integrate, or run exams in Salesforce?

**Client Notes**

> _______________________________________________________________________________

---

### 5.7 Product Management

**Business intent:** Therapy areas, brands, and detail/sample/reminder products power call reports, CLM, samples, and Mendix promo.

**Requirements**

- Hierarchy: **Therapy area → Brand → Product** (SKU / detail / sample as needed).
- Product types including **Brand Reminder** materials.
- External IDs for integrations (distributor files, Mendix).
- Territory product alignment (what a territory can detail) — see §5.11.

**Process walkthrough — capture in Session 2**

1. **Catalog change flow:** Brand wants to add a SKU / Brand Reminder — who requests, who creates in system, when do reps see it on the call report?
2. **Product types:** Detail vs Sample vs Brand Reminder vs competitor — which appear on the call report picker?
3. **Brand Reminder distribution:** Is it logged like a sample (qty, recipient), handed without lot, or information-only?
4. **Codes:** Where do product codes live today (Mendix, Excel, ERP)? Which code must Salesforce store as external ID?
5. **Retirement:** How are discontinued products hidden from detailing but kept for history?

**Client Notes**

> Brand Reminder currently managed by Brand Managers [15].  
> Confirm with **Sameh Samy** (IT Manager) regarding Mendix product codes if present.

---

### 5.8 Users Management

**Requirements**

- User provisioning aligned to hierarchy: MR → DM → AM → NSM → BUM (and trainers / brand / admin).
- Roles, profiles / permission sets, and app access (Field / Management / Executive).
- Vacant territory slots supported (**81 vacant** Medical Rep positions) without breaking alignment or targets.
- Admin tiers: Super admin / Admin / Super user + dedicated Sameh super admin.

**Process walkthrough — capture in Session 2**

1. **Hire → login:** New Medical Rep joining — who creates user, assigns manager, assigns territory, grants app access? SLA to first login?
2. **Transfer / promotion:** Rep moves district — what happens to open planned visits, samples inventory, coaching history?
3. **Vacant territory (81):** Who “owns” the customers meanwhile? Does DM cover? Are targets still set?
4. **Leave / terminate:** Disable login day-of? Reassign in-flight records?
5. **Admin tiers:** For the 3+2+3 admins + Sameh — what can each do (users, territories, CLM publish, unlock visits)?

**Client Notes**

> See §3 Company users table (Session 1 headcount).  
> Admin footprint: 8 = (3) Super admins / (2) Admins / (3) Super users; + 1 super admin for Sameh.

---

### 5.9 Distributor Sales Data Management

**Business intent:** Connect sell-out / distributor withdrawals to the same accounts and territories the field uses.

**Requirements**

- Import distributor / wholesaler sales files (format, cadence, external IDs to confirm).
- Map to Pharmacy / brick / product.
- Dashboards and field recommendations (coverage gaps, high-withdrawal pharmacies).
- Error handling for unmatched products / outlets.

**Process walkthrough — capture in Session 2**

1. **File arrival:** Who sends the distributor file, how often, in what format? Who receives it today (David?)?
2. **Cleanse → load:** How are pharmacies/products matched? What happens to unmatched rows?
3. **Publish to field:** When can a rep act on the numbers — next day, next week? Any approval before publish?
4. **Field action:** Desired outcome — brick dashboard only, auto draft visits, affiliation-based HCP suggestions?
5. **Corrections:** Distributor sends a restatement — re-load process?

**Client Notes**

> _______________________________________________________________________________

---

### 5.10 Mendix Integration (Promotional Activities)

**Requirements**

- Integrate Salesforce with Mendix for promotional activity processes as agreed (initiate, sync status, product references).
- Align **product codes** between systems (Sameh).
- Clear system-of-record rules per step (who creates, who closes).
- Secure integration (Named Credentials / middleware ownership).

**Process walkthrough — capture in Session 2**

1. **As-is promo in Mendix:** Screen-walk (or describe) create → approve → execute → close. Capture field list and statuses.
2. **System of record:** For each step, Mendix or Salesforce owns the truth?
3. **Sync events:** On which status changes must the other system update? Near-real-time or batch?
4. **Product codes:** Confirm Sameh’s Mendix product code list and mapping rules to Salesforce Product2.
5. **Failure handling:** If sync fails mid-approval, who is alerted and what is the manual workaround?

**Client Notes**

> Product codes in Mendix — confirm with **Sameh Samy** (IT Manager).  
> Promotional activities workflow ownership TBD (Marketing / Brand / SFE).

---

### 5.11 Territory Alignment & Targeting

**Business intent:** Ratings and visits only work if Account × Territory and Account × Territory × Product matrices are correct. Critical for a ~721-rep Egypt footprint including vacant slots. In OCE terms: **alignment / roster / targeting cycle**.

**Requirements**

- Territory hierarchy (Country → Region → District → Territory — exact levels to confirm).
- **ATF:** Account × Territory fields (potential, penetration, classification, KOL flags).
- **ATPF:** Account × Territory × Product fields (Rx, adoption, loyalty, target frequency).
- **PTA:** Product × Territory alignment (what can be detailed).
- Optional **bricks** and pharmacy–brick membership for sell-out.
- Realignment process each cycle; vacant territories retain alignments.

**Process walkthrough — capture in Session 2**

1. **Cycle:** How often do you realign territories / account lists (quarterly, biannual, ad hoc)? Who runs the cycle (SFE / Ahmed Abdallah)?
2. **Account → territory:** How does an HCP get onto a rep’s list today? Shared accounts across reps?
3. **Product → territory:** Who decides which brands a territory can detail (PTA)? Brand Manager or SFE?
4. **KOL lists:** Who maintains KOL lists used for DM/AM/NSM Single visits? How do they differ from normal ATF?
5. **Mid-cycle change:** Doctor moves hospital / new hire in vacant slot — process and effective date?
6. **Enforcement:** Must call report / CLM product pickers **only** show territory-aligned products?

**Client Notes**

> 81 vacant Medical Rep slots — territories should still receive account alignments and PTA so coverage can be planned before hire.

---

### 5.12 CLM / e-detailing

**Business intent:** Approved content presented in-call with measurable engagement — not screenshots in a chat thread. In OCE terms: **CLM / approved content in the call**.

**Requirements**

- CLM library with territory / role targeting and MLR / medical publish controls (process to confirm).
- In-visit CLM player; log dwell time, slides, message / sentiment, ratings where required.
- Formats: PDF / HTML / ZIP (confirm).
- Brand / Marketing ownership of content lifecycle; SFE visibility on utilization.

**Process walkthrough — capture in Session 2**

1. **Content lifecycle:** Brand creates material → Medical/MLR approve → who uploads → who targets which territories → publish → expire. Walk with **Aya**.
2. **In the call:** Must CLM be launched from the visit? Can reps present offline? Mandatory slides / locked sequence?
3. **Capture:** What must be stored — slides viewed, seconds on slide, HCP reaction, verbal consent to present?
4. **After the call:** Where do Brand / SFE see utilization? Any feedback loop to update content?
5. **Formats & devices:** PDF / HTML / video? Android vs iPad reality in the field?

**Client Notes**

> Provided by **Aya** in the data sheet. Owner: **Aya** (Senior SFE).

---

### 5.13 Sample Management

**Business intent:** Lot- and expiry-controlled sample distribution with audit trail at the point of visit. In OCE terms: **sample allocation → inventory → disbursement on call → audit**.

**Requirements**

- Rep inventory by product and lot; expiry tracking.
- Issue samples on visit with quantity validation (no over-issue, no expired lots).
- Automatic transaction / deduction on visit completion.
- Transfers between reps and returns (if required).
- Compliance reporting for logistics / audit.

**Process walkthrough — capture in Session 2** *(priority with Marketing / Ashmawy / David)*

1. **As-is end-to-end:** Request → warehouse/pack → dispatch to rep → receive into bag → give to HCP → paperwork. Name every system and hand-off.
2. **Allocation rules:** Limits per HCP / month / product? Who sets limits (Brand, Compliance)?
3. **On the call:** Is signature / stamp / acknowledgment required? Lot number visible to rep?
4. **Submit effects:** When does inventory deduct — on save or on call submit? What if call is cancelled after sample entry?
5. **Transfers / returns / expired:** Process and approvers.
6. **Exceptions:** Lost bag, damaged lot, HCP refuses after scan — how recorded?
7. **Wave decision:** Must this be Wave 1, or can field go live with call-only first?

**Client Notes**

> Current flow to be determined.  
> Marketing team to be involved.  
> Mr. Ashmawy.  
> **@David** to help.

---

### 5.14 Field Experience — Home + Planner

**Business intent:** How reps start the day and plan the week — separate from the visit form itself. In OCE terms: **Home / My Schedule / next-best prioritization**.

**Requirements**

- **Field Rep Home:** coverage KPIs, today’s plan / map, next-best customer (NBC) or equivalent prompts.
- **Planner:** weekly calendar, drag-drop planning, TOT slots, map / route assist.
- In-plan vs out-of-plan account browsing as agreed.
- Mobile-first Salesforce experience.

**Process walkthrough — capture in Session 2**

1. **Monday morning:** What does a good Medical Rep look at before leaving home today? What do they wish they saw?
2. **Build the week:** Drag-to-plan from account list? Copy last week? DM-assigned plan?
3. **Day-of changes:** Reschedule / cancel / add ad-hoc — allowed until when?
4. **Map / route:** Is route optimization wanted, or map view only?
5. **Manager lens:** Does DM see / edit the rep’s planner? Approve weekly plan?
6. **Next-best:** Any prioritization rules today (A doctors first, high Rx pharmacies…)? Who defines them (SFE / Business Excellence)?

**Client Notes**

> _______________________________________________________________________________

---

### 5.15 Plan Cycle & Medical Rep 360 / KPIs

**Business intent:** Honest capacity and targets — visits alone inflate coverage if leave and working days are ignored. In OCE terms: **call plan / frequency / working days / MR 360**.

**Requirements**

- Plan-cycle cadence (typically monthly): account targets, working days, copy-forward.
- Medical Rep 360-style KPIs: coverage, RF, CLM%, TOT, coaching trend (confirm set).
- TOT and vacant days correctly affect denominators.
- Manager rollups by district / area / national / BU.

**Process walkthrough — capture in Session 2**

1. **Cycle setup:** Who opens a new month — SFE? What is copied forward vs rebuilt?
2. **Target setting:** Who sets #visits per account / class? Rep proposes + DM approves, or central push?
3. **Working days:** Default working days/month by role? How do public holidays enter?
4. **KPI definitions:** Write formulas you use today for Coverage, RF / frequency, LCF-RCF-MCF if used.
5. **Review ritual:** DM Monday review — which report, which actions (coach, reassign targets)?
6. **Closed month:** Can historical KPIs be recalculated if late visits/TOT are entered?

**Client Notes**

> _______________________________________________________________________________

---

### 5.16 Reporting & Dashboards

**Requirements**

- Role-based dashboards for Rep, DM / AM / NSM, SFE, Brand, Executive.
- Coverage heat maps / geographic views where valuable.
- Scheduled report packs vs live Lightning dashboards (preference).
- Same data truth as field-created visits (no parallel spreadsheet rebuild).

**Process walkthrough — capture in Session 2**

1. **Persona Monday packs:** For MR / DM / AM / NSM / Brand / BUM / SFE — what report do they open first, and what decision does it drive?
2. **Trust issues:** Which numbers today are not trusted (coverage inflation, late entry, double counting)? Why?
3. **Distribution:** Live dashboard vs Excel emailed weekly? Who builds the Excel today (David)?
4. **Brand vs SFE:** Different views needed for Brand Reminder / CLM vs field KPIs?

**Client Notes**

> _______________________________________________________________________________

---

### 5.17 Admin / Commercial Ops

**Requirements**

- Self-service admin for territories, bricks, CLM publish, coaching templates, plan cycles without full IT deployment each cycle.
- Clear separation: Super admin / Admin / Super user capabilities.
- Change control for MLR-sensitive CLM content.

**Process walkthrough — capture in Session 2**

1. **Ops calendar:** List recurring ops tasks each cycle (alignments, CLM publish, coaching template update, plan open, user changes).
2. **RACI:** For each task — Business Excellence (Ahmed Hamid) / SFE Manager (Ahmed Abdallah) / Aya / David / Sameh / Marketing.
3. **IT boundary:** What must Sameh / IT still do vs what commercial ops will self-serve?
4. **Emergency unlock:** Visit unlock, sample adjust, wrong territory — who is allowed, with what audit?

**Client Notes**

> 8 admin-tier users: (3) Super admins / (2) Admins / (3) Super users; + 1 super admin for Sameh.

---

### 5.18 Offline & Mobile

**Requirements**

- Define must-work-offline journeys: planner view, visit draft/complete, CLM playback (rank priority).
- Salesforce mobile app as primary field client.
- Sync / conflict rules when connectivity returns.
- Do **not** assume App Plus Offline SKU timelines without AE confirmation; position hybrid briefcase / device-cache pattern as needed.

**Process walkthrough — capture in Session 2**

1. **Field reality:** Describe a clinic day with bad signal — which steps must still complete before the rep leaves the building?
2. **Rank 1–5 offline:** Planner view / Start-edit visit / Submit visit / CLM play / Sample entry / Ratings edit.
3. **Sync conflicts:** Two edits offline (rep + DM) — who wins? What must never be editable offline?
4. **Devices:** Company Android / BYOD / iPad? OS versions to support.
5. **Pilot geographies:** Worst connectivity territories for Wave 1 pilot.

**Client Notes**

> _______________________________________________________________________________

---

## 6. Approval matrix

| Process | Initiator | Approver(s) | Notes / SLA |
|---------|-----------|-------------|-------------|
| New account (HCP) | | | |
| New account (Pharmacy / HCO) | | | |
| Visit plan / submit | | | Optional — confirm |
| TOT | | | |
| Promotional activity | | | Mendix vs SF |
| Sample request / transfer | | | Marketing / Ashmawy |
| CLM content publish | | | Aya / Medical / MLR |
| Coaching finalize | | | |

---

## 7. Integrations matrix

| System / channel | Purpose | Wave | Owner | Notes |
|------------------|---------|------|-------|-------|
| Mendix | Promotional activities; product codes | | Sameh Samy / Marketing | Confirm SoR |
| Distributor / wholesaler files | Sell-out data | | David / Trade | Format TBD |
| WhatsApp provider | Reminders / surveys | | | Consent TBD |
| MDM / OneKey / other | HCP master (if any) | | | Day 1 vs later |
| ERP / warehouse | Sample logistics (if any) | | Mr. Ashmawy | |
| Existing LMS | Courses / exams (if not native) | | | |

---

## 8. Master data & migration

| Domain | Source today | Load approach | Owner | Status |
|--------|--------------|---------------|-------|--------|
| Users & territories | | Onboarding workbook (Users/Territories) | | Incl. 81 vacant |
| Products / brands / Brand Reminder | | Products sheet; Mendix codes | Brand / Sameh | |
| Accounts (HCP / HCO / Pharmacy) | | Accounts sheet | | |
| Affiliations | | Feed / visit-derived | | |
| Ratings / ATF / ATPF / PTA | | Alignment sheets | SFE | |
| CLM library | Aya data sheet | CLM load | **Aya** | Provided |
| Sample inventory | | TBD | Marketing / Ashmawy / David | Flow TBD |
| Plan targets | | Plan cycle sheets | SFE | |

Load order (reference): Users/Territories ? Products ? Accounts ? Alignments/Ratings ? PTA ? Plan targets ? CLM ? optional extras.

---

## 9. Non-functional requirements

| Area | Requirement | Client confirmation |
|------|-------------|---------------------|
| Mobile | Salesforce mobile for field execution | |
| Language | Arabic UI / bilingual? | |
| Performance | Acceptable load times on 4G in field | |
| Security | Role hierarchy, sharing, admin tiers | |
| Audit | Visits, samples, CLM, approvals immutable history | |
| Licensing | Confirm Salesforce + WhatsApp + AI (if any) with AE | |
| Devices | Android / iOS standards | |

---

## 10. Assumptions & constraints

1. Program focus is **Sales / Medical field work and management**; deep HRIS replacement is out of scope unless explicitly added.
2. Multi-BU structure (Cluster, Diab, CHC, GIT) will be reflected in products, users, and reporting.
3. Vacant Medical Rep slots remain in the territory model.
4. CLM content inventory will be supplied under Aya’s ownership.
5. Sample management process is **not yet defined** — Wave placement is a Session 2 decision.
6. Mendix remains in the landscape for promotional activities until scope says otherwise.
7. Offline capability depends on licensing and agreed hybrid pattern — confirm with Salesforce AE before promising native Offline App Plus.

---

## 11. Out of scope / later waves (draft — confirm MoSCoW)

| Item | Proposed | Notes |
|------|----------|-------|
| Executive Project Management hub | C / W | Unless leadership insists |
| Promo Budget portfolio dashboard | C | May stay Mendix-adjacent |
| Agentforce / AI planning apply | C | After sell-out data quality |
| Fleet / live GPS tracking | C / W | Privacy constraints |
| Full LMS depth beyond courses/exams | C | Confirm native vs integrate |
| Diagnostics / radiology verticals | W | Not Zetapharma core |

---

## 12. Success metrics (fill in Session 2)

| Metric | Baseline today | Target (90 days) | Owner |
|--------|----------------|------------------|-------|
| Visit compliance / on-time submit % | | | |
| Coverage % (by class A/B/C) | | | |
| RF % | | | |
| CLM utilization % of visits | | | |
| Coaching completion (double visits) | | | |
| Sample audit exceptions | | | |
| Data quality (unmatched distributor rows) | | | |

**Primary success metric (one sentence):** _______________________________________________

---

## 13. Proposed phasing

| Wave | Focus | Candidate modules |
|------|-------|-------------------|
| **0 — Foundation** | Users, territories (incl. vacant), accounts, products, security, admin | 1, 2, 3, 7, 8, 11, 17 |
| **1 — Field core** | Home, Planner, Visits, TOT, Coaching basics, Offline journeys | 4.1, 4.2, 5, 14, 15, 18 |
| **2 — Content & compliance** | CLM, MI, Samples (if ready), WhatsApp | 4.1.1, 4.3, 12, 13 |
| **3 — Market & promo** | Distributor data, Mendix promo, Promotional activities | 4.5, 9, 10 |
| **4 — Learning & leadership** | LMS depth, advanced dashboards | 6, 16 |

Adjust after MoSCoW cut in Session 2.

---

## 14. Open decisions log

| # | Decision | Owner | Needed by | Status |
|---|----------|-------|-----------|--------|
| D1 | Sample management end-to-end flow & Wave placement | Marketing / Ashmawy / David | Session 2 | Open |
| D2 | Mendix product codes as external IDs | Sameh Samy | Session 2 | Open |
| D3 | New account approval chain | SFE / Commercial | Session 2 | Open |
| D4 | Visit approval required? (plan and/or submit) | SFE | Session 2 | Open |
| D5 | Brand Manager count split (15 vs 12 noted) | Brand / SFE | Session 2 | Open |
| D6 | WhatsApp provider & consent | Marketing / IT | Session 2 | Open |
| D7 | Offline must-haves ranking | Field / SFE | Session 2 | Open |
| D8 | LMS native vs integrate | L&D / IT | Session 2 | Open |
| D9 | Pilot territories / user count for Wave 1 | Commercial | Session 2 | Open |

---

## 15. Appendix A — Discovery Session 2 agenda (~90–120 min)

| Time | Topic | Goal |
|------|-------|------|
| 0–5 min | Stakeholders + org footprint | Confirm §2–§3; fix Brand Manager split |
| 5–30 min | Account / Affiliation / Ratings / Territory | Fill process sheets **C1 + C8**; walk as-is → to-be |
| 30–60 min | Daily execution: Planner → Visit → CLM → Samples → MI | Fill **C2 + C3 + C4**; status model + mandatory fields |
| 60–75 min | Coaching + TOT + Plan KPIs | Fill **C5 + C6**; KPI formulas |
| 75–85 min | Products + Brand Reminder + LMS | Catalog change + gating flows |
| 85–100 min | Distributor data + Mendix promo + WhatsApp | Fill **C7 + C9**; system-of-record |
| 100–110 min | Offline / mobile + Admin ops | Offline rank + ops RACI |
| 110–120 min | MoSCoW + wave cut + open decisions | Fill §12–§14; next steps |

---

## 16. Appendix B — Workshop decision summary

| Item | Decision |
|------|----------|
| Wave 1 go-live date | |
| In-scope modules (list #s) | |
| Explicit out of scope | |
| Licensing to confirm (AE) | |
| Data migration sources | |
| Pilot territories / user count | |
| Risks / open questions | |
| Next workshop date | |

---

## 17. Sign-off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Customer sponsor | | | |
| Commercial / SFE | | | |
| IT / Salesforce owner | | | |
| Compliance / Medical (if needed) | | | |
| Delivery lead | | | |

---


## Appendix C — Workflow Capture Sheets (fill in Session 2)

Use one sheet per critical process. Copy rows as needed. Prefer verbs + roles + systems.

### C1 — New Account (search-before-create → approve → usable)

| Step # | Step (verb) | Actor | System today | Status after step | Rule / validation | SLA |
|--------|-------------|-------|--------------|-------------------|-------------------|-----|
| 1 | | | | | | |
| 2 | | | | | | |
| 3 | | | | | | |
| 4 | | | | | | |

**Exceptions / amend / reject:** _______________________________________________

---

### C2 — Call / Visit (plan → execute → submit → lock)

| Step # | Step (verb) | Actor | System today | Status after step | Mandatory data | Rule |
|--------|-------------|-------|--------------|-------------------|----------------|------|
| 1 | Plan visit on calendar | | | | | |
| 2 | Start / open call | | | | | |
| 3 | Add attendees | | | | | |
| 4 | Detail products + reactions | | | | | |
| 5 | Present CLM | | | | | |
| 6 | Disburse samples | | | | | |
| 7 | Submit / complete | | | | | |
| 8 | Post-submit amend (if any) | | | | | |

**Channels allowed:** F2F / Remote / Phone / Group / Other: _______________  
**In-plan vs out-of-plan rule:** _______________________________________________  
**KOL Single vs Double rule:** _______________________________________________

---

### C3 — Sample (allocate → bag → disburse → audit)

| Step # | Step (verb) | Actor | System today | Inventory effect | Approval | Doc / signature |
|--------|-------------|-------|--------------|------------------|----------|-----------------|
| 1 | | | | | | |
| 2 | | | | | | |
| 3 | | | | | | |
| 4 | | | | | | |
| 5 | | | | | | |

**Limits (per HCP / product / period):** _______________________________________________  
**Wave placement (1 / 2 / later):** _______________

---

### C4 — CLM content (create → MLR → publish → present → measure)

| Step # | Step (verb) | Actor | System today | Status | Targeting rule |
|--------|-------------|-------|--------------|--------|----------------|
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |
| 4 | Present in call | Medical Rep | | | |
| 5 | Review utilization | | | | |

**Owner:** Aya — notes: _______________________________________________

---

### C5 — TOT (request → approve → block planner → KPI)

| Step # | Step (verb) | Actor | TOT type(s) | Approval | Reduces working days? Y/N |
|--------|-------------|-------|-------------|----------|---------------------------|
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |

**Conflict with planned visits:** _______________________________________________

---

### C6 — Coaching / Double visit

| Step # | Step (verb) | Actor | Template / scorecard | Visible to | Follow-up |
|--------|-------------|-------|----------------------|------------|-----------|
| 1 | Schedule double | | | | |
| 2 | Execute joint call | | | | |
| 3 | Complete coaching form | | | | |
| 4 | Review / action plan | | | | |

---

### C7 — Promotional activity (Mendix ↔ Salesforce)

| Step # | Step (verb) | Actor | System of record | Sync to other system? | Approval |
|--------|-------------|-------|------------------|----------------------|----------|
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |
| 4 | | | | | |

**Product code owner:** Sameh Samy — notes: _______________________________________________

---

### C8 — Territory / targeting cycle

| Step # | Step (verb) | Actor | Cadence | Objects touched (accounts / PTA / KOL) | Effective date rule |
|--------|-------------|-------|---------|----------------------------------------|---------------------|
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |

---

### C9 — Distributor sell-out load → field action

| Step # | Step (verb) | Actor | Input file | Match keys | Output for field |
|--------|-------------|-------|------------|------------|------------------|
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |

---

## Related documents (internal)

- [`Plan/Zeta_Pharma_Sales_Enablement_Guide.md`](./Zeta_Pharma_Sales_Enablement_Guide.md) — module depth & talk tracks  
- [`Plan/Pharma_Discovery_Scoping_Template.md`](./Pharma_Discovery_Scoping_Template.md) — discovery question bank  
- [`Plan/Pharma_Onboarding_Template_Fill_Guide.md`](./Pharma_Onboarding_Template_Fill_Guide.md) — data collection workbook guide  
- [`Plan/Pharma_Onboarding_Data_Collection_Template.xlsx`](./Pharma_Onboarding_Data_Collection_Template.xlsx) — onboarding data template  
