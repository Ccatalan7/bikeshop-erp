#!/usr/bin/env python3
"""Audit and safely standardize ecommerce product images.

This is intentionally conservative:
- audit every image before changing anything
- write outputs to a review folder
- never overwrite source images
- keep AI upscaling behind an explicit test mode

Examples:
  python3 scripts/product_image_pipeline.py audit --input image.jpg
  python3 scripts/product_image_pipeline.py process --input image.jpg --output-dir reports/product_images
  python3 scripts/product_image_pipeline.py ai-test --input image.jpg --realesrgan-bin /path/to/realesrgan-ncnn-vulkan
  python3 scripts/product_image_pipeline.py openai-test --input image.jpg --openai-model gpt-image-1.5
  python3 scripts/product_image_pipeline.py process --manifest products.csv --source-column image_url --id-column id
"""

from __future__ import annotations

import argparse
import base64
import csv
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import warnings
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

try:
    import numpy as np
except Exception:  # pragma: no cover - optional fallback
    np = None

from PIL import Image, ImageChops, ImageColor, ImageFilter, ImageOps, ImageStat

warnings.filterwarnings(
    "ignore",
    message="Image.Image.getdata is deprecated.*",
    category=DeprecationWarning,
)

DEFAULT_OUTPUT_DIR = "reports/product_image_pipeline"
DEFAULT_TARGET_SIZE = 1600
DEFAULT_WEBP_QUALITY = 88
DEFAULT_BG = "#ffffff"
USER_AGENT = "VinabikeProductImagePipeline/1.0"
OPENAI_IMAGES_EDIT_URL = "https://api.openai.com/v1/images/edits"


@dataclass
class ImageInput:
    source: str
    item_id: str
    name: str = ""


@dataclass
class AuditResult:
    item_id: str
    source: str
    ok: bool
    error: str
    format: str
    mode: str
    width: int
    height: int
    file_size_kb: float
    megapixels: float
    blur_score: float
    subject_fill: float
    subject_bbox: str
    border_white_score: float
    has_alpha: bool
    flags: str
    recommendation: str


@dataclass
class ProcessResult:
    item_id: str
    source: str
    audit_flags: str
    safe_output: str
    ai_output: str
    comparison_output: str
    status: str
    error: str


