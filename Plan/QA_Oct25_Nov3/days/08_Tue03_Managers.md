# Day 8 — Tue 3 Nov 2026 — Approve the plan, see the visit, read the team numbers

**Standup:** yes  
**Zeta today:** retest [07_Mon02_ClassEngine_Home.md](07_Mon02_ClassEngine_Home.md) — Class Engine, the learning and the quiz, and the numbers on the rep home  
**Cloudastick today:** the manager walks the same path, one level up  
**User:** the manager who owns the Thursday–Sunday rep (e.g. Ahmed Magdy for GIT-I)  
**App:** Lead Co-pilot in Lightning, or PWA `Pharma_Management` if the Lightning app is missing (see Day 1, the Lead Co-pilot check)

**Prerequisite:** Thursday’s visit is **submitted**, and Sunday put a sample or a request and a CLM on it. Do not start this script on an unsubmitted draft.

Same order as the rep:

1. Approve the visit plan.
2. See the team’s target customers.
3. See the executed visit, the samples, and the CLM.
4. Open Class Engine for that rep.
5. Read the numbers on the team home, including the KPI SFE added on Tue 27 Oct.

---

## 1. Approve the submitted visit plan

| # | Step | Pass if | CS | Zeta (Wed 4) | Evidence |
|---|---|---|---|---|---|
| M1 | Login Lead Co-pilot / PWA Lead | District manager permission set; no field-level security error on entry | | | |
| M2 | Open the rep’s planner week | The submitted plan is there; no object errors | | | |
| M3 | Approve one item | Act on one item only: the visit, time off, or a classification | | | |

## 2. See the team’s target customers

| # | Step | Pass if | CS | Zeta (Wed 4) | Evidence |
|---|---|---|---|---|---|
| M4 | Search inside the team | A customer on this rep’s book is found; a customer outside the book is not | | | |

## 3. See the executed visit, the samples, and the CLM

| # | Step | Pass if | CS | Zeta (Wed 4) | Evidence |
|---|---|---|---|---|---|
| M5 | Open that visit | The Thursday / Sunday visit shows the products, the sample or request, and the CLM | | | |
| M6 | Field tracking | Team activity includes that rep | | | |

## 4. Open Class Engine for that rep

| # | Step | Pass if | CS | Zeta (Wed 4) | Evidence |
|---|---|---|---|---|---|
| M16 | Class Engine | Opens on the test rep’s territory. Quarter is on the page, and the test customers show a class. Another district is not in the territory picker. If it says Class Engine is turned off, that is a Fail | | | |

## 5. See the reflected numbers on the team home

| # | Step | Pass if | CS | Zeta (Wed 4) | Evidence |
|---|---|---|---|---|---|
| M7 | Workforce numbers | Headcount, visits, CLM %, days not reported, and time off are on the page, and this rep’s visit is in that picture | | | |
| M8 | Filter business unit → line → district | The filters work, and the numbers follow the filter | | | |
| M15 | The new KPI | The label SFE added on Tue 27 Oct for this manager is on the team home or the scorecard | | | |

## Also on this day

| # | Step | Pass if | CS | Zeta (Wed 4) | Evidence |
|---|---|---|---|---|---|
| M9 | My Team | The roster and the links work | | | |
| M10 | Field Voice | Opens, or Blocked with a reason | | | |
| M11 | My Learning | Opens | | | |
| M12 | Coaching event on that rep | The event is created or opened, and the manager can score it | | | |
| M13 | Rep can open the coaching | The rep’s login shows the event | | | |
| M14 | Stay in your own district | Does not see another district’s book | | | |

## Day pass criteria

The manager can see the submitted plan and acts on one approval, can see the team’s customers, can open the executed visit with its sample or CLM, can open Class Engine for that rep, and can read that work on the team home, including the KPI SFE added on Tue 27 Oct. Another district’s book stays hidden.

## Linked evidence

Rep visit Id from Thursday: _______________  
Coaching event Id: _______________  
Approval acted on: type _______________ Id _______________

## Log

- Tester (CS): _______________ Date: 3 Nov 2026  
- Surface used: Lightning Lead Co-pilot / PWA Lead / Both  
- Overall: Pass / Fail / Blocked  
