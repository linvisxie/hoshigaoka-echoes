"""Record the two generated sources and their runtime derivatives."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[1]
assets=[]
for character,source in [('fujiwara_rin','rin_full_motion_v3.png'),('kamiya_yuma','yuma_recovery_v3.png')]:
    original=ROOT/'tools/source_art'/source
    files=(ROOT/'assets/art/characters'/character).glob('fujiwara_rin_*.png') if character=='fujiwara_rin' else [ROOT/'assets/art/characters/kamiya_yuma/kamiya_yuma_recovery.png']
    for file in files:
        if file.stem.endswith(('story','portrait_256')):continue
        source_file=ROOT/'assets/art/characters/fujiwara_rin/fujiwara_rin_portrait_256.png' if file.stem.endswith('portrait_64') else original
        assets.append({'asset':file.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(file.read_bytes()).hexdigest(),
            'source':source_file.relative_to(ROOT).as_posix(),'sourceSha256':hashlib.sha256(source_file.read_bytes()).hexdigest()})
(ROOT/'docs/v3_round9_asset_sources.json').write_text(json.dumps({
    'provider':'Built-in OpenAI image generation; model ID not exposed',
    'referenceRights':'User confirmed GPT-generated project concepts and authorized adaptation; Rin existing project figure and Yuma existing pixel poses used as references',
    'terms':'https://openai.com/policies/terms-of-use/','termsChecked':'2026-10-11',
    'ownershipNote':'OpenAI terms assign output rights as between user and provider, subject to applicable law; no guarantee of uniqueness or final artistic quality',
    'finalUserArtAcceptance':False,
    'importRecords':['docs/v3_rin_motion_import.json','docs/v3_kamiya_yuma_recovery_import.json'],
    'portraitNote':'Rin 64px portrait is a resize of the existing project 256px portrait; not derived from the new pose sheet',
    'assets':assets},ensure_ascii=False,indent=2),encoding='utf8')
print('Recorded',len(assets),'runtime derivatives')
