# Pharma Onboarding Workbook — Sheet Fill Guide

**Audience:** Zeta Pharma commercial / SFE / marketing / IT data owners  
**File:** `Pharma_Onboarding_Data_Collection_Template.xlsx`  
**Purpose:** Explain each sheet, how to fill it, what every column means, and how it is used in Salesforce.

---

## How the workbook works (read first)

1. **Blue row under headers** = column dictionary. Do not overwrite it.
2. **Amber rows** = examples only. Replace with your real data (or leave and add real rows below).
3. **Dropdowns** come from sheet `01_Reference_Lists`. Use those values so data loads cleanly.
4. **External IDs** are the join keys across sheets (and into Salesforce). Keep them unique and stable — never reuse or rename after load.
5. **Dates** = `YYYY-MM-DD` (example: `2026-07-01`).
6. **Load order matters:** Users/Territories → Products → Accounts → Alignments/Ratings → PTA → Plan targets → CLM → optional extras.

### What “used on system” means

| Business need | Salesforce objects / features |
|---|---|
| Login & org chart | `User`, manager hierarchy, Profiles / Permission Sets |
| Geo / field structure | `Territory2` hierarchy + user–territory assignment |
| Customer 360 | `Account` (HCP / Pharmacy / HCO record types) |
| Who owns which customer | `Account_Territory_Fields__c` (**ATF**) |
| Potential / classification / KOL | ATF rating fields |
| Product adoption per account | `Account_Territory_Product_Fields__c` (**ATPF**) |
| What products a territory can detail | `Product_Territory_Alignment__c` (**PTA**) |
| Product catalog on call report | `Product2` (Brand / Detail / Sample / Brand Reminder) |
| Monthly visit targets & coverage | `Employee_Time_Card__c` + `Employee_Time_Card_Account_Target__c` |
| Approved content in visit | CLM library + player + slide product/message tracking |
| Samples on visit | `Sample_Inventory__c` (lot / expiry / qty) |
| Map / planner / home KPIs | Same ATF + plan targets + geo on Account |

---

## 00_Instructions

**What it is:** Overview, colour legend, validation rules, sheet index.  
**How to fill:** Read only — no data entry.  
**On system:** Not loaded.

---

## 01_Reference_Lists

**What it is:** Master lists that drive dropdowns on other sheets (Role, Specialty, Product Type, Potential, etc.).

**How to fill**
- Prefer existing values.
- To add a new specialty/role/form: append it at the bottom of that column.
- If a new value does not appear in a dropdown, ask IT to extend the named range (`LIST_Specialty`, etc.).

**On system:** Becomes picklist / global value set values (or load validation rules) so reps and SFE see consistent LOVs.

---

## 02_Users_Territories  
*(Users + roles + managers + territories + assignments — one combined sheet)*

**What it is:** One row = one territory slot. Optionally assign a user to that slot. Vacant territories are allowed.

**How to fill**
1. Create hierarchy top-down: Country → Region → District → Territory.
2. Set `Parent_Territory_External_Id` for every non-top row.
3. For an assigned territory: fill user columns + `Is_Vacant = No`.
4. For a vacant territory: `Is_Vacant = Yes`, leave User_* blank — still create the territory.
5. Managers must appear as their own row (or elsewhere) so `Manager_Email` resolves.
6. Do managers before their direct reports.

**On system**
- Creates `Territory2` hierarchy.
- Creates / invites `User` records and manager hierarchy.
- Assigns users to territories (UserTerritory2Association pattern).
- Vacant territories still receive account alignments and PTA so coverage can be planned before hire.

