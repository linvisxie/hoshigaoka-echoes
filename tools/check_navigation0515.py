from pathlib import Path
from PIL import Image
import numpy as np,json
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'_testenv/navigation0515'
for run in ('ui720_final','ui1080_final'):
 d=BASE/run/'appdata/HoshigaokaEchoes/frontend_shots'
 metrics={}
 for locale in ('zh','en'):
  a=np.asarray(Image.open(d/('warm_before_'+locale+'.png')),dtype=float)
  b=np.asarray(Image.open(d/('warm_after_'+locale+'.png')),dtype=float)
  h,w=a.shape[:2]; x=int(350*w/1672);y=int(537*h/941);r=int(40*w/1672)
  before=float(a[y-r:y+r,x-r:x+r,:3].mean());after=float(b[y-r:y+r,x-r:x+r,:3].mean())
  assert after>before+10, (run,locale,before,after)
  metrics[locale]=dict(before=before,after=after,increasePercent=(after/before-1)*100)
 report=dict(ok=True,metrics=metrics,scope='Rendered window light region; does not measure human preference')
 (BASE/run/'visual_regression.json').write_text(json.dumps(report,indent=2),encoding='utf8')
 print(run,metrics)
