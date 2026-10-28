# Day 5 — Thu 29 Oct 2026 — Create the visit plan, submit it, and see target customers

**Standup:** yes  
**Zeta today:** retest [04_Wed28_Visit_Content.md](04_Wed28_Visit_Content.md) — what the visit will use is covered by both teams after Zeta finishes  
**Cloudastick today:** create the visit plan, submit it for approval, then see the target customers  
**Users:** one rep with a real book (e.g. Abadir Esmat)  
**Surfaces:** Lightning **and** PWA (`ph/offline`)

**Slip rule:** If this day does not finish, Sunday morning finishes the submit before anyone executes a visit. The manager day (Tue 3 Nov) needs a **submitted** visit.

Channel: AM = hospital · PM = HCP / clinic / pharmacy / other non-hospital.

Do this day in this order. Sunday executes the visit. Monday opens Class Engine and reads Home. Do not judge Home until that visit exists.

---

## 1. Create the visit plan and submit it for approval

| # | Step | Pass if | CS SF | CS PWA | Zeta SF (Sun 1) | Zeta PWA (Sun 1) | Evidence |
|---|---|---|---|---|---|---|---|
| P1 | Login Field Co-pilot | No permission errors; field apps visible | | | | | |
| P2 | Planner — week + sidebar | Sees the target book only, not the full 135k | | | | | |
| P3 | Draft — in-plan doctor | Draft saves; on the day | | | | | |
| P4 | Draft — hospital (AM) | Counts toward planned AM | | | | | |
| P5 | Draft — pharmacy (PM) | Counts toward planned PM | | | | | |
| P6 | Overlap — visit × visit | Blocked / warned per the planner rules from Sunday | | | | | |
| P7 | Overlap — visit × time off | Blocked / warned | | | | | |
| P8 | Weekend / holiday plan | Blocked / warned | | | | | |
| P9 | Submit one visit | Status Submitted (or pending approval) | | | | | |
| P10 | Submit the week | Eligible drafts submit; conflicts listed if any | | | | | |
| P11 | PWA syncs the book | Account count ≈ the target book | | N/A | | N/A | |
| P12 | Offline draft → sync | Appears in Lightning as Draft | | | | | |

## 2. See the target customers

| # | Step | Pass if | CS SF | CS PWA | Zeta SF (Sun 1) | Zeta PWA (Sun 1) | Evidence |
|---|---|---|---|---|---|---|---|
| C1 | Customer — HCP | Person account / DOC-\*; affiliations visible | | | | | |
| C2 | Customer — pharmacy | Pharmacy page opens | | | | | |
| C3 | Customer — hospital | Hospital page opens | | | | | |
| C4 | Ratings on that customer | Rating form loads | | | | | |
| C5 | Search أحمد | Hits via the name search | | | | | |
| C6 | Search Ahmed | Same family of hits | | | | | |
| C7 | Search a pharmacy brand | Brand hit; no blank crash | | | | | |

## Day pass criteria

A visit is **submitted**. Hospital counts as AM; pharmacy and doctor count as PM. The rep can open target customers on that book. An offline draft appears in Lightning as Draft.

## Submitted visit Id (required for Sunday’s execution, and for the manager on Tue 3)

Visit Id: _______________ Account: _______________ Rep: _______________

## Log

- Tester (CS): _______________ Date: 29 Oct 2026  
- Overall Lightning: Pass / Fail / Blocked  
- Overall PWA: Pass / Fail / Blocked  
