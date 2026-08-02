#!/usr/bin/env python3
"""Bulk rename Zeta metadata to Pharma in force-app."""

from __future__ import annotations

import re
import shutil
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path("/Users/ashrafrezk/Salesforce Projects/Pharmaceuticals")
FORCE_APP = ROOT / "force-app" / "main" / "default"
MANIFEST = ROOT / "manifest" / "destructiveChanges-zeta-strip.xml"

OBJECT_RENAMES = [
    "Zeta_Project__c",
    "Zeta_Project_Member__c",
    "Zeta_Project_Activity__c",
    "Zeta_Project_Budget_Line__c",
    "Zeta_Project_Account_Goal__c",
    "Zeta_Project_Milestone__c",
    "Zeta_Project_KPI__c",
    "Zeta_Business_Objective__c",
]

GVS_RENAMES = [
    "Zeta_Business_Objective_Scope",
    "Zeta_Campaign_Type",
    "Zeta_Project_Activity_Type",
    "Zeta_Project_Member_Role",
]

EXCLUDED_APEX_FILES = {
    "ZetaPharmaProductCatalogService.cls",
    "ZetaPharmaProductCatalogServiceTest.cls",
    "ZetaDemoDataProfiles.cls",
    "ZetaDemoDataProfilesTest.cls",
    "ZetaAppPersonaSeed.cls",
    "ZetaAppSetupSeed.cls",
}

LABEL_REPLACEMENTS = [
    ("Zeta Business Objective", "Pharma Business Objective"),
    ("Zeta Business Objectives", "Pharma Business Objectives"),
    ("Zeta Business", "Pharma Business"),
    ("Zeta Project Member", "Pharma Project Member"),
    ("Zeta Project Activity", "Pharma Project Activity"),
    ("Zeta Project Budget Line", "Pharma Project Budget Line"),
    ("Zeta Project Account Goal", "Pharma Project Account Goal"),
    ("Zeta Project Milestone", "Pharma Project Milestone"),
    ("Zeta Project KPI", "Pharma Project KPI"),
    ("Zeta Projects", "Pharma Projects"),
    ("Zeta Project", "Pharma Project"),
    ("Zeta Management", "Pharma Management"),
    ("Zeta C-Levels", "Pharma C-Levels"),
    ("Zeta C Levels", "Pharma C Levels"),
    ("Zeta Field", "Pharma Field"),
]

created: list[str] = []
deleted: list[str] = []
updated_refs: list[str] = []


def transform_content(text: str) -> str:
    result = text
    result = result.replace("Zeta_", "Pharma_")
    for old, new in LABEL_REPLACEMENTS:
        result = result.replace(old, new)
    return result


def transform_filename(name: str) -> str:
    return name.replace("Zeta_", "Pharma_").replace("Zeta ", "Pharma ")


def copy_tree_with_transform(src: Path, dst: Path) -> None:
    if dst.exists():
        shutil.rmtree(dst)
    dst.parent.mkdir(parents=True, exist_ok=True)

    for src_path in sorted(src.rglob("*")):
        rel = src_path.relative_to(src)
        parts = [transform_filename(p) for p in rel.parts]
        dst_path = dst.joinpath(*parts)
        if src_path.is_dir():
            dst_path.mkdir(parents=True, exist_ok=True)
        else:
            dst_path.parent.mkdir(parents=True, exist_ok=True)
            content = src_path.read_text(encoding="utf-8")
            dst_path.write_text(transform_content(content), encoding="utf-8")
            created.append(str(dst_path.relative_to(ROOT)))


