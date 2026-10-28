# Request to Zeta — post 21 Oct 2026 dry run

**From:** Cloudastick  
**To:** Zeta Pharma (SFE, Commercial, Training)  
**Re:** Files and decisions needed before Cairo rep training and incentive go-live  
**Date:** 22 October 2026

Please reply on each numbered item. Items marked **URGENT** block training or sales go-live.

## Files (URGENT)

1. **Sales data after June 2026** — fresh distributor and any Zeta Direct files, same column layout as the last accepted load (or a short mapping note if the layout changed).
2. **Visits and TOT historical data** — at least 1–3 months before Cairo rep training. Send **Diabetes** and **Neuroscience** as separate files. Mendix TOTs are not ready; use Excel.
3. **Latest KPIs PPT** — working-days quota, double-visit call rate (single vs double), which KPIs are monthly vs quarterly, and any line-specific targets.
4. **Promo Grid numbers** — fill [Zeta_Promo_Grid_Template.xlsx](Zeta_Promo_Grid_Template.xlsx) (one sheet set per line). Do not invent weights; Brand / BU owners fill them.
5. **HCO / HCP target lists** for the wipe-and-reload. Confirm pharmacies stay; confirm whether CRM pharmacy accounts are ignored.

## Decisions

6. **Earliest Cairo reps training date** — confirm so Cloudastick can cut scope for “before training.”
7. **CRM Pharmacies Data** — ignore and keep out of the field target, or load? Default assumption: ignore unless you say otherwise.
8. **Doaa vs Odoo** — is Mendix ↔ Odoo enough, or must Doaa also integrate into Salesforce?
9. **Group Brand Leads** — name the Group Brand Lead for each Brand Manager who currently has no manager (CHC, GIT I, GIT III, Derma, CNS Brand Managers).
10. **Product mirrors** — confirm CHC details → CHC_Sales, GIT details → GIT-SALES, and CVM lines also see the CHC_Sales set; confirm the real detail count (room said “100”).
11. **Visita** — if Visita is a third validation source beyond Google Places and OpenStreetMap, send the file or API credentials before the retro-validation batch runs.
12. **One labeled example** per pharmacy type, subtype, chain, and tender (government hospital) account — required before achievement pricing goes live.

## Cloudastick is sending you

| Deliverable | Path |
|---|---|
| Validation checklist (dry-run failures included) | `Zeta_DryRun_Validation_Checklist.xlsx` |
| Promo Grid template | `Zeta_Promo_Grid_Template.xlsx` |
| SFE bug / issue log | `Zeta_SFE_Issue_Log.xlsx` |
| This request | `Zeta_Data_And_Decisions_Request.md` |

## Already agreed in the room

- Mendix owns TOT **status** changes.
- Sales and incentive KPIs are the primary motivation; company OKRs sit as org-level targets on the same cascade as planner rules.
- Account merge on create is not permitted for the rep; only SFE approves merge. DM can report duplicates.
- Out-of-target visits count only after the rep’s DM marks the visit Valid.

Please acknowledge receipt and attach the URGENT files as soon as they are ready.
