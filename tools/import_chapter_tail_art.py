"""Register generated original assets. Preserve raw source; no hand redraw."""
from pathlib import Path
from PIL import Image
import json,shutil,hashlib
ROOT=Path(__file__).resolve().parents[1]
GEN=Path(r'C:\Users\linvisxie\.codex\generated_images\01a12374-ae46-7552-ad65-5bdc38457258')
RAW=ROOT/'tools/source_art/chapter_tail';RAW.mkdir(parents=True,exist_ok=True)
MANIFEST=ROOT/'docs/chapter_tail_assets.json'
records=json.loads(MANIFEST.read_text(encoding='utf8')) if MANIFEST.exists() else []
def record(name,source,targets):
    records[:]=[r for r in records if r['name']!=name]
    records.append(dict(name=name,source=str(source.relative_to(ROOT)),targets=[str(t.relative_to(ROOT)) for t in targets],sha256=hashlib.sha256(source.read_bytes()).hexdigest(),origin='OpenAI built-in imagegen with user-owned visual bible',licenseRecord='assets/licenses/AI_GENERATED_ART_NOTICE.txt',finalUserArtAcceptance=False))
def background(name,filename):
    raw=RAW/(name+'.png');shutil.copy2(GEN/filename,raw)
    target=ROOT/'assets/art/environments'/(name+'.png')
    Image.open(raw).convert('RGB').resize((1920,1080),Image.Resampling.LANCZOS).save(target)
    record(name,raw,[target])
def sheet(cid,filename,kind='characters',frame=128):
    raw=RAW/(cid+'_sheet.png');shutil.copy2(GEN/filename,raw)
    im=Image.open(raw).convert('RGBA');folder=ROOT/'assets/art'/kind/cid;folder.mkdir(parents=True,exist_ok=True)
    cells=[]
    # One uniform scale across the sheet. Preserve body proportions and effects.
    cellw=im.width/4;cellh=im.height/4
    for i in range(16):
        cell=im.crop((round(i%4*cellw),round(i//4*cellh),round((i%4+1)*cellw),round((i//4+1)*cellh)))
        bbox=cell.getbbox()
        cells.append(cell.crop(bbox) if bbox else Image.new('RGBA',(1,1)))
    scale=(frame-12)/max(max(c.width,c.height) for c in cells)
    frames=[]
    for c in cells:
        c=c.resize((max(1,round(c.width*scale)),max(1,round(c.height*scale))),Image.Resampling.NEAREST)
        f=Image.new('RGBA',(frame,frame));f.alpha_composite(c,((frame-c.width)//2,frame-6-c.height));frames.append(f)
    mapping={'idle':[0,1,2,3],'move':[0,1,2,3],'attack':[4,5,6,7],'skill':[8,9,10,11],'deploy':[8,9,10,11],'hit':[12,13],'death':[13,14,15,15],'victory':[0,1,2,3]}
    targets=[]
    for anim,indices in mapping.items():
        strip=Image.new('RGBA',(frame*len(indices),frame))
        for x,i in enumerate(indices):strip.alpha_composite(frames[i],(x*frame,0))
        target=folder/(cid+'_'+anim+'.png');strip.save(target);targets.append(target)
    target=folder/(cid+'_base.png');frames[0].save(target);targets.append(target)
    record(cid,raw,targets)
def portrait(cid,filename):
    raw=RAW/(cid+'_portrait.png');shutil.copy2(GEN/filename,raw)
    folder=ROOT/'assets/art/characters'/cid;folder.mkdir(parents=True,exist_ok=True)
    im=Image.open(raw).convert('RGBA');targets=[]
    for suffix,size in [('polished',512),('256',256),('64',64)]:
        t=folder/(cid+'_portrait_'+suffix+'.png');im.resize((size,size),Image.Resampling.LANCZOS).save(t);targets.append(t)
    record(cid+'_portrait',raw,targets)
if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('mode',choices=['background','sheet','portrait']);p.add_argument('name');p.add_argument('filename');p.add_argument('--kind',default='characters');a=p.parse_args()
    if a.mode=='sheet':sheet(a.name,a.filename,a.kind)
    elif a.mode=='portrait':portrait(a.name,a.filename)
    else:background(a.name,a.filename)
    MANIFEST.write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf8')
