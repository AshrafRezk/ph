# Pharma Commercial Discovery & Scoping Template

**Purpose:** Run discovery with any pharmaceutical company, ask the right questions, and map needs to a proven Salesforce Sales Cloud pharma stack (Field + Management + Executive).  
**Audience:** Solution consultants, architects, sales engineers, delivery leads  
**Based on:** Implemented modules in this Pharmaceuticals org (see also `Zeta_Pharma_Sales_Enablement_Guide.md`)  
**Version:** July 2026

---

## How to Use This Template

1. **Pre-read** the customer’s current tools (Veeva / OCE / spreadsheets / custom CRM) and org chart (Field, SFE, Medical, Marketing, Compliance).
2. **Fill Section A** in the first call (company profile + pain).
3. Walk **Sections B–K** module by module — use **Must / Should / Could / Won’t** for each capability.
4. Capture answers in the blank lines / tables; mark **Out of scope** explicitly.
5. Close with **Section L** (phased recommendation) and share a one-page capability map.
6. Do **not** promise App Plus Offline SKU timelines — position **offline journeys** (CLM, visits, planner) as a hybrid Briefcase + device cache pattern; confirm licensing with Salesforce AE.

**MoSCoW legend**

| Code | Meaning |
|------|---------|
| **M** | Must have for go-live |
| **S** | Should have in wave 1–2 |
| **C** | Could have / later |
| **W** | Won’t have this program |

---

## A. Customer Profile (fill first)

| Field | Answer |
|-------|--------|
| Company / BU | |
| Markets / countries | |
| Therapy areas / product count | |
| Field force size (reps / MSLs / DMs) | |
| Current CRM / CLM / sample system | |
| Target go-live | |
| Sponsors (Commercial / IT / Compliance) | |
| Primary success metric | |

### Opening pain prompts

- Where do reps lose the most time today (planning, call logging, content, samples, reporting)?
- What breaks when connectivity is poor (clinics, rural routes, hospitals)?
- What does leadership not trust in today’s numbers (coverage, RF, sell-out, coaching)?
- What audit / compliance risk keeps Medical Affairs or Legal awake at night?

**Customer notes:**

_______________________________________________________________________________

_______________________________________________________________________________

---

## Capability Map — What Salesforce Delivers for Pharma

Use this table in the room to show the commercial loop on one platform.

| Pharma challenge | Salesforce capability (built pattern) | Typical persona |
|------------------|----------------------------------------|-----------------|
| Wrong account model for HCP vs pharmacy vs HCO | Pharma Account record types + layouts | Rep, data steward |
| Misaligned targeting / wasted calls | Territory ATF / ATPF / PTA + bricks | SFE, DM, rep |
| No single morning view | Field Rep Home (coverage, route, NBC) | Medical rep |
| Hard to plan the week | Planner (calendar + map + route) | Rep, DM |
| Incomplete / late call reports | Visit call reporting (desktop + mobile) | Rep, compliance |
| Sample / lot risk | Sample inventory + visit deduction | Rep, logistics |
| Approved content not tracked | CLM player + dwell / message / ratings | Marketing, rep |
| No HCP feedback loop | Product surveys / WhatsApp-style links | Rep, medical |
| Medical questions lost in email | Medical Inquiry → Case | Rep, MA |
| Network of influence invisible | Account affiliations graph | Rep, KAM |
| Coaching tribal knowledge | Coaching templates + dual scoring | DM, SFE |
| Coverage inflated by leave | Time Off Territory + plan-cycle KPIs | Rep, DM, SFE |
| Sell-out disconnected from visits | Pharmacy sales import + AI recommendations | Trade, SFE |
| Leadership lag | Management / Executive dashboards + projects | DM, C-level |
| Field works offline | Briefcase + IndexedDB hybrid (CLM / visits / planner) | Rep |

---

## B. Customer Master & Segmentation

**Module in stack:** Account foundation (HCP / Pharmacy / Institution / Business Contact), specialties, ratings layouts.

### Discovery questions

1. Which customer types must exist Day 1? (HCP / Pharmacy / HCO / wholesaler / other)  
   **Answer:** ________________________________
2. Person Accounts for HCPs? Multi-specialty (Specialty 1–N)? License / tier / local IDs?  
   **Answer:** ________________________________
3. Who owns master data today (OneKey, IQVIA, internal MDM, Excel)? Sync cadence?  
   **Answer:** ________________________________
