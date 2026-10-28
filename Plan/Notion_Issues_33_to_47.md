# Notion Issues Reports — rows 33–47 to add

Status for all: **Reported** · Issuer: **Ahmed Abdallah (via chat)** · Reported Date: **2026-10-24**

Add these in the Issues Reports database when signed in. Ref # should continue from 33.

| Ref # | Issue | Priority | Module | Description |
|------:|-------|----------|--------|-------------|
| 33 | Service request module — BRD workflow + separate module | High | Service Requests | Write detailed workflow into BRD (actors, statuses, routing by department/amount, 10% re-approval). Build as separate module for managers (not only from visit). BRD 5.4.5 partly covers Marketing/Medical; visit-raised path only in meeting minutes. Open: Sales catalogue, L&D approvers, exactly-10%. |
| 34 | Sales targets per rep × item × month (qty and value) | Critical | Sales | Related to #29. Load Original + Buffer sheets from ZETA TOTAL TARGET 2026. Grain: position × item × month. Achievement vs engine output. |
| 35 | Product settings — items, prices, distributor mapping | High | Sales / Products | Product master (186) with public price; price history in Product_Monthly_Price__c; 859 distributor item codes editable in Admin Console. |
| 36 | KPI metrics — add new metrics and calculation settings | High | KPI | Related to #15. Recipe builder: numerator/denominator sources, period, scope, live preview; metric engine. |
| 37 | Reports and dashboards functionality | High | Reports | Related to #5. Sales by line/brand/item/position/brick; achievement; bulk/chain shares; KPI/coverage. Reports Hub. |
| 38 | Confirm understanding of distributor sheet types and sub-sheets | Critical | Sales | Sign-off on data dictionary (EgyDrug 8 sheets, IBNSINA, POS, Sofico, Elezaby, EPDA, targets, reference). |
| 39 | Sales engine — product mapping | Critical | Sales Engine | Distributor item code → Zeta code. |
| 40 | Sales engine — customer type mapping | Critical | Sales Engine | Each distributor's types → MainType / SubType. |
| 41 | Sales engine — unified customer code across distributors | Critical | Sales Engine | One customer master + crosswalk from every distributor customer code. |
| 42 | Sales engine — allocation to 702 bricks → 148 → medical rep | Critical | Sales Engine | Brick crosswalk + organogram per line. |
| 43 | Sales engine — chain pharmacy distribution rules | Critical | Sales Engine | Fixed yearly percentages per brick per line (except Ezzaby sales-out). |
| 44 | Sales engine — bulk sales per item, customer, customer type | Critical | Sales Engine | Identify and flag bulk lines. |
| 45 | Sales engine — bulk customer definition | Critical | Sales Engine | Confirm: Stores + subagents + retail above ceiling (vs SOP wording). |
| 46 | Sales engine — bulk sales allocation | Critical | Sales Engine | Variable monthly percentages from selected accounts' contribution. |
| 47 | PWA call reports and offline actions never reach Salesforce | Critical | PWA / Visits | Found in review. SAVE_CALL_REPORT and other actions queued to planner outbox which rejects them. Fix outbox handlers; re-queue dead actions. |

Voice-note items (48+) will be appended after Ashraf pastes the summary.
