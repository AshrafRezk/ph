# Business Requirements Document (BRD)

**Project:** Pharmaceuticals Salesforce Implementation  
**Org:** pharma-prod (`admin@pharma.eg`)  
**Status:** Draft — Planning  
**Last updated:** June 2026

---

## Document Purpose

This BRD defines planned implementations for the Pharmaceuticals org. Each section describes business context, requirements, and a **wireframe reference** that must be reviewed before development begins.

**Related documents:**

- [General Rules for All Implementations](./general-rules-for-all-implementations.md)
- Wireframes folder: [`wireframes and references/`](./wireframes%20and%20references/)

---

## Table of Contents

| ID | Implementation | Wireframe | Priority |
|----|----------------|-----------|----------|
| IMP-001 | Field Rep Home Dashboard | [WF-001](#imp-001-field-rep-home-dashboard) | High |
| IMP-002 | Call / Visit Reporting | [WF-002](#imp-002-call--visit-reporting) | High |
| IMP-003 | HCP Account Detail & Activity | [WF-003](#imp-003-hcp-account-detail--activity) | High |
| IMP-003a | Pharma Account Record Types & Fields | — | High (foundation) |

**Person account record types:** Salesforce Metadata API cannot create new person-account record types with custom developer names. The org uses `PersonAccount` (label: BC (Business Contact)) and `SDO_PersonAccounts` (label: Medical Professional (HCP)) for person accounts. Inactive business duplicates `Business_Contact` and `Medical_Professional_HCP` remain in the org but are deactivated.
| IMP-004 | Sample Distribution Tracking | TBD | Medium |
| IMP-005 | Medical Inquiry (MI) Intake | TBD | Medium |
| IMP-006 | Coaching Templates & Events | [WF-004–WF-008](#imp-006-coaching-templates--events) | High |
| IMP-007 | Field Rep Planner (Calendar & Map) | [WF-009](#imp-007-field-rep-planner-calendar--map) | High |
| IMP-008 | Medical Rep 360 Dashboard | [WF-010](#imp-008-medical-rep-360-dashboard) | High |
| IMP-009 | CLM Presentation Logging & Feedback | [WF-011–WF-018](#imp-009-clm-presentation-logging--feedback) | High |
| IMP-010 | Project Management — C-Level Planning & Tracking | [WF-PM-001–WF-PM-002](#imp-010-project-management--c-level-planning--tracking) | High |

---

## IMP-001: Field Rep Home Dashboard

### Business Context

Field representatives need a single landing page showing daily priorities: upcoming calls, sample inventory alerts, and territory KPIs. Pattern reference: OCE home / Veeva My Schedule.

### Requirements

| # | Requirement |
|---|-------------|
| R1 | Display KPI summary cards: calls this week, samples distributed, target attainment |
| R2 | Show upcoming visits for the next 7 days (Tasks/Events or custom Call object) |
| R3 | Mobile-first layout; must render in Salesforce One |
| R4 | Use standard Task/Event objects where profiles allow; custom Call object if Platform license restricts Events |
| R5 | Show coverage % (achieved visits / target visits) across all accounts with drill-down to potential, penetration, and calculated classification |
| R6 | Show coverage % aggregated by classification A / B / C |
| R7 | Show RF% for each classification A / B / C and the overall total (with LF% / MF% context) |
| R8 | Show a map of the rep’s location and today’s route, plus optimization ideas |
| R9 | Show Top 5 Next Best Customer recommendations with a quick action to create a draft call |

### Technical Approach

- **Primary:** Lightning Home Page with LWC dashboard components (SLDS)
- **Fallback:** If KPI logic is complex, embed HTML/CSS/JS page in LWC with Apex REST endpoints

- **Implemented components (this release):**
  - `fieldRepHomeMetrics`: coverage + drill-down + RF% by classification
  - `fieldRepHomeTodayPlan`: Up Next + map + optimization ideas
  - `fieldRepHomeNextBestCustomer`: Top 5 Next Best Customer + draft call action

### Wireframe

**WF-001 — Field Rep Home Dashboard**

![Field Rep Dashboard](./wireframes%20and%20references/wireframe-dashboard.png)

> See also: [`wireframes and references/wireframe-dashboard.png`](./wireframes%20and%20references/wireframe-dashboard.png)

### Acceptance Criteria

- [ ] Dashboard loads in < 3 seconds on mobile
- [ ] KPIs reflect logged-in user's territory only
- [ ] SLDS-compliant; no horizontal scroll on phone viewport

---

## IMP-002: Call / Visit Reporting

### Business Context

Reps must log each HCP visit with products discussed, samples issued, and follow-up date. Align terminology with OCE Call Reporting and Veeva Call Reporting.

### Requirements

| # | Requirement |
|---|-------------|
| R1 | Select Account (HCP) and related Contact |
| R2 | Capture call date, call type, duration, products discussed |
| R3 | Sample line items with lot number and quantity (if applicable) |
| R4 | Next call date and free-text notes |
| R5 | Submit for manager review (optional approval Flow) |

### Technical Approach

- **Visit record page:** `visitCallShell` LWC with left-nav sections (Details, Attendees, Products, Samples, Presentations)
- **Salesforce One:** `VisitCallReport` Visualforce page with JavaScript remoting to `VisitCallReportController`
- **Data model:** junction objects `Visit_Attendee__c`, `Visit_Product_Detail__c`, `Visit_Product_Message__c`, `Visit_Sample__c`; sample compliance via `Sample_Inventory__c` and `Sample_Transaction__c`
- **Product scope:** `Product_Territory_Alignment__c` intersected with `Account_Territory_Product_Fields__c` for the visit account
- **Attendee discovery:** primary account, `Account_Affiliation__c`, and territory account search

### Wireframe

**WF-002 — Call / Visit Reporting Form**

![Call Report Form](./wireframes%20and%20references/wireframe-call-report.png)

> OCE reference screenshots: WF-002a through WF-002f in [`wireframes and references/README.md`](./wireframes%20and%20references/README.md)

### Acceptance Criteria

- [ ] Form completable on mobile in Salesforce One via `VisitCallReport` Visualforce page
- [ ] Desktop call report completable via `visitCallShell` on Visit record page
- [ ] Territory-aligned products and attendees selectable with chip + modal UX
- [ ] Per-product detail messages and sample lines persist as related lists on `Visit__c`
- [ ] Required fields enforced before save; sample quantities validated against inventory

### Manual Test Checklist

1. Open a Draft visit on desktop — confirm `visitCallShell` sections load (Details, Attendees, Products, Samples, Presentations).
2. Add affiliated attendee via modal search; confirm chip appears and related list row on save.
3. Add territory-aligned product; add topic/sentiment message; save and verify `Visit_Product_Detail__c` / `Visit_Product_Message__c` rows.
4. Add sample row linked to inventory lot; complete visit; confirm inventory deducted and `Sample_Transaction__c` created.
5. On phone (Salesforce app), open **Call Report (Mobile)** button or `/apex/VisitCallReport?id=...`; complete same flow.
6. Confirm Completed visit is read-only in both desktop LWC and mobile VF page.

---

## IMP-003: HCP Account Detail & Activity

### Business Context

Medical reps and MSLs need a consolidated HCP view: demographics, specialty, visit history, samples, and affiliations. Reference: Veeva Account profile, OCE Account page.

### Requirements

| # | Requirement |
|---|-------------|
| R1 | Account header with name, specialty, tier, and key identifiers |
| R2 | Tabbed layout: Overview, Visits, Samples, Affiliations |
| R3 | Activity timeline of recent calls and tasks |
| R4 | Related list for sample transactions |

### Technical Approach

- **Primary:** Lightning Record Page with dynamic related lists on standard Account
- Use Person Account or Contact model based on org configuration
- Custom related lists via LWC if standard related lists are insufficient

### Wireframe

**WF-003 — HCP Account Detail**

![Account Detail](./wireframes%20and%20references/wireframe-account-detail.png)

> See also: [`wireframes and references/wireframe-account-detail.png`](./wireframes%20and%20references/wireframe-account-detail.png)

### Acceptance Criteria

- [ ] All tabs load without full page refresh
- [ ] Visit history sorted by date descending
- [ ] Page performs acceptably with 500+ related records (pagination)

---

## IMP-003a: Pharma Account Record Types & Fields

### Business Context

Pharma field teams need distinct Account record types aligned with OCE/Veeva terminology: Pharmacy, Institution (HCO), Business Contact (BC), and Medical Professional (HCP). HCP accounts require up to four medical specialties drawn from a shared global picklist. This foundation enables IMP-003 (HCP detail page), Account Affiliations, call reporting, and sample tracking.

### Requirements

| # | Requirement |
|---|-------------|
| R1 | Four record types: Pharmacy, Institution (HCO), BC (Business Contact), Medical Professional (HCP) |
| R2 | Person Accounts for BC and HCP; business accounts for Pharmacy and Institution |
| R3 | HCP fields: Specialty 1–4 referencing Medical_Specialty global picklist (46 values) |
| R4 | Minimal OCE-aligned fields per record type (status, license, designation, tier, etc.) |
| R5 | Dedicated page layouts and Lightning record pages per record type |
| R6 | Deactivate SDO demo record types |

### Technical Approach

- Standard **Account** object with Person Accounts enabled
- Global value set: `Medical_Specialty`
- Module config: [`account_record_types_module_config.yaml`](./account_record_types_module_config.yaml)
- Deploy manifest: [`manifest/account-record-types-package.xml`](../manifest/account-record-types-package.xml)
- Permission set: `Pharma_Account_Module`
- Affiliations LWC updated to display `RecordType.Name` on network nodes

### Record Type Summary

| Record Type | Type | Key Fields |
|-------------|------|------------|
| Pharmacy | Business | Pharmacy Type, License Number, Status |
| Institution (HCO) | Business | Institution Type, Status |
| BC (Business Contact) | Person | Professional Title, Department, Status |
| Medical Professional (HCP) | Person | Designation, License, Specialty 1–4, Tier, Status |

### Acceptance Criteria

- [ ] Four pharma record types available; SDO demo types inactive
- [ ] HCP Specialty 1–4 show expanded Medical Specialty labels
- [ ] Each record type has dedicated layout with only relevant fields
- [ ] HCP Lightning page ready for IMP-003 (Overview, Affiliations, Activity tabs)
- [ ] Metadata in source under `force-app/main/default/`

---

## IMP-004: Sample Distribution Tracking

### Business Context

Track sample inventory, distribution to HCPs, and compliance with local regulations. Reference: OCE Sample Management.

### Requirements

| # | Requirement |
|---|-------------|
| R1 | Rep sample inventory view by product and lot |
| R2 | Deduct inventory on call report submission |
| R3 | Audit trail of all sample movements |
| R4 | Block distribution when inventory is zero or expired |

### Technical Approach

- Custom objects likely required: `Sample_Inventory__c`, `Sample_Transaction__c`
- Link transactions to Call records (IMP-002)
- Consider Platform license constraints when linking to standard objects

### Wireframe

**WF-004 — Sample Distribution** *(pending)*

> Wireframe to be added: `wireframes and references/wireframe-sample-distribution.png`

### Acceptance Criteria

- [ ] Inventory cannot go negative
- [ ] Transaction history visible on Account record

---

## IMP-005: Medical Inquiry (MI) Intake

### Business Context

Medical Affairs receives HCP questions about products. Reference: IQVIA MI inquiry handling workflows.

### Requirements

| # | Requirement |
|---|-------------|
| R1 | Intake form: inquirer, product, question category, question text |
| R2 | Route to Medical Affairs queue (Case or custom object) |
| R3 | SLA tracking and response documentation |
| R4 | Standard Case object preferred; custom if Platform license restricts Cases |

### Technical Approach

- **Primary:** Case with record type "Medical Inquiry" + Screen Flow intake
- Email-to-Case optional for async intake

### Wireframe

**WF-005 — MI Intake Form** *(pending)*

> Wireframe to be added: `wireframes and references/wireframe-mi-intake.png`

### Acceptance Criteria

- [ ] Inquiry assigned to queue within 1 minute of submission
- [ ] Response and closure fields captured on record

---

## IMP-006: Coaching Templates & Events

### Business Context

District Managers conduct field coaching sessions with Sales Reps using structured competency assessments. Templates define scale-based questions grouped by section (Core Values, Selling Skills, etc.). Both Rep and Manager score each competency; strengths, weaknesses, and calibration gaps are computed from manager scores.

### Requirements

| # | Requirement |
|---|-------------|
| R1 | Admin configures coaching templates with questions stored as JSON |
| R2 | Coaching events link template, Employee (User), and Manager (User) |
| R3 | Dual Rep + Manager scoring on gradient scale with qualitative labels |
| R4 | Section scores, strengths, weaknesses, and gaps stored on event record |
| R5 | Mobile-compatible LWCs on Lightning record pages |

### Technical Approach

- `Coaching_Template__c` + `Coaching_Event__c` custom objects
- `coachingTemplateEditor` LWC (LDS) + `coachingEventEvaluation` LWC (Apex)
- `CoachingScoringService` for dual-score computation
- **Admin Console:** single **Coaching Management** tile opens `coachingTemplateManager` modal (template list, search/filter, New Template → record page editor). Coaching Events are not surfaced in Admin Console.

### Wireframes

- **WF-004:** [AdminConsoleCoachingTemplateEditingView.png](./wireframes%20and%20references/AdminConsoleCoachingTemplateEditingView.png)
- **WF-005:** [CoachingEvent(DoubleVisitForm)DesktopView.png](./wireframes%20and%20references/CoachingEvent(DoubleVisitForm)DesktopView.png)
- **WF-006:** [Coaching Template Primitive UI_UX with Questions.png](./wireframes%20and%20references/Coaching%20Template%20Primitive%20UI_UX%20with%20Questions.png)
- **WF-007:** [CoachingTemplateQuestion.png](./wireframes%20and%20references/CoachingTemplateQuestion.png)
- **WF-008:** Dual Rep + DM marker UI (user-provided screenshot)

### Acceptance Criteria

- [ ] Template editor saves JSON with sections, respondents, scale labels
- [ ] Event evaluation shows dual markers and both total scores
- [ ] Manager strengths/weaknesses computed per section
- [ ] Permission set grants access to both objects and Apex

---

## IMP-007: Field Rep Planner (Calendar & Map)

### Business Context

Field reps need a weekly planner similar to Salesforce Calendar / OCE My Schedule: drag HCP accounts onto time slots to plan visits, move and resize visit blocks, block time with TOT (Time Off Territory), and visualize the day's calls on a map with driving route optimization. Reference: OCE planner, Veeva My Schedule, IQVIA field force routing.

### Requirements

| # | Requirement |
|---|-------------|
| R1 | Week calendar view (Mon–Sun) with 30-minute slots, 6:00–20:00 |
| R2 | Sidebar list of territory accounts; drag account onto calendar to create `Visit__c` |
| R3 | Drag visit blocks to reschedule; resize to change duration |
| R4 | Drag TOT palette onto calendar to open Time Off Request creation (Draft or Submit) |
| R5 | Map view using **OpenStreetMap** tiles (Leaflet); show geocoded visits for selected day |
| R6 | Build driving route across ordered visits (OSRM); display distance and duration |
| R7 | SLDS styling; responsive layout for desktop and mobile |
| R8 | Enforce sharing/FLS via `with sharing` Apex and `WITH SECURITY_ENFORCED` |

### Technical Approach

- **Visit__c** custom object (Account, Assigned To, Start/End, Status, Visit Type)
- **fieldRepPlanner** LWC on App Page + **Planner** tab
- **FieldPlannerController** Apex for planner data and mutations
- **Leaflet** static resource + OSM tiles + OSRM public routing API
- TOT integrates with existing **Time_Off_Request__c** module
- CSP Trusted Sites: `tile.openstreetmap.org`, `router.project-osrm.org`

### Wireframe

**WF-009 — Field Rep Planner** *(reference: OCE / Salesforce calendar planner patterns)*

> Implementation config: [`field_planner_module_config.yaml`](./field_planner_module_config.yaml)

### Acceptance Criteria

- [ ] Drop account on calendar creates visit assigned to current user
- [ ] Drag and resize visit updates `Start_Date__c` / `End_Date__c`
- [ ] TOT drag opens modal; saved request appears on calendar
- [ ] Map shows pins for accounts with Billing geocode; route polyline renders
- [ ] Completed visits cannot be moved from planner

---

## IMP-008: Medical Rep 360 Dashboard

### Business Context

District managers and leadership need an OCE-style **Medical Rep 360** view: submitted calls, coverage, visit targets, CLM usage, frequency status (LCF/RCF/MCF), and coaching score progression — filterable by rep.

### Requirements

| # | Requirement |
|---|-------------|
| R1 | **Management** report and dashboard folders |
| R2 | Dashboard components: submitted calls/month, target customers, customers not seen, coverage %, visit rate, visit target, not-reported days, TOT days, CLM%, frequency status, coverage by rating, rep score progression |
| R3 | Dashboard filter by **Employee (Rep)** |
| R4 | KPIs sourced from **Employee Time Card** with **account targets**; actuals from completed **Visit__c** records |
| R5 | Demo seed data for current month (Jun 2026) with realistic volumes |

**Wireframe:** [WF-010 — Medical Rep 360 Dashboard](./wireframes%20and%20references/MedicalRep360Dashboard.png)

### Acceptance Criteria

- [x] Management folder contains source reports and Medical Rep 360 Dashboard
- [x] Employee filter limits all components to selected rep
- [x] Completed visits update time card and account target actuals
- [x] `MedicalRep360Seed.seedDemoData()` populates Jan–Jun 2026 demo data for four MR users

---

## IMP-009: CLM Presentation Logging & Feedback

### Business Context

Field reps need to launch approved CLM presentations during a visit, automatically log time spent on each slide, capture HCP feedback on product messages, and give managers reporting by rep globally or by specific HCP.

### Requirements

| # | Requirement |
|---|-------------|
| R1 | Admin console to upload PDF/HTML/ZIP presentations and configure slide sequences |
| R2 | Link slides to products and messages; optional mandatory slides |
| R3 | Territory targeting for presentation availability |
| R4 | Rep opens presentation from Visit record; fullscreen player with tracking pause/resume |
| R5 | Per-slide dwell time logged to visit session metrics |
| R6 | Product-message feedback (Positive / Neutral / Negative) per topic |
| R7 | Configurable rating layouts deployed for rep capture |
| R8 | Account activity history shows CLM usage per visit |
| R9 | Reports: time by presentation, by HCP, by slide, message sentiment |

### Wireframes

- **WF-011:** [AdminConsole_CLMManagement_Modal.png](./wireframes%20and%20references/AdminConsole_CLMManagement_Modal.png)
- **WF-012:** [AdminConsole_CLM_UploadPDF_HTMLMODAL.png](./wireframes%20and%20references/AdminConsole_CLM_UploadPDF_HTMLMODAL.png)
- **WF-013:** [AdminConsole_CLM_Slidessetup_LinkingToProducts.png](./wireframes%20and%20references/AdminConsole_CLM_Slidessetup_LinkingToProducts.png)
- **WF-014:** [CLMRepView](./wireframes%20and%20references/CLMRepView(Tracks%20every%20second%20on%20each%20slide%20for%20each%20visit_doc....%20and%20captures%20reactions).png)
- **WF-015:** [VISIT LWC or PAGE Tablet and desktop.png](./wireframes%20and%20references/VISIT%20LWC%20or%20PAGE%20Tablet%20and%20desktop.png)
- **WF-016:** [Visit Detailed Product Messages Response Capture.png](./wireframes%20and%20references/Visit%20Detailed%20Product%20Messages%20Response%20Capture.png)
- **WF-017:** [AdminConsoleRatingsConfigModalView.png](./wireframes%20and%20references/AdminConsoleRatingsConfigModalView.png)
- **WF-018:** [AccountActivityHistoryMobileanddesktopview...png](./wireframes%20and%20references/AccountActivityHistoryMobileanddesktopview%20showing%20detailed%20products%20and%20CLMs%20used.png)

> Implementation config: [`clm_module_config.yaml`](./clm_module_config.yaml)

### Acceptance Criteria

- [ ] Admin can upload a presentation and publish it as Available
- [ ] Rep sees territory-filtered presentations on Visit Presentations tab
- [ ] Player logs dwell seconds per slide and completes session
- [ ] Feedback and ratings save to session child records
- [ ] Account CLM activity history and report types support HCP/global analysis

---

## IMP-010: Project Management — C-Level Planning & Tracking

### Business Context

C-Level executives need to create and plan projects (campaigns, Zeta competitions, competency evaluations), assign people and budgets, set goals, and track execution across meetings, round tables, field visits, and promotional activities.

### Native Salesforce approach (standard vs custom)

| Requirement | Native choice | Custom only where needed |
|-------------|---------------|--------------------------|
| Project header | — | `Zeta_Project__c` |
| Team assignment | — | `Zeta_Project_Member__c` |
| User goals / tasks | **Standard `Task`** (`WhatId` → project) | Task custom fields for target/actual metrics |
| Meetings / round tables | **Standard `Event`** + `Event_Category__c` | — |
| Field visits | **`Visit__c`** + project lookup | — |
| Campaign execution (signage, ecommerce, brochures) | — | `Zeta_Project_Activity__c` |
| Brand budget lines | — | `Zeta_Project_Budget_Line__c` with roll-up summary |
| Account goals | — | `Zeta_Project_Account_Goal__c` |
| Business objectives | — | `Zeta_Business_Objective__c` |
| Create project | **Screen Flow** (`New_Project_Wizard`) | — |
| Project workspace | **Lightning Record Page** + related lists + Path | `projectSummaryPanel` LWC for roll-up tiles only |
| Portfolio view | **`projectManagementHub` LWC** → navigates to record page | — |

### Requirements

| # | Requirement |
|---|-------------|
| R1 | C-Level can create projects via Screen Flow with BU, campaign type, dates, lead, and budget |
| R2 | Project record page shows team, budget lines, account goals, objectives, activities, tasks, events, visits, and KPIs via native related lists |
| R3 | Standard Tasks assigned to users track project goals with optional target/actual values |
| R4 | Standard Events with category Meeting or Round Table roll up to competition tracking metrics |
| R5 | Field visits link to projects; Link Visits action bulk-associates eligible visits |
| R6 | Portfolio hub filters by BU/status and navigates to native project record pages |
| R7 | Promo budget lines can reference a Zeta Project lookup |

### Wireframes

**WF-PM-001 — Project Management Portfolio Hub**

![Portfolio Hub](./wireframes%20and%20references/WF-PM-001-portfolio-hub.png)

**WF-PM-002 — Zeta Project Record Page**

![Project Record Page](./wireframes%20and%20references/WF-PM-002-project-record-page.png)

### Acceptance Criteria

- [ ] New Project Screen Flow creates `Zeta_Project__c` in Planning status
- [ ] Record page renders Path, related lists, Activity Timeline, and summary panel on desktop and mobile
- [ ] Hub cards show budget, meetings, round tables, visits, open tasks, and team size
- [ ] Link Visits associates `Visit__c` records within project date range
- [ ] Promo budget line shows linked project name

---

## Appendix A — Wireframe Index

| ID | File | Implementation |
|----|------|----------------|
| WF-001 | [wireframe-dashboard.png](./wireframes%20and%20references/wireframe-dashboard.png) | IMP-001 |
| WF-002 | [wireframe-call-report.png](./wireframes%20and%20references/wireframe-call-report.png) | IMP-002 |
| WF-003 | [wireframe-account-detail.png](./wireframes%20and%20references/wireframe-account-detail.png) | IMP-003 |
| WF-004 | [AdminConsoleCoachingTemplateEditingView.png](./wireframes%20and%20references/AdminConsoleCoachingTemplateEditingView.png) | IMP-006 |
| WF-005 | [CoachingEvent(DoubleVisitForm)DesktopView.png](./wireframes%20and%20references/CoachingEvent(DoubleVisitForm)DesktopView.png) | IMP-006 |
| WF-006 | [Coaching Template Primitive UI_UX with Questions.png](./wireframes%20and%20references/Coaching%20Template%20Primitive%20UI_UX%20with%20Questions.png) | IMP-006 |
| WF-007 | [CoachingTemplateQuestion.png](./wireframes%20and%20references/CoachingTemplateQuestion.png) | IMP-006 |
| WF-008 | Dual-score competency card (user-provided) | IMP-006 |
| WF-009 | Field Rep Planner (calendar + map) | IMP-007 |
| WF-010 | [MedicalRep360Dashboard.png](./wireframes%20and%20references/MedicalRep360Dashboard.png) | IMP-008 |
| WF-011 | [AdminConsole_CLMManagement_Modal.png](./wireframes%20and%20references/AdminConsole_CLMManagement_Modal.png) | IMP-009 |
| WF-012 | [AdminConsole_CLM_UploadPDF_HTMLMODAL.png](./wireframes%20and%20references/AdminConsole_CLM_UploadPDF_HTMLMODAL.png) | IMP-009 |
| WF-013 | [AdminConsole_CLM_Slidessetup_LinkingToProducts.png](./wireframes%20and%20references/AdminConsole_CLM_Slidessetup_LinkingToProducts.png) | IMP-009 |
| WF-014 | CLM Rep Player | IMP-009 |
| WF-015 | [VISIT LWC or PAGE Tablet and desktop.png](./wireframes%20and%20references/VISIT%20LWC%20or%20PAGE%20Tablet%20and%20desktop.png) | IMP-009 |
| WF-016 | [Visit Detailed Product Messages Response Capture.png](./wireframes%20and%20references/Visit%20Detailed%20Product%20Messages%20Response%20Capture.png) | IMP-009 |
| WF-017 | [AdminConsoleRatingsConfigModalView.png](./wireframes%20and%20references/AdminConsoleRatingsConfigModalView.png) | IMP-009 |
| WF-018 | [AccountActivityHistory...png](./wireframes%20and%20references/AccountActivityHistoryMobileanddesktopview%20showing%20detailed%20products%20and%20CLMs%20used.png) | IMP-009 |
| WF-PM-001 | [WF-PM-001-portfolio-hub.png](./wireframes%20and%20references/WF-PM-001-portfolio-hub.png) | IMP-010 |
| WF-PM-002 | [WF-PM-002-project-record-page.png](./wireframes%20and%20references/WF-PM-002-project-record-page.png) | IMP-010 |

---

## Appendix B — Glossary

| Term | Definition |
|------|------------|
| **HCP** | Healthcare Professional |
| **OCE** | Orchestrated Customer Engagement (IQVIA) |
| **MI** | Medical Information (IQVIA) |
| **MSL** | Medical Science Liaison |
| **SLDS** | Salesforce Lightning Design System |

---

## Revision History

| Date | Version | Author | Changes |
|------|---------|--------|---------|
| Jun 2026 | 0.6 | — | Added IMP-010 Project Management — C-Level Planning & Tracking, WF-PM-001–WF-PM-002 |
| Jun 2026 | 0.5 | — | Added IMP-009 CLM Presentation Logging & Feedback, WF-011–WF-018 |
| Jun 2026 | 0.4 | — | Added IMP-008 Medical Rep 360 Dashboard, WF-010 |
| Jun 2026 | 0.3 | — | Added IMP-007 Field Rep Planner |
| Jun 2026 | 0.2 | — | Added IMP-006 Coaching Templates & Events, WF-004–WF-008 |
| Jun 2026 | 0.1 | — | Initial BRD structure, IMP-001 to IMP-005, starter wireframes |
