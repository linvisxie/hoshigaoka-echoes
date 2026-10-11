"""Import user-requested portrait revisions and an empty core cradle."""
from pathlib import Path
import hashlib,json,shutil
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
GEN=Path(r'C:\Users\linvisxie\.codex\generated_images\01a12374-ae46-7552-ad65-5bdc38457258')
sources={
 'amamiya_mio':'exec-b1341620-4bad-4fea-befa-ce26fbee400d.png',
 'kamiya_yuma':'exec-22042fa0-8d4e-43ed-9e15-b722cb3c0402.png',
 'core_cradle':'exec-1760082f-704d-40bd-b165-06746b307612.png',
}
records=[]
for name,filename in sources.items():
 source=GEN/filename
 preserved=ROOT/'tools/source_art'/f'{name}_round10.png'
 shutil.copy2(source,preserved)
 im=Image.open(source).convert('RGBA')
 if name=='core_cradle':
  # Only register and resize; the generated cradle has no central crystal.
  im=im.crop(im.getbbox()).resize((336,652),Image.Resampling.LANCZOS)
  target=ROOT/'assets/art/ui/core_cradle_round10.png'
 else:
  im=im.resize((512,512),Image.Resampling.LANCZOS)
  target=ROOT/f'assets/art/characters/{name}/{name}_portrait_polished.png'
 im.save(target)
 records.append({'source':preserved.relative_to(ROOT).as_posix(),'runtime':target.relative_to(ROOT).as_posix(),
  'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),
  'origin':'OpenAI built-in image generation; edited project-owned character/core references',
  'licenseRecord':'assets/licenses/AI_GENERATED_ART_NOTICE.txt',
  'finalUserArtAcceptance':False})
(ROOT/'docs/v3_round10_asset_sources.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf8')
source=GEN/'exec-4c99ada5-bb36-487a-8406-8f2d36d14b15.png'
preserved=ROOT/'tools/source_art/core_crystal_round10.png'
shutil.copy2(source,preserved)
sheet=Image.open(source).convert('RGBA')
strip=Image.new('RGBA',(128*16,128))
for index in range(16):
 col,row=index%4,index//4
 frame=sheet.crop((round(col*sheet.width/4),round(row*sheet.height/4),round((col+1)*sheet.width/4),round((row+1)*sheet.height/4)))
 # Connected alpha mask separates the actual gem from detached generation residue.
 alpha=frame.getchannel('A')
 pixels=alpha.load()
 visited=set()
 largest=[]
 for y in range(frame.height):
  for x in range(frame.width):
   if (x,y) in visited or pixels[x,y]<48: continue
   component=[]; pending=[(x,y)]; visited.add((x,y))
   while pending:
    p=pending.pop();component.append(p)
    for q in ((p[0]-1,p[1]),(p[0]+1,p[1]),(p[0],p[1]-1),(p[0],p[1]+1)):
     if 0<=q[0]<frame.width and 0<=q[1]<frame.height and q not in visited and pixels[q[0],q[1]]>=48:
      visited.add(q);pending.append(q)
   if len(component)>len(largest):largest=component
 xs=[p[0] for p in largest];ys=[p[1] for p in largest]
 mask=Image.new('L',frame.size)
 for p in largest:mask.putpixel(p,pixels[p])
 frame.putalpha(mask)
 frame=frame.crop((min(xs),min(ys),max(xs)+1,max(ys)+1))
 frame=frame.resize((round(frame.width*112/frame.height),112),Image.Resampling.NEAREST)
 strip.paste(frame,(index*128+(128-frame.width)//2,8))
target=ROOT/'assets/art/ui/core_crystal_turn.png'
strip.save(target)
records.append({'source':preserved.relative_to(ROOT).as_posix(),'runtime':target.relative_to(ROOT).as_posix(),'frames':16,'frameSize':128,'cycleSeconds':2.4,'registration':'largest connected alpha component, fixed height and center','sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'origin':'OpenAI built-in generation; referenced project crystal','licenseRecord':'assets/licenses/AI_GENERATED_ART_NOTICE.txt','finalUserArtAcceptance':False})
(ROOT/'docs/v3_round10_asset_sources.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf8')
print('Imported portraits, empty cradle and registered sixteen-frame crystal turn.')
