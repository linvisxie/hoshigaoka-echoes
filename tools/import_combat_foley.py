"""Import a small, attributed CC0 combat set; originals stay under D:/星丘基础."""
from pathlib import Path
import hashlib,json,shutil
ROOT=Path(__file__).resolve().parents[1]
BASE=Path('D:/星丘基础/downloads/ui-polish')
mapping={
 'foley_blade_01':('kenney_rpg-audio','knifeSlice.ogg'),
 'foley_blade_02':('kenney_rpg-audio','knifeSlice2.ogg'),
 'foley_hit_01':('kenney_impact-sounds','impactGeneric_light_000.ogg'),
 'foley_hit_02':('kenney_impact-sounds','impactGeneric_light_001.ogg'),
 'foley_hit_03':('kenney_impact-sounds','impactGeneric_light_002.ogg'),
 'foley_metal_01':('kenney_impact-sounds','impactMetal_light_000.ogg'),
 'foley_metal_02':('kenney_impact-sounds','impactMetal_light_001.ogg'),
 'foley_crystal_01':('kenney_impact-sounds','impactGlass_light_000.ogg'),
 'foley_crystal_02':('kenney_impact-sounds','impactGlass_light_001.ogg')}
record={'author':'Kenney (www.kenney.nl)','license':'CC0-1.0','cost':0,
 'sources':['https://kenney.nl/assets/rpg-audio','https://kenney.nl/assets/impact-sounds'],
 'usage':'Blade swishes, normal impacts, armored impacts, crystal dissipation; rotating takes with bounded existing voice pool',
 'assets':[],'listeningApproval':'Pending; runtime event checks and Windows loopback are distinct from human listening'}
for name,(library,filename) in mapping.items():
 src=BASE/library/'Audio'/filename
 assert src.read_bytes().startswith(b'OggS')
 target=ROOT/'assets/audio/sfx'/(name+'.ogg');shutil.copy2(src,target)
 record['assets'].append({'asset':target.relative_to(ROOT).as_posix(),'source':library+'/Audio/'+filename,
  'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
for library,label in [('kenney_rpg-audio','RPG-Audio'),('kenney_impact-sounds','Impact-Sounds')]:
 license_path=BASE/library/'License.txt'
 assert 'CC0' in license_path.read_text(encoding='utf8')
 shutil.copy2(license_path,ROOT/'assets/licenses'/('Kenney-'+label+'-CC0.txt'))
(ROOT/'docs/v3_combat_foley_sources.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf8')
audio_record=ROOT/'assets/audio/source_record.json'
audio_data=json.loads(audio_record.read_text(encoding='utf8'))
audio_data['combatFoleyRecord']='docs/v3_combat_foley_sources.json'
audio_data['commercialUse']='Original melodies rendered with CC0-1.0 piano samples; project synthesized accompaniment/SFX; Kenney CC0 UI and combat cues separately recorded'
audio_record.write_text(json.dumps(audio_data,ensure_ascii=False,indent=2),encoding='utf8')
print('Imported',len(mapping),'licensed combat takes')
