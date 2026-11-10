#!/usr/bin/env python3
"""Generate ATINA solution illustrations locally with FLUX.1-schnell.

The private CSV manifest must be exported from Supabase SQL Editor and kept
outside version control. Generated files are WebP and named by challenge ID.
"""

from __future__ import annotations

import argparse
import csv
# Supabase exports can contain a single JSON field larger than csv's 128 KiB default.
csv.field_size_limit(2**31 - 1)
import hashlib
import json
import os
import sys
from pathlib import Path
from urllib.parse import quote

import requests
import torch
from diffusers import FluxPipeline
from PIL import Image

ROOT = Path(__file__).resolve().parent
DEFAULT_MODEL = "black-forest-labs/FLUX.1-schnell"
BUCKET = "atina-challenge-images"
MODEL_CARD = "https://huggingface.co/black-forest-labs/FLUX.1-schnell"
MODEL_LICENSE = "https://www.apache.org/licenses/LICENSE-2.0"


def sql_text(value: str | None) -> str:
    if value is None:
        return "NULL"
    return "'" + str(value).replace("'", "''") + "'"


def parse_list(value: str | None) -> list[str]:
    if not value:
        return []
    try:
        parsed = json.loads(value)
        if isinstance(parsed, list):
            return [str(item).strip() for item in parsed if str(item).strip()]
    except (json.JSONDecodeError, TypeError):
        pass
    return [part.strip() for part in value.split("|") if part.strip()]


def build_prompt(row: dict[str, str]) -> str:
    answer = (row.get("answer") or "").strip()
    category = (row.get("category") or "").strip()
    tags = parse_list(row.get("image_tags"))
    description = (row.get("image_description") or "").strip()
    # Keep prompts short: FLUX's CLIP encoder truncates long prompts and
    # long T5 sequences increase memory pressure on 16 GB Tesla T4 GPUs.
    subject = description or ", ".join(tags[:3]) or category
    return (
        "Editorial educational illustration, square composition. "
        f"Exact recognizable subject: {answer}. "
        f"Visual direction: {subject}. "
        "Single clear focal point, accurate natural appearance, refined lighting, "
        "balanced colours. No text, letters, numbers, logos, watermark or collage."
    )


def load_pipeline(model_id: str) -> FluxPipeline:
    if not torch.cuda.is_available():
        raise RuntimeError(
            "Não foi detetada uma GPU CUDA. Este modelo é demasiado pesado para "
            "recomendar geração em CPU. Usa uma máquina com GPU NVIDIA compatível."
        )
    # Tesla T4 (Turing) is most reliable with FP16; BF16 is not supported.
    dtype = torch.float16
    print(f"A carregar {model_id} em {dtype} com sequential CPU offload...", flush=True)
    hf_token = os.getenv("HF_TOKEN", "").strip() or None
    pipe = FluxPipeline.from_pretrained(
        model_id,
        torch_dtype=dtype,
        use_safetensors=True,
        token=hf_token,
        low_cpu_mem_usage=True,
    )
    # Must be enabled before any pipe.to("cuda") call. This is slower,
    # but uses substantially less VRAM than model-level offload.
    pipe.enable_sequential_cpu_offload()
    try:
        pipe.vae.enable_slicing()
        pipe.vae.enable_tiling()
    except Exception:
        pass
    return pipe


