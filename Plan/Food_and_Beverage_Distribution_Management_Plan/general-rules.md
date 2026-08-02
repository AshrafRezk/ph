# General Rules — Everbrook / VAMOS Implementations

Adapted from Pharmaceuticals org rules. Apply to all Everbrook Salesforce work.

---

## 1. UI / UX

- **Field rep UI:** Mobile-first Visualforce public site; min tap target 48px; test 320px viewport.
- **Backoffice / Distributor:** Lightning + SLDS; desktop and tablet.
- **Arabic:** Default for field rep site; full RTL when Arabic selected; all strings via Custom Labels (`fb_*`).
- Prefer LWC for Lightning apps; VF + static resources for guest field site maps.

---

## 2. Data model

- Use **standard objects** where possible: Account, Contact, Case, Product2, Pricebook2.
- **Custom objects** for van sales domain: Visit, Route, Order, Van, Targets, Distributor expenses.
- **Field reps = Contact** records (no User license for Module 1).
- **Distributor scoping:** Every transactional record carries `Distributor__c` lookup for sharing.

---

## 3. Branding

- Ship **VAMOS** / **Everbrook** branding only — no third-party SFA product names in UI metadata.
- Planning docs may reference SalesBuzz as industry context; do not deploy "SalesBuzz" labels.

---

## 4. Engineering discipline

- Simplest solution that meets requirements.
- Configuration over code when sufficient.
- Guest site Apex: `without sharing` + explicit rep-scoped SOQL from session token only.
- Hash passwords on Contact — never store plain text.

---

## 5. Security

- Guest profile: minimum CRUD on objects needed for field site.
- Distributor portal: sharing by `Distributor__c` — no cross-distributor leakage.
- Everbrook backoffice: view all distributors.
- Session tokens for VF rep login — no credentials in cookies.

---

## 6. Maps

- **OpenStreetMap** tiles + **Leaflet** + **OSRM** routing (same stack as pharma reference).
- CSP trusted sites required before deploy.

---

## 7. Documentation

- Each implementation maps to BRD ID (IMP-FB-xxx).
- Adaptation notes in `SOURCE_MANIFEST.md` when copying pharma components.
