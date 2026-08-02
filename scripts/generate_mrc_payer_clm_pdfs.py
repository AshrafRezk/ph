#!/usr/bin/env python3
"""Generate payer-specific MRC CLM PDF decks from Plan/mrc_payer_clm_catalog.yaml."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml

try:
    import fitz  # pymupdf
except ImportError:
    fitz = None

PROJECT_ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = PROJECT_ROOT / "Plan/mrc_payer_clm_catalog.yaml"
OUTPUT_DIR = PROJECT_ROOT / "Plan/Demo Slides/MRC"

PAGE_WIDTH = 960
PAGE_HEIGHT = 540

PAYER_COLORS = {
    "axa": (0, 0, 0.56),
    "metlife": (0, 0.48, 0.24),
}

SERVICE_CONTENT = {
    "mri": {
        "headline": "Advanced MRI Diagnostics",
        "overview": [
            "High-field MRI for neurological, musculoskeletal, abdominal, and oncologic imaging.",
            "Same-day scheduling for urgent cases with dedicated neuroradiology review.",
            "Contrast protocols aligned with international safety guidelines.",
        ],
        "coverage": [
            "In-network coverage for medically indicated MRI studies.",
            "Pre-authorization required for elective and contrast-enhanced scans.",
            "Member co-pay applies per plan tier; direct billing available.",
        ],
        "preauth": [
            "Submit clinical indication, prior imaging, and referring physician details.",
            "Turnaround: 24–48 hours for standard requests; same-day for emergencies.",
            "MRC provides payer-ready reports and DICOM access on request.",
        ],
    },
    "ct_scan": {
        "headline": "Multi-Slice CT Imaging",
        "overview": [
            "Low-dose CT for trauma, oncology, vascular, and chest imaging.",
            "Rapid throughput for emergency and inpatient referrals.",
            "3D reconstruction and specialist reporting included.",
        ],
        "coverage": [
            "Covered for trauma, oncology staging, and documented clinical indications.",
            "Pre-auth required for elective whole-body and repeat studies.",
            "Package pricing available for oncology follow-up pathways.",
        ],
        "preauth": [
            "Referral letter with ICD-10 diagnosis and clinical question required.",
            "Prior CT comparison reports accelerate approval.",
            "MRC coordinates directly with payer medical review teams.",
        ],
    },
    "pet_ct": {
        "headline": "PET/CT Hybrid Imaging",
        "overview": [
            "Oncology restaging, treatment response, and metabolic mapping.",
            "FDG and specialty tracers per oncologist protocol.",
            "Multidisciplinary tumor board support available.",
        ],
        "coverage": [
            "Covered for approved oncology indications per payer formulary.",
            "Pre-authorization mandatory; staging vs restaging rules apply.",
            "Limited annual sessions may apply — verify member benefits.",
        ],
        "preauth": [
            "Oncology referral, histopathology, and prior imaging required.",
            "MRC provides standardized PET/CT justification templates.",
            "Expedited review for progression-of-disease cases.",
        ],
    },
    "ultrasound": {
        "headline": "Diagnostic Ultrasound",
        "overview": [
            "Abdominal, pelvic, vascular, thyroid, and musculoskeletal studies.",
            "Same-day walk-in slots for urgent referrals.",
            "Pediatric and women's health protocols available.",
        ],
        "coverage": [
            "Broad coverage for diagnostic ultrasound with valid referral.",
            "Screening studies may require additional pre-auth.",
            "Competitive panel rates for employer groups.",
        ],
        "preauth": [
            "Referral with clinical indication sufficient for most studies.",
            "High-risk pregnancy and vascular duplex may need pre-approval.",
            "MRC issues itemized invoices for payer reconciliation.",
        ],
    },
    "breast_imaging": {
        "headline": "Breast Imaging & Mammography",
        "overview": [
            "Digital mammography for screening and diagnostic workup.",
            "Tomosynthesis and ultrasound correlation when indicated.",
            "BI-RADS reporting with rapid specialist follow-up.",
        ],
        "coverage": [
            "Annual screening mammography covered per preventive benefits.",
            "Diagnostic mammography and ultrasound require referral.",
            "High-risk surveillance pathways supported with payer packages.",
        ],
        "preauth": [
            "Screening: member ID and eligibility check at registration.",
            "Diagnostic: physician referral with palpable lump or abnormal finding.",
            "MRC tracks recall rates for quality and payer reporting.",
        ],
    },
    "dental_imaging": {
        "headline": "Dental Imaging Unit",
        "overview": [
            "Panoramic and cone-beam CT for oral surgery and implants.",
            "Low-radiation protocols for pediatric dental cases.",
            "Digital export compatible with major dental planning software.",
        ],
        "coverage": [
            "Dental rider benefits may apply — verify dental vs medical coverage.",
            "Pre-surgical CBCT often covered under oral surgery benefits.",
            "Employer dental panels: direct settlement available.",
        ],
        "preauth": [
            "Dental surgeon referral with treatment plan recommended.",
            "Medical necessity letter required for TMJ and trauma cases.",
            "MRC provides standardized imaging request forms for payers.",
        ],
    },
}


def load_catalog() -> dict:
    with CATALOG_PATH.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def presentation_name(payer_name: str, service_name: str) -> str:
    return f"{payer_name} — {service_name} Coverage Overview"


def draw_title_page(page: fitz.Page, payer_name: str, service_name: str, payer_key: str):
    color = PAYER_COLORS.get(payer_key, (0.1, 0.2, 0.5))
    page.draw_rect(fitz.Rect(0, 0, PAGE_WIDTH, PAGE_HEIGHT), color=(0.97, 0.98, 1.0), fill=1)
    page.draw_rect(fitz.Rect(0, 0, PAGE_WIDTH, 120), color=color, fill=1)
    page.insert_textbox(
        fitz.Rect(48, 28, PAGE_WIDTH - 48, 100),
        payer_name,
        fontsize=34,
        fontname="helv",
        color=(1, 1, 1),
        align=fitz.TEXT_ALIGN_LEFT,
    )
    page.insert_textbox(
        fitz.Rect(48, 170, PAGE_WIDTH - 48, 280),
        service_name,
        fontsize=42,
        fontname="helv",
        color=color,
        align=fitz.TEXT_ALIGN_LEFT,
    )
    page.insert_textbox(
        fitz.Rect(48, 290, PAGE_WIDTH - 48, 360),
        "Coverage Overview",
        fontsize=28,
        fontname="helv",
        color=(0.2, 0.2, 0.2),
        align=fitz.TEXT_ALIGN_LEFT,
    )
    page.insert_textbox(
        fitz.Rect(48, 400, PAGE_WIDTH - 48, 500),
        "Misr Radiology Center\nPayer Partnership Presentation",
        fontsize=18,
        fontname="helv",
        color=(0.35, 0.35, 0.35),
        align=fitz.TEXT_ALIGN_LEFT,
    )


def draw_bullet_page(
    page: fitz.Page,
    title: str,
    bullets: list[str],
    payer_key: str,
    accent: str | None = None,
):
    color = PAYER_COLORS.get(payer_key, (0.1, 0.2, 0.5))
    page.draw_rect(fitz.Rect(0, 0, PAGE_WIDTH, 72), color=color, fill=1)
    page.insert_textbox(
        fitz.Rect(48, 18, PAGE_WIDTH - 48, 64),
        title,
        fontsize=24,
        fontname="helv",
        color=(1, 1, 1),
        align=fitz.TEXT_ALIGN_LEFT,
    )
    if accent:
        page.insert_textbox(
            fitz.Rect(48, 88, PAGE_WIDTH - 48, 130),
            accent,
            fontsize=20,
            fontname="helv",
            color=color,
            align=fitz.TEXT_ALIGN_LEFT,
        )
        top = 140
    else:
        top = 100

    y = top
    for bullet in bullets:
        page.insert_textbox(
            fitz.Rect(64, y, PAGE_WIDTH - 48, y + 70),
            f"• {bullet}",
            fontsize=16,
            fontname="helv",
            color=(0.15, 0.15, 0.15),
            align=fitz.TEXT_ALIGN_LEFT,
        )
        y += 72


def draw_closing_page(page: fitz.Page, payer_name: str, payer_key: str):
    color = PAYER_COLORS.get(payer_key, (0.1, 0.2, 0.5))
    page.draw_rect(fitz.Rect(0, 0, PAGE_WIDTH, PAGE_HEIGHT), color=(0.97, 0.98, 1.0), fill=1)
    page.draw_rect(fitz.Rect(0, 0, PAGE_WIDTH, 72), color=color, fill=1)
    page.insert_textbox(
        fitz.Rect(48, 18, PAGE_WIDTH - 48, 64),
        "Why Misr Radiology Center?",
        fontsize=24,
        fontname="helv",
        color=(1, 1, 1),
        align=fitz.TEXT_ALIGN_LEFT,
    )
    reasons = [
        "Accredited imaging across MRI, CT, PET/CT, ultrasound, and breast imaging.",
        "Dedicated payer relations desk for pre-auth and claims support.",
        "Fast turnaround with subspecialty radiologist reporting.",
        f"Preferred partner pathway for {payer_name} members.",
    ]
    y = 110
    for reason in reasons:
        page.insert_textbox(
            fitz.Rect(64, y, PAGE_WIDTH - 48, y + 70),
            f"• {reason}",
            fontsize=16,
            fontname="helv",
            color=(0.15, 0.15, 0.15),
            align=fitz.TEXT_ALIGN_LEFT,
        )
        y += 72
    page.insert_textbox(
        fitz.Rect(48, PAGE_HEIGHT - 100, PAGE_WIDTH - 48, PAGE_HEIGHT - 40),
        "Contact: payer.relations@misrradiology.eg  |  MRC Payer Desk: +20 2 0000 0000",
        fontsize=14,
        fontname="helv",
        color=(0.4, 0.4, 0.4),
        align=fitz.TEXT_ALIGN_CENTER,
    )


def build_pdf(payer_name: str, payer_key: str, service_name: str, service_key: str) -> bytes:
    content = SERVICE_CONTENT[service_key]
    doc = fitz.open()
    try:
        page1 = doc.new_page(width=PAGE_WIDTH, height=PAGE_HEIGHT)
        draw_title_page(page1, payer_name, service_name, payer_key)

        page2 = doc.new_page(width=PAGE_WIDTH, height=PAGE_HEIGHT)
        draw_bullet_page(
            page2,
            "Service Overview",
            content["overview"],
            payer_key,
            accent=content["headline"],
        )

        page3 = doc.new_page(width=PAGE_WIDTH, height=PAGE_HEIGHT)
        draw_bullet_page(
            page3,
            f"{payer_name} Coverage & Benefits",
            content["coverage"],
            payer_key,
        )

        page4 = doc.new_page(width=PAGE_WIDTH, height=PAGE_HEIGHT)
        draw_bullet_page(
            page4,
            "Pre-Authorization & Referral Path",
            content["preauth"],
            payer_key,
        )

        page5 = doc.new_page(width=PAGE_WIDTH, height=PAGE_HEIGHT)
        draw_closing_page(page5, payer_name, payer_key)

        return doc.tobytes()
    finally:
        doc.close()


def generate_all(output_dir: Path) -> list[Path]:
    catalog = load_catalog()
    output_dir.mkdir(parents=True, exist_ok=True)
    created: list[Path] = []

    for payer in catalog["payers"]:
        for product in catalog["products"]:
            service_key = product["service_key"]
            service_name = product["name"]
            payer_name = payer["name"]
            payer_key = payer["key"]
            name = presentation_name(payer_name, service_name)
            safe_name = name.replace("—", "-").replace("/", "-")
            pdf_path = output_dir / f"{safe_name}.pdf"
            pdf_bytes = build_pdf(payer_name, payer_key, service_name, service_key)
            pdf_path.write_bytes(pdf_bytes)
            created.append(pdf_path)
            print(f"Generated {pdf_path.name} ({len(pdf_bytes)} bytes)")
    return created


def parse_args():
    parser = argparse.ArgumentParser(description="Generate MRC payer CLM PDF decks")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=OUTPUT_DIR,
        help="Directory for generated PDF files",
    )
    return parser.parse_args()


def main():
    if fitz is None:
        print("pymupdf is required. Run: pip install pymupdf pyyaml", file=sys.stderr)
        sys.exit(1)
    args = parse_args()
    paths = generate_all(args.output_dir)
    print(f"Generated {len(paths)} PDF decks in {args.output_dir}")


if __name__ == "__main__":
    main()
