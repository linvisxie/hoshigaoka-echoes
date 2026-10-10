"""Import reviewed 4x5 pose atlases with one scale and palette per enemy.
Cropping/format conversion only; no synthetic translation animation.
"""
from pathlib import Path
from PIL import Image
import json, hashlib, shutil

ROOT=Path(__file__).resolve().parents[1]
GEN=Path(r'C:\Users\linvisxie\.codex\generated_images\01a12374-ae46-7552-ad65-5bdc38457258')
SOURCES={
 'echo_normal':('exec-051b4e1f-ba2d-4c0e-a3ed-3941a448f5f0.png',64),
 'echo_runner':('exec-b12bbc5d-a3ce-4069-b264-b6cb256a782a.png',64),
 'echo_armored':('exec-8906788f-e523-4d81-8b63-df3d301bd2d6.png',96),
 'echo_exam_sheet':('exec-bdd54e2f-d994-4c4e-919d-5218ae3d3304.png',64),
 'echo_invigilator':('exec-01bc240e-4c43-4674-ac7b-070e0c111de6.png',96),
}
records=[]
for cid,(filename,size) in SOURCES.items():
 source=ROOT/'tools/source_art'/f'{cid}_v3_atlas.png'
 shutil.copy2(GEN/filename,source)
 im=Image.open(source).convert('RGBA')
 cells=[]
 # Fixed global scale preserves the larger wind-up silhouettes instead of
 # resizing every frame to a different apparent body size.
 factor=(size-8)/max(im.width/4,im.height/5)
 for row in range(5):
  frames=[]
  for col in range(4):
   cell=im.crop((round(col*im.width/4),round(row*im.height/5),round((col+1)*im.width/4),round((row+1)*im.height/5)))
   alpha=cell.getchannel('A').point(lambda x:255 if x>=128 else 0)
   cell.putalpha(alpha)
   reduced=cell.resize((round(cell.width*factor),round(cell.height*factor)),Image.Resampling.BOX)
   reduced.putalpha(reduced.getchannel('A').point(lambda x:255 if x>=128 else 0))
   frame=Image.new('RGBA',(size,size))
   frame.alpha_composite(reduced,((size-reduced.width)//2,size-4-reduced.height))
   frames.append(frame)
  cells.append(frames)
 palette_image=Image.new('RGB',(size*4,size*5),(14,16,32))
 for row,frames in enumerate(cells):
  for col,frame in enumerate(frames):palette_image.paste(frame,(col*size,row*size),frame)
 palette=palette_image.quantize(colors=48,method=Image.Quantize.MEDIANCUT)
 out=ROOT/'assets/art/enemies'/cid
 out.mkdir(parents=True,exist_ok=True)
 for row,name in enumerate(['idle','move','attack','hit','death']):
  poses=cells[row][:2] if name=='hit' else cells[row]
  strip=Image.new('RGBA',(size*len(poses),size))
  for col,frame in enumerate(poses):
   q=frame.convert('RGB').quantize(palette=palette,dither=Image.Dither.NONE).convert('RGBA')
   q.putalpha(frame.getchannel('A'));strip.alpha_composite(q,(col*size,0))
  strip.save(out/f'{cid}_{name}.png')
 cells[0][0].save(out/f'{cid}_base.png')
 preview=palette_image.resize((size*12,size*15),Image.Resampling.NEAREST)
 preview.save(ROOT/'docs/art_screenshots'/f'{cid}_v3_registered.png')
 records.append({'id':cid,'source':source.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'frameSize':size,'rows':['idle','move','attack','hit','death'],'poseCount':20,'transforms':['equal 4x5 crop','uniform scale','alpha threshold128','shared48colour palette','fixed canvas registration'],'reference':'02_visual_bible_overview.png section05'})
(ROOT/'docs/v3_enemy_source_record.json').write_text(json.dumps({'provider':'built-in image_gen; precise model identity not exposed','terms':'https://openai.com/policies/terms-of-use/','checked':'2026-10-10','inputRights':'User-supplied reference; underlying rights not independently established','status':'Integrated internal candidates; final visual and commercial-reference-rights approval pending','rejected':['exec-76ff1f8e-36fc-4909-89ee-bfd397e67fc8.png: changed normal echo into a girl, not integrated'],'assets':records},ensure_ascii=False,indent=2),encoding='utf-8')
