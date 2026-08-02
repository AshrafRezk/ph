# Offline Salesforce Runtime (OSR) Architecture

## Goal

A Capacitor-based client that clones Salesforce mobile UX offline: apps, tabs, Lightning pages, layouts, validation rules, files, and LWCs — syncing via a custom **Sync Pack** with **zero Briefcase / Mobile Offline SKU** dependency.

## Stack

| Layer | Package / tech |
|-------|----------------|
| Shell | `@osr/shell` — Capacitor + Vite + TypeScript + Lit |
| DB | `@osr/db` — SQLite (Capacitor Community) with web jeep-sqlite fallback |
| Sync | `@osr/sync` — pull/push engine + OAuth client helpers |
| UI | `@osr/ui-runtime` — tabs, FlexiPage, layout forms, LWC host |
| Validation | `@osr/validation` — formula subset + VR engine |
| Salesforce | `salesforce/sync-pack` — Apex REST APIs + CMDT profiles |

## Data flow

1. User authenticates (OAuth PKCE) → tokens in Secure Storage.
2. Client calls `/services/apexrest/osr/v1/profile` for sync profile.
3. Pull channels: metadata → records (cursor) → files → LWC bundles.
4. UI reads SQLite local-first; writes go to `outbox`.
5. On reconnect, outbox FIFO push to `/osr/v1/outbox`; conflicts → `conflicts` table.

## LWC tiers

- **A** — LDS-style local wire adapters only
- **B** — Allowlisted named Apex actions as outbox ops
- **C (Pharma Field — current)** — **Vite/Lit catalog**: each Field app LWC maps to an offline Vite component (`mode: 'vite'` in the fidelity registry). Same UI online/offline; data from SQLite / `apex_payload_cache`, with live Apex refresh when online.
- **C-experimental** — Local iframe + `@lwc/engine-dom` + `@osr/bridge` (not the Field default).

### Tier C — Vite catalog (Pharma Field)

1. FlexiPage / tab `c/*` slots resolve via [`fidelity-registry.ts`](packages/ui-runtime/src/fidelity-registry.ts) → shell Lit widgets under `apps/shell/src/ui/widgets/`.
2. Catalog covers Home, Planner, Visit Call (+ children), Accounts, CLM hub/player, Time Off, Account record panels, Coaching event panels.
3. **Standard object tabs** use CrmListHub-inspired chrome ([`Plan/CrmListHub/`](../Plan/CrmListHub/)): org list views, in-tab text search, global search, list/cards/calendar/kanban, record modal.
4. Iframe engine packages (`@osr/bridge`, `@osr/platform`, `@osr/lwc-engine`, `@osr/lwc-compile`) remain for experiments; Field UI prefers Vite catalog.

---

## Formula matrix

See `packages/validation/src/formula-matrix.ts` for supported / unsupported functions.

---

## Lightning record page + object tab parity

Hybrid model: Sync Pack digests org metadata when online; SQLite is the offline source of truth. Profile scoping stays CMDT (`Offline_Sync_Profile`).

### Layout priority

1. Dynamic Forms field instances on the FlexiPage (when present)
2. Real Layout metadata (Tooling) + record-type assignment
3. Describe-derived stub layout (`buildSimpleLayout`)

### FormFactor

| Viewport | FormFactor | UI |
|----------|------------|-----|
| &lt; 768px | `Small` | Stacked regions, cards default on object tabs |
| 768–1023px | `Medium` | Main + collapsible sidebar |
| ≥ 1024px | `Large` | Main + sidebar grid; table + inline edit |

When FlexiPage JSON includes `templates` / per-region `formFactor`, the shell selects the matching region set; otherwise all regions render with CSS responsive layout.

### Metadata contracts (SQLite JSON)

#### `meta_flexipages.page_json`