def generate_one(pipe: FluxPipeline, row: dict[str, str], target: Path, force: bool) -> Path:
    challenge_id = int(row["challenge_id"])
    if target.exists() and not force:
        print(f"[{challenge_id}] já existe; a reutilizar {target.name}", flush=True)
        return target

    prompt = build_prompt(row)
    generator = torch.Generator(device="cpu").manual_seed(730000 + challenge_id)
    resolution = int(os.getenv("ATINA_IMAGE_RESOLUTION", "512"))
    try:
        result = pipe(
            prompt=prompt,
            height=resolution,
            width=resolution,
            num_inference_steps=4,
            guidance_scale=0.0,
            max_sequence_length=128,
            generator=generator,
        )
    except torch.cuda.OutOfMemoryError:
        print(f"[{challenge_id}] OOM a {resolution}px; a tentar novamente a 384px...", flush=True)
        del generator
        torch.cuda.empty_cache()
        generator = torch.Generator(device="cpu").manual_seed(730000 + challenge_id)
        result = pipe(
            prompt=prompt,
            height=384,
            width=384,
            num_inference_steps=4,
            guidance_scale=0.0,
            max_sequence_length=96,
            generator=generator,
        )
    image: Image.Image = result.images[0]
    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target, format="WEBP", quality=88, method=6)
    print(f"[{challenge_id}] gerada: {target.name} ({target.stat().st_size:,} bytes)", flush=True)
    return target


def upload_image(path: Path, challenge_id: int, base_url: str, service_key: str) -> tuple[str, str]:
    storage_path = f"solutions/{challenge_id}.webp"
    endpoint = (
        base_url.rstrip("/")
        + "/storage/v1/object/"
        + quote(BUCKET, safe="")
        + "/"
        + quote(storage_path, safe="/")
    )
    headers = {
        "Authorization": f"Bearer {service_key}",
        "apikey": service_key,
        "Content-Type": "image/webp",
        "x-upsert": "true",
    }
    with path.open("rb") as handle:
        response = requests.post(endpoint, headers=headers, data=handle, timeout=180)
    if response.status_code not in (200, 201):
        raise RuntimeError(
            f"Falha no upload do desafio {challenge_id}: "
            f"HTTP {response.status_code} — {response.text[:500]}"
        )
    public_url = (
        base_url.rstrip("/")
        + "/storage/v1/object/public/"
        + quote(BUCKET, safe="")
        + "/"
        + quote(storage_path, safe="/")
    )
    return public_url, storage_path


