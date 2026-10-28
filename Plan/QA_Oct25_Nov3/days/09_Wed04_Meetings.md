# Day 9 — Wed 4 Nov 2026 — Meetings, requests, and KAM

**Standup:** yes  
**Zeta today:** retest [08_Tue03_Managers.md](08_Tue03_Managers.md) — approve the plan, open Class Engine, see the visit, read the team home  
**Cloudastick today:** send a meeting and a request for approval, see KAM, and ask Field AI. Reports and dashboards are Thursday.  
**Users:** a rep to raise the meeting and the request; the approver (manager) to open each doctor; SFE for KAM  

**Safety:** the HCP invite and the QR use a **test contact**, not a live doctor’s WhatsApp. The request uses a doctor already on the test rep’s book. Do not approve a live expense. One request only.

Patient care coach is not in this UAT.

---

## A. Create a meeting and send it on for approval

| # | Step | Pass if | CS | Zeta (Thu 5) | Evidence |
|---|---|---|---|---|---|
| MT1 | Create the meeting from the planner | A meeting record is created | | | |
| MT2 | Send it to the next approver | Matches the meeting-approval sequence from Tuesday | | | |
| MT3 | Speakers, topics, locations | The tabs or related lists open | | | |
| MT4 | Budget and meeting accounting | Opens | | | |
| MT5 | HCP invite and QR (test contact) | The invite and the entry pass work, without a live WhatsApp | | | |
| MT6 | Approver opens each doctor | APM opens. The visit history is there. The service history shows expenses already done, and expenses still planned, separately | | | |

Meeting Id: _______________ Next approver: _______________ Doctor: _______________

## A2. Send a request — not only a meeting

The approver has to see the doctor, and what was done for them, on the request itself.

| # | Step | Pass if | CS | Zeta (Thu 5) | Evidence |
|---|---|---|---|---|---|
| RQ1 | Create a request | A service request is created for the test doctor. It is not a meeting | | | |
| RQ2 | Send it for approval | It sits with the approver | | | |
| RQ3 | Approver opens that doctor | The doctor is named on the request | | | |
| RQ4 | APM | APM opens for that doctor from the request | | | |
| RQ5 | History of visits | Past visits for that doctor are listed | | | |
| RQ6 | History of services | Expenses and services already done are listed | | | |
| RQ7 | Still planned | Expenses or services still planned are listed, separate from what is already done | | | |

Request Id: _______________ Doctor: _______________ Approver: _______________

## B. See KAM

| # | Step | Pass if | CS | Zeta (Thu 5) | Evidence |
|---|---|---|---|---|---|
| K1 | KAM plan | The metric or the list loads | | | |
| K2 | Stakeholder coverage | Loads | | | |
| K3 | Objectives achieved | Loads | | | |
| K4 | Upcoming visits | Loads | | | |

## C. Ask Field AI

| # | Step | Pass if | CS | Zeta (Thu 5) | Evidence |
|---|---|---|---|---|---|
| AI1 | One question on Home or the planner | It answers, or the error is written down | | | |

## Day pass criteria

The meeting and the request each sit with the approver. On the request, the approver sees that doctor’s APM, visit history, and service history — what was already done, and what is still planned. KAM loads. Field AI answers or the error is logged.

## Log

- Tester (CS): _______________ Date: 4 Nov 2026  
- Meetings: Pass / Fail / Blocked  
- Requests: Pass / Fail / Blocked  
- KAM: Pass / Fail / Blocked  
- Field AI: Pass / Fail / Blocked  