def main() -> int:
    args = parse_args()
    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    inputs = list(load_inputs(args))
    if args.max_items:
        inputs = inputs[: args.max_items]

    if not inputs:
        print("No images to process.", file=sys.stderr)
        return 2

    work_dir = out_dir / "work"
    originals_dir = out_dir / "originals"
    processed_dir = out_dir / "processed"
    ai_dir = out_dir / "ai_previews"
    compare_dir = out_dir / "comparisons"
    for directory in (work_dir, originals_dir, processed_dir, ai_dir, compare_dir):
        directory.mkdir(parents=True, exist_ok=True)

    audit_rows: list[AuditResult] = []
    process_rows: list[ProcessResult] = []

    for index, item in enumerate(inputs, start=1):
        print(f"[{index}/{len(inputs)}] {item.item_id}: {item.source}")
        local_path = ""
        try:
            local_path = materialize_source(item, originals_dir)
            audit = audit_image(item, local_path)
            audit_rows.append(audit)

            if args.command == "audit":
                continue

            process_rows.append(
                process_image(
                    args=args,
                    item=item,
                    local_path=local_path,
                    audit=audit,
                    processed_dir=processed_dir,
                    ai_dir=ai_dir,
                    compare_dir=compare_dir,
                    work_dir=work_dir,
                )
            )
        except Exception as exc:  # keep batch runs alive
            audit_rows.append(
                AuditResult(
                    item_id=item.item_id,
                    source=item.source,
                    ok=False,
                    error=str(exc),
                    format="",
                    mode="",
                    width=0,
                    height=0,
                    file_size_kb=0,
                    megapixels=0,
                    blur_score=0,
                    subject_fill=0,
                    subject_bbox="",
                    border_white_score=0,
                    has_alpha=False,
                    flags="broken_image",
                    recommendation="Replace source image",
                )
            )
            process_rows.append(
                ProcessResult(
                    item_id=item.item_id,
                    source=item.source,
                    audit_flags="broken_image",
                    safe_output="",
                    ai_output="",
                    comparison_output="",
                    status="failed",
                    error=str(exc),
                )
            )
            print(f"  failed: {exc}", file=sys.stderr)

    write_audit_reports(out_dir, audit_rows)
    if args.command != "audit":
        write_process_reports(out_dir, process_rows)

    print("")
    print(f"Audit report: {out_dir / 'audit.csv'}")
    if args.command != "audit":
        print(f"Process report: {out_dir / 'process_report.csv'}")
        print(f"Review images in: {processed_dir}")
        if args.command in ("ai-test", "openai-test"):
            print(f"AI test previews in: {ai_dir}")
            print(f"Comparisons in: {compare_dir}")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Audit, standardize, and optionally AI-test product images.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    for name in ("audit", "process", "ai-test", "openai-test"):
        p = sub.add_parser(name)
        p.add_argument("--input", nargs="*", default=[], help="Image paths or image URLs.")
        p.add_argument("--manifest", help="CSV with image sources.")
        p.add_argument("--source-column", default="image_url")
        p.add_argument("--id-column", default="id")
        p.add_argument("--name-column", default="name")
        p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
        p.add_argument("--max-items", type=int)
        p.add_argument("--target-size", type=int, default=DEFAULT_TARGET_SIZE)
        p.add_argument("--webp-quality", type=int, default=DEFAULT_WEBP_QUALITY)
        p.add_argument("--background", default=DEFAULT_BG)
        p.add_argument("--margin", type=int, default=120)
        p.add_argument(
            "--max-safe-upscale",
            type=float,
            default=8.0,
            help="Maximum non-AI upscale factor used for the safe review image.",
        )
        p.add_argument("--no-autocontrast", action="store_true")
        p.add_argument("--no-sharpen", action="store_true")
        p.add_argument("--keep-work", action="store_true")

        if name == "ai-test":
            p.add_argument("--realesrgan-bin", help="Path to realesrgan-ncnn-vulkan or compatible binary.")
            p.add_argument(
                "--realesrgan-model-dir",
                help="Model folder. Defaults to a sibling 'models' folder next to the Real-ESRGAN binary.",
            )
            p.add_argument("--realesrgan-model", default="realesrgan-x4plus")
            p.add_argument("--realesrgan-scale", type=int, default=4)
            p.add_argument(
                "--allow-lanczos-fallback",
                action="store_true",
                help="Create a non-AI upscale baseline if Real-ESRGAN is unavailable.",
            )

        if name == "openai-test":
            p.add_argument("--openai-model", default="gpt-image-1.5")
            p.add_argument("--openai-quality", default="high", choices=("low", "medium", "high"))
            p.add_argument("--openai-size", default="1024x1024")
            p.add_argument("--openai-output-format", default="png", choices=("png", "jpeg", "webp"))
            p.add_argument(
                "--openai-prompt",
                help="Override the default ecommerce product enhancement prompt.",
            )

    return parser.parse_args()


def load_inputs(args: argparse.Namespace) -> Iterable[ImageInput]:
    seen: set[str] = set()

    if args.manifest:
        with open(args.manifest, newline="", encoding="utf-8-sig") as fh:
            reader = csv.DictReader(fh)
            for row_index, row in enumerate(reader, start=1):
                source = (row.get(args.source_column) or "").strip()
                if not source or source in seen:
                    continue
                seen.add(source)
                item_id = (row.get(args.id_column) or "").strip() or stable_id(source, row_index)
                name = (row.get(args.name_column) or "").strip()
                yield ImageInput(source=source, item_id=safe_slug(item_id), name=name)

    for row_index, source in enumerate(args.input, start=1):
        source = source.strip()
        if not source or source in seen:
            continue
        seen.add(source)
        yield ImageInput(source=source, item_id=stable_id(source, row_index))


