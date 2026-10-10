"""Collect real renderer/Windows evidence; derived previews are explicitly labelled."""
from pathlib import Path
import json,shutil
from PIL import Image,ImageOps,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'_testenv/v3-round3'
OUT=ROOT/'docs/art_screenshots/v3_concept_polish_20261011'
OUT.mkdir(parents=True,exist_ok=True)
groups={
 'campaign':BASE/'campaign_release_corrected/appdata/HoshigaokaEchoes/campaign_shots',
 'frontend':BASE/'frontend_controls/appdata/HoshigaokaEchoes/frontend_shots',
 'finish':BASE/'finish_frozen/appdata/HoshigaokaEchoes/frontend_shots',
 'dynamic':BASE/'dynamic_latest/appdata/HoshigaokaEchoes/p0.3_shots',
 'failure':BASE/'failure_latest/appdata/HoshigaokaEchoes/p0.3_shots',
 'retail':BASE/'retail_latest'}
for prefix,folder in groups.items():
 assert folder.exists(),str(folder)
 for p in folder.glob('*.png'):
  if prefix=='dynamic' and not p.name.startswith('v3_'):continue
  shutil.copy2(p,OUT/f'{prefix}_{p.name}')
  for sidecar in [p.with_suffix('.json'),p.with_suffix('.png.json')]:
   if sidecar.exists():shutil.copy2(sidecar,OUT/f'{prefix}_{sidecar.name}')
reports={
 'campaign':BASE/'campaign_release_corrected/appdata/HoshigaokaEchoes/campaign_report.json',
 'frontend':BASE/'frontend_controls/appdata/HoshigaokaEchoes/frontend_report.json',
 'finish':BASE/'finish_frozen/appdata/HoshigaokaEchoes/finish_polish_report.json',
 'dynamic':BASE/'dynamic_latest/appdata/HoshigaokaEchoes/visual_slice_report.json',
 'failure':BASE/'failure_latest/appdata/HoshigaokaEchoes/core_failure_report.json',
 'regression':BASE/'regression_latest/result.json',
 'retail':BASE/'retail_latest/retail_report.json',
 'audio':BASE/'release_audio/audio_report.json'}
for prefix,p in reports.items():
 assert p.exists(),str(p)
 shutil.copy2(p,OUT/f'{prefix}_report.json')
shutil.copy2(BASE/'music_mix_metrics.json',OUT/'music_signal_metrics.json')
offer=BASE/'offer_caption/appdata/HoshigaokaEchoes/p0.3_shots/v3_upgrade_offer.png'
assert offer.exists(),str(offer)
shutil.copy2(offer,OUT/'upgrade_tutorial_final.png')
shutil.copy2(offer.with_suffix('.png.json'),OUT/'upgrade_tutorial_final.png.json')
for group,name,pattern,duration in [
 ('dynamic','mio_attack','v3_attack_*.png',60),
 ('dynamic','mio_skill','v3_skill_amamiya_mio_*.png',90),
 ('dynamic','yuma_skill','v3_skill_kamiya_yuma_*.png',90),
 ('dynamic','victory','v3_victory_*.png',100),
 ('failure','core_danger','core_danger_*.png',130),
 ('failure','core_break','core_break_*.png',100)]:
 frames=[Image.open(p).convert('RGB').resize((960,540),Image.Resampling.LANCZOS) for p in sorted(groups[group].glob(pattern))]
 assert frames,(group,pattern)
 frames[0].save(OUT/f'{name}.gif',save_all=True,append_images=frames[1:],duration=duration,loop=0)
font=ImageFont.truetype(str(ROOT/'assets/fonts/NotoSansCJKsc-Regular.otf'),25)
concept=ROOT.parent/'meishu/Hoshigaoka_Art_Preview_Pack'
pairs=[('标题原始概念图',concept/'01_title_screen_concept.png','0.4.0 Windows 标题原始实机',OUT/'retail_title.png'),
 ('整体视觉圣经',concept/'02_visual_bible_overview.png','0.4.0 Windows 体育馆原始实机',OUT/'retail_battle_deployed.png'),
 ('雨宫澪详细设定',concept/'03_p0_asset_sheet_amamiya_mio.png','真实技能事件帧（自动操作）',OUT/'dynamic_v3_skill_amamiya_mio_02.png')]
sheet=Image.new('RGB',(1920,1800),(12,19,34));draw=ImageDraw.Draw(sheet)
for row,(lt,lp,rt,rp) in enumerate(pairs):
 for col,(title,path) in enumerate([(lt,lp),(rt,rp)]):
  assert path.exists(),str(path)
  draw.text((col*960+20,row*600+10),title,font=font,fill=(232,210,163))
  im=ImageOps.contain(Image.open(path).convert('RGB'),(940,540),Image.Resampling.LANCZOS)
  sheet.paste(im,(col*960+(960-im.width)//2,row*600+55+(540-im.height)//2))
sheet.save(OUT/'concept_runtime_comparison.jpg',quality=94)
stages=Image.new('RGB',(1280,3*410),(12,19,34));draw=ImageDraw.Draw(stages)
for i in range(5):
 x=(i%2)*640;y=(i//2)*410
 draw.text((x+16,y+10),'1-%d · 正常流程实机（自动操作）' % (i+1),font=font,fill=(232,210,163))
 p=OUT/('campaign_battle_1-%d.png' % (i+1));assert p.exists(),str(p)
 stages.paste(Image.open(p).convert('RGB').resize((640,360),Image.Resampling.LANCZOS),(x,y+50))
stages.save(OUT/'first_five_runtime_overview.jpg',quality=94)
(OUT/'证据说明.txt').write_text('PNG 为真实 Godot 视口或 Windows 客户区原始截图；JSON 标记来源与自动操作。GIF 为连续实机帧的缩放回放，不是重新绘制的动画。concept_runtime_comparison.jpg 是排版后的对照图，不能作为单张实机截图。完整五关为正常计时自动流程，不等于人工试玩或最终美术验收。',encoding='utf8')
print('Collected',len(list(OUT.iterdir())),'files')
