"""Compose iPad App Store artwork from genuine iPad screenshots only.

Never stretches iPhone UI or redraws app interface pixels. The capture source
configuration is validated against the actual raw PNG before any output exists.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'artifacts/app-store-2.1.1-14'
WIDTH, HEIGHT = 2064, 2752
PAPER, INK, BLUE, MUTED = '#F6F6F3', '#222828', '#365F70', '#667073'
CJK = '/System/Library/Fonts/Hiragino Sans GB.ttc'
LATIN = '/System/Library/Fonts/HelveticaNeue.ttc'


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def font(size: int, bold=False):
    return ImageFont.truetype(CJK, size, index=2 if bold else 0)


def render(spec: dict) -> dict:
    raw = ROOT / spec['source']
    picture = Image.open(raw).convert('RGB')
    if picture.size != (2064, 2752):
        raise ValueError(f'Actual 13-inch iPad capture required, received {picture.size}: {raw}')
    texture = ImageOps.fit(Image.open(BASE/'design/paper-background-ai.png').convert('RGB'), (WIDTH, HEIGHT), method=Image.Resampling.LANCZOS)
    canvas = Image.blend(Image.new('RGB', (WIDTH, HEIGHT), PAPER), texture, .22).convert('RGBA')
    d = ImageDraw.Draw(canvas)
    d.text((136, 74), '语渡', font=ImageFont.truetype(str(ROOT/'assets/fonts/lingfer-display-semibold.ttf'), 43), fill=BLUE, anchor='lt')
    d.text((245, 86), 'LINGFER', font=ImageFont.truetype(LATIN, 29, index=1), fill=BLUE, anchor='lt')
    d.text((1820, 85), 'iPad', font=ImageFont.truetype(LATIN, 32), fill=MUTED, anchor='lt')
    lines=spec['title'].split('\n')
    size=138
    while max(d.textlength(line, font=font(size, True)) for line in lines)>WIDTH-272:
        size-=1
    for n,line in enumerate(lines):
        d.text((132, 170+n*164),line,font=font(size,True),fill=INK if n==0 else BLUE,anchor='lt')
    for value,y,sz,color in [(spec['subtitle'],510,42,MUTED),(spec['note'],584,35,BLUE)]:
        bounds=d.textbbox((140,y),value,font=font(sz),anchor='lt')
        if bounds[2]>WIDTH-132:raise ValueError(f'Copy would clip: {value}')
        d.text((140,y),value,font=font(sz),fill=color,anchor='lt')
    screen_width=1450
    screen_height=round(picture.height*screen_width/picture.width)
    rim=15;outerw=screen_width+2*rim;outerh=screen_height+2*rim
    x=(WIDTH-outerw)//2;y=715
    assert y+outerh<HEIGHT-45
    shadow=Image.new('RGBA',canvas.size)
    ImageDraw.Draw(shadow).rounded_rectangle((x-3,y+18,x+outerw+3,y+outerh+18),66,fill=(27,40,44,46))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(34)))
    d=ImageDraw.Draw(canvas)
    d.rounded_rectangle((x,y,x+outerw-1,y+outerh-1),60,fill='#2B3338',outline='#A6ABAE',width=2)
    resized=picture.resize((screen_width,screen_height),Image.Resampling.LANCZOS).convert('RGBA')
    mask=Image.new('L',resized.size)
    ImageDraw.Draw(mask).rounded_rectangle((0,0,screen_width-1,screen_height-1),47,fill=255)
    resized.putalpha(mask);canvas.alpha_composite(resized,(x+rim,y+rim))
    directory=BASE/'screenshots-ipad';directory.mkdir(exist_ok=True)
    target=directory/(spec['id']+'.png');canvas.convert('RGB').save(target,optimize=True)
    return dict(file=str(target.relative_to(BASE)),size=[WIDTH,HEIGHT],mode='RGB',bitDepth=8,alpha=False,sha256=digest(target),source=spec['source'],sourceSha256=digest(raw),sourceBuild=14,title=spec['title'],subtitle=spec['subtitle'],note=spec['note'],composition=dict(sourceSize=list(picture.size),sourceCrop=None,screenRect=[x+rim,y+rim,screen_width,screen_height],interfaceTransform='Uniform proportional scale with integer raster rounding; tablet-corner mask only',hardware='Simple tablet rim; no invented app, camera or system UI'),captureTest=spec['captureTest'])


def main():
    specs=json.loads((BASE/'design/ipad-poster-sources.json').read_text())
    if len(specs)!=6:raise ValueError('Exactly six reviewed iPad sources required')
    for s in specs:
        if not s.get('source') or s.get('sourceBuild')!=14 or s.get('privacyReviewed') is not True:
            raise ValueError(f'Unreviewed/pending iPad source: {s["id"]}')
        if digest(ROOT/s['source'])!=s['sourceSha256']:raise ValueError('Source changed after review')
    manifest=[render(s) for s in specs]
    (BASE/'screenshots-ipad-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    # Compact six-up view retains each complete canvas at uniform scale.
    sheet=Image.new('RGB',(1548,1376),PAPER)
    for n,item in enumerate(manifest):
        thumb=Image.open(BASE/item['file']).resize((510,680),Image.Resampling.LANCZOS)
        sheet.paste(thumb,((n%3)*516+3,(n//3)*688+3))
    sheet.save(BASE/'ipad-poster-contact-sheet.jpg',quality=95)
    print('Rendered six actual-iPad posters: 2064×2752 RGB8')


if __name__=='__main__':main()
