"""Register generated revision sheets; preserve originals and uniform action scale."""
from pathlib import Path
from PIL import Image
import json, shutil, hashlib
ROOT=Path(__file__).resolve().parents[1]
GEN=Path(r'C:\Users\linvisxie\.codex\generated_images\01a12374-ae46-7552-ad65-5bdc38457258')
specs={
 'amamiya_mio':('exec-5946c9e9-2071-4a8f-828b-a9e174bb51a8.png',(0,350,650,940,1214)),
 'kamiya_yuma':('exec-73a1d071-a51d-4fe1-9406-a4c94a02e1b4.png',(0,338,647,942,1216)),
 'ogawa_yui':('exec-0fb26905-ec73-4a1e-92e5-3f28e51b9c39.png',(0,333,637,940,1216)),
}
rawdir=ROOT/'tools/source_art/glass_revision';rawdir.mkdir(parents=True,exist_ok=True)
records=[];preview=Image.new('RGBA',(768,384),(20,40,60,255))
for row,(cid,(name,ys)) in enumerate(specs.items()):
 raw=rawdir/(cid+'_sheet.png');shutil.copy2(GEN/name,raw)
 im=Image.open(raw).convert('RGBA')
 cells=[]
 for i in range(16):
  c=im.crop((round(i%4*im.width/4),ys[i//4],round((i%4+1)*im.width/4),ys[i//4+1]))
  bbox=c.getchannel('A').point(lambda v:255 if v>24 else 0).getbbox()
  cells.append(c.crop(bbox) if bbox else Image.new('RGBA',(1,1)))
 scale=116/max(max(c.size) for c in cells)
 frames=[]
 for c in cells:
  c=c.resize((max(1,round(c.width*scale)),max(1,round(c.height*scale))),Image.Resampling.NEAREST)
  f=Image.new('RGBA',(128,128));f.alpha_composite(c,((128-c.width)//2,122-c.height));frames.append(f)
 mapping={'base':[0],'idle':[0,1,2,3],'move':[0,1,2,3],'attack':[4,5,6,7],'recovery':[6,7],
          'skill':[8,9,10,11],'deploy':[8,9,10,11],'hit':[12,13],'death':[13,14,15,15],'victory':[0,2,3,2]}
 targets=[]
 for anim,indices in mapping.items():
  strip=Image.new('RGBA',(128*len(indices),128))
  for x,i in enumerate(indices):strip.alpha_composite(frames[i],(128*x,0))
  target=ROOT/'assets/art/characters'/cid/(cid+'_'+anim+'.png');strip.save(target);targets.append(str(target.relative_to(ROOT)))
 for x,i in enumerate([0,4,7,8,11,13]):preview.alpha_composite(frames[i],(128*x,128*row))
 records.append({'character':cid,'source':str(raw.relative_to(ROOT)),'sourceSha256':hashlib.sha256(raw.read_bytes()).hexdigest(),
                 'origin':'OpenAI built-in imagegen, edited from existing user-owned character sheets and Sara style reference',
                 'frameSize':128,'uniformScale':scale,'reviewedRows':ys,'targets':targets,'humanArtAcceptance':False})
(ROOT/'docs/glass_character_assets.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf8')
preview.save(ROOT/'docs/glass_character_frames.png')
print('Registered three transparent character sheets; source preserved')
