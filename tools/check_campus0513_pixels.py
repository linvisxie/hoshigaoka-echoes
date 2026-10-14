"""Compare rendered evidence, without changing source art or screenshots."""
from pathlib import Path
import argparse, json
import numpy as np
from PIL import Image

p=argparse.ArgumentParser()
p.add_argument('evidence',type=Path)
a=p.parse_args()
checks=[]
for locale in ('zh','en'):
    images=a.evidence/'appdata/HoshigaokaEchoes/frontend_shots'
    reference=np.asarray(Image.open(images/f'static_reference_{locale}.png').convert('RGB')).astype(float)
    motion=np.asarray(Image.open(images/f'motion_reference_{locale}.png').convert('RGB')).astype(float)
    h,w=reference.shape[:2]
    if abs(w/h-1672/941)<.002:
        sx,sy,ox,oy=w/1672,h/941,0,0
    else:
        sx=sy=min(w/1672,h/941)
        ox,oy=np.floor((w-1672*sx)/2),np.floor((h-941*sy)/2)
    def region(rect):
        x,y,r,b=rect
        return (slice(round(oy+y*sy),round(oy+b*sy)),slice(round(ox+x*sx),round(ox+r*sx)))
    for name,rect in {'footer':(0,858,450,941),'header':(22,22,374,108),'resources':(1339,29,1589,67),'handbook':(1454,92,1659,474),'card':(1220,695,1644,863)}.items():
        bounds=region(rect)
        peak=float(abs(reference[bounds]-motion[bounds]).max())
        checks.append(dict(locale=locale,name=name,ok=peak==0,maximumPixelDifference=peak))
    bounds=region((280,520,322,580))
    before=reference[bounds].mean()
    after=motion[bounds].mean()
    ratio=float(after/before)
    checks.append(dict(locale=locale,name='original_character_brightness',ok=abs(ratio-1)<.04,ratio=ratio))
    # Animated evidence only, never used as a game asset.
    frames=[Image.open(images/f'motion_{i}_{locale}.png').convert('RGB') for i in range(12)]
    frames[0].save(a.evidence/f'campus_motion_{locale}.gif',save_all=True,append_images=frames[1:],duration=100,loop=0)
report=dict(ok=all(c['ok'] for c in checks),checks=checks,type='Rendered pixel comparison with effects enabled/disabled, petals hidden in both references')
(a.evidence/'visual_regression.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(report,ensure_ascii=False))
raise SystemExit(0 if report['ok'] else 1)
