"""Render the build-14 iPhone App Store set from genuine iOS captures.

Use --draft while any source is pending. Final rendering is all-or-nothing: no
placeholder, old-build screenshot or diagnostic UI can be exported. Interface
pixels are scaled, never redrawn. Both current iPhone display sizes are emitted.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "artifacts/app-store-2.1.1-14"
CONFIG = BASE / "design/poster-sources.json"
TEXTURE = BASE / "design/paper-background-ai.png"
WIDTH, HEIGHT = 1320, 2868
PAPER = "#F6F6F3"
INK = "#222828"
BLUE = "#365F70"
MUTED = "#667073"
CJK = "/System/Library/Fonts/Hiragino Sans GB.ttc"
LATIN = "/System/Library/Fonts/HelveticaNeue.ttc"
BRAND = ROOT / "assets/fonts/lingfer-display-semibold.ttf"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def font(size: int, weight: str = "regular") -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(CJK, size, index=2 if weight == "bold" else 0)


def text(
    canvas: Image.Image,
    value: str,
    xy: tuple[int, int],
    size: int,
    color: str = INK,
    weight: str = "regular",
) -> None:
    draw = ImageDraw.Draw(canvas)
    face = font(size, weight)
    bounds = draw.textbbox(xy, value, font=face, anchor="lt")
    if bounds[0] < 0 or bounds[2] > WIDTH - 64:
        raise ValueError(f"Poster copy would clip: {value}")
    draw.text(xy, value, font=face, fill=color, anchor="lt")


def background() -> Image.Image:
    grain = ImageOps.fit(
        Image.open(TEXTURE).convert("RGB"),
        (WIDTH, HEIGHT),
        method=Image.Resampling.LANCZOS,
        centering=(0.5, 0.5),
    )
    # The pre-existing AI asset is background only. Keep its fold restrained.
    return Image.blend(Image.new("RGB", grain.size, PAPER), grain, 0.22).convert(
        "RGBA"
    )


def phone(canvas: Image.Image, source: Path, y: int = 692) -> dict:
    screenshot = Image.open(source).convert("RGB")
    screen_width = 960
    screen_height = round(screenshot.height * screen_width / screenshot.width)
    rim = 13
    outer_width, outer_height = screen_width + rim * 2, screen_height + rim * 2
    x = (WIDTH - outer_width) // 2
    if y + outer_height > HEIGHT - 48:
        raise ValueError(f"Phone would clip: {source}")

    shadow = Image.new("RGBA", canvas.size)
    ImageDraw.Draw(shadow).rounded_rectangle(
        (x - 4, y + 17, x + outer_width + 4, y + outer_height + 17),
        104,
        fill=(27, 40, 44, 45),
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(30)))
    draw = ImageDraw.Draw(canvas)
    # Physical rim and side buttons are framing, not invented app/system UI.
    draw.rounded_rectangle(
        (x - 5, y + 220, x + 1, y + 288), 3, fill="#A9ADAD"
    )
    draw.rounded_rectangle(
        (x - 5, y + 325, x + 1, y + 425), 3, fill="#A9ADAD"
    )
    draw.rounded_rectangle(
        (x + outer_width - 1, y + 340, x + outer_width + 5, y + 485),
        3,
        fill="#A9ADAD",
    )
    draw.rounded_rectangle(
        (x, y, x + outer_width - 1, y + outer_height - 1),
        104,
        fill="#2B3338",
        outline="#A6ABAE",
        width=2,
    )
    picture = screenshot.resize(
        (screen_width, screen_height), Image.Resampling.LANCZOS
    ).convert("RGBA")
    mask = Image.new("L", picture.size)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, screen_width - 1, screen_height - 1), 91, fill=255
    )
    picture.putalpha(mask)
    canvas.alpha_composite(picture, (x + rim, y + rim))
    return {
        "screenRect": [x + rim, y + rim, screen_width, screen_height],
        "sourceSize": list(screenshot.size),
        "sourceCrop": None,
        "interfaceTransform": "uniform scale; rounded device-corner mask only",
        "hardware": "simple physical rim; no invented camera/Island content",
    }


def render(spec: dict, *, draft: bool) -> dict:
    approved = bool(spec.get("source"))
    relative = spec["source"] if approved else spec["draftSource"]
    source = ROOT / relative
    canvas = background()
    draw = ImageDraw.Draw(canvas)
    draw.text(
        (88, 74),
        "语渡",
        font=ImageFont.truetype(str(BRAND), 37),
        fill=BLUE,
        anchor="lt",
    )
    draw.text(
        (182, 85),
        "LINGFER",
        font=ImageFont.truetype(LATIN, 24, index=1),
        fill=BLUE,
        anchor="lt",
    )
    draw.text(
        (1107, 85),
        "iPhone",
        font=ImageFont.truetype(LATIN, 25),
        fill=MUTED,
        anchor="lt",
    )

    lines = spec["title"].split("\n")
    title_size = 114
    while max(draw.textlength(line, font=font(title_size, "bold")) for line in lines) > 1144:
        title_size -= 1
    for i, line in enumerate(lines):
        text(canvas, line, (86, 164 + i * 146), title_size, INK if i == 0 else BLUE, "bold")
    text(canvas, spec["subtitle"], (91, 484), 36, MUTED)
    text(canvas, spec["note"], (92, 552), 30, BLUE)
    composition = phone(canvas, source)

    if draft and not approved:
        # Deliberately outside the UI. A draft must never look upload-ready.
        draw = ImageDraw.Draw(canvas)
        draw.rounded_rectangle((87, 604, 1233, 659), 18, fill="#E8ECEA")
        text(canvas, "版式草稿 · 待本轮真实 iOS 画面", (113, 616), 27, BLUE)

    target = BASE / ("draft-previews" if draft else "screenshots-iphone")
    target.mkdir(parents=True, exist_ok=True)
    path = target / f"{spec['id']}.png"
    canvas.convert("RGB").save(path, optimize=True)
    return {
        "file": str(path.relative_to(BASE)),
        "size": [WIDTH, HEIGHT],
        "mode": "RGB",
        "sha256": sha256(path),
        "title": spec["title"],
        "subtitle": spec["subtitle"],
        "note": spec["note"],
        "source": relative,
        "sourceSha256": sha256(source),
        "sourceBuild": spec.get("sourceBuild") if approved else 14,
        "sourceKind": spec.get("sourceKind") if approved else "current iOS layout stand-in",
        "status": "layout-draft-source-pending" if not approved else "ready-for-review",
        "composition": composition,
        "approvedScreenshot": approved,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--draft", action="store_true")
    args = parser.parse_args()
    specs = json.loads(CONFIG.read_text())
    if len(specs) != 6:
        raise ValueError("Exactly six posters are required")
    if not args.draft:
        provenance = json.loads((BASE / "design/provenance.json").read_text())
        rejected_sources = {
            (BASE / item["file"]).resolve()
            for item in provenance.get("sources", [])
            if item.get("approvedForFinal") is False
        }
        missing = [spec["id"] for spec in specs if not spec.get("source")]
        if missing:
            raise ValueError(f"Cannot deliver placeholder screenshots: {missing}")
        for spec in specs:
            if (ROOT / spec["source"]).resolve() in rejected_sources:
                raise ValueError(f"Screenshot superseded by user feedback: {spec['id']}")
            if spec.get("sourceBuild") != 14 or spec.get("privacyReviewed") is not True:
                raise ValueError(f"Unreviewed or old screenshot: {spec['id']}")
            expected = spec.get("sourceSha256")
            if not expected or sha256(ROOT / spec["source"]) != expected:
                raise ValueError(f"Screenshot changed since visual approval: {spec['id']}")
    for spec in specs:
        source = ROOT / (spec["source"] or spec["draftSource"])
        if not source.is_file():
            raise FileNotFoundError(source)
    manifest = [render(spec, draft=args.draft) for spec in specs]
    medium_manifest = []
    if not args.draft:
        medium_dir = BASE / "screenshots-iphone-medium"
        medium_dir.mkdir(parents=True, exist_ok=True)
        for item in manifest:
            large = BASE / item["file"]
            image = Image.open(large).convert("RGB")
            # Fit 1320×2868 into 1206×2622 with one uniform scale. Rounded
            # height is 2620, leaving one pixel of paper above and below.
            scaled_size = (1206, round(HEIGHT * 1206 / WIDTH))
            resized = image.resize(scaled_size, Image.Resampling.LANCZOS)
            medium = Image.new("RGB", (1206, 2622), PAPER)
            offset = (0, (2622 - scaled_size[1]) // 2)
            medium.paste(resized, offset)
            path = medium_dir / large.name
            medium.save(path, optimize=True)
            medium_manifest.append({
                "file": str(path.relative_to(BASE)),
                "size": [1206, 2622],
                "mode": "RGB",
                "sha256": sha256(path),
                "largePoster": item["file"],
                "largePosterSha256": item["sha256"],
                "source": item["source"],
                "sourceSha256": item["sourceSha256"],
                "transform": {
                    "method": "uniform proportional fit; LANCZOS",
                    "nominalScale": 1206 / WIDTH,
                    "resampledSize": list(scaled_size),
                    "paddingLeftTopRightBottom": [0, offset[1], 0, 2622 - scaled_size[1] - offset[1]],
                    "paper": PAPER,
                    "interfaceRedrawn": False,
                },
            })
        (BASE / "screenshots-medium-manifest.json").write_text(
            json.dumps(medium_manifest, ensure_ascii=False, indent=2) + "\n"
        )
    sheet = Image.new("RGB", (1320, 1954), PAPER)
    for index, item in enumerate(manifest):
        thumb = Image.open(BASE / item["file"]).resize(
            (432, 939), Image.Resampling.LANCZOS
        )
        sheet.paste(thumb, ((index % 3) * 440 + 4, (index // 3) * 969 + 4))
    sheet_name = "draft-contact-sheet.jpg" if args.draft else "poster-contact-sheet.jpg"
    sheet.save(BASE / sheet_name, quality=95)
    filename = "draft-manifest.json" if args.draft else "screenshots-manifest.json"
    (BASE / filename).write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"Rendered {len(manifest)} {'drafts' if args.draft else 'final review assets'}: {WIDTH}×{HEIGHT} RGB")
    if medium_manifest:
        print(f"Also rendered {len(medium_manifest)} medium iPhone assets: 1206×2622 RGB")


if __name__ == "__main__":
    main()
