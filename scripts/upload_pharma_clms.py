#!/usr/bin/env python3
"""Upload Chemipharm + Soul Pharma CLM decks only.

Deactivates every other Available CLM_Presentation__c so the org keeps
exactly these two decks, with per-slide Product_Names / Message_Names
from the YAML catalogs.

Usage:
  python scripts/upload_pharma_clms.py
  python scripts/upload_pharma_clms.py --org pharma-prod
  python scripts/upload_pharma_clms.py --chemipharm-only
  python scripts/upload_pharma_clms.py --soul-only
"""

from __future__ import annotations

import argparse
import base64
import json
import re
import subprocess
import sys
from pathlib import Path

import requests

try:
    import fitz  # pymupdf
except ImportError:
    fitz = None

try:
    import yaml
except ImportError:
    yaml = None

PROJECT_ROOT = Path(__file__).resolve().parents[1]
ORG_ALIAS = "pharma-prod"
PNG_SCALE = 1.5

KEEP_ACTIVE_NAMES = (
    "Chemipharm Presentation Deck",
    "Soul Pharma Product Deck",
)

CATALOGS = {
    "chemipharm": PROJECT_ROOT / "Plan/chemipharm_clm_catalog.yaml",
    "soul": PROJECT_ROOT / "Plan/soul_pharma_clm_catalog.yaml",
}

CHEMIPHARM_FALLBACK_SLIDES = {
    1: ("Chemipharm", "INDICATION"),
    2: ("Chemipharm; Coloverin; Verserc", "INDICATION"),
    3: ("Coloverin; Coloverin D; Coloverin A; Coloverin SR", "EFFICACY; SAFETY"),
    4: ("Coloverin D", "EFFICACY"),
    5: ("Verserc", "SAFETY"),
    6: ("Dantrelax; Dantrelax Compound", "EFFICACY; SAFETY"),
    7: ("Dantrelax", "SAFETY"),
    8: ("Rosuvast", "EFFICACY"),
    9: ("Algesal Suractive", "SAFETY"),
    10: ("Coloverin D; Verserc; Dantrelax; Rosuvast; Algesal Suractive", "EFFICACY; SAFETY"),
    11: ("Coloverin D; Verserc; Dantrelax; Rosuvast", "EFFICACY"),
    12: ("Chemipharm", "SUPPORT"),
    13: ("Chemipharm", "SUPPORT"),
}

SOUL_FALLBACK_SLIDES = {
    1: ("Soul Pharma; Soulfort; Genolight", "INDICATION"),
    2: ("Soulfort; Genolight", "INDICATION"),
    3: ("Soulfort", "EFFICACY"),
    4: ("Soulfort", "SAFETY; SUPPORT"),
    5: ("Genolight", "EFFICACY"),
    6: ("Genolight", "SAFETY"),
    7: ("Soulfort; Genolight", "EFFICACY; SAFETY; SUPPORT"),
}


def sf_org(org_alias: str):
    result = subprocess.run(
        ["sf", "org", "display", "--target-org", org_alias, "--json"],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)["result"]


def sf_query(instance_url, headers, soql):
    response = requests.get(
        f"{instance_url}/services/data/v58.0/query",
        headers=headers,
        params={"q": soql},
        timeout=120,
    )
    response.raise_for_status()
    return response.json()


def sf_create(instance_url, headers, sobject, payload):
    response = requests.post(
        f"{instance_url}/services/data/v58.0/sobjects/{sobject}",
        headers=headers,
        json=payload,
        timeout=300,
    )
    response.raise_for_status()
    return response.json()


def sf_update(instance_url, headers, sobject, record_id, payload):
    response = requests.patch(
        f"{instance_url}/services/data/v58.0/sobjects/{sobject}/{record_id}",
        headers=headers,
        json=payload,
        timeout=120,
    )
    response.raise_for_status()


def load_catalog(path: Path):
    if yaml is None or not path.exists():
        return None
    with path.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def count_pdf_pages(data: bytes) -> int:
    if fitz is not None:
        with fitz.open(stream=data, filetype="pdf") as doc:
            return doc.page_count
    text = data.decode("latin1", errors="ignore")
    pages = len(re.findall(r"/Type\s*/Page(?!s)", text))
    return pages or 1