| Column | Meaning | Used on system for |
|---|---|---|
| Territory_External_Id | Stable territory key | Territory2 external id; join key for ATF/PTA/plan |
| Territory_Name | Display name | Territory label in planner, admin, reports |
| Territory_Type | Country/Region/District/Territory… | Hierarchy level / reporting rollups |
| Parent_Territory_External_Id | Parent territory key | Builds territory tree |
| Is_Vacant | Yes = no assignee | Allows territory without user |
| User_External_Id | Stable user key | User external id |
| User_Email | Login email | Username / federation identifier |
| First_Name / Last_Name | Person name | User name on UI |
| Role | Medical Rep, DM, RM… | Role / persona mapping & app visibility |
| Manager_Email | Manager’s email | User.ManagerId hierarchy |
| User_Status | Active / Inactive / To Be Hired | Whether to provision login |
| Mobile | Phone | User mobile / contact |
| Profile_Hint | Suggested Profile | License & UI profile assignment |
| Permission_Set_Group | PSG name | Feature access (Field / Manager apps) |
| Start_Date | Hire / assignment start | Effective dating |
| Working_Days_Per_Month | Default working days | Coverage denominator in plan KPIs |
| Notes | Free text | Ops comments only |

---

## 03_Products

**What it is:** Product catalog hierarchy.

**Hierarchy rule**
```
Brand (parent)
  ├── Detail          (commercial SKU — form, UoM, qty, box)
  ├── Sample          (leave-behind — same dosing fields)
  └── Brand Reminder  (Brochure / Bug — no dosing)
```

**How to fill**
1. Insert all **Brand** rows first (`Parent_Product_External_Id` blank).
2. Then Detail / Sample / Reminder with parent = Brand external id.
3. Detail & Sample **must** have Form, Unit_Of_Measure, Quantity_Per_Unit, Box_Quantity.

**On system**
- Loads `Product2` (and price book entries if price provided).
- Powers visit product picker, CLM product links, sample inventory, ATPF, PTA.

| Column | Meaning | Used on system for |
|---|---|---|
| Product_External_Id | Stable product key | Join key everywhere |
| Product_Name | Display name | Call report / CLM / catalog |
| Product_Code | SKU code | ProductCode |
| Product_Type | Brand/Detail/Sample/Reminder | Record typing & UI rules |
| Parent_Product_External_Id | Parent Brand key | Product hierarchy |
| Product_Family | Franchise | Filters & reports |
| Therapy_Area | TA | Filters & dashboards |
| Active_Ingredient | Molecule | Medical / search |
| Strength | e.g. 135mg | Display on detail aid |
| Form | Dosage form | Required on Detail/Sample |
| Unit_Of_Measure | mg, ml… | Dosing metadata |
| Quantity_Per_Unit | Numeric strength | Dosing metadata |
| Box_Quantity | Pack size | Samples / catalog |
| Unit_Price / Currency | List price | Price book (optional) |
| Brand_Reminder_Kind | Brochure / Bug | Reminder subtype |
| Is_Active | Yes/No | Hide from pickers if No |
| Manufacturer | MAH | Catalog attribute |
| External_System_Id | ERP/MDM id | Future integration |
| Notes | Free text | Ops only |

---

## 04_Accounts

**What it is:** Customer master — HCP, Pharmacy, HCO, Business Contact, Wholesaler.

**How to fill**
1. One row per customer.
2. HCP: fill First_Name, Last_Name, Specialty_1 (Person Account model if agreed).
3. Org accounts (Pharmacy/HCO): leave First/Last blank; fill Account_Name.
4. Add address + lat/long when available (needed for map & planner routing).
5. Put OneKey/IQVIA ids if you have MDM — do not invent them.

**On system**
- Creates `Account` with the correct record type.
- Feeds Field Rep Home, Accounts tab map, visit header, affiliations, ATF, plan targets.

| Column | Meaning | Used on system for |
|---|---|---|
| Account_External_Id | Stable account key | Join key for all account links |
| Account_Type | HCP/Pharmacy/HCO… | Record type / page layout |
| Account_Name | Display / legal name | Account.Name |
| First_Name / Last_Name | HCP person name | Person Account fields |
| Specialty_1/2/3 | Specialties | Targeting & filters |
| License_Number | License id | Compliance / identity |
| Tier | Commercial tier | Segmentation |
| Phone / Email | Contact | Communication |
| Street…Country | Address | Account address |
| Latitude / Longitude | Map pin | Planner map / route |
| Brick_Code | Brick membership | Brick analytics link |
| OneKey_Id / IQVIA_Id | MDM keys | Integration match |
| Is_Active | Yes/No | Soft delete from pickers |
| Notes | Free text | Rep guidance |