4. How often do reps refresh potential / penetration / loyalty ratings? AI validation wanted?  
   **Answer:** ________________________________
5. Are affiliations (HCP↔pharmacy↔HCO) required for attendee picking and sell-out bridge?  
   **Answer:** ________________________________

| Capability | MoSCoW | Notes |
|------------|--------|-------|
| HCP / Pharmacy / HCO / BC record types | | |
| Specialty taxonomy (global picklist) | | |
| Account rating forms (potential / adoption / loyalty) | | |
| Affiliation network | | |

**Salesforce talk track:** *One Account object, governed record types — visits, samples, CLM, and sell-out hang off the same customer 360.*

---

## C. Territory, Targeting & Bricks

**Module in stack:** ATF / ATPF / PTA, bricks, Admin Console territory & bricks tools.

### Discovery questions

1. Classification model today (A/B/C × penetration)? Visit frequency by product?  
   **Answer:** ________________________________
2. Who maintains Account × Territory and Account × Territory × Product matrices? Cycle length?  
   **Answer:** ________________________________
3. Do you use geographic bricks (IMS or custom)? Pharmacy membership rules?  
   **Answer:** ________________________________
4. Enterprise Territory Management vs custom hierarchy? Realignment process per cycle?  
   **Answer:** ________________________________
5. Must call report / CLM product pickers filter to territory-aligned products only?  
   **Answer:** ________________________________

| Capability | MoSCoW | Notes |
|------------|--------|-------|
| ATF (potential / penetration / classification) | | |
| ATPF (Rx, adoption, loyalty, target frequency) | | |
| PTA (sellable products per territory) | | |
| Bricks & pharmacy–brick links | | |
| Territory / bricks admin console | | |

**Salesforce talk track:** *OCE-style targeting without a second database — home KPIs, NBC, and visit product scope all read the same alignment.*

---

## D. Daily Field Execution (Home + Planner + Visits)

**Module in stack:** Field Rep Home, Accounts Tab, Field Planner, Visit Call Shell / mobile call report.

### Discovery questions

1. What must the rep see before leaving home (coverage by A/B/C, RF%, today’s map, NBC)?  
   **Answer:** ________________________________
2. Planner: week calendar, drag-drop, TOT slots, map route optimize — which are mandatory?  
   **Answer:** ________________________________
3. Visit sections required: Details / Attendees / Products+messages / Samples / CLM / Affiliations / Coaching / MI?  
   **Answer:** ________________________________
4. Draft → Completed rules? Manager approval? Completed read-only? Double-visits?  
   **Answer:** ________________________________
5. Desktop Lightning + Salesforce mobile (VF/LWC) both required?  
   **Answer:** ________________________________
6. In-plan vs out-of-plan account browsing / map pins needed?  
   **Answer:** ________________________________

| Capability | MoSCoW | Notes |
|------------|--------|-------|
| Field Rep Home (metrics + today plan + NBC) | | |
| Accounts tab (list + map + collections) | | |
| Weekly planner (calendar + map + route) | | |
| Visit call report (full sections) | | |
| Home Office messages | | |

**Salesforce talk track:** *Plan → execute → report on one mobile-first loop; KPIs roll up from the same Visit records managers trust.*

---

## E. Compliance Content & Samples (CLM + Sampling + MI)

**Module in stack:** CLM admin + player + metrics; sample inventory/transactions; Medical Inquiry → Case.

### Discovery questions

1. CLM formats (PDF / HTML / ZIP slides)? Mandatory slides? MLR / medical approval before publish?  
   **Answer:** ________________________________
2. Must presentations be territory-targeted and logged with dwell time + message sentiment + ratings?  
   **Answer:** ________________________________
3. Sampling regulated? Lot / expiry / signature? Transfers between reps? Block expired/over-qty?  
   **Answer:** ________________________________
4. Medical Inquiry: Case queues, SLAs, who closes, email-to-case?  
   **Answer:** ________________________________
5. Product surveys or WhatsApp/SMS links from the visit? Consent requirements?  
   **Answer:** ________________________________

| Capability | MoSCoW | Notes |
|------------|--------|-------|
| CLM library + territory targeting | | |
| In-visit CLM player + analytics | | |
| Sample inventory + visit deduction | | |
| Medical Inquiry intake | | |
| HCP product survey / messaging links | | |

**Salesforce talk track:** *Approved content and samples become auditable visit facts — not screenshots in a chat thread.*

---

## F. People, Capacity & Field Development

