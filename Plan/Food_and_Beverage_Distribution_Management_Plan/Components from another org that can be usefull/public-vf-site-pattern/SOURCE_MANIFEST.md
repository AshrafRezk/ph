# SOURCE_MANIFEST — public-vf-site-pattern

## Purpose
Mobile-first Visualforce guest site pattern: no header, PWA meta, glass UI.

## Original pharma paths

| File | Source |
|------|--------|
| pages/ProductSurvey.page | `force-app/main/default/pages/ProductSurvey.page` |
| pages/VisitCallReport.page | `force-app/main/default/pages/VisitCallReport.page` |
| classes/ProductSurveyController.cls | `force-app/main/default/classes/ProductSurveyController.cls` |
| sites/Product_Survey.site-meta.xml | `force-app/main/default/sites/` |

## Everbrook adaptations

1. Clone ProductSurvey.page CSS/shell → FieldSalesLogin.page, FieldSalesHome.page
2. Replace ProductSurveyController with FbFieldSalesController:
   - Contact username/password validation
   - Session token in ViewState
   - Arabic/English label switching
3. New site: `Field_Sales` url prefix `fieldsales`
4. Guest permission set for Visit, Order, Location snapshot CRUD
5. VisitCallReport.page — reference for mobile form layout patterns

## Security notes
- `without sharing` + rep-scoped queries only
- Store password hash on Contact, never plain text