```json
{
  "type": "RecordPage",
  "sobjectType": "Account",
  "formFactor": "Large",
  "templates": [{ "name": "default", "formFactor": "Large", "regions": ["main", "sidebar"] }],
  "regions": [{
    "name": "main",
    "formFactor": null,
    "components": [{
      "type": "flexipage:fieldSection",
      "attributes": { "label": "Details" },
      "visibilityRule": { "criteria": "ISPICKVAL(Industry, \"Healthcare\")", "booleanFilter": null },
      "fieldInstances": [
        { "fieldApiName": "Name", "uiBehavior": "Required" },
        { "fieldApiName": "Industry", "uiBehavior": "Edit" }
      ]
    }]
  }],
  "source": "tooling"
}
```

#### `meta_layouts.layout_json`

```json
{
  "source": "tooling|stub",
  "sections": [{
    "label": "Information",
    "columns": [[{ "field": "Name", "behavior": "Required" }, { "field": "Phone", "behavior": "Edit" }]]
  }],
  "relatedLists": [{
    "relatedList": "Contacts",
    "label": "Contacts",
    "objectApi": "Contact",
    "lookupField": "AccountId",
    "fields": ["Name", "Title", "Phone"]
  }],
  "highlightsFields": ["Name", "Industry", "Phone"],
  "platformActionList": ["Edit", "Delete", "NewContact"],
  "pathField": "Status__c",
  "pathValues": ["Planned", "In Progress", "Completed"]
}
```

#### `meta_listviews.listview_json`

```json
{
  "id": "00B…",
  "developerName": "AllAccounts",
  "label": "All Accounts",
  "soqlCompatible": true,
  "columns": [
    { "fieldOrColumn": "Name", "label": "Account Name", "type": "string", "sortable": true },
    { "fieldOrColumn": "Industry", "label": "Industry", "type": "picklist", "sortable": true }
  ],
  "filters": [
    { "field": "Industry", "operation": "equals", "value": "Healthcare" }
  ],
  "booleanFilter": "1",
  "filtersSupported": true,
  "displayType": "List",
  "kanbanGroupField": null,
  "recordIds": []
}
```

Unsupported filter ops → `filtersSupported: false`; shell shows all synced rows + warning badge.

#### `meta_validation_rules`

Unchanged row shape; Sync Pack fills via batched Tooling `ValidationRule` query.

#### `meta_actions`

```json
{
  "type": "QuickAction",
  "actionType": "Create",
  "targetObject": "Contact",
  "offlineSafe": true,
  "fieldDefaults": {},
  "apexName": null
}
```

Offline-safe kinds: `Create`, `Update`, `Delete`, `Navigate`, allowlisted Apex. Others render disabled with tooltip.

#### `meta_compact_layouts`

```json
{ "fields": ["Name", "Industry", "Phone", "OwnerId"] }
```

Used by `force:highlightsPanel` when present.

### Supported list-filter ops (client)

`equals`, `notEquals`, `contains`, `notContains`, `startsWith`, `gt`, `gte`, `lt`, `lte`, `isNull`, `isNotNull`

Boolean filter: `1 AND 2`, `1 OR 2` (digit references only). Unsupported → degrade.

### Supported offline actions

| Kind | Behavior |
|------|----------|
| Create / New* | Open new local record modal |
| Edit / Update | Toggle edit mode |
| Delete | Soft-delete + outbox |
| Navigate / View | Open related record / list |
| Apex (allowlisted) | Enqueue outbox Apex op |
| Other | Disabled + “Unavailable offline” |

### Component visibility

`visibilityRule.criteria` evaluated with `@osr/validation` formula engine against current record (+ limited `$User` stubs). Fail-open on unsupported formulas (show component + console warn).

### Parity policy / non-goals

Faithful **structure** + supported offline subset. Tier C iframe engine runs compiled / engine-ready `c/*` with SQLite-backed shims. Not in scope: Aura/VF runtime, iframing live `*.salesforce.com`, full proprietary `lightning-*` catalog, live SOQL for every list view.

### Phase checklist

| Phase | Outcome |
|-------|---------|
| 0 | Contracts + mocks + this doc |
| 1 | Sync Pack digestion (layouts, VRs, list columns/filters, Flexi DF, related lists, actions) |
| 2 | Record page typed fields / DF / related lists / actions / VR errors |
| 3 | Object tabs columns / filters / kanban / inline edit |
| 4 | FormFactor templates, visibility, path/compact polish |
