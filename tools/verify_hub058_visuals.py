"""Check captured Hub lettering for dark backing blocks and ambient movement."""
from pathlib import Path
import argparse,json
from PIL import Image,ImageChops,ImageStat

p=argparse.ArgumentParser()
p.add_argument('--shots',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args()
root=Path(__file__).resolve().parents[1]
reference=Image.open(root/'assets/art/hub/campus_approved.png').convert('RGB')
actual=Image.open(a.shots/'hub_reference.png').convert('RGB')
later=Image.open(a.shots/'hub_petals_later.png').convert('RGB')
assert actual.size==reference.size==(1672,941)
bounds=[(121,37,350,77),(630,281,708,311),(425,351,550,383),
        (810,374,901,404),(1051,423,1119,454),(1335,441,1403,471),
        (77,870,421,901),(41,334,187,407)]
regions=[]
for box in bounds:
    before=ImageStat.Stat(reference.crop(box).convert('L')).mean[0]
    after=ImageStat.Stat(actual.crop(box).convert('L')).mean[0]
    regions.append({'bounds':box,'brightnessRatio':after/before,'ok':.9<after/before<1.12})
moving=ImageChops.difference(actual,later).getbbox() is not None
report={'ok':all(r['ok'] for r in regions) and moving,'noDarkGlyphBacking':regions,
        'ambientChangesBetweenFrames':moving,
        'scope':'1672x941 runtime captures; brightness check detects dark rectangle regression; human visual inspection also required'}
a.output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(report,ensure_ascii=False))
assert report['ok']
