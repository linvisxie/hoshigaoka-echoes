"""Copy actual runtime evidence and make explicitly labelled comparison/animation previews."""
from pathlib import Path
import json,shutil
from PIL import Image,ImageOps,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'_testenv/v3-round2'
OUT=ROOT/'docs/art_screenshots/v3_ui_polish_20261010'
OUT.mkdir(parents=True,exist_ok=True)
groups={
 'campaign':BASE/'campaign_final/appdata/HoshigaokaEchoes/campaign_shots',
 'frontend':BASE/'frontend_final/appdata/HoshigaokaEchoes/frontend_shots',
 'pause':BASE/'polish3/appdata/HoshigaokaEchoes/frontend_shots',
 'dynamic':BASE/'dynamic/appdata/HoshigaokaEchoes/p0.3_shots',
 'retail':BASE/'retail_battle'}
for prefix,folder in groups.items():
 for p in folder.glob('*.png'):
  if prefix=='dynamic' and not p.name.startswith('v3_'):continue
  shutil.copy2(p,OUT/f'{prefix}_{p.name}')
reports={
 'campaign':BASE/'campaign_final/appdata/HoshigaokaEchoes/campaign_report.json',
 'frontend':BASE/'frontend_final/appdata/HoshigaokaEchoes/frontend_report.json',
 'pause':BASE/'polish3/appdata/HoshigaokaEchoes/ui_polish_report.json',
 'dynamic':BASE/'dynamic/appdata/HoshigaokaEchoes/visual_slice_report.json',
 'regression':BASE/'regression_final/result.json',
 'retail':BASE/'retail_battle/retail_report.json',
 'audio':BASE/'release_audio/audio_report.json'}
for prefix,p in reports.items():
 if p.exists():shutil.copy2(p,OUT/f'{prefix}_report.json')
for name,pattern,duration in [('mio_attack','v3_attack_*.png',70),('mio_skill','v3_skill_amamiya_mio_*.png',90),('yuma_skill','v3_skill_kamiya_yuma_*.png',90),('victory','v3_victory_*.png',100)]:
 frames=[Image.open(p).convert('RGB').resize((960,540),Image.Resampling.LANCZOS) for p in sorted(groups['dynamic'].glob(pattern))]
 if frames:frames[0].save(OUT/f'{name}.gif',save_all=True,append_images=frames[1:],duration=duration,loop=0)
font=ImageFont.truetype(r'C:\Windows\Fonts\msyh.ttc',26)
concept=ROOT.parent/'meishu/Hoshigaoka_Art_Preview_Pack'
pairs=[('标题概念图',concept/'01_title_screen_concept.png','新版 Windows 标题实机',OUT/'retail_title.png'),
 ('整体视觉圣经',concept/'02_visual_bible_overview.png','新版 Windows 第五关实机',OUT/'retail_battle_deployed.png'),
 ('雨宫澪详细设定',concept/'03_p0_asset_sheet_amamiya_mio.png','实际战斗技能事件',OUT/'dynamic_v3_skill_amamiya_mio_04.png')]
sheet=Image.new('RGB',(1920,3*600),(12,19,34));d=ImageDraw.Draw(sheet)
for row,(lt,lp,rt,rp) in enumerate(pairs):
 for col,(title,path) in enumerate([(lt,lp),(rt,rp)]):
  d.text((col*960+20,row*600+10),title,font=font,fill=(232,210,163))
  if path.exists():
   im=ImageOps.contain(Image.open(path).convert('RGB'),(940,540),Image.Resampling.LANCZOS)
   sheet.paste(im,(col*960+(960-im.width)//2,row*600+55+(540-im.height)//2))
sheet.save(OUT/'concept_runtime_comparison.jpg',quality=94)
print('Round 2 runtime evidence copied:',len(list(OUT.iterdir())),'files')
