# Client-friendly Notion resolutions

Use **Closed** (not Fixed). Keep language plain for Ahmed / Zeta.

## Close now (work is done)

| Ref | Resolution Description |
|----:|------------------------|
| 1 | EPDA customer sales files import correctly. Re-load October data from Admin Console → Monthly data pack when ready. |
| 2 | POS tender sales files import correctly. Re-load October data from Admin Console → Monthly data pack when ready. |
| 3 | IBNSINA tender files now parse rows (no longer empty). Re-load October data when ready. |
| 4 | IBNSINA customer batches finish instead of staying “processing.” Re-load October data when ready. |
| 5 | You can download the consolidated monthly sales sheet from Admin Console (Export month). Product and revenue columns are included. |
| 6 | Presentations play in Salesforce Lightning and on the offline app (salesforceoffline.com). We verified with Bilastegic flyer 2. Field Co-pilot now shows the CLM Presentations tab. Very large PDF decks may still need Marketing to compress the file. |
| 7 | You can delete sample products from CHC-SALES territory product management again. |
| 8 | Marketing Services appears as a request type on the request form. |
| 9 | Bulk remove works in Manage Products for CHC_Sales. |
| 10 | CHC_Sales product mirror includes the correct CHC lines (not only a partial set). |
| 11 | Filtering Users by Title works as expected (list no longer collapses to the wrong titles). |
| 12 | Business Unit filter shows the organogram BUs: CHC, Cluster, Diabetes, GIT, and Training (no combined labels like CVM-ORTHO-PEDIA). |
| 14 | Hire date, resignation date, and last work day are visible on Users. Existing employee HR dates were loaded where we could match them. |
| 16 | Call rate can be set by territory / line / BU (with org default 12 until you seed specific rules in Admin). |
| 17 | Sales policy settings load without error. |
| 18 | Accounts show class, specialty, plan, and targets again. Specialty values were filled for accounts that had source data. |
| 19 | Planner Rules can target a line and job title together (example: CHC + Medical Rep). |
| 20 | Classification / Promo Grid shows accounts again. |
| 21 | Visit Tabs configuration opens and saves for admins (no permission error). |
| 22 | Coaching templates open with their questions and data (no blank screen when the template is valid). |
| 23 | Call targets use one pro-rated number. Approving time off recalculates the target. Weekends follow Planner Rules (Thursday/Friday by default for Egypt). |
| 24 | IBNSINA pharmacy matching uses the same name engine as account search, plus brick and Egypt map bounds. Use **Re-match unmapped** in Distributors Management when needed. |
| 25 | “Login As” works for Cloudastick admin. Ahmed can be used for go-live checks. |
| 26 | Visit date and time cannot be changed after the visit is submitted or synced. |
| 27 | LMS upload cards are visible again under LMS in Admin Console. |
| 28 | Product activation by date per line works as designed. (Already closed — keep client wording if empty.) |
| 30 | Classification approvals route to the SFE approver on the territory. |
| 47 | Call reports and other offline actions from the phone/PWA now reach Salesforce. Pending actions can be recovered from the offline outbox. |

## Keep In Progress (honest — not finished)

| Ref | Status | Resolution Description |
|----:|--------|------------------------|
| 13 | In Progress | Territory cleanup partly done (Neuroscience products remapped, stale districts retired, Diabetes BMs seated, BU names updated). Still blocked on 9 Neuroscience products and 3 duplicate district names — need a business decision before we can finish. |
| 15 | In Progress | KPI targets can pick a count source. Building custom metric formulas (full recipe builder) is tracked as issue #36. |
| 29 | In Progress | Sales admin screens and digestion tools are live (no longer a stub). Please Login-As Ahmed and confirm you can view/upload sales and see targets. Related: issues #34–46 for the full sales engine. |
| 33 | In Progress | Waiting on a walkthrough/sign-off of the sales sheet dictionary with Ahmed/David before we treat sheet structure as agreed. |

## Leave Reported (future work — do not close)

34–46, 48, 31, 32 — new intake / backlog. No fake Closed status.
