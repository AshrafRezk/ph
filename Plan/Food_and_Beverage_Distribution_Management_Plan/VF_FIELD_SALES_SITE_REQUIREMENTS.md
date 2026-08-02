# VF Field Sales Site Requirements — Module 1

**Platform:** Visualforce public site (Guest User + Contact session)  
**Audience:** Field reps / van drivers (Contact records)  
**Language:** Arabic default, English toggle, RTL support

---

## Site configuration

| Setting | Value |
|---------|-------|
| Site type | Visualforce |
| URL prefix | `fieldsales` (suggested) |
| Index page | `FieldSalesLogin` |
| Guest profile | `Field Sales Guest Profile` |
| Permission set | `Field_Sales_Guest` |

**Reference:** `Components from another org that can be usefull/public-vf-site-pattern/`

---

## Page map

| Page | Sub-module | Purpose |
|------|------------|---------|
| `FieldSalesLogin` | — | Username/password + language selector |
| `FieldSalesHome` | Targets | KPI rings + today's summary |
| `FieldSalesRoute` | Route Viewing | Read-only route map |
| `FieldSalesPlanner` | Planner | Edit route |
| `FieldSalesVisit` | Visit Management | Check-in/out |
| `FieldSalesOrder` | Order Management | Sell products |
| `FieldSalesReturn` | Order Management | Return products |
| `FieldSalesCase` | Case Logging | Log issue |
| `FieldSalesVanStock` | Order Management | Van inventory |
| `FieldSalesDeviation` | GPS Tracking | Off-route reason |
| `FieldSalesProfile` | — | Rep info, logout |

---

## Authentication (R-LOGIN-*)

| ID | Requirement |
|----|-------------|
| R-LOGIN-01 | Mobile login screen; min tap target 48px; Arabic default |
| R-LOGIN-02 | Validate `Mobile_Username__c` + `Mobile_Password_Hash__c` where `Is_Mobile_Active__c = true` |
| R-LOGIN-03 | On success load distributor, van, today's route, targets, open visits |
| R-LOGIN-04 | Generic "Invalid credentials" message |
| R-LOGIN-05 | All pages require valid session token; redirect if expired |
| R-LOGIN-06 | Session timeout 8 hours idle |
| R-LOGIN-07 | Lockout 5 failed attempts / 15 min cooldown |

---

## i18n (R-I18N-*)

| ID | Requirement |
|----|-------------|
| R-I18N-01 | Default UI language = Arabic on first login |
| R-I18N-02 | Language toggle on login and profile; save to `Preferred_Language__c` |
| R-I18N-03 | RTL layout (`dir="rtl"`) when Arabic |
| R-I18N-04 | All strings via Custom Labels `fb_*` |
| R-I18N-05 | Arabic picklist values for reasons and outcomes |
| R-I18N-06 | Locale-aware date/number formatting |
| R-I18N-07 | Order receipt printable in Arabic |

---

## Targets (R-TARGET-*)

| ID | Requirement |
|----|-------------|
| R-TARGET-01 | Home shows overall, sales (70%), coverage (30%) scores |
| R-TARGET-02 | SKU breakdown for 4 VAMOS products |
| R-TARGET-03 | Color-coded progress rings |
| R-TARGET-04 | Per KPI_SCORING_MODEL.md formulas |

---

## Home (R-HOME-*)

| ID | Requirement |
|----|-------------|
| R-HOME-01 | Route name, stop count, completed vs remaining |
| R-HOME-02 | Today's sales and return totals |
| R-HOME-03 | Van stock warnings |
| R-HOME-04 | CTA "Start Route" → Route page |

---

## Route viewing (R-ROUTE-VIEW-*)

| ID | Requirement |
|----|-------------|
| R-ROUTE-VIEW-01 | Read-only OpenStreetMap + Leaflet |
| R-ROUTE-VIEW-02 | Stop list with sequence, outlet, status |
| R-ROUTE-VIEW-03 | OSRM distance/ETA to next stop |

