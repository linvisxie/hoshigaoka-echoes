"""Compare snapshots taken from five actual Windows battle scene instances."""
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'_testenv/v3-round9'
snapshots={}
missing=[]
for stage in range(1,6):
    folder=BASE/f'layout_stage_{stage}'
    probe=json.loads((folder/'appdata/HoshigaokaEchoes/art_probe/latest.json').read_text(encoding='utf8'))
    assert probe['stage']==f'1-{stage}'
    snapshots[f'1-{stage}']=probe['layout']
    if not (folder/'initial.png').exists():missing.append(f'1-{stage}')
baseline=snapshots['1-1']
for stage,layout in snapshots.items():
    assert layout==baseline, f'Actual layout drift in {stage}'
    assert len(layout['cells'])==18
report={'evidenceType':'Snapshots from five real Windows game instances; screenshots retained separately',
    'identicalCoreCellAndHudGeometry':True,'stages':list(snapshots),'missingScreenshots':missing,'layout':baseline}
(BASE/'layout_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('Identical geometry across five real scene instances; missing screenshots:',missing)
if missing:raise SystemExit(2)