def materialize_source(item: ImageInput, originals_dir: Path) -> str:
    if is_url(item.source):
        ext = extension_from_source(item.source) or ".jpg"
        dest = originals_dir / f"{item.item_id}{ext}"
        if not dest.exists():
            req = urllib.request.Request(item.source, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=30) as response:
                content_type = response.headers.get("content-type", "")
                if "html" in content_type.lower():
                    raise ValueError(f"URL returned HTML instead of an image: {item.source}")
                dest.write_bytes(response.read())
        return str(dest)

    path = Path(item.source).expanduser()
    if not path.exists():
        raise FileNotFoundError(item.source)
    ext = path.suffix.lower() or ".jpg"
    dest = originals_dir / f"{item.item_id}{ext}"
    if path.resolve() != dest.resolve() and not dest.exists():
        shutil.copy2(path, dest)
    return str(dest)


def audit_image(item: ImageInput, local_path: str) -> AuditResult:
    path = Path(local_path)
    with Image.open(path) as raw:
        image = ImageOps.exif_transpose(raw)
        width, height = image.size
        has_alpha = image_has_alpha(image)
        bbox = find_subject_bbox(image)
        subject_fill = bbox_area_ratio(bbox, width, height)
        blur = blur_score(image)
        white_score = border_white_score(image)
        flags = quality_flags(width, height, blur, subject_fill, white_score, has_alpha)

        return AuditResult(
            item_id=item.item_id,
            source=item.source,
            ok=True,
            error="",
            format=raw.format or "",
            mode=image.mode,
            width=width,
            height=height,
            file_size_kb=round(path.stat().st_size / 1024, 1),
            megapixels=round((width * height) / 1_000_000, 3),
            blur_score=round(blur, 2),
            subject_fill=round(subject_fill, 3),
            subject_bbox=",".join(str(v) for v in bbox) if bbox else "",
            border_white_score=round(white_score, 3),
            has_alpha=has_alpha,
            flags="|".join(flags),
            recommendation=recommendation(flags),
        )


def process_image(
    *,
    args: argparse.Namespace,
    item: ImageInput,
    local_path: str,
    audit: AuditResult,
    processed_dir: Path,
    ai_dir: Path,
    compare_dir: Path,
    work_dir: Path,
) -> ProcessResult:
    safe_output = ""
    ai_output = ""
    comparison_output = ""
    status = "ok"
    error = ""

    try:
        with Image.open(local_path) as raw:
            image = ImageOps.exif_transpose(raw)
            safe = make_safe_product_image(
                image,
                target_size=args.target_size,
                background=args.background,
                margin=args.margin,
                max_safe_upscale=args.max_safe_upscale,
                autocontrast=not args.no_autocontrast,
                sharpen=not args.no_sharpen,
            )
            safe_path = processed_dir / f"{item.item_id}_safe_{args.target_size}.webp"
            safe.save(safe_path, "WEBP", quality=args.webp_quality, method=6)
            safe_output = str(safe_path)

        if args.command == "ai-test":
            ai_path = run_ai_test(
                args=args,
                item=item,
                local_path=local_path,
                ai_dir=ai_dir,
                work_dir=work_dir,
            )
            if ai_path:
                ai_output = str(ai_path)
                comparison = compare_dir / f"{item.item_id}_comparison.jpg"
                make_comparison_sheet(
                    original_path=Path(local_path),
                    safe_path=Path(safe_output),
                    ai_path=Path(ai_output),
                    output_path=comparison,
                    item_id=item.item_id,
                )
                comparison_output = str(comparison)
            else:
                status = "safe_only_missing_ai"
                error = "Real-ESRGAN binary not provided or not found"

        if args.command == "openai-test":
            ai_path = run_openai_image_test(
                args=args,
                item=item,
                local_path=local_path,
                ai_dir=ai_dir,
                work_dir=work_dir,
            )
            ai_output = str(ai_path)
            comparison = compare_dir / f"{item.item_id}_comparison.jpg"
            make_comparison_sheet(
                original_path=Path(local_path),
                safe_path=Path(safe_output),
                ai_path=Path(ai_output),
                output_path=comparison,
                item_id=item.item_id,
            )
            comparison_output = str(comparison)

        if not args.keep_work:
            cleanup_work_dir(work_dir)
    except Exception as exc:
        status = "failed"
        error = str(exc)

    return ProcessResult(
        item_id=item.item_id,
        source=item.source,
        audit_flags=audit.flags,
        safe_output=safe_output,
        ai_output=ai_output,
        comparison_output=comparison_output,
        status=status,
        error=error,
    )