---

## Planner (R-ROUTE-*)

| ID | Requirement |
|----|-------------|
| R-ROUTE-01 | Editable map with today's stops |
| R-ROUTE-02 | OSRM optimized polyline |
| R-ROUTE-03 | Add outlet from territory search |
| R-ROUTE-04 | Remove unvisited stop with reason |
| R-ROUTE-05 | Reorder stops or Optimize button |
| R-ROUTE-06 | Deviation: >500m off route >5 min → mandatory reason |
| R-ROUTE-07 | GPS publish to `Rep_Location_Snapshot__c` every 60s |

---

## Visit (R-VISIT-*)

| ID | Requirement |
|----|-------------|
| R-VISIT-01 | Check-in sets `Actual_Start__c` + GPS |
| R-VISIT-02 | Outcome: Sale, No Sale, Return Only, Skipped |
| R-VISIT-03 | No Sale / Skipped → mandatory `No_Sale_Reason__c` |
| R-VISIT-04 | Sale → Order page; Return Only → Return page |

---

## Order (R-ORDER-*)

| ID | Requirement |
|----|-------------|
| R-ORDER-01 | 4 VAMOS SKUs from van load + price book |
| R-ORDER-02 | Line items: qty, price, discount, total |
| R-ORDER-03 | Cannot exceed `Van_Inventory__c.Quantity__c` |
| R-ORDER-04 | Credit hold blocks order |
| R-ORDER-05 | Create `Sales_Order__c` + lines; decrement inventory |
| R-ORDER-06 | Mobile receipt in active language |

---

## Return (R-RETURN-*)

| ID | Requirement |
|----|-------------|
| R-RETURN-01 | Select products and qty |
| R-RETURN-02 | Mandatory reason per line |
| R-RETURN-03 | Update inventory or write-off |
| R-RETURN-04 | Link to visit and optional order |

---

## Van stock (R-VAN-*)

| ID | Requirement |
|----|-------------|
| R-VAN-01 | Current stock by product |
| R-VAN-02 | Morning load vs current |
| R-VAN-03 | End-of-day summary |

---

## Case logging (R-CASE-*)

| ID | Requirement |
|----|-------------|
| R-CASE-01 | Create from visit or global action |
| R-CASE-02 | Types: Delivery, Quality, Equipment, Complaint, Credit, Other |
| R-CASE-03 | Auto-populate Account, Contact, Visit, Distributor |
| R-CASE-04 | Optional photo attachment |
| R-CASE-05 | Visible to Everbrook + owning distributor |
| R-CASE-06 | Arabic subject/description supported |

---

## Non-functional (R-NFR-*)

| ID | Requirement |
|----|-------------|
| R-NFR-01 | iOS Safari + Android Chrome; 320–428px |
| R-NFR-02 | Page load < 3s on 4G |
| R-NFR-03 | Guest profile minimal CRUD |
| R-NFR-04 | Apex `without sharing` + rep-scoped SOQL |
| R-NFR-05 | Arabic + English labels |
| R-NFR-06 | Offline = Phase 2 |

---

## Guest permission set (minimum)

| Object | Create | Read | Update |
|--------|--------|------|--------|
| Contact | — | Own session | Last login |
| Visit__c | Yes | Own | Yes |
| Sales_Order__c | Yes | Own | — |
| Sales_Order_Line__c | Yes | Own | — |
| Rep_Location_Snapshot__c | Yes | Own | Yes |
| Daily_Route_Stop__c | — | Own | Yes |
| Case | Yes | Own | — |
| Route_Deviation__c | Yes | Own | — |

---

## Mobile UI pattern

Copy from `ProductSurvey.page`:
- `showHeader="false"`, HTML5 doctype
- `viewport-fit=cover`, PWA meta tags
- Glass-morphism CSS, 48px tap targets
- Dark/light mode via `prefers-color-scheme`
