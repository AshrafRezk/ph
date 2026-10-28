# Day 10 — Thu 5 Nov 2026 — Reports and dashboards

**Standup:** yes  
**Zeta today:** retest [09_Wed04_Meetings.md](09_Wed04_Meetings.md) — the meeting, the request, and KAM  
**Cloudastick today:** open the reports and dashboards in BRD §5.16, on the same records from this UAT  
**Users:** the test rep, the test manager, and the SFE user. Brand and executive only if a login exists.

BRD §5.16: each role has its own dashboard, they read the visits the field created, and a manager can roll the same numbers from the rep up to the district and the business unit. §5.15 names what Medical Rep 360 has to show.

Do not rebuild the numbers in a spreadsheet. If a dashboard disagrees with Home, that is a Fail.

---

## A. Reports Hub

| # | Step | Pass if | CS | Zeta (Sun 8) | Evidence |
|---|---|---|---|---|---|
| RD1 | Reports Hub | The tiles load | | | |
| RD2 | Working Days Analysis | Opens for the test territory and this month. Visits and time off are on it | | | |
| RD3 | Medical Rep 360 — the test rep | Shows the Sunday visit. Coverage, RF, CLM %, time off, and coaching are on the page | | | |
| RD4 | Pharmacy sales | The dashboard opens for a brick or a product | | | |
| RD5 | Bulk and chain share | The sales view shows how bulk or chain sales were shared, or you write down that the split is not on the page | | | |

## B. Who sees which dashboard

Open each one with the role that owns it. A missing login is **Blocked-no-user**. Do not skip the row.

| # | Role | What they open | Pass if | CS | Zeta (Sun 8) | Evidence |
|---|---|---|---|---|---|---|
| RD6 | Rep | Reports Hub and Home | Own book only. The Sunday visit is there. Another district is not | | | |
| RD7 | Manager (DM) | Medical Rep 360 and the team home | The test rep’s visit, coverage, and CLM % match Home | | | |
| RD8 | Manager, filtered up | Working Days, then business unit → line → district | The numbers follow the filter | | | |
| RD9 | SFE | Medical Rep 360 for that rep | Same visit Id as Sunday. CLM from that visit is in the CLM % | | | |
| RD10 | Brand | Pharmacy sales or the brand view | Opens for a brand, or Blocked-no-user | | | |
| RD11 | Executive | Executive home | Org snapshot and the business-unit cards open (visits, coverage, CLM), or Blocked-no-user | | | |

## C. The folders

| # | Step | Pass if | CS | Zeta (Sun 8) | Evidence |
|---|---|---|---|---|---|
| RD12 | Standard reports | The folder opens | | | |
| RD13 | Standard dashboards | The folder opens | | | |
| RD14 | Same truth | Medical Rep 360 and Working Days show the Sunday visit Id, and the visit count matches the rep home | | | |

Visit Id: _______________ Rep: _______________

## Day pass criteria

Reports Hub opens. Working Days Analysis and Medical Rep 360 show the Sunday visit. Pharmacy sales opens. The rep, the manager, and SFE each see that visit on their own dashboard, and the numbers match Home. Brand and executive are opened or marked Blocked-no-user.

## Log

- Tester (CS): _______________ Date: 5 Nov 2026  
- Reports Hub: Pass / Fail / Blocked  
- Medical Rep 360: Pass / Fail / Blocked  
- Working Days: Pass / Fail / Blocked  
- Pharmacy sales: Pass / Fail / Blocked  
- Role dashboards: Pass / Fail / Blocked  
