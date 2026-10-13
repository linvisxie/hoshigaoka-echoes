"""Compare the approved raster against an actual Godot viewport capture."""
from pathlib import Path
import argparse, json
from PIL import Image, ImageChops

p = argparse.ArgumentParser()
p.add_argument('--capture', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
reference = Path(__file__).resolve().parents[1]/'assets/art/hub/campus_approved.png'
approved = Image.open(reference).convert('RGB')
actual = Image.open(a.capture).convert('RGB')
assert approved.size == actual.size == (1672, 941)
# Currency uses the existing game skin. The unread badge follows real progress.
masks = [(1337,24,1590,72), (1284,426,1434,506)]
diff = ImageChops.difference(approved, actual)
mask = Image.new('L', approved.size, 255)
for bounds in masks:
    diff.paste((0,0,0), bounds)
    mask.paste(0, bounds)
considered = mask.histogram()[255]
different = sum(pixel != (0,0,0) for pixel in diff.getdata())
report = {'ok':different == 0, 'reference':str(reference), 'capture':str(a.capture),
          'resolution':approved.size, 'excludedRectangles':masks,
          'consideredPixels':considered, 'differentPixels':different,
          'exactPixelsPercent':100*(considered-different)/considered,
          'scope':'1-3 reference fixture at rest; live currencies/unread badge excluded; source runtime viewport capture'}
a.output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(report,ensure_ascii=False))
assert report['ok']
