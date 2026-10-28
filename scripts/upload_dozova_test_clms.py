#!/usr/bin/env python3
"""Replace all Available CLMs with one HTML and one PDF Dozova Man test deck.

Usage:
  python scripts/upload_dozova_test_clms.py
  python scripts/upload_dozova_test_clms.py --org ZetaPharma --dry-run
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import re
import subprocess
import zipfile
from pathlib import Path

import requests

try:
    import fitz  # pymupdf
except ImportError:
    fitz = None

ORG_ALIAS = "ZetaPharma"
API = "v64.0"
SKIP_SCENE_NAMES = {"master", "untitled scene", "untitled layout"}

DEFAULT_ZIP = Path("/Users/ashrafrezk/Downloads/Dozova Man.zip")
DEFAULT_PDF = Path(
    "/Users/ashrafrezk/.cursor/projects/Users-ashrafrezk-Salesforce-Projects-Zeta-Pharma"
    "/attachments/d24e840d-7730-4427-bf16-a9beee16c3e9/Dozova_Man_MAX_Brochure_Final.pdf"
)

HYPE_SCENE_RE = re.compile(r'\{n:"([^"]+)",o:"\d+",X:\[\d+\]\}')


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
        f"{instance_url}/services/data/{API}/query",
        headers=headers,
        params={"q": soql},
        timeout=180,
    )
    response.raise_for_status()
    return response.json()


def sf_create(instance_url, headers, sobject, payload):
    response = requests.post(
        f"{instance_url}/services/data/{API}/sobjects/{sobject}",
        headers=headers,
        json=payload,
        timeout=300,
    )
    if response.status_code >= 400:
        raise RuntimeError(f"create {sobject} failed: {response.status_code} {response.text[:800]}")
    return response.json()


def sf_update(instance_url, headers, sobject, record_id, payload):
    response = requests.patch(
        f"{instance_url}/services/data/{API}/sobjects/{sobject}/{record_id}",
        headers={**headers, "Content-Type": "application/json"},
        json=payload,
        timeout=180,
    )
    if response.status_code >= 400:
        raise RuntimeError(f"update {sobject} failed: {response.status_code} {response.text[:800]}")


def resolve_instance_url(org: dict) -> str:
    raw = (org.get("instanceUrl") or "").rstrip("/")
    if "force-agility-8950" in raw or "zetapharma" in raw.lower():
        return "https://zetapharma.my.salesforce.com"
    return raw


def upload_content_version(instance_url, token, title: str, path_on_client: str, data: bytes) -> str:
    boundary = "----ZetaClmBoundary7MA4YWxkTrZu0gW"
    meta = json.dumps({"Title": title, "PathOnClient": path_on_client})
    mime = mimetypes.guess_type(path_on_client)[0] or "application/octet-stream"
    safe_name = path_on_client.replace('"', "").replace("\r", "").replace("\n", "")
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="entity_content";\r\n'
        f"Content-Type: application/json\r\n\r\n"
        f"{meta}\r\n"
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="VersionData"; filename="{safe_name}"\r\n'
        f"Content-Type: {mime}\r\n\r\n"
    ).encode("utf-8") + data + f"\r\n--{boundary}--\r\n".encode("utf-8")

    response = requests.post(
        f"{instance_url}/services/data/{API}/sobjects/ContentVersion",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
        data=body,
        timeout=600,
        allow_redirects=True,
    )
    if response.status_code >= 400:
        raise RuntimeError(
            f"ContentVersion upload failed ({path_on_client}): "
            f"{response.status_code} {response.text[:1000]}"
        )
    return response.json()["id"]


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


def count_pdf_pages(data: bytes) -> int:
    if fitz is not None:
        with fitz.open(stream=data, filetype="pdf") as doc:
            return doc.page_count
    text = data.decode("latin1", errors="ignore")
    pages = len(re.findall(r"/Type\s*/Page(?!s)", text))
    return pages or 1


def find_html_entries(zip_path: Path) -> list[str]:
    with zipfile.ZipFile(zip_path) as zf:
        htmls = [
            n
            for n in zf.namelist()
            if n.lower().endswith((".html", ".htm"))
            and "__MACOSX" not in n
            and not Path(n).name.startswith(".")
            and not n.endswith("/")
        ]
    htmls.sort()
    return htmls


def parse_hype_scenes(zip_path: Path) -> list[str]:
    with zipfile.ZipFile(zip_path) as zf:
        names = [n for n in zf.namelist() if n.lower().endswith(".js") and "__MACOSX" not in n]
        generated = [n for n in names if "hype_generated_script" in n.lower()]
        for name in generated + names:
            try:
                text = zf.read(name).decode("utf-8", errors="ignore")
            except KeyError:
                continue
            scenes = [
                match.group(1)
                for match in HYPE_SCENE_RE.finditer(text)
                if match.group(1).strip().lower() not in SKIP_SCENE_NAMES
            ]
            # Keep first unique run of p1..pN style scenes when present.
            if scenes:
                seen = []
                for scene in scenes:
                    if scene not in seen:
                        seen.append(scene)
                return seen
    return []


def deactivate_all_available(instance_url, headers):
    records = sf_query(
        instance_url,
        headers,
        "SELECT Id, Name, Status__c FROM CLM_Presentation__c WHERE Status__c != 'Deactivated'",
    ).get("records", [])
    for record in records:
        sf_update(
            instance_url,
            headers,
            "CLM_Presentation__c",
            record["Id"],
            {"Status__c": "Deactivated"},
        )
        print(f"  deactivated {record['Id']} ({record['Name']})")
    print(f"Deactivated {len(records)} presentation(s)")


def upload_pdf_deck(instance_url, token, headers, pdf_path: Path):
    name = "Dozova Man PDF"
    pdf_bytes = pdf_path.read_bytes()
    page_count = count_pdf_pages(pdf_bytes)
    print(f"\n[PDF] {name} size={len(pdf_bytes)/1e6:.1f}MB pages={page_count}")

    version_id = upload_content_version(instance_url, token, name, "Dozova_Man_MAX_Brochure_Final.pdf", pdf_bytes)
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
            "Name": name,
            "Status__c": "Available",
            "Format__c": "PDF",
            "Slide_Count__c": page_count,
            "Content_Document_Id__c": content_document_id,
            "Allow_Unaligned__c": True,
            "Tags__c": "Zeta;PDF;Dozova;Test",
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
                "File_Name__c": pdf_path.name,
                "Page_Number__c": page,
            },
        )
    print(f"  created {presentation_id}")
    return presentation_id


def upload_html_deck(instance_url, token, headers, zip_path: Path):
    name = "Dozova Man HTML"
    entries = find_html_entries(zip_path)
    if not entries:
        raise RuntimeError(f"No HTML files found in {zip_path}")
    entry = entries[0]
    scenes = parse_hype_scenes(zip_path)
    slide_names = scenes or ["p1"]
    print(
        f"\n[HTML] {name} size={zip_path.stat().st_size/1e6:.1f}MB "
        f"entry={entry} scenes={len(slide_names)} {slide_names}"
    )

    zip_bytes = zip_path.read_bytes()
    version_id = upload_content_version(instance_url, token, name, "Dozova Man.zip", zip_bytes)
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
            "Name": name,
            "Status__c": "Available",
            "Format__c": "HTML",
            "Slide_Count__c": len(slide_names),
            "Content_Document_Id__c": content_document_id,
            "Allow_Unaligned__c": True,
            "Tags__c": "Zeta;HTML;Dozova;Test",
            "Player_Gesture__c": "Tap Bottom",
            "Pinch_Zoom__c": "Enabled",
            "Double_Tap_Zoom__c": "Enabled",
        },
    )
    presentation_id = presentation["id"]
    link_content_document(instance_url, headers, content_document_id, presentation_id)

    for index, scene in enumerate(slide_names, start=1):
        sf_create(
            instance_url,
            headers,
            "CLM_Sequence__c",
            {
                "CLM_Presentation__c": presentation_id,
                "Sequence_Order__c": index,
                "Sequence_Name__c": scene,
                "Name": scene[:80],
                "File_Name__c": zip_path.name,
                "Page_Number__c": index,
                "HTML_Entry_Point__c": entry,
            },
        )
    print(f"  created {presentation_id}")
    return presentation_id


def parse_args():
    parser = argparse.ArgumentParser(description="Replace CLMs with Dozova Man HTML + PDF test decks")
    parser.add_argument("--org", default=ORG_ALIAS)
    parser.add_argument("--zip", type=Path, default=DEFAULT_ZIP)
    parser.add_argument("--pdf", type=Path, default=DEFAULT_PDF)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()
    if not args.zip.exists():
        raise SystemExit(f"HTML zip not found: {args.zip}")
    if not args.pdf.exists():
        raise SystemExit(f"PDF not found: {args.pdf}")

    html_entries = find_html_entries(args.zip)
    scenes = parse_hype_scenes(args.zip)
    pdf_pages = count_pdf_pages(args.pdf.read_bytes())
    print(f"HTML zip: {args.zip}")
    print(f"  entries={html_entries}")
    print(f"  hype scenes={scenes}")
    print(f"PDF: {args.pdf} pages={pdf_pages} size={args.pdf.stat().st_size/1e6:.1f}MB")

    if args.dry_run:
        return

    org = sf_org(args.org)
    instance_url = resolve_instance_url(org)
    token = org["accessToken"]
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    print(f"Org instance: {instance_url}")

    deactivate_all_available(instance_url, headers)
    pdf_id = upload_pdf_deck(instance_url, token, headers, args.pdf)
    html_id = upload_html_deck(instance_url, token, headers, args.zip)

    available = sf_query(
        instance_url,
        headers,
        "SELECT Id, Name, Format__c, Slide_Count__c, Status__c, Content_Document_Id__c "
        "FROM CLM_Presentation__c WHERE Status__c = 'Available' ORDER BY Format__c, Name",
    ).get("records", [])
    print("\n==== Available CLMs ====")
    for row in available:
        print(
            f"  [{row.get('Format__c')}] slides={row.get('Slide_Count__c')} "
            f"{row.get('Name')} ({row.get('Id')}) doc={row.get('Content_Document_Id__c')}"
        )
    print(f"PDF presentation: {pdf_id}")
    print(f"HTML presentation: {html_id}")
    if len(available) != 2:
        raise SystemExit(f"Expected exactly 2 available CLMs, found {len(available)}")


if __name__ == "__main__":
    main()