---

## 05_Account_Territory

**What it is:** Which accounts belong to which territory (alignment backbone).

**How to fill**
1. Every account that reps will visit must appear here.
2. Prefer **leaf** territories (rep territories), not Country/Region.
3. One primary alignment (`Is_Primary = Yes`).
4. Extra territories only if intentional dual coverage (`Dual_Aligned = Yes`).

**On system**
- Creates / updates `Account_Territory_Fields__c` (**ATF**).
- Controls which accounts appear in a rep’s book, NBC, planner, and coverage KPIs.

| Column | Meaning | Used on system for |
|---|---|---|
| Alignment_External_Id | Unique ATF row key | Upsert key |
| Account_External_Id | Account key | ATF.Account__c |
| Territory_External_Id | Territory key | ATF.Territory2_Id__c |
| Is_Primary | Primary owner | Ownership / reporting |
| Dual_Aligned | Shared coverage flag | Governance |
| Effective_Start_Date / End_Date | Validity window | Cycle realignment |
| Is_Active | Yes/No | Active alignment |
| Notes | Why dual / temp | Ops audit |

---

## 06_Account_Ratings

**What it is:** Territory-level customer ratings on top of ATF (potential, penetration, classification, KOL).

**How to fill**
1. One rating row per Account × Territory that you care about for targeting.
2. Account + Territory must already exist on sheet 05.
3. Potential = A/B/C; Penetration = 1–5; Classification = A/B/C (often matrix-derived).
4. Fill KOL fields for KOLs / sites with KOLs.

**On system**
- Writes ATF fields: `Potential__c`, `Penetration__c`, `Classification__c`, `Is_KOL__c`, etc.
- Drives rating layouts on account, Field Home coverage by class, NBC prioritization.

| Column | Meaning | Used on system for |
|---|---|---|
| Rating_External_Id | Unique rating key | Upsert / audit |
| Account_External_Id / Territory_External_Id | Join keys | Locate ATF row |
| Potential | A/B/C potential | ATF.Potential__c |
| Penetration | 1–5 share | ATF.Penetration__c |
| Classification | A/B/C class | ATF.Classification__c / matrix |
| Is_KOL | HCP is KOL | ATF.Is_KOL__c |
| KOL_In_What | KOL focus | ATF.KOL_In_What__c |
| Has_KOLs | Site has KOLs | ATF.Has_KOLs__c (HCO/Pharmacy) |
| KOL_Profile | Short profile | ATF.KOL_Profile__c |
| Is_Active | Yes/No | Active rating |
| Rated_By_Email / Rated_Date | Provenance | Audit / coaching |
| Notes | Free text | Ops |

---

## 07_Product_Ratings (ATPF) — recommended

**What it is:** Ratings at Account × Territory × **Product** level (adoption, loyalty, Rx, visit frequency).

**How to fill**
1. Only for priority products on priority accounts.
2. Product should be Brand or Detail from sheet 03.
3. Account must be aligned to that territory on sheet 05.

**On system**
- Creates `Account_Territory_Product_Fields__c` (**ATPF**).
- Powers product rating UI on visit/account, target frequency hints, product matrix badges.

| Column | Meaning | Used on system for |
|---|---|---|
| ATPF_External_Id | Unique ATPF key | Upsert key |
| Account / Territory / Product External Ids | Triangle join | ATPF unique key |
| Rx_Per_Week | Est. Rx / week | ATPF.Rx_Per_Week__c |
| Adoption | H/M/L | ATPF.Adoption__c |
| Loyalty | H/M/L | ATPF.Loyalty__c |
| Target_Visit_Frequency | Weekly…None | ATPF.Target_Visit_Frequency__c |
| Is_Active | Yes/No | Active ATPF |
| Notes | Barriers / competitor | ATPF.Notes__c |

---

## 08_Product_Territory (PTA) — recommended / often required

**What it is:** Which products each territory is allowed to detail / sell.

**How to fill**
1. At least one active product per **leaf** territory (including vacant ones).
2. Usually align Brands (and key Details) used in that geography.
3. Without PTA, visit and CLM product pickers cannot filter correctly.