**Module in stack:** Coaching templates/events, Time Off Territory, Employee Plan Cycle / Medical Rep 360.

### Discovery questions

1. Competency model for ride-alongs? Dual score (rep + manager) mandatory?  
   **Answer:** ________________________________
2. TOT types (leave, training, admin, travel)? Who approves? Must TOT reduce coverage denominator?  
   **Answer:** ________________________________
3. Plan-cycle cadence (monthly)? Who sets account targets? Copy-forward process?  
   **Answer:** ________________________________
4. Medical Rep 360 KPIs needed (coverage, RF, LCF/RCF/MCF, CLM%, TOT, coaching trend)?  
   **Answer:** ________________________________
5. Fleet / live location tracking for managers? Privacy / consent constraints?  
   **Answer:** ________________________________

| Capability | MoSCoW | Notes |
|------------|--------|-------|
| Coaching templates + events | | |
| Time Off Territory + approvals | | |
| Plan cycles + account targets | | |
| Medical Rep 360 / working-days metrics | | |
| Management fleet map | | |

**Salesforce talk track:** *Honest capacity + structured coaching — coverage and development share one data model.*

---

## G. Market Data → Field Action (Pharmacy Sell-Out & AI)

**Module in stack:** Pharmacy sales CSV import, brick dashboards, Agentforce planning recommendations.

### Discovery questions

1. Wholesaler / distributor sources and file formats? External IDs for pharmacies / products?  
   **Answer:** ________________________________
2. Desired output: brick revenue, HCP recommendations via affiliations, auto draft visits, plan targets?  
   **Answer:** ________________________________
3. AI: advise only vs bulk-apply recommendations? Local language? Trust / review process?  
   **Answer:** ________________________________
4. Einstein / Agentforce licensing available?  
   **Answer:** ________________________________

| Capability | MoSCoW | Notes |
|------------|--------|-------|
| Sales data import batches | | |
| Pharmacy / brick analytics dashboards | | |
| AI planning insights + apply actions | | |

**Salesforce talk track:** *Connect sell-out to the same accounts and visits — Agentforce recommends on your data, not a generic chatbot.*

---

## H. Leadership Stack (Projects, Budgets, Dashboards)

**Module in stack:** Executive projects, promo budgets, cross-dept collaboration, management KPI / executive home, reports hub, coverage heat maps.

### Discovery questions

1. Do brand / C-level need project portfolios (budget, milestones, KPIs, linked visits)?  
   **Answer:** ________________________________
2. Promo budget utilization by BU? Cross-department collaboration requests?  
   **Answer:** ________________________________
3. Manager command center: team KPIs, heat maps, compensation context visibility rules?  
   **Answer:** ________________________________
4. Scheduled report packs vs live Lightning dashboards?  
   **Answer:** ________________________________

| Capability | MoSCoW | Notes |
|------------|--------|-------|
| Project management hub | | |
| Promo budget dashboard | | |
| Cross-dept collaboration | | |
| Management team KPI dashboard | | |
| Executive home / reports hub | | |
| Geographic coverage heat map | | |

**Salesforce talk track:** *Leadership sees the same visit and spend truth the field creates — no monthly PowerPoint rebuild.*

---

## I. Ops, Catalog & Integrations

**Module in stack:** Admin Console, product catalog, integrations console (maps/OSRM, CSV, Einstein; placeholders for OneKey / SAP / Mendix / Outlook).

### Discovery questions

1. Who runs commercial ops changes each cycle (CLM, territory, plan, coaching) without IT?  
   **Answer:** ________________________________
2. Product catalog depth (therapy area, brand, SKU images, external IDs)?  
   **Answer:** ________________________________
3. Must-have connectors Day 1 vs later (MDM, ERP samples, email, middleware)?  
   **Answer:** ________________________________
4. Named Credential / security ownership (IT vs vendor)?  
   **Answer:** ________________________________

| Capability | MoSCoW | Notes |
|------------|--------|-------|
| Admin Console (self-service ops) | | |
| Product catalog governance | | |
| Maps / routing (OSM + OSRM or vendor) | | |
| MDM / OneKey | | |
| ERP / sample master | | |
| Middleware (e.g. Mendix) | | |

**Salesforce talk track:** *Commercial ops change every cycle in Admin Console; IT owns the pipes, not every content tweak.*

---

## J. Offline & Mobile Journeys (critical for field pharma)

