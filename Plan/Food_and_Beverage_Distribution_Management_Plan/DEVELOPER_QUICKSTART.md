# Developer Quickstart — Everbrook / VAMOS MVP (~1 hour)

Follow this sequence in a **new Salesforce org**. Each step has a time budget. Skip nothing in the MVP column.

---

## Prerequisites (5 min)

- Salesforce CLI (`sf`) authenticated to target org
- API version 59+ recommended
- Enable: **My Domain**, **Lightning Experience**, **Digital Experiences** (optional for distributor portal later)

---

## Step 1 — Data model (15 min)

Deploy custom objects and fields from [DATA_MODEL.md](./DATA_MODEL.md).

**MVP minimum objects:**

| Object | Priority |
|--------|----------|
| `Van__c` | Required |
| `Van_Inventory__c` | Required |
| `Daily_Route__c` | Required |
| `Daily_Route_Stop__c` | Required |
| `Visit__c` | Required |
| `Sales_Order__c` + `Sales_Order_Line__c` | Required |
| `Rep_Location_Snapshot__c` | Required (copy from `Components.../management-fleet-tracking/objects/`) |
| `Rep_Target__c` | Required |
| `Route_Deviation__c` | MVP stub |
| `Distributor_Expense__c` | Phase 2 |

**Contact fields (create on Contact):**

- `Mobile_Username__c` (Text, External ID, Unique)
- `Mobile_Password_Hash__c` (Text 255)
- `Is_Mobile_Active__c` (Checkbox)
- `Employer_Distributor__c` (Lookup Account)
- `Assigned_Van__c` (Lookup Van__c)
- `Preferred_Language__c` (Picklist: Arabic, English — default Arabic)

**Account record types:** `Distributor`, `Outlet`

**Products:** Create 4 VAMOS SKUs in Product2 (see DATA_MODEL.md)

**Seed script:** Run `mvp-stubs/scripts/seed-everbrook-demo.apex` after objects exist.

---

## Step 2 — Map stack + CSP (5 min)

Copy from `Components from another org that can be usefull/map-stack/`:

1. Deploy `plannerMapUtils`, `plannerMapPins`, `plannerRouteUtils` LWCs
2. Deploy CSP trusted sites: OpenStreetMap tiles + OSRM routing
3. Upload **leaflet** static resource (copy from pharma org `staticresources/leaflet` or CDN bundle)

---

## Step 3 — Backoffice Lightning MVP (15 min)

Copy and adapt (see `mvp-stubs/RENAME_MAP.md`):

| Source folder | Deploy as |
|---------------|-----------|
| `management-fleet-tracking/` | Fleet map tab — change `User__c` → `Contact__c` on snapshot |
| `management-kpi-dashboard/` | Management home — adapt KPIs to van sales |
| `field-rep-home/` | Optional internal rep home if using User licenses later |

**Quick adapt checklist:**

1. Rename Apex classes with `Fb` prefix or namespace to avoid collisions
2. Replace `User__c` lookups with `Contact__c` on `Rep_Location_Snapshot__c`
3. Add `Distributor__c` filter to fleet map controller
4. Create Lightning app **Everbrook Management** with tabs: Home, Fleet Tracking

**Package manifest:** `mvp-stubs/manifests/mvp-backoffice-package.xml`

---

## Step 4 — VF Field Sales site MVP (20 min)

Use `public-vf-site-pattern/` as shell:

1. Clone `ProductSurvey.page` → `FieldSalesLogin.page`, `FieldSalesHome.page`
2. Create `FieldSalesController.cls` — Contact username/password validation (see VF requirements R-LOGIN-*)
3. Create Guest Profile + `Field_Sales_Guest` permission set
4. Create Site: URL prefix `fieldsales`, index `FieldSalesLogin`
5. Port map JS from `map-stack/lwc/plannerMapUtils.js` to static resource for VF pages

**MVP pages only:** Login, Home (targets), Route (view), Visit (check-in/out), Order (sell)

**Arabic:** Create Custom Labels prefix `fb_` — minimum 20 labels for login, nav, buttons (see VF requirements R-I18N-*)

---

## Step 5 — KPI scoring (5 min)

Implement formula from [KPI_SCORING_MODEL.md](./KPI_SCORING_MODEL.md):

- 70% sales vs SKU target (capped)
- 30% coverage (active customers + GTM priority list + strike rate)

Add fields on `Rep_Target__c` or formula fields on Contact/report.

---

## Step 6 — Smoke test (5 min)

| Test | Expected |
|------|----------|
| Login as demo rep Contact on VF site | Arabic home loads |
| View today's route on map | OSM tiles + stops |
| Check in to visit, no sale | Reason required |
| Create order for VAMOS SKU | Van inventory decrements |
| Backoffice fleet map | Rep pin visible |
| GPS publish | Snapshot updated |

---

## Post-MVP (do not block hour 1)

- Distributor portal (Module 3)
- Product returns, case logging, deviation detection
- ERP integration
- Full Arabic label set
- Experience Cloud for Juhayna

---

## File reference

| Need | Location |
|------|----------|
| Rename / field mapping | `mvp-stubs/RENAME_MAP.md` |
| Deploy manifests | `mvp-stubs/manifests/` |
| Demo seed | `mvp-stubs/scripts/seed-everbrook-demo.apex` |
| Module YAML | `module-configs/*.yaml` |
| Source LWCs | `Components from another org that can be usefull/` |