def make_safe_product_image(
    image: Image.Image,
    *,
    target_size: int,
    background: str,
    margin: int,
    max_safe_upscale: float,
    autocontrast: bool,
    sharpen: bool,
) -> Image.Image:
    bg_rgb = ImageColor.getrgb(background)
    rgb = flatten_to_background(image, bg_rgb)
    bbox = find_subject_bbox(rgb)
    if bbox:
        rgb = rgb.crop(add_bbox_margin(bbox, rgb.size, margin=24))

    if autocontrast:
        rgb = ImageOps.autocontrast(rgb, cutoff=0.5)
    if sharpen:
        rgb = rgb.filter(ImageFilter.UnsharpMask(radius=1.0, percent=65, threshold=3))

    inner = max(64, target_size - (margin * 2))
    scale = inner / max(rgb.width, rgb.height)
    if scale > 1:
        scale = min(scale, max(1.0, max_safe_upscale))

    new_size = (
        max(1, round(rgb.width * scale)),
        max(1, round(rgb.height * scale)),
    )
    if new_size != rgb.size:
        rgb = rgb.resize(new_size, Image.Resampling.LANCZOS)

    canvas = Image.new("RGB", (target_size, target_size), bg_rgb)
    x = (target_size - rgb.width) // 2
    y = (target_size - rgb.height) // 2
    canvas.paste(rgb, (x, y))
    return canvas


def run_ai_test(
    *,
    args: argparse.Namespace,
    item: ImageInput,
    local_path: str,
    ai_dir: Path,
    work_dir: Path,
) -> Path | None:
    bin_path = getattr(args, "realesrgan_bin", None)
    if bin_path:
        bin_file = Path(bin_path).expanduser()
        if bin_file.exists():
            input_png = work_dir / f"{item.item_id}_ai_input.png"
            output_png = ai_dir / f"{item.item_id}_realesrgan_x{args.realesrgan_scale}.png"
            with Image.open(local_path) as raw:
                image = ImageOps.exif_transpose(raw)
                flatten_to_background(image, (255, 255, 255)).save(input_png, "PNG")

            cmd = [
                str(bin_file),
                "-i",
                str(input_png),
                "-o",
                str(output_png),
                "-s",
                str(args.realesrgan_scale),
                "-n",
                args.realesrgan_model,
            ]
            model_dir = getattr(args, "realesrgan_model_dir", None)
            if model_dir:
                cmd.extend(["-m", str(Path(model_dir).expanduser())])
            elif (bin_file.parent / "models").exists():
                cmd.extend(["-m", str(bin_file.parent / "models")])
            subprocess.run(cmd, check=True)
            return output_png

    if getattr(args, "allow_lanczos_fallback", False):
        output = ai_dir / f"{item.item_id}_lanczos_baseline_x{args.realesrgan_scale}.png"
        with Image.open(local_path) as raw:
            image = ImageOps.exif_transpose(raw)
            rgb = flatten_to_background(image, (255, 255, 255))
            rgb = rgb.resize(
                (rgb.width * args.realesrgan_scale, rgb.height * args.realesrgan_scale),
                Image.Resampling.LANCZOS,
            )
            rgb.save(output, "PNG")
        return output

    return None


