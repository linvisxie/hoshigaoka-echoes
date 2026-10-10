from pathlib import Path
from PIL import Image
import hashlib,json,shutil,math
ROOT=Path(__file__).resolve().parents[1]
GEN=Path(r'C:\Users\linvisxie\.codex\generated_images\01a12374-ae46-7552-ad65-5bdc38457258')
records=[]
for target,source,size in [
 ('assets/art/environments/bg_title_gate.png','exec-8e676551-a558-478f-ae72-b11b03c66b46.png',(1920,1080)),
 ('assets/art/environments/bg_env_gym_battle.png','exec-1c430c82-2296-43bd-906f-5cb55b39c12c.png',(1920,1080)),
 ('assets/art/ui/core_tower_six.png','exec-3530b28c-e79a-4c73-80e2-e936e7b37745.png',(192,336))]:
    src=ROOT/'tools/source_art'/source
    shutil.copy2(GEN/source,src)
    im=Image.open(src).convert('RGBA')
    im.resize(size,Image.Resampling.LANCZOS if size[0]>500 else Image.Resampling.BOX).save(ROOT/target)
    records.append({'asset':target,'source':src.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256((ROOT/target).read_bytes()).hexdigest()})
svg=['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 288">',
 '<defs><linearGradient id="gold" x2="0" y2="1"><stop stop-color="#fff0bf"/><stop offset=".5" stop-color="#ddbd7e"/><stop offset="1" stop-color="#a67c49"/></linearGradient></defs>',
 '<path d="M128 13 225 66 215 188Q197 237 128 268Q59 237 41 188L31 66Z" fill="#15213b" stroke="url(#gold)" stroke-width="4"/>',
 '<path d="M128 25 213 72 204 184Q187 228 128 255Q69 228 52 184L43 72Z" fill="none" stroke="#ddbd7e" stroke-width="1.5"/>']
for deg in range(0,360,60):
    svg.append(f'<path d="M128 132 Q106 102 128 60 Q150 102 128 132Z" fill="url(#gold)" transform="rotate({deg} 128 132)"/>')
svg.append('<circle cx="128" cy="132" r="7" fill="#15213b"/><path d="M128 112 131 129 148 132 131 135 128 152 125 135 108 132 125 129Z" fill="#ddbd7e"/>')
for side in [-1,1]:
    for n in range(7):
        x=128+side*(77-n*7);y=156+n*12
        svg.append(f'<ellipse cx="{x}" cy="{y}" rx="5" ry="13" fill="#ddbd7e" transform="rotate({side*(25+n*5)} {x} {y})"/>')
    svg.append(f'<path d="M{128+side*76} 145Q{128+side*75} 213 128 246" fill="none" stroke="#ddbd7e" stroke-width="2"/>')
svg.append('<path d="m128 243 8 9-8 9-8-9Z" fill="#ddbd7e"/></svg>')
(ROOT/'assets/art/ui/school_crest_six.svg').write_text(''.join(svg).replace('url(#gold)','#e6c993'),encoding='utf-8')
(ROOT/'docs/v3_round2_asset_sources.json').write_text(json.dumps({'date':'2026-10-10','provider':'built-in image_gen',
 'referenceOrigin':'User confirms three reference images were generated with GPT',
 'terms':'https://openai.com/policies/terms-of-use/','assets':records,
 'crest':'Original project-native SVG; six radial petals, matching user ruling'},ensure_ascii=False,indent=2),encoding='utf-8')
