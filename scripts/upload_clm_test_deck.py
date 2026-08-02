#!/usr/bin/env python3
"""Upload CLM presentation deck with PNG slide previews.

Usage:
  python scripts/upload_clm_test_deck.py
  python scripts/upload_clm_test_deck.py --patch-presentation-id <id>
  python scripts/upload_clm_test_deck.py --patch-name "Empacoza Beyond Glycemic T2"
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

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PDF_PATH = PROJECT_ROOT / "Plan/Demo Slides/Empacoza Beyond Glycemic T2.pdf"
ORG_ALIAS = "pharma-prod"
DEFAULT_PRESENTATION_NAME = "CURSOR TEST - CLM Debug Deck"
PRODUCT_ID = "01tHu00000ZD9D2IAL"
PNG_SCALE = 1.5


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
        raise RuntimeError("pymupdf is required. Run: pip install pymupdf")

    images: list[tuple[int, bytes]] = []
    with fitz.open(stream=pdf_bytes, filetype="pdf") as doc:
        total = min(page_count, doc.page_count)
        for page_num in range(1, total + 1):
            page = doc.load_page(page_num - 1)
            matrix = fitz.Matrix(PNG_SCALE, PNG_SCALE)
            pix = page.get_pixmap(matrix=matrix, alpha=False)
            images.append((page_num, pix.tobytes("png")))
            print(f"  Rendered slide {page_num}/{total}")
    return images


def build_slide_image_url(content_version_id: str) -> str:
    return (
        "/sfc/servlet.shepherd/version/renditionDownload"
        f"?rendition=ORIGINAL_Png&versionId={content_version_id}"
    )


def deactivate_by_name(instance_url, headers, presentation_name: str):
    soql = (
        "SELECT Id, Name, Status__c FROM CLM_Presentation__c "
        f"WHERE Name = '{presentation_name.replace(chr(39), chr(92)+chr(39))}'"
    )
    records = sf_query(instance_url, headers, soql).get("records", [])
    for record in records:
        if record.get("Status__c") == "Deactivated":
            continue
        sf_update(
            instance_url,
            headers,
            "CLM_Presentation__c",
            record["Id"],
            {"Status__c": "Deactivated"},
        )
        print(f"Deactivated {record['Id']} ({record['Name']})")


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


def upload_presentation(
    instance_url,
    headers,
    pdf_bytes: bytes,
    page_count: int,
    presentation_name: str,
) -> tuple[str, str]:
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
            "Product__c": PRODUCT_ID,
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
            },
        )

    print(f"Created presentation {presentation_id}")
    print(f"ContentDocumentId {content_document_id}")
    print(f"Pages {page_count}")
    return presentation_id, content_document_id


def get_sequences_by_page(instance_url, headers, presentation_id: str) -> dict[int, dict]:
    records = sf_query(
        instance_url,
        headers,
        (
            "SELECT Id, Sequence_Order__c, Page_Number__c, Slide_Image_URL__c "
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
    return by_page


def attach_slide_images(
    instance_url,
    headers,
    presentation_id: str,
    slide_images: list[tuple[int, bytes]],
):
    sequences_by_page = get_sequences_by_page(instance_url, headers, presentation_id)
    attached = 0
    for page_number, png_bytes in slide_images:
        sequence = sequences_by_page.get(page_number)
        if sequence is None:
            print(f"  Skipping page {page_number}: no CLM_Sequence__c")
            continue
        if sequence.get("Slide_Image_URL__c"):
            print(f"  Skipping page {page_number}: already has slide image")
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
        attached += 1
        print(f"  Attached slide image for page {page_number}")
    print(f"Attached {attached} slide images")


def resolve_presentation(instance_url, headers, presentation_id: str | None, presentation_name: str | None):
    if presentation_id:
        records = sf_query(
            instance_url,
            headers,
            (
                "SELECT Id, Name, Content_Document_Id__c "
                "FROM CLM_Presentation__c "
                f"WHERE Id = '{presentation_id}'"
            ),
        ).get("records", [])
        if not records:
            raise RuntimeError(f"Presentation not found: {presentation_id}")
        return records[0]

    if not presentation_name:
        raise RuntimeError("Provide --patch-presentation-id or --patch-name")

    escaped = presentation_name.replace("'", "\\'")
    records = sf_query(
        instance_url,
        headers,
        (
            "SELECT Id, Name, Content_Document_Id__c "
            "FROM CLM_Presentation__c "
            f"WHERE Name = '{escaped}' AND Status__c = 'Available' "
            "ORDER BY CreatedDate DESC LIMIT 1"
        ),
    ).get("records", [])
    if not records:
        records = sf_query(
            instance_url,
            headers,
            (
                "SELECT Id, Name, Content_Document_Id__c "
                "FROM CLM_Presentation__c "
                f"WHERE Name LIKE '%{escaped}%' "
                "ORDER BY CreatedDate DESC LIMIT 1"
            ),
        ).get("records", [])
    if not records:
        raise RuntimeError(f"Presentation not found by name: {presentation_name}")
    return records[0]


def decode_version_data(version_data: str) -> bytes:
    padded = version_data + ("=" * (-len(version_data) % 4))
    return base64.b64decode(padded)


def download_presentation_pdf(instance_url, headers, content_document_id: str) -> bytes:
    records = sf_query(
        instance_url,
        headers,
        (
            "SELECT VersionData FROM ContentVersion "
            f"WHERE ContentDocumentId = '{content_document_id}' AND IsLatest = true "
            "LIMIT 1"
        ),
    ).get("records", [])
    if not records or not records[0].get("VersionData"):
        raise RuntimeError(f"Unable to download PDF for ContentDocument {content_document_id}")
    return decode_version_data(records[0]["VersionData"])


def parse_args():
    parser = argparse.ArgumentParser(description="Upload CLM deck with PNG slide previews")
    parser.add_argument(
        "--pdf-path",
        type=Path,
        default=DEFAULT_PDF_PATH,
        help="Path to source PDF",
    )
    parser.add_argument(
        "--presentation-name",
        default=DEFAULT_PRESENTATION_NAME,
        help="CLM_Presentation__c name for new uploads",
    )
    parser.add_argument(
        "--patch-presentation-id",
        help="Existing presentation Id to backfill slide images only",
    )
    parser.add_argument(
        "--patch-name",
        help="Existing presentation name to backfill slide images only",
    )
    parser.add_argument(
        "--skip-deactivate",
        action="store_true",
        help="Do not deactivate prior decks with the same name",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    if fitz is None:
        print("pymupdf is required. Run: pip install pymupdf", file=sys.stderr)
        sys.exit(1)

    org = sf_org()
    headers = {
        "Authorization": f"Bearer {org['accessToken']}",
        "Content-Type": "application/json",
    }
    instance_url = org["instanceUrl"]

    if args.patch_presentation_id or args.patch_name:
        presentation = resolve_presentation(
            instance_url,
            headers,
            args.patch_presentation_id,
            args.patch_name,
        )
        presentation_id = presentation["Id"]
        content_document_id = presentation["Content_Document_Id__c"]
        print(f"Patching presentation {presentation_id} ({presentation['Name']})")
        if args.pdf_path.exists():
            pdf_bytes = args.pdf_path.read_bytes()
            print(f"Using local PDF: {args.pdf_path}")
        else:
            pdf_bytes = download_presentation_pdf(instance_url, headers, content_document_id)
        page_count = count_pdf_pages(pdf_bytes)
        print(f"PDF size={len(pdf_bytes)} pages={page_count}")
        print("Rendering PNG previews...")
        slide_images = render_slide_pngs(pdf_bytes, page_count)
        print("Uploading slide images...")
        attach_slide_images(instance_url, headers, presentation_id, slide_images)
        print("Patch complete.")
        return

    pdf_path = args.pdf_path
    if not pdf_path.exists():
        print(f"PDF not found: {pdf_path}", file=sys.stderr)
        sys.exit(1)

    pdf_bytes = pdf_path.read_bytes()
    page_count = count_pdf_pages(pdf_bytes)
    print(f"PDF size={len(pdf_bytes)} pages={page_count} name={args.presentation_name}")

    if not args.skip_deactivate:
        deactivate_by_name(instance_url, headers, args.presentation_name)

    presentation_id, _content_document_id = upload_presentation(
        instance_url,
        headers,
        pdf_bytes,
        page_count,
        args.presentation_name,
    )

    print("Rendering PNG previews...")
    slide_images = render_slide_pngs(pdf_bytes, page_count)
    print("Uploading slide images...")
    attach_slide_images(instance_url, headers, presentation_id, slide_images)
    print("Done.")


if __name__ == "__main__":
    main()