def copy_file_with_transform(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    content = src.read_text(encoding="utf-8")
    dst.write_text(transform_content(content), encoding="utf-8")
    created.append(str(dst.relative_to(ROOT)))


def delete_path(path: Path) -> None:
    if not path.exists():
        return
    if path.is_dir():
        shutil.rmtree(path)
    else:
        path.unlink()
    deleted.append(str(path.relative_to(ROOT)))


def find_zeta_files_in_dir(directory: Path, suffix: str) -> list[Path]:
    if not directory.exists():
        return []
    return sorted(p for p in directory.iterdir() if p.is_file() and p.name.startswith("Zeta") and p.name.endswith(suffix))


def update_external_lookup_fields() -> None:
    renames = [
        (
            FORCE_APP / "objects" / "Visit__c" / "fields" / "Zeta_Project__c.field-meta.xml",
            FORCE_APP / "objects" / "Visit__c" / "fields" / "Pharma_Project__c.field-meta.xml",
        ),
        (
            FORCE_APP / "objects" / "Promo_Budget_Line__c" / "fields" / "Zeta_Project__c.field-meta.xml",
            FORCE_APP / "objects" / "Promo_Budget_Line__c" / "fields" / "Pharma_Project__c.field-meta.xml",
        ),
    ]
    for src, dst in renames:
        if src.exists():
            copy_file_with_transform(src, dst)
            delete_path(src)

    related = FORCE_APP / "objects" / "Collaboration_Request__c" / "fields" / "Related_Project__c.field-meta.xml"
    if related.exists():
        text = related.read_text(encoding="utf-8")
        new_text = transform_content(text)
        if new_text != text:
            related.write_text(new_text, encoding="utf-8")
            updated_refs.append(str(related.relative_to(ROOT)))


def update_force_app_references() -> None:
    scan_dirs = [
        FORCE_APP / "classes",
        FORCE_APP / "lwc",
        FORCE_APP / "flows",
        FORCE_APP / "profiles",
        FORCE_APP / "applications",
        FORCE_APP / "flexipages",
        FORCE_APP / "layouts",
        FORCE_APP / "tabs",
        FORCE_APP / "pathAssistants",
        FORCE_APP / "permissionsets",
        FORCE_APP / "permissionsetgroups",
        FORCE_APP / "objects",
        FORCE_APP / "triggers",
        FORCE_APP / "pages",
        FORCE_APP / "genAiPromptTemplates",
        FORCE_APP / "genAiPlannerBundles",
    ]

    patterns = [
        "Zeta_Project__c",
        "Zeta_Project_Member__c",
        "Zeta_Project_Activity__c",
        "Zeta_Project_Budget_Line__c",
        "Zeta_Project_Account_Goal__c",
        "Zeta_Project_Milestone__c",
        "Zeta_Project_KPI__c",
        "Zeta_Business_Objective__c",
        "Zeta_Business_Objective_Scope",
        "Zeta_Campaign_Type",
        "Zeta_Project_Activity_Type",
        "Zeta_Project_Member_Role",
        "Zeta_Project_Record_Page",
        "Zeta_Project",
        "Zeta_Management",
        "Zeta_C_Levels",
        "Zeta_Field_App",
        "Zeta_Product_Catalog",
        "Zeta_Management_App",
        "Zeta_C_Levels_App",
        "Zeta_Region_Manager_PSG",
        "Zeta_Field_Rep_PSG",
        "Zeta_District_Manager_PSG",
        "Zeta_C_Level_PSG",
    ]

    for base in scan_dirs:
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if not path.is_file():
                continue
            if ".cursor" in path.parts:
                continue
            if path.name in EXCLUDED_APEX_FILES:
                continue
            if path.name.startswith("Zeta") and path.suffix in {".cls", ".cls-meta.xml"}:
                if any(path.name.startswith(prefix.replace(".cls", "")) for prefix in EXCLUDED_APEX_FILES):
                    continue
                # Skip excluded class files by stem
                stem = path.stem.replace("-meta", "")
                if stem in {f.replace(".cls", "") for f in EXCLUDED_APEX_FILES}:
                    continue
            if path.name.startswith("Zeta_") and path.parent.name in {
                "objects", "layouts", "tabs", "flexipages", "pathAssistants",
                "globalValueSets", "applications", "permissionsets", "permissionsetgroups",
            }:
                continue
            if any(part.startswith("Zeta_") for part in path.parts if part.endswith("__c")):
                # skip files inside old zeta object dirs (will be deleted)
                if any(part.startswith("Zeta_") and part.endswith("__c") for part in path.parts):
                    continue

            try:
                text = path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue

            if not any(p in text for p in patterns) and "Zeta " not in text and "Zeta_" not in text:
                continue

            # Excluded apex class content updates
            if path.parent.name == "classes":
                stem = path.stem.replace("-meta", "")
                excluded_stems = {f.replace(".cls", "") for f in EXCLUDED_APEX_FILES}
                if stem in excluded_stems:
                    continue

            new_text = transform_content(text)
            if new_text != text:
                path.write_text(new_text, encoding="utf-8")
                updated_refs.append(str(path.relative_to(ROOT)))


def collect_destructive_members() -> dict[str, list[str]]:
    type_members: dict[str, list[str]] = {
        "CustomObject": OBJECT_RENAMES.copy(),
        "GlobalValueSet": GVS_RENAMES.copy(),
        "CustomApplication": ["Zeta_Management", "Zeta_C_Levels"],
        "PermissionSet": [
            "Zeta_Management_App",
            "Zeta_C_Levels_App",
            "Zeta_Field_App",
            "Zeta_Product_Catalog",
        ],
        "PermissionSetGroup": [
            "Zeta_Region_Manager_PSG",
            "Zeta_Field_Rep_PSG",
            "Zeta_District_Manager_PSG",
            "Zeta_C_Level_PSG",
        ],
        "Layout": [],
        "FlexiPage": ["Zeta_Project_Record_Page"],
        "CustomTab": ["Zeta_Project__c"],
        "PathAssistant": ["Zeta_Project"],
    }

    layouts_dir = FORCE_APP / "layouts"
    for layout in find_zeta_files_in_dir(layouts_dir, ".layout-meta.xml"):
        member = layout.name.replace(".layout-meta.xml", "")
        type_members["Layout"].append(member)
    return type_members


def write_destructive_changes(type_members: dict[str, list[str]]) -> None:
    package = ET.Element("Package", xmlns="http://soap.sforce.com/2006/04/metadata")
    version = ET.SubElement(package, "version")
    version.text = "67.0"

    for type_name in sorted(type_members.keys()):
        members = sorted(set(type_members[type_name]))
        if not members:
            continue
        types_el = ET.SubElement(package, "types")
        for member in members:
            m = ET.SubElement(types_el, "members")
            m.text = member
        name_el = ET.SubElement(types_el, "name")
        name_el.text = type_name

    tree = ET.ElementTree(package)
    ET.indent(tree, space="    ")
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    tree.write(MANIFEST, encoding="UTF-8", xml_declaration=True)


def main() -> None:
    # 1. Copy object folders
    objects_dir = FORCE_APP / "objects"
    for obj in OBJECT_RENAMES:
        src = objects_dir / obj
        dst = objects_dir / obj.replace("Zeta_", "Pharma_", 1)
        if src.exists():
            copy_tree_with_transform(src, dst)

    # 2. Global value sets
    gvs_dir = FORCE_APP / "globalValueSets"
    for gvs in GVS_RENAMES:
        src = gvs_dir / f"{gvs}.globalValueSet-meta.xml"
        dst = gvs_dir / f"{gvs.replace('Zeta_', 'Pharma_', 1)}.globalValueSet-meta.xml"
        if src.exists():
            copy_file_with_transform(src, dst)

    # 3. Layouts
    for layout in find_zeta_files_in_dir(FORCE_APP / "layouts", ".layout-meta.xml"):
        new_name = transform_filename(layout.name)
        copy_file_with_transform(layout, layout.parent / new_name)

    # 4. Tabs
    for tab in find_zeta_files_in_dir(FORCE_APP / "tabs", ".tab-meta.xml"):
        new_name = transform_filename(tab.name)
        copy_file_with_transform(tab, tab.parent / new_name)

    # 5. Flexipages
    for fp in find_zeta_files_in_dir(FORCE_APP / "flexipages", ".flexipage-meta.xml"):
        new_name = transform_filename(fp.name)
        copy_file_with_transform(fp, fp.parent / new_name)

    # 6. Path assistants
    for pa in find_zeta_files_in_dir(FORCE_APP / "pathAssistants", ".pathAssistant-meta.xml"):
        new_name = transform_filename(pa.name)
        copy_file_with_transform(pa, pa.parent / new_name)

    # 7. Apps
    for app in find_zeta_files_in_dir(FORCE_APP / "applications", ".app-meta.xml"):
        if app.name == "standard__LightningSales.app-meta.xml":
            continue
        new_name = transform_filename(app.name)
        copy_file_with_transform(app, app.parent / new_name)

    # 8. Permission sets
    for ps in find_zeta_files_in_dir(FORCE_APP / "permissionsets", ".permissionset-meta.xml"):
        new_name = transform_filename(ps.name)
        copy_file_with_transform(ps, ps.parent / new_name)

    # 9. Permission set groups
    for psg in find_zeta_files_in_dir(FORCE_APP / "permissionsetgroups", ".permissionsetgroup-meta.xml"):
        new_name = transform_filename(psg.name)
        copy_file_with_transform(psg, psg.parent / new_name)

    # 10. Collect destructive members before deletion
    destructive_members = collect_destructive_members()

    # 11. External lookup fields
    update_external_lookup_fields()

    # 12. Update references across force-app
    update_force_app_references()

    # 13. Update standard__LightningSales (logo/apps references)
    lightning_sales = FORCE_APP / "applications" / "standard__LightningSales.app-meta.xml"
    if lightning_sales.exists():
        text = lightning_sales.read_text(encoding="utf-8")
        new_text = transform_content(text)
        if new_text != text:
            lightning_sales.write_text(new_text, encoding="utf-8")
            updated_refs.append(str(lightning_sales.relative_to(ROOT)))

    # 14. Delete old Zeta metadata
    for obj in OBJECT_RENAMES:
        delete_path(objects_dir / obj)

    for gvs in GVS_RENAMES:
        delete_path(gvs_dir / f"{gvs}.globalValueSet-meta.xml")

    for layout in find_zeta_files_in_dir(FORCE_APP / "layouts", ".layout-meta.xml"):
        delete_path(layout)

    for tab in find_zeta_files_in_dir(FORCE_APP / "tabs", ".tab-meta.xml"):
        delete_path(tab)

    for fp in find_zeta_files_in_dir(FORCE_APP / "flexipages", ".flexipage-meta.xml"):
        delete_path(fp)

    for pa in find_zeta_files_in_dir(FORCE_APP / "pathAssistants", ".pathAssistant-meta.xml"):
        delete_path(pa)

    for app in find_zeta_files_in_dir(FORCE_APP / "applications", ".app-meta.xml"):
        delete_path(app)

    for ps in find_zeta_files_in_dir(FORCE_APP / "permissionsets", ".permissionset-meta.xml"):
        delete_path(ps)

    for psg in find_zeta_files_in_dir(FORCE_APP / "permissionsetgroups", ".permissionsetgroup-meta.xml"):
        delete_path(psg)

    # 15. Destructive changes manifest
    write_destructive_changes(destructive_members)

    # Report remaining Zeta references
    remaining: list[str] = []
    for path in FORCE_APP.rglob("*"):
        if not path.is_file():
            continue
        if ".cursor" in path.parts:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        if "Zeta" in text or "zeta" in text.lower():
            remaining.append(str(path.relative_to(ROOT)))

    print("=== CREATED ===")
    for item in sorted(set(created)):
        print(item)
    print(f"\nTotal created: {len(set(created))}")

    print("\n=== DELETED ===")
    for item in sorted(set(deleted)):
        print(item)
    print(f"\nTotal deleted: {len(set(deleted))}")

    print("\n=== UPDATED REFERENCES ===")
    for item in sorted(set(updated_refs)):
        print(item)
    print(f"\nTotal updated: {len(set(updated_refs))}")

    print("\n=== REMAINING ZETA REFERENCES IN force-app ===")
    for item in sorted(set(remaining)):
        print(item)
    print(f"\nTotal remaining files with Zeta: {len(set(remaining))}")

    print(f"\nDestructive changes written to: {MANIFEST}")


if __name__ == "__main__":
    main()
