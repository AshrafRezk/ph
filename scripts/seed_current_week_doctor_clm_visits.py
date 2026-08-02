#!/usr/bin/env python3
"""Seed five completed HCP visits with product details and completed CLM sessions.

Each record is created through REST as a separate Salesforce transaction. This
keeps the org's visit automation within per-transaction SOQL governor limits.
"""

from __future__ import annotations

import argparse
import json
import subprocess
from datetime import date, datetime, time, timedelta, timezone

import requests


VISITS = [
    {
        "doctor": "Magdi Yacoub 240",
        "specialty": "Tropical_Medicine",
        "username": "git.mr@pharma.demo",
        "product_external_id": "CPI_COLOVERIN_D_135_40",
        "products": "Coloverin D; Coloverin SR",
        "details": "Targeted IBS antispasmodic efficacy, rapid bloating relief, and anticholinergic safety.",
        "deck": "Chemipharm Presentation Deck",
        "slides": [3, 4],
        "clm_picklist": "CLM1",
    },
    {
        "doctor": "Heba Mohamed 182",
        "specialty": "Geriatrics",
        "username": "diabetes.mr@pharma.demo",
        "product_external_id": "CPI_VERSERC_16",
        "products": "Verserc 16 mg",
        "details": "Vertigo symptom control and preserved daytime alertness without cognitive sedation.",
        "deck": "Chemipharm Presentation Deck",
        "slides": [5],
        "clm_picklist": "CLM1",
    },
    {
        "doctor": "Ahmed Ibrahim",
        "specialty": "Orthopaedics",
        "username": "cluster.mr@pharma.demo",
        "product_external_id": "CPI_DANTRELAX_25",
        "products": "Dantrelax; Algesal Suractive",
        "details": "Muscle-spasm relief, reduced daytime drowsiness, and topical analgesia positioning.",
        "deck": "Chemipharm Presentation Deck",
        "slides": [6, 7, 9],
        "clm_picklist": "CLM1",
    },
    {
        "doctor": "Rania Nasser 186",
        "specialty": "Cardiology",
        "username": "cardio.mr@pharma.demo",
        "product_external_id": "CPI_ROSUVAST_10",
        "products": "Rosuvast 10 mg",
        "details": "LDL-C reduction, target attainment, dosing, and cardiovascular safety monitoring.",
        "deck": "Chemipharm Presentation Deck",
        "slides": [8],
        "clm_picklist": "CLM1",
    },
    {
        "doctor": "Salma Ali 303",
        "specialty": "Esthetics_and_Cosmetology",
        "username": "chc.mr@pharma.demo",
        "product_external_id": "SOUL_SOULFORT_CAP_20",
        "products": "Soulfort; Genolight",
        "details": "Daily immunity and energy support plus Genolight pigmentation efficacy and safe application.",
        "deck": "Soul Pharma Product Deck",
        "slides": [3, 4, 5, 6],
        "clm_picklist": "CLM2",
    },
]


def org_auth(alias: str) -> tuple[str, dict[str, str]]:
    raw = subprocess.check_output(
        ["sf", "org", "display", "--target-org", alias, "--json"], text=True
    )
    org = json.loads(raw)["result"]
    return (
        org["instanceUrl"] + "/services/data/v67.0",
        {
            "Authorization": f"Bearer {org['accessToken']}",
            "Content-Type": "application/json",
        },
    )


def query(base: str, headers: dict[str, str], soql: str) -> list[dict]:
    response = requests.get(
        base + "/query", headers=headers, params={"q": soql}, timeout=120
    )
    response.raise_for_status()
    return response.json()["records"]


def create(base: str, headers: dict[str, str], obj: str, payload: dict) -> str:
    response = requests.post(
        base + f"/sobjects/{obj}", headers=headers, json=payload, timeout=120
    )
    if response.status_code >= 300:
        raise RuntimeError(f"{obj} create failed: {response.status_code} {response.text}")
    return response.json()["id"]


