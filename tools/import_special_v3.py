"""Crop additional drawn deployment/skill/victory poses; fixed feet registration."""
from pathlib import Path
from PIL import Image
import shutil,json,hashlib
ROOT=Path(__file__).resolve().parents[1]
GEN=Path(r'C:\Users\linvisxie\.codex\generated_images\01a12374-ae46-7552-ad65-5bdc38457258')
records=[]
size=96
for cid,file,scale in [('amamiya_mio','exec-60d8104e-324c-4a6d-ba89-6be7047ac6c5.png',.155),('kamiya_yuma','exec-e5f01127-b768-4eec-884e-ba740f808134.png',.135)]:
 src=ROOT/'tools/source_art'/f'{cid}_special_v3.png';shutil.copy2(GEN/file,src)
 im=Image.open(src).convert('RGBA')
 scale*=size/64
 for row,name in enumerate(['deploy','skill','victory']):
  strip=Image.new('RGBA',(size*4,size))
  for col in range(4):
   cell=im.crop((round(col*im.width/4),round(row*im.height/3),round((col+1)*im.width/4),round((row+1)*im.height/3)))
   cell.putalpha(cell.getchannel('A').point(lambda a:255 if a>=128 else 0))
   box=cell.getchannel('A').getbbox()
   small=cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.BOX)
   small.putalpha(small.getchannel('A').point(lambda a:255 if a>=128 else 0))
   frame=Image.new('RGBA',(size,size));frame.alpha_composite(small,((size-small.width)//2,round(size*60/64)-round(box[3]*scale)))
   strip.alpha_composite(frame,(col*size,0))
  strip.save(ROOT/'assets/art/characters'/cid/f'{cid}_{name}.png')
 records.append({'id':cid,'source':src.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'scale':scale,'poses':12,'rows':['deploy','skill','victory']})
(ROOT/'docs/v3_special_source_record.json').write_text(json.dumps({'provider':'built-in image_gen','reference':'user concept sheets02/03','terms':'https://openai.com/policies/terms-of-use/','status':'internal integrated candidate; final visual approval pending; underlying reference rights not independently established','assets':records},ensure_ascii=False,indent=2),encoding='utf8')
