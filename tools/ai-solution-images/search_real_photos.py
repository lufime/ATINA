#!/usr/bin/env python3
"""Find real, openly licensed photographs for ATINA challenges via Wikimedia Commons.

This script retrieves existing photographs; it does not synthesize or alter the
depicted subject. It saves attribution/license metadata beside every image.
The private challenge manifest must never be committed to the repository.
"""
from __future__ import annotations

import argparse
import csv
import html
import json
import re
import time
from pathlib import Path

import requests
from PIL import Image
from io import BytesIO

API = "https://commons.wikimedia.org/w/api.php"
HEADERS = {"User-Agent": "ATINA-image-research/1.0 (educational challenge image sourcing)"}
ALLOWED_LICENSES = ("CC BY", "CC BY-SA", "CC0", "Public domain", "public domain")


def parse_list(value):
    if not value:
        return []
    try:
        data = json.loads(value)
        if isinstance(data, list):
            return [str(x).strip() for x in data if str(x).strip()]
    except (ValueError, TypeError):
        pass
    return [x.strip() for x in str(value).split("|") if x.strip()]


def clean_html(value):
    value = re.sub(r"<[^>]+>", " ", str(value or ""))
    return re.sub(r"\s+", " ", html.unescape(value)).strip()


def terms(value):
    return {x for x in re.findall(r"[\wÀ-ÿ]{3,}", str(value or "").casefold())}


def search_query(row):
    answer = (row.get("answer") or "").strip()
    description = (row.get("image_description") or "").strip()
    tags = parse_list(row.get("image_tags"))
    # Keep the query focused on the answer, with descriptive context only.
    context = description or " ".join(tags[:4])
    return " ".join(x for x in (answer, context) if x).strip()


def commons_candidates(query, row, limit=8):
    params = {
        "action": "query", "format": "json", "generator": "search",
        "gsrsearch": f"filetype:bitmap {query}", "gsrnamespace": 6,
        "gsrlimit": limit, "prop": "imageinfo", "iiprop": "url|extmetadata",
        "iiurlwidth": 1200,
    }
    response = requests.get(API, params=params, headers=HEADERS, timeout=45)
    response.raise_for_status()
    pages = response.json().get("query", {}).get("pages", {}).values()
    wanted = terms(" ".join([
        row.get("answer", ""), row.get("category", ""),
        row.get("image_description", ""), " ".join(parse_list(row.get("image_tags")))
    ]))
    results = []
    for page in pages:
        info = (page.get("imageinfo") or [{}])[0]
        meta = info.get("extmetadata", {})
        license_name = clean_html((meta.get("LicenseShortName") or {}).get("value", ""))
        if not any(x.casefold() in license_name.casefold() for x in ALLOWED_LICENSES):
            continue
        title = page.get("title", "")
        description = clean_html((meta.get("ImageDescription") or {}).get("value", ""))
        artist = clean_html((meta.get("Artist") or {}).get("value", ""))
        credit = clean_html((meta.get("Credit") or {}).get("value", ""))
        candidate_terms = terms(title + " " + description)
        score = len(wanted & candidate_terms) / max(1, len(wanted))
        thumb = info.get("thumburl") or info.get("url")
        if not thumb:
            continue
        results.append({
            "score": score, "title": title, "description": description,
            "artist": artist, "credit": credit, "license": license_name,
            "license_url": clean_html((meta.get("LicenseUrl") or {}).get("value", "")),
            "source_page": info.get("descriptionurl", ""),
            "image_url": thumb,
        })
    results.sort(key=lambda x: x["score"], reverse=True)
    return results


def load_rows(path):
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    if rows and len(rows[0]) == 1 and "challenges" in rows[0]:
        payload = json.loads(rows[0]["challenges"])
        rows = [
            {k: json.dumps(v, ensure_ascii=False) if isinstance(v, (list, dict))
             else "" if v is None else str(v) for k, v in item.items()}
            for item in payload if isinstance(item, dict)
        ]
    required = {"challenge_id", "answer", "category"}
    if not rows or not required.issubset(rows[0]):
        raise ValueError("Manifesto sem os campos challenge_id, answer e category.")
    return rows


def main():
    parser = argparse.ArgumentParser(description="Pesquisar fotografias reais e licenciadas para ATINA")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output", default="/kaggle/working/ATINA-real-photos")
    parser.add_argument("--limit", type=int, default=5)
    parser.add_argument("--ids", default="")
    parser.add_argument("--candidates", type=int, default=8)
    args = parser.parse_args()

    rows = load_rows(Path(args.manifest))
    ids = {int(x.strip()) for x in args.ids.split(",") if x.strip()}
    if ids:
        rows = [r for r in rows if int(r["challenge_id"]) in ids]
    if args.limit:
        rows = rows[:args.limit]
    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=True)
    session = requests.Session()
    done = 0
    for row in rows:
        cid = int(row["challenge_id"])
        query = search_query(row)
        print(f"[{cid}] Pesquisa de fotografia real para: {row.get('answer','')}", flush=True)
        try:
            found = commons_candidates(query, row, args.candidates)
            if not found:
                print(f"[{cid}] Sem fotografia com licença aceite; requer pesquisa manual.", flush=True)
                continue
            # Save ranked candidates and metadata. Candidate #1 is a suggestion,
            # not an automatic approval; human review remains mandatory.
            saved = []
            for rank, item in enumerate(found[:3], start=1):
                response = session.get(item["image_url"], headers=HEADERS, timeout=60)
                response.raise_for_status()
                image = Image.open(BytesIO(response.content)).convert("RGB")
                image.thumbnail((1200, 1200))
                filename = f"{cid:04d}-candidate-{rank}.webp"
                image.save(out / filename, "WEBP", quality=92, method=6)
                saved.append({"rank": rank, "file": filename, **item})
            (out / f"{cid:04d}-sources.json").write_text(
                json.dumps({"challenge_id": cid, "answer": row.get("answer",""),
                            "query": query, "candidates": saved}, ensure_ascii=False, indent=2),
                encoding="utf-8")
            print(f"[{cid}] {len(saved)} fotografias candidatas guardadas; nenhuma aprovada automaticamente.", flush=True)
            done += 1
            time.sleep(0.2)
        except Exception as exc:
            print(f"[{cid}] ERRO: {exc}", flush=True)
    print(f"Pesquisa concluída: {done}/{len(rows)} desafios com candidatos. Rever antes de usar.")


if __name__ == "__main__":
    main()
