"""Keep original captures and reports; create a separately labeled animation preview."""
from pathlib import Path
import hashlib,json,shutil
from PIL import Image,ImageChops
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'_testenv/v3-round10'
OUT=ROOT/'docs/art_screenshots/v3_eight_fixes_20261011'
OUT.mkdir(parents=True,exist_ok=True)
records=[]
def retain(source,name):
 assert source.is_file(),str(source)
 target=OUT/name;shutil.copy2(source,target)
 records.append({'file':name,'source':str(source),'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
for prefix,folder in [('ui',BASE/'ui_verified/appdata/HoshigaokaEchoes/frontend_shots'),('retail',BASE/'retail_final')]:
 for p in sorted(folder.glob('*.png')):
  retain(p,prefix+'_'+p.name)
  sidecar=p.with_suffix('.png.json')
  if sidecar.exists():retain(sidecar,prefix+'_'+sidecar.name)
for name,path in {
 'ui_report.json':'ui_verified/appdata/HoshigaokaEchoes/round10_ui_report.json',
 'retail_report.json':'retail_final/retail_report.json',
 'regression.txt':'regression_release/gut.log',
 'retail_runtime.txt':'retail_final/game.log',
}.items():retain(BASE/path,name)
for index,filename in enumerate([
 'codex-clipboard-d53df685-ae94-48a6-89d3-29d8a229348d.png',
 'codex-clipboard-32ce3413-ec91-4860-9e31-54c06c4bd9a9.png',
 'codex-clipboard-5b02dcfe-7da3-4906-90a5-83cf4b8d8529.png',
 'codex-clipboard-ee0b0182-16e4-4294-ac09-d0f093856f2b.png',
 'codex-clipboard-8a91dcfc-eeb1-46ba-bf85-c6d62faf0adb.png',
 'codex-clipboard-eea905d9-dcd3-425f-96e7-aea74cb611f0.png',
],1):retain(Path(r'C:\Users\LINVIS~1\AppData\Local\Temp')/filename,f'user_before_{index}.png')
report=json.loads((OUT/'ui_report.json').read_text(encoding='utf8'))
assert all(item['ok'] for item in report['checks']), 'UI evidence must be a passing run'
frames=[Image.open(p).convert('RGB') for p in sorted(OUT.glob('ui_core_turn_*.png'))]
assert len(frames)==16
# This is a derived preview, never substituted for the original screenshots above.
frames[0].save(OUT/'core_rotation_preview.gif',save_all=True,append_images=frames[1:],duration=160,loop=0,optimize=False)
w,h=frames[0].size
close_region=(round(w*.025),round(h*.37),round(w*.15),round(h*.69))
closeups=[p.crop(close_region).resize((320,460),Image.Resampling.NEAREST) for p in frames]
closeups[0].save(OUT/'core_rotation_closeup.gif',save_all=True,append_images=closeups[1:],duration=160,loop=0,optimize=False)
region=(round(w*.055),round(h*.42),round(w*.12),round(h*.56))
different=sum(ImageChops.difference(frames[0].crop(region),p.crop(region)).getbbox() is not None for p in frames[1:])
assert different>=8,'Crystal region must visibly change across real frames'
(OUT/'evidence_manifest.json').write_text(json.dumps({'version':'0.4.7','type':'Original Windows runtime screenshots, automated input; user aesthetic acceptance pending','uiChecks':len(report['checks']),'coreFrameCount':16,'coreChangedFramesComparedWithFirst':different,'preview':'GIFs are derived timing previews (closeup is cropped and enlarged); original ui_core_turn PNGs are retained','uiRevision':'Final UI/art and AP/retry behavior; before moving legacy normalization to App and explicit shutdown cache release','retailRevision':'Final exported binary, including explicit cache release; real OS input','regression':'602/602,10159 assertions; existing GUT shutdown resource warnings remain','files':records},ensure_ascii=False,indent=2),encoding='utf8')
print(f'Retained {len(records)} original evidence files; {different}/15 changed core regions.')