def sql_for_asset(challenge_id: int, image_url: str, storage_path: str, path: Path) -> str:
    payload = path.read_bytes()
    checksum = hashlib.sha256(payload).hexdigest()
    size = len(payload)
    source = "ATINA AI / FLUX.1-schnell"
    author = "Imagem gerada localmente para ATINA"
    license_label = "Imagem gerada por IA; modelo FLUX.1-schnell sob Apache-2.0"
    attribution = "Gerada localmente para ATINA; não é fotografia de terceiro."
    notes = "Gerada por IA. Revisão humana de correspondência factual necessária antes de aprovação."
    return (
        "INSERT INTO private.atina_image_assets "
        "(challenge_id, image_url, storage_path, source, source_url, author, license, "
        "license_url, attribution, mime_type, file_size_bytes, checksum_sha256, "
        "status, verification_notes, verified_at) VALUES ("
        f"{challenge_id}, {sql_text(image_url)}, {sql_text(storage_path)}, "
        f"{sql_text(source)}, {sql_text(MODEL_CARD)}, {sql_text(author)}, "
        f"{sql_text(license_label)}, {sql_text(MODEL_LICENSE)}, "
        f"{sql_text(attribution)}, 'image/webp', {size}, {sql_text(checksum)}, "
        f"'generated', {sql_text(notes)}, NULL"
        ") ON CONFLICT (challenge_id) DO UPDATE SET "
        "image_url = EXCLUDED.image_url, storage_path = EXCLUDED.storage_path, "
        "source = EXCLUDED.source, source_url = EXCLUDED.source_url, "
        "author = EXCLUDED.author, license = EXCLUDED.license, "
        "license_url = EXCLUDED.license_url, attribution = EXCLUDED.attribution, "
        "mime_type = EXCLUDED.mime_type, file_size_bytes = EXCLUDED.file_size_bytes, "
        "checksum_sha256 = EXCLUDED.checksum_sha256, status = 'generated', "
        "verification_notes = EXCLUDED.verification_notes, verified_at = NULL;\n"
        "UPDATE private.atina_challenges SET solution_image_url = "
        f"{sql_text(image_url)} WHERE challenge_id = {challenge_id};\n"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Geração local de imagens de solução ATINA")
    parser.add_argument("--manifest", required=True, help="CSV privado exportado do Supabase")
    parser.add_argument("--output", default=str(ROOT / "generated" / "images"))
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--limit", type=int, default=0, help="Limita o número de desafios (teste)")
    parser.add_argument("--ids", default="", help="IDs separados por vírgula")
    parser.add_argument("--force", action="store_true", help="Regenera imagens já existentes")
    parser.add_argument("--upload", action="store_true", help="Envia as imagens para o bucket Supabase")
    args = parser.parse_args()

    manifest = Path(args.manifest)
    output_dir = Path(args.output)
    if not manifest.is_file():
        print(f"Manifesto não encontrado: {manifest}", file=sys.stderr)
        return 2

    with manifest.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))

    # Also accept a one-row CSV exported from jsonb_agg(...) in Supabase SQL Editor.
    if rows and len(rows[0]) == 1 and "challenges" in rows[0]:
        try:
            payload = json.loads(rows[0]["challenges"])
            if isinstance(payload, list):
                rows = [
                    {
                        key: (json.dumps(value, ensure_ascii=False) if isinstance(value, (list, dict)) else "" if value is None else str(value))
                        for key, value in item.items()
                    }
                    for item in payload
                    if isinstance(item, dict)
                ]
        except (json.JSONDecodeError, TypeError):
            rows = []

    required = {"challenge_id", "category", "answer", "clues"}
    if not rows or not required.issubset(rows[0].keys()):
        print("CSV inválido. Esperava as colunas do manifesto ou uma coluna 'challenges' com JSON.", file=sys.stderr)
        return 2

    wanted_ids = {int(value.strip()) for value in args.ids.split(",") if value.strip()}
    if wanted_ids:
        rows = [row for row in rows if int(row["challenge_id"]) in wanted_ids]
    if args.limit:
        rows = rows[:args.limit]
    if not rows:
        print("Nenhum desafio corresponde aos filtros.", file=sys.stderr)
        return 2

    base_url = os.getenv("SUPABASE_URL", "").strip()
    service_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if args.upload and (not base_url or not service_key):
        print("Para --upload define SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY no ambiente local.", file=sys.stderr)
        return 2

    print(f"Desafios selecionados: {len(rows)}", flush=True)
    pipe = load_pipeline(args.model)
    sql_statements: list[str] = []
    completed = 0

    for row in rows:
        challenge_id = int(row["challenge_id"])
        target = output_dir / f"{challenge_id:04d}.webp"
        try:
            image_path = generate_one(pipe, row, target, args.force)
            if args.upload:
                image_url, storage_path = upload_image(image_path, challenge_id, base_url, service_key)
                sql_statements.append(sql_for_asset(challenge_id, image_url, storage_path, image_path))
                print(f"[{challenge_id}] enviado para Storage", flush=True)
            completed += 1
        except Exception as exc:
            print(f"[{challenge_id}] ERRO: {exc}", file=sys.stderr, flush=True)
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
            continue
        finally:
            if torch.cuda.is_available():
                torch.cuda.empty_cache()

    if args.upload and sql_statements:
        sql_path = ROOT / "generated" / "apply-generated-images.sql"
        sql_path.parent.mkdir(parents=True, exist_ok=True)
        sql_path.write_text(
            "-- ATINA: aplicar apenas depois da revisão humana das imagens geradas.\n"
            + "\n".join(sql_statements),
            encoding="utf-8",
        )
        print(f"SQL criado: {sql_path}", flush=True)

    print(f"Concluído: {completed}/{len(rows)} imagens.", flush=True)
    if args.upload:
        print("O SQL ainda precisa de revisão e execução manual no Supabase SQL Editor.", flush=True)
    return 0 if completed == len(rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