def update(
    base: str, headers: dict[str, str], obj: str, record_id: str, payload: dict
) -> None:
    response = requests.patch(
        base + f"/sobjects/{obj}/{record_id}",
        headers=headers,
        json=payload,
        timeout=120,
    )
    if response.status_code >= 300:
        raise RuntimeError(f"{obj} update failed: {response.status_code} {response.text}")


def delete(base: str, headers: dict[str, str], obj: str, record_id: str) -> None:
    response = requests.delete(
        base + f"/sobjects/{obj}/{record_id}", headers=headers, timeout=120
    )
    if response.status_code not in (204, 404):
        raise RuntimeError(f"{obj} delete failed: {response.status_code} {response.text}")


def soql_quote(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "\\'")


def iso_at(day: date, hour: int, minute: int = 0) -> str:
    value = datetime.combine(day, time(hour, minute), tzinfo=timezone.utc)
    return value.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--org", default="pharma-prod")
    args = parser.parse_args()
    base, headers = org_auth(args.org)
    today = date.today()

    # Replace all visits in the current Salesforce week.
    old_visits = query(
        base,
        headers,
        "SELECT Id FROM Visit__c WHERE Visit_Date__c = THIS_WEEK",
    )
    old_ids = [row["Id"] for row in old_visits]
    if old_ids:
        ids = ",".join(f"'{record_id}'" for record_id in old_ids)
        old_sessions = query(
            base,
            headers,
            f"SELECT Id FROM CLM_Presentation_Session__c WHERE Visit__c IN ({ids})",
        )
        for session in old_sessions:
            delete(base, headers, "CLM_Presentation_Session__c", session["Id"])
        for visit in old_visits:
            delete(base, headers, "Visit__c", visit["Id"])

    deck_names = {item["deck"] for item in VISITS}
    quoted_decks = ",".join(f"'{soql_quote(name)}'" for name in deck_names)
    decks = query(
        base,
        headers,
        "SELECT Id, Name FROM CLM_Presentation__c "
        f"WHERE Name IN ({quoted_decks}) AND Status__c = 'Available'",
    )
    decks_by_name = {row["Name"]: row for row in decks}

    product_ext_ids = {item["product_external_id"] for item in VISITS}
    quoted_products = ",".join(f"'{value}'" for value in product_ext_ids)
    products = query(
        base,
        headers,
        "SELECT Id, Name, External_ID__c FROM Product2 "
        f"WHERE External_ID__c IN ({quoted_products}) AND IsActive = true",
    )
    products_by_ext = {row["External_ID__c"]: row for row in products}

    usernames = {item["username"] for item in VISITS}
    quoted_users = ",".join(f"'{value}'" for value in usernames)
    users = query(
        base,
        headers,
        f"SELECT Id, Username FROM User WHERE Username IN ({quoted_users}) AND IsActive = true",
    )
    users_by_name = {row["Username"]: row for row in users}

    doctor_names = {item["doctor"] for item in VISITS}
    quoted_doctors = ",".join(f"'{soql_quote(value)}'" for value in doctor_names)
    doctors = query(
        base,
        headers,
        "SELECT Id, Name, Specialty_1__c FROM Account "
        f"WHERE Name IN ({quoted_doctors}) "
        "AND RecordType.DeveloperName = 'SDO_PersonAccounts'",
    )
    doctors_by_name = {row["Name"]: row for row in doctors}

    for item in VISITS:
        doctor = doctors_by_name.get(item["doctor"])
        rep = users_by_name.get(item["username"])
        product = products_by_ext.get(item["product_external_id"])
        deck = decks_by_name.get(item["deck"])
        if not all((doctor, rep, product, deck)):
            raise RuntimeError(f"Missing seed dependency for {item}")
        if doctor.get("Specialty_1__c") != item["specialty"]:
            update(
                base,
                headers,
                "Account",
                doctor["Id"],
                {"Specialty_1__c": item["specialty"]},
            )

    sequence_rows = query(
        base,
        headers,
        "SELECT Id, CLM_Presentation__c, Sequence_Order__c, Sequence_Name__c, "
        "Product_Names__c, Message_Names__c FROM CLM_Sequence__c "
        f"WHERE CLM_Presentation__c IN ({','.join(repr(row['Id']) for row in decks)})",
    )
    sequences = {
        (row["CLM_Presentation__c"], int(row["Sequence_Order__c"])): row
        for row in sequence_rows
    }

    for index, item in enumerate(VISITS):
        doctor = doctors_by_name[item["doctor"]]
        rep = users_by_name[item["username"]]
        product = products_by_ext[item["product_external_id"]]
        deck = decks_by_name[item["deck"]]
        start = iso_at(today, 9 + index)
        end = iso_at(today, 9 + index, 40)

        visit_id = create(
            base,
            headers,
            "Visit__c",
            {
                "Account__c": doctor["Id"],
                "Assigned_To__c": rep["Id"],
                "Start_Date__c": start,
                "End_Date__c": end,
                "Visit_Date__c": start,
                "Status__c": "Completed",
                "Visit_Type__c": "Planned (Automatically)",
                "Visit_Objective__c": "Clinical detailing and product-message discussion",
                "Products_Discussed__c": item["products"],
                "Product_Details__c": item["details"],
                "Visit_Notes__c": "Doctor engaged with the evidence and agreed on an appropriate patient profile.",
                "Next_Visit_Date__c": (today + timedelta(days=14)).isoformat(),
                "CLM_Presentation__c": item["clm_picklist"],
            },
        )
        create(
            base,
            headers,
            "Visit_Product_Detail__c",
            {
                "Visit__c": visit_id,
                "Product2__c": product["Id"],
                "Detail_Type__c": "Detail",
                "Display_Order__c": 1,
                "Notes__c": item["details"],
            },
        )

        duration = 75 * len(item["slides"])
        session_start = iso_at(today, 9 + index, 5)
        session_end_dt = datetime.fromisoformat(
            session_start.replace("Z", "+00:00")
        ) + timedelta(seconds=duration)
        session_id = create(
            base,
            headers,
            "CLM_Presentation_Session__c",
            {
                "Visit__c": visit_id,
                "Account__c": doctor["Id"],
                "User__c": rep["Id"],
                "CLM_Presentation__c": deck["Id"],
                "Status__c": "Completed",
                "Started_At__c": session_start,
                "Ended_At__c": session_end_dt.isoformat(timespec="milliseconds").replace(
                    "+00:00", "Z"
                ),
                "Slides_Presented_Count__c": len(item["slides"]),
                "Total_Duration_Seconds__c": duration,
                "Tracking_Paused__c": False,
                "Client_Session_Key__c": f"DEMO-{today.isoformat()}-{index + 1}",
            },
        )

        for order, slide_number in enumerate(item["slides"], start=1):
            sequence = sequences[(deck["Id"], slide_number)]
            viewed_at = datetime.fromisoformat(
                session_start.replace("Z", "+00:00")
            ) + timedelta(seconds=(order - 1) * 75)
            create(
                base,
                headers,
                "CLM_Slide_Metric__c",
                {
                    "CLM_Presentation_Session__c": session_id,
                    "CLM_Sequence__c": sequence["Id"],
                    "Sequence_Order__c": sequence["Sequence_Order__c"],
                    "Sequence_Name__c": sequence.get("Sequence_Name__c"),
                    "Dwell_Time_Seconds__c": 75,
                    "First_Viewed_At__c": viewed_at.isoformat(
                        timespec="milliseconds"
                    ).replace("+00:00", "Z"),
                    "Last_Viewed_At__c": (
                        viewed_at + timedelta(seconds=75)
                    ).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
                    "Was_Presented__c": True,
                },
            )
            create(
                base,
                headers,
                "CLM_Message_Response__c",
                {
                    "CLM_Presentation_Session__c": session_id,
                    "Product_Name__c": sequence.get("Product_Names__c"),
                    "Message_Name__c": sequence.get("Message_Names__c"),
                    "Sentiment__c": "Positive",
                    "Sort_Order__c": order,
                },
            )
        print(
            f"Created completed visit for {doctor['Name']} / {rep['Username']} / "
            f"{deck['Name']} ({len(item['slides'])} slides)"
        )

    print("Seeded 5 completed HCP visits with detailing and completed CLM activity.")


if __name__ == "__main__":
    main()
