"""Copy verifiable runtime evidence and retain asset provenance, without altering saves."""
from pathlib import Path
from PIL import Image, ImageOps, ImageDraw
import hashlib, json, shutil

ROOT = Path(__file__).resolve().parents[1]
TEST = ROOT.parent / '_testenv/v3-twohour'
OUT = ROOT / 'docs/art_screenshots/v3_first_five_20261010'
OUT.mkdir(parents=True, exist_ok=True)
GEN = Path(r'C:\Users\linvisxie\.codex\generated_images\01a12374-ae46-7552-ad65-5bdc38457258')
records = []
sources = {
 'assets/art/environments/bg_env_classroom_exam.png':'exec-240d9935-945c-4593-b2cd-a7ef884131bf.png',
 'assets/art/environments/bg_env_corridor_convergence.png':'exec-47cab6e8-3a43-4bd5-829b-7a1d01217b51.png',
 'assets/art/environments/bg_env_classroom_battle.png':'exec-039683d5-7801-4336-a78b-6a96a41fa939.png',
 'assets/art/environments/bg_env_corridor_battle.png':'exec-df97ea59-f596-4a99-b64a-1a84a4516042.png',
 'assets/art/characters/amamiya_mio/amamiya_mio_story.png':'exec-581ac2d7-2627-4702-9468-1178e3867c48.png',
 'assets/art/characters/kamiya_yuma/kamiya_yuma_story.png':'exec-4e70bad4-772d-4e7b-8027-fd62039030c0.png',
 'assets/art/characters/fujiwara_rin/fujiwara_rin_story.png':'exec-beb74a7e-92d3-433c-a2dd-6d1eb052afbe.png',
 'assets/art/ui/core_tower.png':'exec-d58d39fe-2e0d-4fc8-b56e-80ac598614d1.png',
 'assets/art/ui/title_logo.png':'exec-8ac7e281-41d5-488c-98e9-8245b3334012.png',
}
for target, original in sources.items():
    source = GEN / original
    retained = ROOT/'tools/source_art'/('generated_'+original)
    shutil.copy2(source, retained)
    records.append({'asset':target,'sha256':hashlib.sha256((ROOT/target).read_bytes()).hexdigest(),
        'source':retained.relative_to(ROOT).as_posix(),'sourceSha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'method':'Reference-guided image_gen, then crop/scale/format conversion for runtime'})
for target in sorted(ROOT.glob('assets/art/characters/amamiya_mio/*portrait_*.png')):
    records.append({'asset':target.relative_to(ROOT).as_posix(),
        'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),
        'source':'User supplied 03_p0_asset_sheet_amamiya_mio.png; nine facial-expression cells',
        'method':'Direct crop and rescale; no regenerated face'})
(ROOT/'docs/v3_frontend_source_record.json').write_text(json.dumps({
    'provider':'Built-in image_gen; precise model identity not exposed',
    'terms':'https://openai.com/policies/terms-of-use/', 'termsChecked':'2026-10-10',
    'referenceRights':'User-supplied concepts; underlying rights not independently established',
    'status':'Internal integrated candidates; final art acceptance and commercial release rights review remain pending',
    'assets':records},ensure_ascii=False,indent=2),encoding='utf-8')
for area, prefix in [('release','release'),('release_continue','release_continue'),
                     ('variant_1_3','variant_1_3'),('variant_1_5','variant_1_5'),
                     ('frontend2/appdata/HoshigaokaEchoes/frontend_shots','frontend'),
                     ('campaign5/appdata/HoshigaokaEchoes/campaign_shots','campaign')]:
    for source in (TEST/area).glob('*.png'):
        shutil.copy2(source, OUT/(prefix+'_'+source.name))
dynamic = TEST/'dynamic_release/appdata/HoshigaokaEchoes/p0.3_shots'
if not (dynamic/'v3_result.png').exists(): dynamic = TEST/'dynamic_final/appdata/HoshigaokaEchoes/p0.3_shots'
if not (dynamic/'v3_result.png').exists(): dynamic = TEST/'dynamic/appdata/HoshigaokaEchoes/p0.3_shots'
for source in dynamic.glob('v3_*.png'):
    shutil.copy2(source, OUT/source.name)
for character in ['amamiya_mio','kamiya_yuma']:
    paths=sorted(dynamic.glob('v3_skill_'+character+'_*.png'))
    if not paths: continue
    frames=[Image.open(p).convert('RGB').resize((960,540),Image.Resampling.LANCZOS) for p in paths]
    frames[0].save(OUT/(character+'_skill_runtime.gif'),save_all=True,append_images=frames[1:],duration=90,loop=0)
    sheet=Image.new('RGB',(960,540),'#101828')
    draw=ImageDraw.Draw(sheet)
    for i,path in enumerate(paths[:9]):
        thumb=Image.open(path).convert('RGB').resize((320,180),Image.Resampling.LANCZOS)
        sheet.paste(thumb,((i%3)*320,(i//3)*180))
    sheet.save(OUT/(character+'_skill_continuous_frames.png'))
paths=sorted(dynamic.glob('v3_victory_*.png'))
if paths:
    frames=[Image.open(p).convert('RGB').resize((960,540),Image.Resampling.LANCZOS) for p in paths]
    frames[0].save(OUT/'victory_runtime.gif',save_all=True,append_images=frames[1:],duration=100,loop=0)
for source, name in [('regression_final/result.json','regression.json'),
                     ('frontend2/appdata/HoshigaokaEchoes/frontend_report.json','frontend.json'),
                     ('campaign5/appdata/HoshigaokaEchoes/campaign_report.json','campaign.json'),
                     ('audio_latest/audio_report.json','windows_audio.json'),
                     ('release/release_report.json','release.json')]:
    path=TEST/source
    if path.exists(): shutil.copy2(path,OUT/name)
print('Evidence retained:',OUT)
CONCEPT=ROOT.parent/'meishu/Hoshigaoka_Art_Preview_Pack'
for name,reference,actual in [('title','01_title_screen_concept.png',TEST/'release/retail_title.png'),
                              ('battle','02_visual_bible_overview.png',dynamic/'v3_battle_60s.png')]:
    if not actual.exists(): continue
    sheet=Image.new('RGB',(1920,650),'#101828')
    draw=ImageDraw.Draw(sheet)
    draw.text((20,10),'USER CONCEPT / VISUAL REFERENCE',fill='white')
    draw.text((980,10),'ACTUAL WINDOWS GAME / AUTOMATED PLAY',fill='white')
    for i,path in enumerate([CONCEPT/reference,actual]):
        im=ImageOps.contain(Image.open(path).convert('RGB'),(940,610),Image.Resampling.LANCZOS)
        sheet.paste(im,(i*960+(960-im.width)//2,35))
    sheet.save(OUT/(name+'_concept_vs_runtime.png'))