**On system**
- Creates `Product_Territory_Alignment__c` (**PTA**).
- Filters products on call report and CLM targeting.

| Column | Meaning | Used on system for |
|---|---|---|
| PTA_External_Id | Unique PTA key | Upsert key |
| Territory_External_Id | Territory | PTA.Territory2_Id__c |
| Product_External_Id | Brand/Detail | PTA.Product2_Id__c |
| Is_Active | Yes/No | Active sellable scope |
| Effective_Start_Date / End_Date | Validity | Launch / retire windows |
| Notes | Restrictions | Ops |

---

## 09_Plan_Cycle_Targets

**What it is:** Monthly account visit targets per rep (this template: **July & August** = `2026-07`, `2026-08`).

**How to fill**
1. One row = one account target for one rep in one month.
2. `Rep_Email` must be an assigned (non-vacant) user.
3. Account should be aligned to that territory (or dual-aligned).
4. Repeat rows for August (copy-forward is fine).
5. `Target_Visit_Count` = how many visits expected that month.

**On system**
- Creates `Employee_Time_Card__c` (plan cycle per rep/month).
- Creates `Employee_Time_Card_Account_Target__c` lines.
- Feeds Field Rep Home coverage, NBC, planner capacity, Medical Rep 360 KPIs.

| Column | Meaning | Used on system for |
|---|---|---|
| Target_External_Id | Unique plan-line key | Upsert key |
| Plan_Month | 2026-07 / 2026-08 | Time card period |
| Rep_Email | Assigned rep | Time card owner |
| Territory_External_Id | Planning territory | Scope |
| Account_External_Id | Target account | Account target line |
| Target_Visit_Count | Visits planned | Target_Visit_Frequency / visit target |
| Suggested_Weekdays | Preferred days | Planner guidance |
| Priority_Class | A/B/C | Coverage / NBC priority |
| Working_Days_In_Month | Capacity days | Coverage denominator |
| Cycle_Owner_Email | Usually DM | Cycle ownership / approval |
| Notes | Special push | Ops |

---

## 10_CLM_Content

**What it is:** CLM presentation master + file location.

**How to fill**
1. One row per deck.
2. Put the real PDF/HTML/ZIP in a folder delivered with this workbook.
3. `File_Folder_Path` + `File_Name` must match the files exactly.
4. Status for go-live decks should be **MLR Approved** or **Published**.

**On system**
- Creates CLM presentation records + stores ContentVersion / files.
- Appears in CLM library; playable in visit; dwell/rating analytics attach here.

| Column | Meaning | Used on system for |
|---|---|---|
| CLM_External_Id | Stable deck key | Upsert / join to slides |
| CLM_Title | Title in library | Player title |
| File_Format | PDF/HTML/ZIP | Player packaging |
| File_Name | Exact file name | ContentVersion title/path |
| File_Folder_Path | Folder of binaries | Load script path |
| Primary_Product_External_Id | Main product | Default product context |
| Tags | Search tags | Library filters |
| Status | Draft→Published | Publish gate |
| MLR_Approved_Date | Compliance date | Audit |
| Effective_Start_Date / End_Date | Usable window | Visibility |
| Language | en/ar… | Localization |
| Is_Mandatory | Must-detail deck | Compliance flag |
| Version | v1 / v1.1 | Version control |
| Notes | Supersedes… | Ops |

---

## 10b_CLM_Alignments

**What it is:** Slide × Product × Message matrix (and optional territory restriction).

**How to fill**
1. For each important slide, add one or more rows (one product/message combo per row).
2. `CLM_External_Id` must match sheet 10.
3. `Slide_Number` starts at 1.
4. Leave Territory blank = available wherever PTA allows the product; fill Territory to restrict.

**On system**
- Drives CLM slide–product–message tracking in the player.
- Enables message sentiment / product coverage analytics from visits.

