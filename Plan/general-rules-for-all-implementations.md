# General Rules for All Implementations

These rules apply to every feature, enhancement, and fix delivered in the Pharmaceuticals Salesforce org. Review this document before starting design or development work.

---

## 1. UI / UX

- All user interfaces must be **user-friendly**, intuitive, and consistent with Salesforce Lightning Design System (**SLDS**).
- Every UI must work correctly on:
  - **Salesforce Desktop** (Lightning Experience)
  - **Salesforce Mobile** and **Salesforce One** app
- Prefer native Salesforce UI patterns first:
  - Lightning record pages, list views, related lists, standard actions
  - **LWC** components styled with SLDS
  - **Screen Flows** for guided multi-step processes
- If the UI is **too complex** for standard Lightning patterns alone, build a dedicated **HTML / CSS / JS** page and surface it from within the app. That page must:
  - Communicate with Salesforce via **REST APIs** (Apex `@RestResource`, or standard Salesforce REST APIs), **or**
  - Be **hosted inside an LWC** (iframe or embedded markup) so it remains part of the Lightning shell
- Avoid custom styling that breaks SLDS conventions. Mobile layouts must be tested on a phone-sized viewport.

---

## 2. Data Model — Standard vs Custom Objects

- **Default priority: standard Salesforce objects** (Account, Contact, Lead, Opportunity, Case, Task, Event, Product2, etc.) and standard fields wherever they meet the business need.
- **Exception — Platform licenses:** If user profiles are on **Salesforce Platform** licenses (limited standard object access), use a **pragmatic mix** of:
  - Standard objects where license and permissions allow
  - Custom objects where standard objects are unavailable or insufficient
- Document the object choice and license constraint in the BRD section for each implementation.

---

## 3. Branding and Industry Alignment

### No third-party product branding in shipped work

**Never** use non-Salesforce product or vendor names in anything users, admins, or integrators see in the org. This includes UI labels, page titles, tab names, help text, toast messages, permission set descriptions, LWC `description` metadata, and similar user-facing copy.

**Prohibited in shipped metadata and UI** (non-exhaustive): OCE, IQVIA, Veeva, MI (as a product name), and any other competitor or vendor CRM / life-sciences platform branding.

Use **Salesforce-native** or **neutral pharma industry** language instead (e.g. “Setup / Modules”, “Visit”, “CLM Presentation”, “HCP”, “Field Rep Planner”).

Internal planning documents (`Plan/`, wireframes, BRD background) may reference external products for context only. That context must **not** be copied into labels or descriptions deployed to the org.

### Industry patterns (without vendor branding)

- Take into consideration familiar life-sciences workflows: field force activity, call reporting, sample management, targeting, medical inquiry handling, and HCP engagement.
- Align labels, picklist values, and process language with common pharma field-force norms so users find the system intuitive.
- Do **not** replicate proprietary third-party product functionality unless explicitly scoped; use industry patterns as **reference**, not as a product clone.

---

## 4. Engineering Discipline

- **Never over-engineer.** Build the simplest solution that correctly meets the stated requirement.
- Avoid premature abstraction, unnecessary layers, and speculative features not in scope.
- Prefer configuration (Flows, page layouts, permission sets) over code when configuration is sufficient.
- When code is required, keep it focused: one responsibility per class/component, minimal dependencies.

---

## 5. Cross-Cutting Requirements

| Area | Rule |
|------|------|
| **Security** | Enforce sharing, FLS, and CRUD in Apex (`with sharing`, `WITH SECURITY_ENFORCED` in SOQL). |
| **Governor limits** | Bulkify all Apex; avoid SOQL/DML in loops. |
| **Testing** | Apex classes require meaningful test coverage; test happy path and key edge cases. |
| **Documentation** | Each BRD implementation section must link to its wireframe in `wireframes and references/`. |
| **Deployment** | Use manifest-based retrieve/deploy; target org: `pharma-prod`. |

---

## 6. Wireframe Reference Convention

When documenting an implementation in `BRD.md`:

1. Assign a wireframe ID (e.g. `WF-001`).
2. Save the wireframe image or screenshot in `Plan/wireframes and references/`.
3. Link the wireframe from the BRD section using a relative path.

Example:

```markdown
**Wireframe:** [WF-001 — Dashboard](../Plan/wireframes%20and%20references/wireframe-dashboard.png)
```

---

*Last updated: June 2026*
