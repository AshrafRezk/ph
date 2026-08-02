#!/usr/bin/env python3
"""Upload Empacoza CLM deck and replace duplicate presentations."""

import base64
import json
import re
import subprocess
import sys
from pathlib import Path

import requests

PDF_PATH = Path("/Users/ashrafrezk/Downloads/Empacoza Beyond Glycemic T2.pdf")
ORG_ALIAS = "pharma-prod"
PRESENTATION_NAME = "Empacoza Beyond Glycemic T2"
PRODUCT_ID = "01tHu00000ZD9D2IAL"


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
    text = data.decode("latin1", errors="ignore")
    pages = len(re.findall(r"/Type\s*/Page(?!s)", text))
    if pages:
        return pages
    max_count = 0
    for match in re.finditer(r"/Count\s+(\d+)", text):
        value = int(match.group(1))
        max_count = max(max_count, value)
    return max_count or 1


def deactivate_duplicates(instance_url, headers):
    soql = (
        "SELECT Id, Name, Status__c FROM CLM_Presentation__c "
        "WHERE Name LIKE '%Empacoza%Beyond Glycemic%' OR Name LIKE '%Empacoza Beyond Glycemic T2%'"
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


def upload_presentation(instance_url, headers, pdf_bytes: bytes, page_count: int):
    file_name = f"{PRESENTATION_NAME}.pdf"
    version = sf_create(
        instance_url,
        headers,
        "ContentVersion",
        {
            "Title": PRESENTATION_NAME,
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
            "Name": PRESENTATION_NAME,
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


def main():
    if not PDF_PATH.exists():
        print(f"PDF not found: {PDF_PATH}", file=sys.stderr)
        sys.exit(1)

    pdf_bytes = PDF_PATH.read_bytes()
    page_count = count_pdf_pages(pdf_bytes)
    print(f"PDF size={len(pdf_bytes)} pages={page_count}")

    org = sf_org()
    headers = {
        "Authorization": f"Bearer {org['accessToken']}",
        "Content-Type": "application/json",
    }
    instance_url = org["instanceUrl"]

    deactivate_duplicates(instance_url, headers)
    upload_presentation(instance_url, headers, pdf_bytes, page_count)
    print("Done.")


if __name__ == "__main__":
    main()
