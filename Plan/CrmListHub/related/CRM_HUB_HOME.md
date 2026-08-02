# CRM Hub Home — org prerequisites

## Field History (Contact info improved)

The Home metric **Contact info improved** counts blank→value Field History rows on Contact (and Lead when available) for:

- `Email`
- `Phone`
- `MobilePhone`

**Enable in Setup** (if not already on):

1. Setup → Object Manager → **Contact** → Fields & Relationships → Set History Tracking  
2. Enable history for **Email**, **Phone**, and **MobilePhone**  
3. Optionally repeat for **Lead**

If history is not available, Home still loads and returns `historyAvailable: false` with `contactImproved: 0` (no silent proxy counts).

## Week definition

Calendar week **Sunday → Saturday** (includes weekends). Working days at Cloudastick are typically Sun–Thu; the Home range still uses the full calendar week.

## Access

Assign permission set **CRM Hub Home** (`CRM_Hub_Home`) for Apex class access to `CrmHubHomeController` / `CrmHubHomeStatsService`. Users who already have **CRM Hub List View** should also get `CRM_Hub_Home` until those class accesses are merged into the main hub permission set in a later sync.
