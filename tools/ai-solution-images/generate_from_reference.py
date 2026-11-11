#!/usr/bin/env python3
"""Create original ATINA images with img2img, grounded in real photo references.

The input references must first be reviewed in the Kaggle candidate gallery.
The script never uploads to Supabase. Output images are new AI-generated files;
source-photo attribution and license are retained in a sidecar JSON.
"""
from __future__ import annotations
import argparse, csv, json, os, sys
from pathlib import Path
from io import BytesIO

import torch
from PIL import Image
from diffusers import StableDiffusionImg2ImgPipeline
import cairosvg

ROOT = Path(__file__).resolve().parent
MODEL = "stable-diffusion-v1-5/stable-diffusion-v1-5"


def parse_list(value):
    if not value:
        return []
    try:
        obj=json.loads(value)
        if isinstance(obj,list): return [str(x).strip() for x in obj if str(x).strip()]
    except (ValueError,TypeError): pass
    return [x.strip() for x in str(value).split("|") if x.strip()]


def read_rows(path):
    csv.field_size_limit(2**31 - 1)
    with Path(path).open("r",encoding="utf-8-sig",newline="") as f:
        rows=list(csv.DictReader(f))
    if rows and len(rows[0])==1 and "challenges" in rows[0]:
        raw=json.loads(rows[0]["challenges"])
        rows=[{k:json.dumps(v,ensure_ascii=False) if isinstance(v,(list,dict)) else "" if v is None else str(v) for k,v in r.items()} for r in raw]
    if not rows or not {"challenge_id","answer"}.issubset(rows[0]):
        raise ValueError("Manifesto sem challenge_id e answer.")
    return rows


def build_prompt(row):
    answer=(row.get("answer") or "").strip()
    description=(row.get("image_description") or "").strip()
    tags=parse_list(row.get("image_tags"))
    details=description or ", ".join(tags[:4])
    # Preserve the identity and geometry of the real reference; create a fresh photograph,
    # not an unrelated interpretation of the answer.
    prompt=f"Create a new, original, highly photorealistic documentary photograph based faithfully on the supplied reference photograph. The exact subject is {answer}."
    if details: prompt += f" Accurate visual details: {details}."
    prompt += " Preserve the real subject's recognizable identity, architecture, object shape, proportions, historical details and geographic character from the reference. Natural available light, true-to-life colours, realistic camera optics, fine natural textures, coherent perspective, physically plausible scene. The result must look like a genuine professional photograph, not an illustration or fantasy."
    return prompt


def load_pipe():
    if not torch.cuda.is_available():
        raise RuntimeError("Ativa GPU no Kaggle para gerar imagens com Stable Diffusion img2img.")
    pipe=StableDiffusionImg2ImgPipeline.from_pretrained(
        MODEL, torch_dtype=torch.float16, use_safetensors=True,
        safety_checker=None, requires_safety_checker=False,
        low_cpu_mem_usage=True,
    )
    pipe.enable_model_cpu_offload()
    pipe.enable_attention_slicing("max")
    try:
        pipe.vae.enable_slicing(); pipe.vae.enable_tiling()
    except Exception: pass
    return pipe


