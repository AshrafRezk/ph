# CrmListHub (inspiration export)

Portable snapshot of the **CRM Hub List** experience from `cloudastickkpi`, for reuse as a reference in another project.

Not a drop-in deploy package — org-specific fields, remote sites, custom objects, and page extensions may still be required.

## Layout

```
CrmListHub/
├── pages/              # CrmHubList Visualforce page
├── classes/            # List controller + list/record util Apex
├── staticresources/    # Client JS for list engine, page UI, modal, lookup, etc.
├── components/         # CrmHubCleanLists
├── permissionsets/     # CRM_Hub_List_View
└── related/            # Page extensions (Home, Voice, Sonic) — optional context
```

## Core stack (start here)

| Layer | Files | Role |
|-------|--------|------|
| Page shell | `pages/CrmHubList.page` | VF host, remoting stubs, assets |
| Controller | `classes/CrmHubListController.cls` | List views, search, hub access, remoting |
| List SOQL / prefs | `HubListViewUtil`, `HubListViewPrefUtil` | ListView options + pin/favorite |
| Record modal | `HubRecordModalUtil`, `HubRecordActionsUtil`, `HubRecordCompletenessScore` | Modal data + actions |
| Client JS | `CrmHubListEngine`, `CrmHubListPage` | Cards/list, sort, pagination, inline edit |
| Modal / lookup UI | `CrmHubRecordModal`, `CrmHubLookup` | Record modal + lookups |
| Chrome | `CrmHubNotifications`, `CrmHubCommandCenter` | Notifications + command center |

## Page extensions (under `related/`)

`CrmHubList.page` also uses:

- `CloudastickSonicController`
- `CrmHubVoiceSearchController`
- `CrmHubHomeController`

Those (plus voice/home/sonic assets) live in `related/` so you can see the full surface without treating them as required for a list-only port.

## Suggested reading order

1. `pages/CrmHubList.page` — wiring and remoting catalog  
2. `staticresources/CrmHubListPage.resource` — UI / UX patterns  
3. `staticresources/CrmHubListEngine.resource` — list data + interactions  
4. `classes/CrmHubListController.cls` — server contract  
5. `classes/HubListViewUtil.cls` — ListView / SOQL merge patterns  
6. `staticresources/CrmHubRecordModal.resource` + `HubRecordModalUtil.cls` — record detail flow  

## Notes

- Static resources are plain JS (`contentType: application/javascript`).
- Controller is `without sharing` and gates tabs via `User.Hub_Access__c` (Full vs Partial).
- Tests are included next to production classes for behavior examples.
- See `FILE_LIST.txt` for the full file inventory.
