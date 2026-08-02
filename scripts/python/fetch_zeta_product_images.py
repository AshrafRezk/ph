#!/usr/bin/env python3
"""
Fetch Zeta Pharma product images from zetapharma.net and attach them to Product2 records.

Usage:
  pip install -r scripts/python/requirements.txt
  python scripts/python/fetch_zeta_product_images.py --target-org pharma-prod
"""

from __future__ import annotations

import argparse
import base64
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any
from urllib.parse import urljoin, urlparse

import requests
import yaml
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = ROOT / "Plan" / "zeta_pharma_diabetes_catalog.yaml"
PLACEHOLDER_PATH = ROOT / "scripts" / "assets" / "zeta-product-placeholder.png"
PRODUCTS_LISTING_URL = "https://zetapharma.net/products/"
API_VERSION = "67.0"
USER_AGENT = "PharmaCatalogBot/1.0 (+https://zetapharma.net/products/)"

# Minimal 1x1 PNG used when no website image is available.
MINIMAL_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)


def load_catalog() -> dict[str, Any]:
    with CATALOG_PATH.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def run_sf(args: list[str]) -> dict[str, Any]:
    command = ["sf", *args, "--json"]
    completed = subprocess.run(command, capture_output=True, text=True, check=False)
    if completed.returncode != 0:
        raise RuntimeError(
            f"Salesforce CLI failed ({' '.join(command)}):\n{completed.stderr or completed.stdout}"
        )
    payload = json.loads(completed.stdout)
    if payload.get("status") != 0:
        raise RuntimeError(f"Salesforce CLI error: {payload}")
    return payload["result"]


def get_org_session(target_org: str) -> tuple[str, str]:
    result = run_sf(["org", "display", "--target-org", target_org])
    access_token = result.get("accessToken")
    instance_url = result.get("instanceUrl")
    if not access_token or not instance_url:
        raise RuntimeError(f"Could not resolve org session for {target_org}")
    return instance_url.rstrip("/"), access_token


def soql_query(instance_url: str, access_token: str, soql: str) -> list[dict[str, Any]]:
    headers = {"Authorization": f"Bearer {access_token}"}
    response = requests.get(
        f"{instance_url}/services/data/v{API_VERSION}/query",
        headers=headers,
        params={"q": soql},
        timeout=60,
    )
    response.raise_for_status()
    return response.json().get("records", [])


def patch_product(
    instance_url: str,
    access_token: str,
    product_id: str,
    display_url: str,
    image_url: str,
) -> None:
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    }
    payload = {"DisplayUrl": display_url, "Product_Image_URL__c": image_url}
    response = requests.patch(
        f"{instance_url}/services/data/v{API_VERSION}/sobjects/Product2/{product_id}",
        headers=headers,
        json=payload,
        timeout=60,
    )
    response.raise_for_status()


def upload_content_version(
    instance_url: str,
    access_token: str,
    product_id: str,
    title: str,
    filename: str,
    image_bytes: bytes,
) -> None:
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    }
    payload = {
        "Title": title,
        "PathOnClient": filename,
        "VersionData": base64.b64encode(image_bytes).decode("ascii"),
        "FirstPublishLocationId": product_id,
    }
    response = requests.post(
        f"{instance_url}/services/data/v{API_VERSION}/sobjects/ContentVersion",
        headers=headers,
        json=payload,
        timeout=120,
    )
    response.raise_for_status()


def is_valid_product_image(url: str) -> bool:
    lowered = url.lower()
    blocked = ("qr", "logo", "icon", "avatar", "favicon", "sprite", "banner")
    return not any(token in lowered for token in blocked)


def fetch_html(url: str, session: requests.Session) -> str:
    response = session.get(url, timeout=60)
    response.raise_for_status()
    return response.text


def normalize_image_url(base_url: str, image_url: str | None) -> str | None:
    if not image_url:
        return None
    image_url = image_url.strip()
    if image_url.startswith("data:"):
        return None
    return urljoin(base_url, image_url)


def extract_og_image(html: str, base_url: str) -> str | None:
    soup = BeautifulSoup(html, "html.parser")
    for selector in (
        ('meta', {"property": "og:image"}),
        ('meta', {"name": "og:image"}),
        ('meta', {"property": "twitter:image"}),
    ):
        tag = soup.find(selector[0], selector[1])
        if tag and tag.get("content"):
            resolved = normalize_image_url(base_url, tag["content"])
            if resolved and is_valid_product_image(resolved):
                return resolved

    for img in soup.select("img.wp-post-image, .product-image img, .fusion-image-wrapper img, article img"):
        src = img.get("src") or img.get("data-src")
        resolved = normalize_image_url(base_url, src)
        if resolved and is_valid_product_image(resolved):
            return resolved
    return None


