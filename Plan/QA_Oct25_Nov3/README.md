# QA calendar — 25 Oct through 8 Nov 2026

Cloudastick ↔ Zeta Pharma joint QA. SFE sets the org up. The rep and the manager then walk the work in the order it happens.

**Org:** `zetapharma.my.salesforce.com`  
**Field PWA:** `ph/offline` (Field / Lead / SFE Co-pilots)  
**Issue log:** [../dry-run-oct21/Zeta_SFE_Issue_Log.xlsx](../dry-run-oct21/Zeta_SFE_Issue_Log.xlsx)  
**Coverage matrix (sign-off):** [Coverage_Matrix.md](Coverage_Matrix.md)  
**Standup agenda:** [Standup_Agenda.md](Standup_Agenda.md)

## How the field days run

Rep first, then the manager, in the order the work happens:

1. Create the visit plan and submit it for approval.
2. See the target customers.
3. Execute the visit, the samples, and the CLM.
4. See those numbers on the home page dashboard.

The manager day uses the same path: approve the plan, see the team’s customers, see the executed visit, then read the numbers on the team home.

Patient care coach is not in this UAT.

SFE uses the same kind of language, split so a day can finish. Set the foundation, then accounts and targets, then KPIs and sales, then prepare what the visit will use. The rep’s execute day is separate from Class Engine and Home.

## Cadence

| Day | Cloudastick | Zeta |
|---|---|---|
| **Sun 25 Oct** | First-pass: set the foundation | — (no standup) |
| **Mon 26 Oct** | First-pass: accounts, targets, customer type | Retest: foundation |
| **Tue 27 Oct** | First-pass: KPIs, bulk sales, distributor sales | Retest: accounts and targets |
| **Wed 28 Oct** | First-pass: prepare what the visit will use | Retest: KPIs and sales |
| **Thu 29 Oct** | First-pass: create the visit plan, submit it, see target customers | Retest: visit content |
| **Fri 30 – Sat 31 Oct** | Off | Off |
| **Sun 1 Nov** | First-pass: execute the visit, samples, and CLM | Retest: plan, submit, and customers |
| **Mon 2 Nov** | First-pass: Class Engine, learning, quiz, then Home | Retest: the executed visit |
| **Tue 3 Nov** | First-pass: approve the plan, open Class Engine, read the team home | Retest: Class Engine and Home |
| **Wed 4 Nov** | First-pass: meetings, requests, and KAM | Retest: manager journey |
| **Thu 5 Nov** | First-pass: reports and dashboards | Retest: meetings, requests, and KAM |
| **Fri 6 – Sat 7 Nov** | Off | Off |
| **Sun 8 Nov** | Retest open fails and walk the same records through | Retest: reports and dashboards → **sign matrix** |

First standup: **Mon 26 Oct**. Final close: **Sun 8 Nov**.

## Day scripts

| Date | File |
|---|---|
| Sun 25 | [days/01_Sun25_SFE_Foundation.md](days/01_Sun25_SFE_Foundation.md) |
| Mon 26 | [days/02_Mon26_SFE_Commercial.md](days/02_Mon26_SFE_Commercial.md) |
| Tue 27 | [days/03_Tue27_KPIs_Sales.md](days/03_Tue27_KPIs_Sales.md) |
| Wed 28 | [days/04_Wed28_Visit_Content.md](days/04_Wed28_Visit_Content.md) |
| Thu 29 | [days/05_Thu29_Rep_Plan.md](days/05_Thu29_Rep_Plan.md) |
| Sun 1 Nov | [days/06_Sun01_Execute.md](days/06_Sun01_Execute.md) |
| Mon 2 Nov | [days/07_Mon02_ClassEngine_Home.md](days/07_Mon02_ClassEngine_Home.md) |
| Tue 3 Nov | [days/08_Tue03_Managers.md](days/08_Tue03_Managers.md) |
| Wed 4 Nov | [days/09_Wed04_Meetings.md](days/09_Wed04_Meetings.md) |
| Thu 5 Nov | [days/10_Thu05_Reports.md](days/10_Thu05_Reports.md) |
| Sun 8 Nov | [days/11_Sun08_Close.md](days/11_Sun08_Close.md) |

## Rules (every day)

1. Log **Pass / Fail / Blocked** the same day in the issue log, with record Id or screenshot.
2. Zeta retests the **same journey on the same users** Cloudastick used the prior working day.
3. Zeta does **not** retest a Cloudastick **Blocker** until a fix or “still blocked” note is posted.
4. Severity: **Blocker** (journey cannot finish), **Major** (wrong number / missing section), **Minor** (label / layout).
5. **Do not:** wipe accounts, copy a plan month, publish a CLM deck to every territory, greenlight a duplicate merge, or load a new monthly zip. View + one reversible edit only.
6. Channel rule: **AM** = hospital; **PM** = HCP, clinic, pharmacy, other non-hospital.

## Suggested test seats

From [../Account_Master_Target_Reload_Validation.md](../Account_Master_Target_Reload_Validation.md). Keep the same person for Cloudastick day N and Zeta day N+1.

| Role | Name | Territory / note | Username |
|---|---|---|---|
| Rep | Abadir Esmat Tawfik Botros | GIT-I ASSUIT-A (~211 ATF) | `abadir.esmat@zetapharma.net` |
| Rep (alt) | Abdelmonsef Galal Elshazly Esmail | ORTHO-I KAFR ELSHEIKH | `abdelmonsef.galal@zetapharma.net` |
| Manager | Ahmed Magdy Elsayed Elmaghawry | GIT-I DM CAIRO B | `ahmed.magdy@zeta-pharma.com` |
| Manager (alt) | Ahmed Mosaad Mostafa Ibrahim | Field Force Supervisor | `ahmed.mosaad@zeta-pharma.com` |
| SFE | Known admin | `Pharma_Admin` + `Pharma_SFE_App` | (org SFE user) |

## Not bugs (22 Oct reload)

Empty bricks until a brick file exists · vacant seats with no ATF · 34 target rows with no account. Log only if the UI hides them or crashes.

## Related validation packs

- [../Account_Master_Target_Reload_Validation.md](../Account_Master_Target_Reload_Validation.md)
- [../dry-run-oct21/README.md](../dry-run-oct21/README.md)
- `../SFE_Validation_Steps.pdf`
- `../SFE_Admin_Console_Validation.pdf`
