# Food and Beverage Distribution Management Plan

**Customer:** Everbrook — FMCG owner of **VAMOS BY Mahou**  
**Region:** Egypt (factory: 10th of Ramadan) → Middle East expansion  
**Status:** Planning package — ready to copy into a new Salesforce org project

---

## Start here (developer)

| Order | Document | Purpose |
|-------|----------|---------|
| 1 | [DEVELOPER_QUICKSTART.md](./DEVELOPER_QUICKSTART.md) | **1-hour MVP** deploy sequence |
| 2 | [ARCHITECTURE.md](./ARCHITECTURE.md) | Three modules, security, data flow |
| 3 | [DATA_MODEL.md](./DATA_MODEL.md) | Objects, fields, relationships |
| 4 | [KPI_SCORING_MODEL.md](./KPI_SCORING_MODEL.md) | 70/30 performance formula |
| 5 | [BRD.md](./BRD.md) | All implementations IMP-FB-001–016 |

---

## Three application modules

| Module | Doc | Platform |
|--------|-----|----------|
| **1 — Field Rep View** | [VF_FIELD_SALES_SITE_REQUIREMENTS.md](./VF_FIELD_SALES_SITE_REQUIREMENTS.md) | VF public site (Contact login, Arabic default) |
| **2 — Backoffice View** | [BACKOFFICE_REQUIREMENTS.md](./BACKOFFICE_REQUIREMENTS.md) | Lightning app (Everbrook Users) |
| **3 — Distributor View** | [DISTRIBUTOR_PORTAL_REQUIREMENTS.md](./DISTRIBUTOR_PORTAL_REQUIREMENTS.md) | Lightning portal (Juhayna, etc.) |

---

## Business context

- **VAMOS BY Mahou** — 4 SKUs with variations (beverage cans)
- **Distribution:** Migrating from **Juhayna** toward owned / multiple / sole private distribution
- **Field reps** are **Contact** records — may work for Vamos distribution, Juhayna, or any distributor (not Everbrook employees)
- **Arabic** is the primary field language; English secondary
- **Stakeholders:** Mahmoud Serag (IT Application), Ibrahim Othaman (IT Infrastructure), Basheer

---

## Folder layout

```
Food_and_Beverage_Distribution_Management_Plan/
├── README.md                          ← you are here
├── DEVELOPER_QUICKSTART.md             ← MVP in ~1 hour
├── BRD.md
├── DATA_MODEL.md
├── ARCHITECTURE.md
├── KPI_SCORING_MODEL.md
├── general-rules.md
├── VF_FIELD_SALES_SITE_REQUIREMENTS.md
├── BACKOFFICE_REQUIREMENTS.md
├── DISTRIBUTOR_PORTAL_REQUIREMENTS.md
├── SALESBUZZ_FEATURE_MAPPING.md
├── module-configs/                    ← YAML deploy configs
├── mvp-stubs/                         ← package.xml, seed script, rename map
├── wireframes-and-references/         ← VAMOS slides + KPI diagram
└── Components from another org that can be usefull/
    ├── README.md
    ├── field-rep-home/
    ├── field-planner/
    ├── management-fleet-tracking/
    ├── management-kpi-dashboard/
    ├── map-stack/
    ├── public-vf-site-pattern/
    ├── accounts-tab/
    └── visit-management/
```

---

## Copy to new org

```bash
# 1. Copy this entire folder into your new SFDX project
cp -R "Plan/Food_and_Beverage_Distribution_Management_Plan" /path/to/everbrook-vamos/

# 2. Follow DEVELOPER_QUICKSTART.md step by step
```

---

## Related pharma source org

Reference components were copied from the **Pharmaceuticals** Salesforce project (`force-app/main/default/`). See each `SOURCE_MANIFEST.md` under `Components from another org that can be usefull/` for original paths and adaptation notes.