def extract_listing_image(html: str, listing_name: str) -> str | None:
    soup = BeautifulSoup(html, "html.parser")
    pattern = re.compile(re.escape(listing_name), re.IGNORECASE)
    for heading in soup.find_all(["h2", "h3", "h4", "h5"]):
        if not pattern.search(heading.get_text(" ", strip=True)):
            continue
        container = heading.find_parent(["article", "div", "section", "li"])
        if not container:
            continue
        image = container.find("img")
        if image:
            src = image.get("src") or image.get("data-src")
            resolved = normalize_image_url(PRODUCTS_LISTING_URL, src)
            if resolved and is_valid_product_image(resolved):
                return resolved
    return None


def resolve_image_url(product: dict[str, Any], session: requests.Session) -> str | None:
    explicit = product.get("image_url")
    if explicit and is_valid_product_image(explicit):
        return explicit

    source_url = product["source_url"]
    listing_name = product.get("listing_name", product["name"])
    product_code = product.get("product_code", "")
    slug_hints = [
        hint
        for hint in (
            product.get("image_slug"),
            product_code.lower().replace("zeta-", "").replace("-", ""),
            listing_name.lower().replace(" ", "-"),
        )
        if hint
    ]

    for slug in slug_hints:
        for extension in ("png", "jpg", "jpeg", "webp"):
            candidate = f"https://zetapharma.net/wp-content/uploads/2025/07/{slug}.{extension}"
            try:
                response = session.head(candidate, timeout=20, allow_redirects=True)
                if response.status_code == 200 and is_valid_product_image(candidate):
                    return candidate
            except requests.RequestException:
                continue

    try:
        detail_html = fetch_html(source_url, session)
        image_url = extract_og_image(detail_html, source_url)
        if image_url:
            return image_url
    except requests.RequestException as exc:
        print(f"  warning: could not fetch detail page {source_url}: {exc}")

    try:
        listing_html = fetch_html(PRODUCTS_LISTING_URL, session)
        image_url = extract_listing_image(listing_html, listing_name)
        if image_url:
            return image_url
    except requests.RequestException as exc:
        print(f"  warning: could not fetch listing page: {exc}")

    return None


def download_image(image_url: str, session: requests.Session) -> tuple[bytes, str]:
    response = session.get(image_url, timeout=60)
    response.raise_for_status()
    content_type = response.headers.get("Content-Type", "image/jpeg").split(";")[0].strip().lower()
    extension = {
        "image/jpeg": ".jpg",
        "image/jpg": ".jpg",
        "image/png": ".png",
        "image/webp": ".webp",
        "image/gif": ".gif",
    }.get(content_type, ".jpg")
    return response.content, extension


def load_placeholder_bytes() -> tuple[bytes, str]:
    if PLACEHOLDER_PATH.exists():
        return PLACEHOLDER_PATH.read_bytes(), PLACEHOLDER_PATH.suffix or ".png"
    PLACEHOLDER_PATH.parent.mkdir(parents=True, exist_ok=True)
    PLACEHOLDER_PATH.write_bytes(MINIMAL_PNG)
    return MINIMAL_PNG, ".png"


def process_product(
    product: dict[str, Any],
    session: requests.Session,
    instance_url: str,
    access_token: str,
) -> None:
    external_id = product["external_id"]
    records = soql_query(
        instance_url,
        access_token,
        f"SELECT Id, Name FROM Product2 WHERE External_ID__c = '{external_id}' LIMIT 1",
    )
    if not records:
        print(f"skip {external_id}: Product2 not found in org")
        return

    product_id = records[0]["Id"]
    product_name = records[0]["Name"]
    display_url = product.get("display_url") or product["source_url"]
    print(f"processing {product_name} ({external_id})")

    image_url = resolve_image_url(product, session)
    if image_url:
        try:
            image_bytes, extension = download_image(image_url, session)
            print(f"  downloaded image from {image_url}")
        except requests.RequestException as exc:
            print(f"  warning: image download failed ({exc}); using placeholder")
            image_bytes, extension = load_placeholder_bytes()
            image_url = display_url
    else:
        print("  no website image found; using placeholder")
        image_bytes, extension = load_placeholder_bytes()
        image_url = display_url

    safe_name = re.sub(r"[^A-Za-z0-9_-]+", "_", product_name)
    filename = f"{safe_name}{extension}"
    upload_content_version(instance_url, access_token, product_id, product_name, filename, image_bytes)
    patch_product(instance_url, access_token, product_id, display_url, image_url)
    print(f"  attached file and updated DisplayUrl/Image_URL__c for {product_id}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch Zeta Pharma product images into Salesforce.")
    parser.add_argument("--target-org", default="pharma-prod", help="Salesforce org alias")
    args = parser.parse_args()

    catalog = load_catalog()
    products = catalog.get("products", [])
    if not products:
        print("No products found in catalog YAML.")
        return 1

    instance_url, access_token = get_org_session(args.target_org)
    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT})

    for product in products:
        process_product(product, session, instance_url, access_token)

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
