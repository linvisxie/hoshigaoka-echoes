"""Read-only pixel/transition checks and derived animation evidence."""
from pathlib import Path
import argparse,json
import numpy as np
from PIL import Image

p=argparse.ArgumentParser();p.add_argument('evidence',type=Path);a=p.parse_args()
images=a.evidence/'appdata/HoshigaokaEchoes/frontend_shots'
checks=[]
def pixels(name):return np.asarray(Image.open(images/name).convert('RGB')).astype(float)
def check(ok,name,**details):checks.append(dict(ok=bool(ok),name=name,**details))
for locale in ('zh','en'):
    ref=pixels(f'static_reference_{locale}.png');animated=pixels(f'motion_reference_{locale}.png')
    h,w=ref.shape[:2]
    if abs(w/h-1672/941)<.002:sx,sy,ox,oy=w/1672,h/941,0,0
    else:sx=sy=min(w/1672,h/941);ox,oy=np.floor((w-1672*sx)/2),np.floor((h-941*sy)/2)
    def region(rect):
        x,y,r,b=rect
        return (slice(round(oy+y*sy),round(oy+b*sy)),slice(round(ox+x*sx),round(ox+r*sx)))
    for name,rect in {'footer':(0,858,450,941),'header':(22,22,374,108),'resources':(1339,29,1589,67),'handbook':(1454,92,1659,474),'card':(1220,695,1644,863)}.items():
        peak=float(abs(ref[region(rect)]-animated[region(rect)]).max())
        check(peak==0,name+' preserved '+locale,maximumPixelDifference=peak)
    brightness=float(animated[region((280,520,322,580))].mean()/ref[region((280,520,322,580))].mean())
    check(abs(brightness-1)<.04,'original character color '+locale,brightnessRatio=brightness)
    transitions=[pixels(f'transition_{locale}_{i}.png') for i in range(12)]
    minimum=float(min(frame.mean() for frame in transitions))
    check(minimum>20,'no black captured transition frame '+locale,minimumFrameMean=minimum,sampledFrames=12)
    setting_frames=[pixels(f'settings_transition_{locale}_{i}.png') for i in range(12)]
    check(min(frame.mean() for frame in setting_frames)>20,'settings crossfade has no black captured frame '+locale)
    wind=[pixels(f'wind_{locale}_{i}.png') for i in range(12)]
    for name,rect in {'sky':(1030,20,1320,160),'paper':(33,416,148,530),'foliage':(420,140,570,230)}.items():
        bounds=region(rect)
        difference=np.max(np.stack([abs(frame[bounds]-wind[0][bounds]).max(axis=2) for frame in wind[1:]]),axis=0)
        fraction=float((difference>2).mean())
        check(fraction>.001,'visible '+name+' motion '+locale,changedPixelFraction=fraction,maximumPixelDifference=float(difference.max()))
    for prefix,count,duration in [('transition',12,70),('settings_transition',12,70),('wind',12,240),('title_motion',6,320),('unread_fixture',5,420)]:
        frames=[Image.open(images/f'{prefix}_{locale}_{i}.png').convert('RGB') for i in range(count)]
        # Derived preview only; source captures remain full resolution and unchanged.
        for frame in frames:frame.thumbnail((960,540))
        frames[0].save(a.evidence/f'{prefix}_{locale}.gif',save_all=True,append_images=frames[1:],duration=duration,loop=0)
report=dict(ok=all(c['ok'] for c in checks),checks=checks,type='Rendered pixel comparison; wind captures hide petals to isolate foliage/paper/sky; unread fixture is presentation-only')
(a.evidence/'visual_regression.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(report,ensure_ascii=False))
raise SystemExit(0 if report['ok'] else 1)
