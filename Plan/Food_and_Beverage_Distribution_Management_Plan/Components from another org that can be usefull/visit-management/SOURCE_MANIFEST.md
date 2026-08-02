# SOURCE_MANIFEST — visit-management

## Purpose
Visit call reporting UI: check-in, product details, samples, attendees.

## Original pharma paths

| File | Source |
|------|--------|
| lwc/visitCallShell | `force-app/main/default/lwc/visitCallShell/` |
| lwc/visitWorkspace | `force-app/main/default/lwc/visitWorkspace/` |
| classes/VisitCallReportController.cls | `force-app/main/default/classes/VisitCallReportController.cls` |

## Everbrook adaptations

1. Simplify for F&B: check-in/out, outcome, no-sale reason — drop CLM/samples
2. Outcome Sale → navigate to order page
3. Port mobile patterns to VF `FieldSalesVisit.page`
4. VisitCallReport.page (in public-vf-site-pattern) for mobile styling reference

## MVP
Build slim VF visit page rather than deploying full visitCallShell LWC.
