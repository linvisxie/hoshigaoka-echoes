"""Record imported UI resources and faithful concept derivatives, without claiming art acceptance."""
from pathlib import Path
import hashlib,json,urllib.request
ROOT=Path(__file__).resolve().parents[1]
DOWNLOADS=Path('D:/星丘基础/downloads/ui-polish')
url='https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/LICENSE'
license_path=ROOT/'assets/licenses/NotoSansCJK-OFL.txt'
if not license_path.exists():
    data=urllib.request.urlopen(url,timeout=45).read()
    assert b'SIL OPEN FONT LICENSE' in data
    (DOWNLOADS/'SANS_FONT_LICENSE.txt').write_bytes(data)
    license_path.write_bytes(data)
path=ROOT/'docs/v3_round3_external_assets.json'
record=json.loads(path.read_text(encoding='utf8'))
record['sources']=[s for s in record['sources'] if s['asset'] not in ['Noto Sans CJK SC Regular','VSCO 2 Community Edition Upright Piano']]
record['sources'] += [
 {'asset':'Noto Sans CJK SC Regular','url':'https://github.com/notofonts/noto-cjk','license':'SIL OFL 1.1','usage':'body text; unmodified font'},
 {'asset':'VSCO 2 Community Edition Upright Piano','url':'https://github.com/sgossner/VSCO-2-CE',
  'license':'CC0-1.0','authors':'Versilian Studios / Sam Gossner; Ivy Audio / Simon Dalzell',
  'usage':'Rendered original project music only; raw samples stay under D:/星丘基础/downloads/ui-polish/VSCO2',
  'sampleHashes':'assets/audio/source_record.json'}]
record['conceptDerivatives']=[
 {'asset':'tools/source_art/title_concept_clean_v3.png','tool':'built-in image_gen',
  'reference':'01_title_screen_concept.png',
  'operation':'Remove all UI, logo, lettering from reference while preserving exact school gate, left stone pillar, right clock tower, sunset and rift composition. Native interactive title and plaque lettering drawn separately.',
  'runtime':'assets/art/environments/bg_title_gate.png'},
 {'asset':'tools/source_art/landing_battle_v3.png','tool':'built-in image_gen',
  'reference':'existing project corridor/classroom environment and visual bible',
  'operation':'Faithful sunset classroom-adjacent broad stair landing, indigo shadows, sakura windows, restrained early rift; unobstructed battle floor.',
  'runtime':'assets/art/environments/bg_env_landing_battle.png'}]
record['rulings']={'1-2':'Keep locked mapId ch1_classroom_sunset and story facts; battle camera shows adjacent classroom stair landing already mentioned in story.',
 '1-5':'Old gym per explicit user ruling; existing gym visuals retained.',
 'crest':'Six petals per explicit user ruling, including native title gate plaque.',
 'title':'Four concept menu entries; functional stage selection stays in campus.',
 'generatedAssets':'User says all three concepts GPT-generated. No blanket legal guarantee or user visual approval inferred.'}
record['sha256']={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
 for folder in ['assets/fonts','assets/licenses','assets/art/ui/menu'] for p in sorted((ROOT/folder).iterdir()) if p.is_file() and p.suffix!='.import'}
for entry in record['conceptDerivatives']:
 for key in ['asset','runtime']:
  p=ROOT/entry[key];record['sha256'][entry[key]]=hashlib.sha256(p.read_bytes()).hexdigest()
record['visualAcceptance']='Pending actual comparison and user judgment; imported assets are not proof of final concept quality.'
path.write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf8')
print('Recorded source licenses, hashes and explicit rulings')