def render_slide_pngs(pdf_bytes: bytes, page_count: int) -> list[tuple[int, bytes]]:
    if fitz is None:
        raise RuntimeError("pymupdf is required. Run: pip install pymupdf")
    images: list[tuple[int, bytes]] = []
    with fitz.open(stream=pdf_bytes, filetype="pdf") as doc:
        total = min(page_count, doc.page_count)
        for page_num in range(1, total + 1):
            page = doc.load_page(page_num - 1)
            pix = page.get_pixmap(matrix=fitz.Matrix(PNG_SCALE, PNG_SCALE), alpha=False)
            images.append((page_num, pix.tobytes("png")))
            print(f"  Rendered slide {page_num}/{total}")
    return images


def build_slide_image_url(content_version_id: str) -> str:
    return (
        "/sfc/servlet.shepherd/version/renditionDownload"
        f"?rendition=ORIGINAL_Png&versionId={content_version_id}"
    )


def link_content_document(instance_url, headers, content_document_id: str, presentation_id: str):
    existing = sf_query(
        instance_url,
        headers,
        (
            "SELECT Id FROM ContentDocumentLink "
            f"WHERE ContentDocumentId = '{content_document_id}' "
            f"AND LinkedEntityId = '{presentation_id}'"
        ),
    ).get("records", [])
    if existing:
        return
    sf_create(
        instance_url,
        headers,
        "ContentDocumentLink",
        {
            "ContentDocumentId": content_document_id,
            "LinkedEntityId": presentation_id,
            "ShareType": "V",
            "Visibility": "AllUsers",
        },
    )


def deactivate_non_keep_decks(instance_url, headers, keep_names: set[str], also_deactivate_names: set[str] | None = None):
    """Deactivate every Available CLM that is not in keep_names.

    also_deactivate_names: force-deactivate these (e.g. same-name prior uploads)
    even if they are in keep_names, so a fresh upload can replace them.
    """
    also_deactivate_names = also_deactivate_names or set()
    records = sf_query(
        instance_url,
        headers,
        "SELECT Id, Name, Status__c FROM CLM_Presentation__c WHERE Status__c != 'Deactivated'",
    ).get("records", [])
    deactivated = 0
    for record in records:
        name = record.get("Name") or ""
        keep = name in keep_names and name not in also_deactivate_names
        if keep:
            continue
        sf_update(
            instance_url,
            headers,
            "CLM_Presentation__c",
            record["Id"],
            {"Status__c": "Deactivated"},
        )
        print(f"  Deactivated {record['Id']} ({name})")
        deactivated += 1
    print(f"Deactivated {deactivated} CLM presentation(s).")
    return deactivated


def resolve_products(instance_url, headers, catalog: dict | None, fallback_ext_ids: list[str], primary_ext: str):
    ext_ids = list(fallback_ext_ids)
    if catalog and catalog.get("presentation"):
        pres = catalog["presentation"]
        primary_ext = pres.get("primary_product_external_id", primary_ext)
        if pres.get("product_external_ids"):
            ext_ids = list(pres["product_external_ids"])

    quoted = ",".join("'" + e.replace("'", "\\'") + "'" for e in ext_ids)
    records = sf_query(
        instance_url,
        headers,
        (
            "SELECT Id, Name, External_ID__c FROM Product2 "
            f"WHERE External_ID__c IN ({quoted}) AND IsActive = true"
        ),
    ).get("records", [])
    by_ext = {r["External_ID__c"]: r for r in records}
    if primary_ext not in by_ext and records:
        primary = records[0]
    elif primary_ext in by_ext:
        primary = by_ext[primary_ext]
    else:
        raise RuntimeError(
            f"No products found for external IDs {ext_ids}. Seed catalog first."
        )

    product_ids = [r["Id"] for r in records]
    product_names = [r["Name"] for r in records]
    products_json = json.dumps({"productIds": product_ids, "productNames": product_names})
    return primary["Id"], products_json


def slide_alignment_map(catalog: dict | None, fallback: dict[int, tuple[str, str]]) -> dict[int, tuple[str, str]]:
    if not catalog or not catalog.get("slides"):
        return fallback
    result: dict[int, tuple[str, str]] = {}
    for page, meta in catalog["slides"].items():
        result[int(page)] = (
            meta.get("product_names") or "",
            meta.get("message_names") or "",
        )
    return result