**Module in stack:** Hybrid offline — Briefcase (`Pharma_Field_Rep_Offline`) + IndexedDB (`clmOfflineStore` / content cache / action queue).

### Must-work-offline checklist (rank 1–5)

| Journey | Need offline? (Y/N) | Priority | Notes |
|---------|---------------------|----------|-------|
| Play CLM decks + capture session / feedback | | | |
| Open / complete visit call report | | | |
| View & edit weekly planner | | | |
| Create / submit coaching from double-visit | | | |
| Field home today plan / NBC (read or draft) | | | |
| Sample lines on visit (with offline validation caveats) | | | |

### Discovery questions

1. Confirm Mobile Offline / Briefcase licensing with Salesforce AE (independent of any App Plus Offline SKU EOL discussions).  
   **Answer:** ________________________________
2. Record volume per rep per day (visits, products, presentations) vs briefcase limits?  
   **Answer:** ________________________________
3. Conflict policy when two devices edit the same visit?  
   **Answer:** ________________________________
4. Prefetch window (today only vs rolling N days)? CLM binary size budget per device?  
   **Answer:** ________________________________

| Capability | MoSCoW | Notes |
|------------|--------|-------|
| Briefcase record sync-down | | |
| IndexedDB CLM asset cache | | |
| Offline write queue + sync on reconnect | | |
| Offline planner week cache | | |

**Salesforce talk track:** *CLM binaries, visit logging, and planner are delivered with a proven hybrid pattern — not blocked on a single discontinued SKU narrative. Licensing for Briefcase/Mobile Offline must still be confirmed.*

---

## K. Optional / Vertical Add-ons

| Capability | In scope? | MoSCoW | Notes |
|------------|-----------|--------|-------|
| Diagnostics / radiology commission cards | Y / N | | |
| Multi-BU (e.g. GIT / Diabetes / Cluster / CHC) | Y / N | | |
| Localization (language, geography, local IDs) | Y / N | | |
| Gamification / commission widgets on home | Y / N | | |

---

## L. Workshop Outputs — Recommended Phasing

### Suggested wave model (adjust per customer)

| Wave | Focus | Typical modules |
|------|-------|-----------------|
| **0 — Foundation** | Accounts, products, territories, security, Admin Console | B, C, I |
| **1 — Field core** | Home, Planner, Visits, Samples, Offline journeys | D, E (samples), J |
| **2 — Content & medical** | CLM, MI, surveys | E |
| **3 — People & cycle** | Coaching, TOT, Plan cycle / 360 | F |
| **4 — Market & AI** | Pharmacy sell-out, Agentforce apply | G |
| **5 — Leadership** | Projects, budgets, exec / mgmt dashboards | H |

### Decision summary (fill at end of workshop)

| Item | Decision |
|------|----------|
| Wave 1 go-live date | |
| In-scope modules (list IDs / names) | |
| Explicit out of scope | |
| Licensing to confirm (AE) | |
| Data migration sources | |
| Pilot territories / user count | |
| Risks / open questions | |
| Next workshop date | |

### Sign-off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Customer sponsor | | | |
| Commercial / SFE | | | |
| IT / Salesforce owner | | | |
| Compliance / Medical (if needed) | | | |
| Delivery lead | | | |

---

## Appendix — Persona Apps (demo framing)

| App | Who | Primary job in discovery demo |
|-----|-----|-------------------------------|
| **Pharma Field** | Medical reps, MSLs | Plan → visit → CLM → sample → offline |
| **Pharma Management** | DMs, SFE, regional | Coach, approve TOT, team KPIs, fleet |
| **Pharma Executive** | C-level, BU heads | Projects, budgets, portfolio KPIs |

## Appendix — Quick question bank (30-minute call)

If time is short, ask only these:

1. What are the three account types that must exist on Day 1?
2. How do you classify and frequency-target HCPs today?
3. Must CLM, visit logging, and planner work without network?
4. Are samples lot/expiry controlled?
5. What does a DM look at every Monday morning?
6. Which external systems are non-negotiable for go-live?
7. Who will administer territories / CLM / plan cycles without IT?
8. What single KPI proves the program succeeded in 90 days?

---

## Related documents

- `Plan/Zeta_Pharma_Sales_Enablement_Guide.md` — module talk tracks & depth  
- `Plan/BRD.md` — implementation IDs / acceptance style  
- `Plan/OFFLINE_BRIEFCASE_SETUP.md` — hybrid offline activation  
- `Plan/general-rules-for-all-implementations.md` — delivery standards  
