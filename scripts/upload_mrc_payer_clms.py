#!/usr/bin/env python3
"""Seed MRC products and upload payer PDF CLM decks bound to MRC Product2 records.

Usage:
  python scripts/upload_mrc_payer_clms.py
  python scripts/upload_mrc_payer_clms.py --skip-seed
  python scripts/upload_mrc_payer_clms.py --dry-run
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
import yaml

try:
    import fitz  # pymupdf
except ImportError:
    fitz = None

PROJECT_ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = PROJECT_ROOT / "Plan/mrc_payer_clm_catalog.yaml"
PDF_DIR = PROJECT_ROOT / "Plan/Demo Slides/MRC"
ORG_ALIAS = "pharma-prod"
PNG_SCALE = 1.5


def load_catalog() -> dict:
    with CATALOG_PATH.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def presentation_name(payer_name: str, service_name: str) -> str:
    return f"{payer_name} — {service_name} Coverage Overview"


def sf_org():
    result = subprocess.run(
        ["sf", "org", "display", "--target-org", ORG_ALIAS, "--json"],
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


def seed_mrc_products():
    print("Seeding MRC products via Apex...")
    apex_file = PROJECT_ROOT / ".tmp-apex/seed-mrc-products.apex"
    apex_file.parent.mkdir(parents=True, exist_ok=True)
    apex_file.write_text(
        "MrcProductCatalogService.CatalogResult r = MrcProductCatalogService.seedMrcCatalog();\n"
        "System.debug(r.message);\n",
        encoding="utf-8",
    )
    result = subprocess.run(
        ["sf", "apex", "run", "--target-org", ORG_ALIAS, "--file", str(apex_file)],
        capture_output=True,
        text=True,
        check=True,
    )
    print(result.stdout.strip() or "  Seed complete.")


def load_product_ids(instance_url, headers, external_ids: list[str]) -> dict[str, str]:
    ids_clause = "', '".join(external_ids)
    records = sf_query(
        instance_url,
        headers,
        f"SELECT Id, External_ID__c, Name FROM Product2 WHERE External_ID__c IN ('{ids_clause}')",
    ).get("records", [])
    return {record["External_ID__c"]: record for record in records}


def count_pdf_pages(data: bytes) -> int:
    if fitz is not None:
        with fitz.open(stream=data, filetype="pdf") as doc:
            return doc.page_count
    text = data.decode("latin1", errors="ignore")
    pages = len(re.findall(r"/Type\s*/Page(?!s)", text))
    if pages:
        return pages
    max_count = 0
    for match in re.finditer(r"/Count\s+(\d+)", text):
        value = int(match.group(1))
        max_count = max(max_count, value)
    return max_count or 1


def render_slide_pngs(pdf_bytes: bytes, page_count: int) -> list[tuple[int, bytes]]:
    if fitz is None:
        raise RuntimeError("pymupdf is required. Run: pip install pymupdf pyyaml")

    images: list[tuple[int, bytes]] = []
    with fitz.open(stream=pdf_bytes, filetype="pdf") as doc:
        total = min(page_count, doc.page_count)
        for page_num in range(1, total + 1):
            page = doc.load_page(page_num - 1)
            matrix = fitz.Matrix(PNG_SCALE, PNG_SCALE)
            pix = page.get_pixmap(matrix=matrix, alpha=False)
            images.append((page_num, pix.tobytes("png")))
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


def deactivate_existing(instance_url, headers, presentation_name_value: str):
    escaped = presentation_name_value.replace("'", "\\'")
    records = sf_query(
        instance_url,
        headers,
        (
            "SELECT Id, Name, Status__c FROM CLM_Presentation__c "
            f"WHERE Name = '{escaped}' AND Status__c != 'Deactivated'"
        ),
    ).get("records", [])
    for record in records:
        sf_update(
            instance_url,
            headers,
            "CLM_Presentation__c",
            record["Id"],
            {"Status__c": "Deactivated"},
        )
        print(f"  Deactivated {record['Id']} ({record['Name']})")


def attach_slide_images(
    instance_url,
    headers,
    presentation_id: str,
    slide_images: list[tuple[int, bytes]],
):
    records = sf_query(
        instance_url,
        headers,
        (
            "SELECT Id, Page_Number__c, Sequence_Order__c "
            "FROM CLM_Sequence__c "
            f"WHERE CLM_Presentation__c = '{presentation_id}' "
            "ORDER BY Sequence_Order__c ASC"
        ),
    ).get("records", [])
    by_page: dict[int, dict] = {}
    for record in records:
        page_number = record.get("Page_Number__c") or record.get("Sequence_Order__c")
        if page_number is not None:
            by_page[int(page_number)] = record

    for page_number, png_bytes in slide_images:
        sequence = by_page.get(page_number)
        if sequence is None:
            continue
        image_name = f"slide-{page_number}.png"
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


def upload_presentation(
    instance_url,
    headers,
    pdf_bytes: bytes,
    page_count: int,
    deck_name: str,
    product_id: str,
    product_name: str,
    tags: str,
) -> str:
    file_name = f"{deck_name}.pdf"
    products_json = json.dumps(
        {"productIds": [product_id], "productNames": [product_name]},
        separators=(",", ":"),
    )

    version = sf_create(
        instance_url,
        headers,
        "ContentVersion",
        {
            "Title": deck_name,
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
            "Name": deck_name,
            "Status__c": "Available",
            "Format__c": "PDF",
            "Slide_Count__c": page_count,
            "Content_Document_Id__c": content_document_id,
            "Product__c": product_id,
            "Products__c": products_json,
            "Tags__c": tags,
            "Allow_Unaligned__c": True,
            "Player_Gesture__c": "Tap Bottom",
            "Pinch_Zoom__c": "Enabled",
            "Double_Tap_Zoom__c": "Enabled",
        },
    )
    presentation_id = presentation["id"]
    link_content_document(instance_url, headers, content_document_id, presentation_id)

    for page in range(1, page_count + 1):
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
                "Product_Names__c": product_name,
            },
        )

    slide_images = render_slide_pngs(pdf_bytes, page_count)
    attach_slide_images(instance_url, headers, presentation_id, slide_images)
    return presentation_id


def ensure_pdfs():
    if not PDF_DIR.exists() or not any(PDF_DIR.glob("*.pdf")):
        print("Generating PDF decks...")
        subprocess.run(
            [sys.executable, str(PROJECT_ROOT / "scripts/generate_mrc_payer_clm_pdfs.py")],
            check=True,
        )


def parse_args():
    parser = argparse.ArgumentParser(description="Upload MRC payer CLM PDF decks")
    parser.add_argument("--skip-seed", action="store_true", help="Skip MRC product seeding")
    parser.add_argument("--dry-run", action="store_true", help="List decks without uploading")
    parser.add_argument("--org", default=ORG_ALIAS, help="Salesforce org alias")
    return parser.parse_args()


def main():
    if fitz is None:
        print("pymupdf is required. Run: pip install pymupdf pyyaml requests", file=sys.stderr)
        sys.exit(1)

    args = parse_args()
    global ORG_ALIAS
    ORG_ALIAS = args.org

    catalog = load_catalog()
    ensure_pdfs()

    decks: list[dict] = []
    for payer in catalog["payers"]:
        for product in catalog["products"]:
            deck_name = presentation_name(payer["name"], product["name"])
            safe_name = deck_name.replace("—", "-").replace("/", "-")
            pdf_path = PDF_DIR / f"{safe_name}.pdf"
            tags = catalog["clm"]["tags_template"].format(
                payer_tag=payer["tag"],
                service_key=product["service_key"],
            )
            decks.append(
                {
                    "deck_name": deck_name,
                    "pdf_path": pdf_path,
                    "external_id": product["external_id"],
                    "product_name": product["name"],
                    "tags": tags,
                }
            )

    if args.dry_run:
        for deck in decks:
            print(f"[dry-run] {deck['deck_name']} -> {deck['external_id']} ({deck['pdf_path']})")
        print(f"{len(decks)} decks ready.")
        return

    org = sf_org()
    headers = {
        "Authorization": f"Bearer {org['accessToken']}",
        "Content-Type": "application/json",
    }
    instance_url = org["instanceUrl"]

    if not args.skip_seed:
        seed_mrc_products()

    external_ids = [product["external_id"] for product in catalog["products"]]
    products_by_ext = load_product_ids(instance_url, headers, external_ids)
    missing = [ext for ext in external_ids if ext not in products_by_ext]
    if missing:
        print(f"Missing products after seed: {missing}", file=sys.stderr)
        sys.exit(1)

    uploaded = 0
    for deck in decks:
        if not deck["pdf_path"].exists():
            print(f"PDF missing, skipping: {deck['pdf_path']}", file=sys.stderr)
            continue

        product = products_by_ext[deck["external_id"]]
        pdf_bytes = deck["pdf_path"].read_bytes()
        page_count = count_pdf_pages(pdf_bytes)
        print(f"Uploading {deck['deck_name']} ({page_count} pages) -> {product['Name']}")

        deactivate_existing(instance_url, headers, deck["deck_name"])
        presentation_id = upload_presentation(
            instance_url,
            headers,
            pdf_bytes,
            page_count,
            deck["deck_name"],
            product["Id"],
            product["Name"],
            deck["tags"],
        )
        print(f"  Created CLM_Presentation__c {presentation_id}")
        uploaded += 1

    print(f"Done. Uploaded {uploaded} MRC payer CLM decks.")


if __name__ == "__main__":
    main()