def add_logo(image):
    logo_path=ROOT/"assets"/"atina-logo-alentejo.svg"
    if not logo_path.is_file():
        return image.convert("RGB")
    import io
    rgba=image.convert("RGBA")
    w=max(100,int(rgba.width*.27))
    logo=Image.open(BytesIO(cairosvg.svg2png(url=str(logo_path),output_width=w))).convert("RGBA")
    pad=max(4,int(rgba.width*.012)); margin=max(7,int(rgba.width*.02))
    panel=Image.new("RGBA",(logo.width+2*pad,logo.height+2*pad),(8,25,42,185))
    x=rgba.width-panel.width-margin; y=rgba.height-panel.height-margin
    rgba.alpha_composite(panel,(x,y)); rgba.alpha_composite(logo,(x+pad,y+pad))
    return rgba.convert("RGB")


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--manifest",required=True)
    ap.add_argument("--references",default="/kaggle/working/ATINA-real-photos")
    ap.add_argument("--output",default="/kaggle/working/ATINA-ai-generated")
    ap.add_argument("--limit",type=int,default=5)
    ap.add_argument("--ids",default="")
    ap.add_argument("--candidate-rank",type=int,default=1)
    ap.add_argument("--strength",type=float,default=.28)
    args=ap.parse_args()
    if not 0.15 <= args.strength <= .45:
        raise ValueError("strength deve ficar entre 0.15 e 0.45 para preservar a referência.")
    rows=read_rows(args.manifest)
    wanted={int(x.strip()) for x in args.ids.split(",") if x.strip()}
    if wanted: rows=[r for r in rows if int(r["challenge_id"]) in wanted]
    if args.limit: rows=rows[:args.limit]
    refdir=Path(args.references); outdir=Path(args.output); outdir.mkdir(parents=True,exist_ok=True)
    jobs=[]
    for row in rows:
        cid=int(row["challenge_id"])
        meta_path=refdir/f"{cid:04d}-sources.json"
        if not meta_path.exists():
            print(f"[{cid}] Sem metadados de referência; ignorado.",flush=True); continue
        meta=json.loads(meta_path.read_text(encoding="utf-8"))
        candidates=meta.get("candidates",[])
        chosen=next((x for x in candidates if x.get("rank")==args.candidate_rank),None)
        if not chosen:
            print(f"[{cid}] Candidata {args.candidate_rank} indisponível; ignorado.",flush=True); continue
        ref=refdir/chosen["file"]
        if not ref.exists():
            print(f"[{cid}] Ficheiro de referência em falta; ignorado.",flush=True); continue
        jobs.append((row,chosen,ref))
    if not jobs: raise RuntimeError("Não existem referências válidas. Executa primeiro a pesquisa e revisão.")
    pipe=load_pipe()
    for row,source,ref in jobs:
        cid=int(row["challenge_id"]); target=outdir/f"{cid:04d}.webp"
        try:
            base=Image.open(ref).convert("RGB")
            base.thumbnail((512,512))
            canvas=Image.new("RGB",(512,512),(245,245,245))
            x=(512-base.width)//2; y=(512-base.height)//2
            canvas.paste(base,(x,y))
            gen=torch.Generator(device="cpu").manual_seed(730000+cid)
            result=pipe(prompt=build_prompt(row), image=canvas, strength=args.strength,
                guidance_scale=6.5, num_inference_steps=30, generator=gen,
                negative_prompt="illustration, painting, drawing, cartoon, fantasy, surreal, CGI, 3D render, distorted architecture, malformed objects, text, watermark")
            final=add_logo(result.images[0])
            final.save(target,"WEBP",quality=92,method=6)
            sidecar={"challenge_id":cid,"answer":row.get("answer",""),"generated_file":target.name,
                "method":"Stable Diffusion 1.5 img2img","reference_file":source["file"],
                "reference_title":source.get("title",""),"reference_page":source.get("source_page",""),
                "reference_author":source.get("artist",""),"reference_license":source.get("license",""),
                "reference_license_url":source.get("license_url",""),"strength":args.strength,
                "review_status":"pending_human_review"}
            (outdir/f"{cid:04d}-provenance.json").write_text(json.dumps(sidecar,ensure_ascii=False,indent=2),encoding="utf-8")
            print(f"[{cid}] Imagem nova criada a partir de {source['file']}: {target}",flush=True)
            del result,canvas,final
            torch.cuda.empty_cache()
        except Exception as e:
            print(f"[{cid}] ERRO: {e}",file=sys.stderr,flush=True)
            torch.cuda.empty_cache()
    print("Concluído. Rever todas as imagens; nenhuma foi enviada para Supabase.")

if __name__=="__main__":
    main()
