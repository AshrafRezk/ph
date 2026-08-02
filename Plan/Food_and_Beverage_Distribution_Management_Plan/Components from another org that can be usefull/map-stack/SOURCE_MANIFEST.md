# SOURCE_MANIFEST — map-stack

## Purpose
Shared map utilities: Leaflet loader, OSM tiles, OSRM routing, route helpers.

## Original pharma paths

| File | Source |
|------|--------|
| lwc/plannerMapUtils | `force-app/main/default/lwc/plannerMapUtils/` |
| lwc/plannerMapPins | `force-app/main/default/lwc/plannerMapPins/` |
| lwc/plannerRouteUtils | `force-app/main/default/lwc/plannerRouteUtils/` |
| cspTrustedSites/* | `force-app/main/default/cspTrustedSites/` |
| remoteSiteSettings/OSRM_Routing | `force-app/main/default/remoteSiteSettings/` |

## Everbrook adaptations

1. Deploy LWCs as-is for Lightning apps
2. For VF site: extract JS into static resources `fbMapUtils.js`, `fbMapPins.js`
3. Deploy CSP trusted sites before any map UI
4. Copy `leaflet` static resource from pharma org (not duplicated here — binary zip)

## Required endpoints
- `https://tile.openstreetmap.org/{z}/{x}/{y}.png`
- `https://router.project-osrm.org`
