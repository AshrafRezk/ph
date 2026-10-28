# Organogram retire / merge — blocked on Zeta decisions

From Wave 1B hierarchy work (deploy series including `0Afiv0000005Zy1CAE` / `0Afiv0000005b5NCAQ`).

## Done already
- Remapped **12** NEUROSCIENCE products; deactivated **106** alignments; retired **57** stale districts/positions
- BU renames: Cluster / GIT / Diabetes
- Seated **4** Diabetes Brand Managers (15 BM + 1 GBL total)

## Still blocked — products on `TERR_LINE_NEUROSCIENCE`

Do not guess destinations. NEUROSCIENCE-I/II have no matching families.

| Notes | Product |
|--------|---------|
| Active | ALZAZONEX |
| Active | DOZOVA BRAIN BOOST |
| Active | MINDOLUX CAP |
| + 6 inactive | (still on the line) |

## Still blocked — same-name districts (in current organogram, not stale)

Need Zeta rename or merge decision:

1. CHC DM DELTA (pair)
2. NEUROSCIENCE DM CAIRO (pair)
3. NEUROSCIENCE DM GIZA-UE (pair)

## After decisions

Run `ZetaOrganogramRetireService` in order: **PRODUCTS → ALIGNMENTS → TERRITORIES** (Territory2 cannot mix with other DML in one transaction).

Also open: **16** vacant DM seats (no emails for missing roster); GBL Mohamed Saied skipped (`Division` null).