def run_openai_image_test(
    *,
    args: argparse.Namespace,
    item: ImageInput,
    local_path: str,
    ai_dir: Path,
    work_dir: Path,
) -> Path:
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY is not set")

    input_png = work_dir / f"{item.item_id}_openai_input.png"
    with Image.open(local_path) as raw:
        image = ImageOps.exif_transpose(raw)
        flatten_to_background(image, (255, 255, 255)).save(input_png, "PNG")

    prompt = args.openai_prompt or default_openai_product_prompt(item)
    fields = {
        "model": args.openai_model,
        "prompt": prompt,
        "quality": args.openai_quality,
        "size": args.openai_size,
        "output_format": args.openai_output_format,
    }
    body, content_type = encode_multipart_form(
        fields,
        [("image[]", input_png, "image/png")],
    )
    request = urllib.request.Request(
        OPENAI_IMAGES_EDIT_URL,
        data=body,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": content_type,
            "User-Agent": USER_AGENT,
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            raw_response = response.read()
            request_id = response.headers.get("x-request-id", "")
    except urllib.error.HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"OpenAI image edit failed ({exc.code}): {details}") from exc

    payload = json.loads(raw_response.decode("utf-8"))
    data = payload.get("data") or []
    if not data or not data[0].get("b64_json"):
        raise RuntimeError(f"OpenAI response did not include image data: {payload}")

    model_slug = safe_slug(args.openai_model)
    output = ai_dir / f"{item.item_id}_openai_{model_slug}_{args.openai_quality}.{args.openai_output_format}"
    output.write_bytes(base64.b64decode(data[0]["b64_json"]))
    output.with_suffix(output.suffix + ".json").write_text(
        json.dumps(
            {
                "item_id": item.item_id,
                "source": item.source,
                "model": args.openai_model,
                "quality": args.openai_quality,
                "size": args.openai_size,
                "output_format": args.openai_output_format,
                "request_id": request_id,
                "prompt": prompt,
                "created_at": datetime.now(timezone.utc).isoformat(),
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    return output


def default_openai_product_prompt(item: ImageInput) -> str:
    product_hint = f" Product name/context: {item.name}." if item.name else ""
    return (
        "Create a premium ecommerce product photo using the supplied product image as reference."
        f"{product_hint} Keep a clean white studio background, centered front-facing composition, "
        "crisp edges, realistic lighting, and high-resolution catalog quality. Preserve the same "
        "product type, model family, colors, package shape, visible brand marks, and major visible "
        "label text. Do not add extra accessories, change the product variant, change colors, or invent "
        "new claims. If tiny source text is unreadable, keep it visually subtle instead of fabricating "
        "incorrect text."
    )


def encode_multipart_form(
    fields: dict[str, str],
    files: list[tuple[str, Path, str]],
) -> tuple[bytes, str]:
    boundary = "----VinabikeImageBoundary" + hashlib.sha256(os.urandom(16)).hexdigest()
    chunks: list[bytes] = []

    for name, value in fields.items():
        chunks.extend(
            [
                f"--{boundary}\r\n".encode(),
                f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode(),
                str(value).encode("utf-8"),
                b"\r\n",
            ]
        )

    for name, path, mime_type in files:
        chunks.extend(
            [
                f"--{boundary}\r\n".encode(),
                (
                    f'Content-Disposition: form-data; name="{name}"; '
                    f'filename="{path.name}"\r\n'
                ).encode(),
                f"Content-Type: {mime_type}\r\n\r\n".encode(),
                path.read_bytes(),
                b"\r\n",
            ]
        )

    chunks.append(f"--{boundary}--\r\n".encode())
    return b"".join(chunks), f"multipart/form-data; boundary={boundary}"


def make_comparison_sheet(
    *,
    original_path: Path,
    safe_path: Path,
    ai_path: Path,
    output_path: Path,
    item_id: str,
) -> None:
    images = [
        ("Original", original_path),
        ("Safe cleanup", safe_path),
        ("AI/upscale test", ai_path),
    ]
    tile_w, tile_h = 420, 480
    label_h = 44
    sheet = Image.new("RGB", (tile_w * len(images), tile_h + label_h), "white")

    for i, (label, path) in enumerate(images):
        with Image.open(path) as raw:
            img = ImageOps.exif_transpose(raw)
            img = flatten_to_background(img, (255, 255, 255))
            img.thumbnail((tile_w - 32, tile_h - 32), Image.Resampling.LANCZOS)
            x = (i * tile_w) + ((tile_w - img.width) // 2)
            y = label_h + ((tile_h - img.height) // 2)
            sheet.paste(img, (x, y))

        # Plain PIL text keeps this dependency-free. It is small but enough.
        sheet.paste(Image.new("RGB", (tile_w, label_h), (245, 247, 250)), (i * tile_w, 0))
        from PIL import ImageDraw

        draw = ImageDraw.Draw(sheet)
        draw.text((i * tile_w + 16, 14), f"{label} - {item_id}", fill=(31, 41, 55))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output_path, "JPEG", quality=92)


def flatten_to_background(image: Image.Image, bg_rgb: tuple[int, int, int]) -> Image.Image:
    if image.mode in ("RGBA", "LA") or ("transparency" in image.info):
        rgba = image.convert("RGBA")
        bg = Image.new("RGBA", rgba.size, (*bg_rgb, 255))
        bg.alpha_composite(rgba)
        return bg.convert("RGB")
    return image.convert("RGB")


def find_subject_bbox(image: Image.Image) -> tuple[int, int, int, int] | None:
    if image.mode in ("RGBA", "LA"):
        alpha = image.getchannel("A")
        bbox = alpha.getbbox()
        if bbox:
            return bbox

    rgb = image.convert("RGB")
    bg = estimate_corner_background(rgb)
    bg_image = Image.new("RGB", rgb.size, bg)
    diff = ImageChops.difference(rgb, bg_image).convert("L")
    mask = diff.point(lambda p: 255 if p > 18 else 0)
    bbox = mask.getbbox()
    if not bbox:
        return None

    # Ignore accidental tiny dust/noise boxes.
    image_area = rgb.width * rgb.height
    if bbox_area_ratio(bbox, rgb.width, rgb.height) < 0.01 and image_area > 120_000:
        return None
    return bbox


def estimate_corner_background(image: Image.Image) -> tuple[int, int, int]:
    w, h = image.size
    sample = max(4, min(w, h) // 16)
    crops = [
        image.crop((0, 0, sample, sample)),
        image.crop((w - sample, 0, w, sample)),
        image.crop((0, h - sample, sample, h)),
        image.crop((w - sample, h - sample, w, h)),
    ]
    pixels: list[tuple[int, int, int]] = []
    for crop in crops:
        pixels.extend(list(crop.resize((1, 1)).getdata()))
    channels = list(zip(*pixels))
    return tuple(int(sorted(channel)[len(channel) // 2]) for channel in channels)  # type: ignore[return-value]


def add_bbox_margin(
    bbox: tuple[int, int, int, int],
    image_size: tuple[int, int],
    *,
    margin: int,
) -> tuple[int, int, int, int]:
    left, top, right, bottom = bbox
    width, height = image_size
    return (
        max(0, left - margin),
        max(0, top - margin),
        min(width, right + margin),
        min(height, bottom + margin),
    )


def bbox_area_ratio(bbox: tuple[int, int, int, int] | None, width: int, height: int) -> float:
    if not bbox or width <= 0 or height <= 0:
        return 0.0
    left, top, right, bottom = bbox
    return ((right - left) * (bottom - top)) / float(width * height)


def blur_score(image: Image.Image) -> float:
    gray = image.convert("L")
    gray.thumbnail((640, 640), Image.Resampling.BILINEAR)
    if np is not None:
        arr = np.asarray(gray, dtype=np.float32)
        center = arr[1:-1, 1:-1] * -4
        lap = (
            center
            + arr[:-2, 1:-1]
            + arr[2:, 1:-1]
            + arr[1:-1, :-2]
            + arr[1:-1, 2:]
        )
        return float(lap.var())

    edges = gray.filter(ImageFilter.FIND_EDGES)
    return float(ImageStat.Stat(edges).var[0])


def border_white_score(image: Image.Image) -> float:
    rgb = flatten_to_background(image, (255, 255, 255))
    w, h = rgb.size
    border = max(3, min(w, h) // 25)
    strips = [
        rgb.crop((0, 0, w, border)),
        rgb.crop((0, h - border, w, h)),
        rgb.crop((0, 0, border, h)),
        rgb.crop((w - border, 0, w, h)),
    ]
    total = 0
    white = 0
    for strip in strips:
        thumb = strip.resize((max(1, strip.width // 8), max(1, strip.height // 8)))
        for r, g, b in thumb.getdata():
            total += 1
            if r >= 245 and g >= 245 and b >= 245:
                white += 1
    return white / total if total else 0.0


def image_has_alpha(image: Image.Image) -> bool:
    return image.mode in ("RGBA", "LA") or ("transparency" in image.info)


def quality_flags(
    width: int,
    height: int,
    blur: float,
    subject_fill: float,
    white_score: float,
    has_alpha: bool,
) -> list[str]:
    flags: list[str] = []
    min_side = min(width, height)
    max_side = max(width, height)
    if min_side < 500:
        flags.append("below_merchant_min_500")
    if max_side < 1200:
        flags.append("small_for_zoom")
    if blur < 55:
        flags.append("likely_blurry")
    if subject_fill and subject_fill < 0.22:
        flags.append("too_much_whitespace")
    if subject_fill > 0.92:
        flags.append("too_tight")
    if white_score < 0.6:
        flags.append("non_white_or_busy_background")
    if has_alpha:
        flags.append("transparent_source")
    if not flags:
        flags.append("ok")
    return flags


def recommendation(flags: list[str]) -> str:
    flag_set = set(flags)
    if "below_merchant_min_500" in flag_set:
        return "Replace or AI-test upscale; source is too small"
    if "likely_blurry" in flag_set and "small_for_zoom" in flag_set:
        return "AI-test upscale, then manually review"
    if "non_white_or_busy_background" in flag_set or "too_much_whitespace" in flag_set:
        return "Safe cleanup and white-canvas standardization"
    if flags == ["ok"]:
        return "Keep; optional WebP optimization"
    return "Review"


def write_audit_reports(out_dir: Path, rows: list[AuditResult]) -> None:
    write_csv(out_dir / "audit.csv", [asdict(row) for row in rows])
    with open(out_dir / "audit.jsonl", "w", encoding="utf-8") as fh:
        for row in rows:
            fh.write(json.dumps(asdict(row), ensure_ascii=False) + "\n")

    summary = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "total": len(rows),
        "ok": sum(1 for row in rows if row.ok),
        "failed": sum(1 for row in rows if not row.ok),
        "flag_counts": count_flags(row.flags for row in rows),
    }
    (out_dir / "audit_summary.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )


def write_process_reports(out_dir: Path, rows: list[ProcessResult]) -> None:
    write_csv(out_dir / "process_report.csv", [asdict(row) for row in rows])
    with open(out_dir / "process_report.jsonl", "w", encoding="utf-8") as fh:
        for row in rows:
            fh.write(json.dumps(asdict(row), ensure_ascii=False) + "\n")


def write_csv(path: Path, rows: list[dict]) -> None:
    if not rows:
        return
    with open(path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def count_flags(flag_strings: Iterable[str]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for flag_string in flag_strings:
        for flag in flag_string.split("|"):
            if not flag:
                continue
            counts[flag] = counts.get(flag, 0) + 1
    return dict(sorted(counts.items(), key=lambda item: (-item[1], item[0])))


def cleanup_work_dir(work_dir: Path) -> None:
    if not work_dir.exists():
        return
    for child in work_dir.iterdir():
        if child.is_file():
            child.unlink()
        elif child.is_dir():
            shutil.rmtree(child)


def is_url(value: str) -> bool:
    parsed = urllib.parse.urlparse(value)
    return parsed.scheme in {"http", "https"}


def extension_from_source(source: str) -> str:
    path = urllib.parse.urlparse(source).path if is_url(source) else source
    ext = Path(path).suffix.lower()
    if ext in {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".tif", ".tiff"}:
        return ext
    return ".jpg"


def stable_id(value: str, index: int) -> str:
    stem = safe_slug(Path(urllib.parse.urlparse(value).path).stem)
    digest = hashlib.sha1(value.encode("utf-8")).hexdigest()[:8]
    if stem:
        return f"{stem[:40]}_{digest}"
    return f"image_{index:04d}_{digest}"


def safe_slug(value: str) -> str:
    out = []
    for char in value.lower().strip():
        if char.isalnum():
            out.append(char)
        elif char in {"-", "_", ".", " "}:
            out.append("-")
    slug = "".join(out).strip("-")
    while "--" in slug:
        slug = slug.replace("--", "-")
    return slug or "image"


if __name__ == "__main__":
    raise SystemExit(main())