def attach_slide_images(instance_url, headers, presentation_id: str, slide_images, image_prefix: str):
    sequences = sf_query(
        instance_url,
        headers,
        (
            "SELECT Id, Sequence_Order__c, Page_Number__c FROM CLM_Sequence__c "
            f"WHERE CLM_Presentation__c = '{presentation_id}' "
            "ORDER BY Sequence_Order__c ASC"
        ),
    ).get("records", [])
    by_page = {}
    for record in sequences:
        page = record.get("Page_Number__c") or record.get("Sequence_Order__c")
        if page is not None:
            by_page[int(page)] = record

    for page_number, png_bytes in slide_images:
        sequence = by_page.get(page_number)
        if sequence is None:
            continue
        image_name = f"{image_prefix}-slide-{page_number}.png"
        image_version = sf_create(
            instance_url,
            headers,
            "ContentVersion",
            {
                "Title": image_name,
                "PathOnClient": image_name,
                "VersionData": base64.b64encode(png_bytes).decode("ascii"),
                "IsMajorVersion": True,
            },
        )
        image_version_id = image_version["id"]
        image_doc_id = sf_query(
            instance_url,
            headers,
            f"SELECT ContentDocumentId FROM ContentVersion WHERE Id = '{image_version_id}'",
        )["records"][0]["ContentDocumentId"]
        link_content_document(instance_url, headers, image_doc_id, presentation_id)
        sf_update(
            instance_url,
            headers,
            "CLM_Sequence__c",
            sequence["Id"],
            {
                "Thumbnail_Content_Version_Id__c": image_version_id,
                "Slide_Image_URL__c": build_slide_image_url(image_version_id),
            },
        )
        print(f"  Attached slide image for page {page_number}")


def upload_deck(
    instance_url,
    headers,
    pdf_path: Path,
    presentation_name: str,
    primary_product_id: str,
    products_json: str,
    alignments: dict[int, tuple[str, str]],
    tags: str,
    image_prefix: str,
):
    pdf_bytes = pdf_path.read_bytes()
    page_count = count_pdf_pages(pdf_bytes)
    file_name = f"{presentation_name}.pdf"

    version = sf_create(
        instance_url,
        headers,
        "ContentVersion",
        {
            "Title": presentation_name,
            "PathOnClient": file_name,
            "VersionData": base64.b64encode(pdf_bytes).decode("ascii"),
        },
    )
    version_id = version["id"]
    content_document_id = sf_query(
        instance_url,
        headers,
        f"SELECT ContentDocumentId FROM ContentVersion WHERE Id = '{version_id}'",
    )["records"][0]["ContentDocumentId"]

    presentation = sf_create(
        instance_url,
        headers,
        "CLM_Presentation__c",
        {
            "Name": presentation_name,
            "Status__c": "Available",
            "Format__c": "PDF",
            "Slide_Count__c": page_count,
            "Content_Document_Id__c": content_document_id,
            "Product__c": primary_product_id,
            "Products__c": products_json,
            "Allow_Unaligned__c": True,
            "Tags__c": tags,
            "Player_Gesture__c": "Tap Bottom",
            "Pinch_Zoom__c": "Enabled",
            "Double_Tap_Zoom__c": "Enabled",
        },
    )
    presentation_id = presentation["id"]
    link_content_document(instance_url, headers, content_document_id, presentation_id)

    for page in range(1, page_count + 1):
        products, messages = alignments.get(page, ("", ""))
        sf_create(
            instance_url,
            headers,
            "CLM_Sequence__c",
            {
                "CLM_Presentation__c": presentation_id,
                "Sequence_Order__c": page,
                "Sequence_Name__c": f"Slide {page}",
                "Name": f"Slide {page}",
                "File_Name__c": file_name,
                "Page_Number__c": page,
                "Product_Names__c": products,
                "Message_Names__c": messages,
            },
        )
        print(f"  Sequence {page}: products=[{products}] messages=[{messages}]")

    if fitz is not None:
        print("Rendering slide PNGs...")
        slide_images = render_slide_pngs(pdf_bytes, page_count)
        attach_slide_images(instance_url, headers, presentation_id, slide_images, image_prefix)
    else:
        print("pymupdf not installed; skipping PNG slide previews")

    print(f"Created presentation {presentation_id} ({page_count} slides)")
    return presentation_id