| Column | Meaning | Used on system for |
|---|---|---|
| CLM_Alignment_Id | Unique slide link key | Upsert |
| CLM_External_Id | Parent deck | Presentation link |
| Slide_Number | Slide index | Player slide map |
| Product_External_Id | Product on slide | Product detailing log |
| Message_Type | INDICATION/EFFICACY… | Message analytics |
| Territory_External_Id | Optional restrict | Territory targeting |
| Is_Mandatory_Slide | Must present | Compliance |
| Notes | Claim / speaker note | Content ops |

---

## 11_Affiliations — recommended

**What it is:** Relationships between accounts (HCP works at HCO, refers to Pharmacy, etc.).

**How to fill:** From_Account → To_Account with a type. Mark primary workplace.

**On system:** Affiliation graph for visit attendees, influence map, pharmacy sell-out bridge recommendations.

| Column | Meaning | Used on system for |
|---|---|---|
| Affiliation_External_Id | Unique key | Upsert |
| From_Account_External_Id | Source (often HCP) | From account |
| To_Account_External_Id | Target (Pharmacy/HCO) | To account |
| Affiliation_Type | Works At / Refers To… | Relationship type |
| Is_Primary | Primary workplace | Default attendee context |
| Is_Active | Yes/No | Active link |
| Notes | Free text | Ops |

---

## 12_Bricks — optional

**What it is:** Geographic bricks and pharmacies in each brick.

**How to fill:** Create brick codes; link owning territory; list pharmacy account ids (semicolon-separated) or one pharmacy per row if preferred later.

**On system:** Brick dashboards, pharmacy membership rules, sell-out by brick.

---

## 13_Sample_Opening_Stock — if samples in Wave 1

**What it is:** Opening sample inventory per rep (lot, expiry, qty).

**How to fill**
1. Product must be `Product_Type = Sample` on sheet 03.
2. Rep_Email must be an active assigned user.
3. Expiry must be after go-live date.

**On system**
- Creates `Sample_Inventory__c`.
- Visit sample deduction validates lot / expiry / quantity on hand.

| Column | Meaning | Used on system for |
|---|---|---|
| Inventory_External_Id | Unique inventory line | Upsert |
| Rep_Email | Holder | Owner_User__c |
| Product_External_Id | Sample SKU | Product2__c |
| Lot_Number | Batch | Lot_Number__c |
| Expiry_Date | Expiry | Expiry_Date__c |
| Quantity_On_Hand | Opening qty | Quantity_On_Hand__c |
| Is_Active | Yes/No | Issuable |
| Notes | Transfer ref | Ops |

---

## 14_Company_Profile

**What it is:** One-page org defaults (market, currency, go-live, working days, owners).

**How to fill:** Answer every Value cell once.  
**On system:** Not a Salesforce object — used by the load team as configuration defaults for the initial phase.

---

## 15_Readiness_Checklist

**What it is:** QA before handover to the data-load team.  
**How to fill:** Mark each check Done = Yes when true; assign Owner.  
**On system:** Not loaded — gate for “ready to import.”

---

## Quick fill sequence (initial phase)

1. `14_Company_Profile` — defaults  
2. `01_Reference_Lists` — add missing LOVs only  
3. `02_Users_Territories` — hierarchy + people (vacant OK)  
4. `03_Products` — Brand then children  
5. `04_Accounts` — customer master  
6. `05_Account_Territory` — who owns whom  
7. `06_Account_Ratings` — potential / class / KOL  
8. `08_Product_Territory` — sellable products per territory  
9. `07_Product_Ratings` — priority ATPF rows  
10. `09_Plan_Cycle_Targets` — July & August  
11. `10_CLM_Content` + files folder + `10b_CLM_Alignments`  
12. Optional: `11_Affiliations`, `12_Bricks`, `13_Sample_Opening_Stock`  
13. `15_Readiness_Checklist` — sign off  

---

## Golden rules

- Never invent External IDs that collide.
- Manager emails and parent territories must already exist in the sheet.
- Vacant territory ≠ delete territory — keep the row, set `Is_Vacant = Yes`.
- Plan targets only for assigned reps.
- CLM files on disk must match `File_Folder_Path` + `File_Name` exactly.
- When unsure whether a sheet is in Wave 1, leave it blank and confirm in discovery — do not guess production data.