def upload_from_catalog(
    instance_url,
    headers,
    catalog_path: Path,
    fallback_slides: dict[int, tuple[str, str]],
    fallback_ext_ids: list[str],
    fallback_primary: str,
    fallback_name: str,
    fallback_pdf: Path,
    fallback_tags: str,
    image_prefix: str,
):
    catalog = load_catalog(catalog_path)
    pres = (catalog or {}).get("presentation") or {}
    presentation_name = pres.get("name") or fallback_name
    pdf_rel = pres.get("pdf_path")
    pdf_path = PROJECT_ROOT / pdf_rel if pdf_rel else fallback_pdf
    if not pdf_path.exists():
        raise SystemExit(f"PDF not found: {pdf_path}")

    tags = pres.get("tags") or fallback_tags
    print(f"Resolving products for {presentation_name}...")
    primary_id, products_json = resolve_products(
        instance_url, headers, catalog, fallback_ext_ids, fallback_primary
    )
    alignments = slide_alignment_map(catalog, fallback_slides)

    print(f"Uploading {pdf_path}...")
    return upload_deck(
        instance_url,
        headers,
        pdf_path,
        presentation_name,
        primary_id,
        products_json,
        alignments,
        tags,
        image_prefix,
    )


def parse_args():
    parser = argparse.ArgumentParser(description="Upload Chemipharm + Soul Pharma CLMs only")
    parser.add_argument("--org", default=ORG_ALIAS)
    parser.add_argument("--chemipharm-only", action="store_true")
    parser.add_argument("--soul-only", action="store_true")
    parser.add_argument("--skip-deactivate", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()
    do_chemipharm = not args.soul_only
    do_soul = not args.chemipharm_only

    org = sf_org(args.org)
    instance_url = org["instanceUrl"]
    headers = {
        "Authorization": f"Bearer {org['accessToken']}",
        "Content-Type": "application/json",
    }

    keep = set(KEEP_ACTIVE_NAMES)
    replace_names: set[str] = set()
    if do_chemipharm:
        replace_names.add("Chemipharm Presentation Deck")
    if do_soul:
        replace_names.add("Soul Pharma Product Deck")

    if not args.skip_deactivate:
        print("Deactivating all CLMs except the two keep decks (and replacing prior uploads)...")
        deactivate_non_keep_decks(instance_url, headers, keep, also_deactivate_names=replace_names)

    if do_chemipharm:
        upload_from_catalog(
            instance_url,
            headers,
            CATALOGS["chemipharm"],
            CHEMIPHARM_FALLBACK_SLIDES,
            [
                "CPI_COLOVERIN_135",
                "CPI_COLOVERIN_D_135_40",
                "CPI_COLOVERIN_A_135_5",
                "CPI_COLOVERIN_SR_200",
                "CPI_VERSERC_16",
                "CPI_DANTRELAX_25",
                "CPI_DANTRELAX_COMPOUND_25_300",
                "CPI_ROSUVAST_10",
                "CPI_ALGESAL_10",
            ],
            "CPI_COLOVERIN_D_135_40",
            "Chemipharm Presentation Deck",
            PROJECT_ROOT / "Plan/Demo Slides/Chemipharm Presentation Deck.pdf",
            "Chemipharm;Coloverin;Verserc;Dantrelax;Rosuvast;Algesal",
            "chemipharm",
        )

    if do_soul:
        upload_from_catalog(
            instance_url,
            headers,
            CATALOGS["soul"],
            SOUL_FALLBACK_SLIDES,
            ["SOUL_SOULFORT_CAP_20", "SOUL_GENOLIGHT_CREAM"],
            "SOUL_SOULFORT_CAP_20",
            "Soul Pharma Product Deck",
            PROJECT_ROOT / "Plan/Demo Slides/Soul Pharma Product Deck.pdf",
            "Soul Pharma;Soulfort;Genolight;Consumer Health",
            "soul-pharma",
        )

    if not args.skip_deactivate:
        print("Final pass: ensure only Chemipharm + Soul Pharma remain Available...")
        deactivate_non_keep_decks(instance_url, headers, keep)

    print("Done. Active CLMs should be Chemipharm Presentation Deck + Soul Pharma Product Deck only.")


if __name__ == "__main__":
    main()
