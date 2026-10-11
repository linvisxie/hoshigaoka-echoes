"""Import imagegen background-removal results without changing their artwork."""
from pathlib import Path
from PIL import Image
import json,hashlib,shutil
ROOT=Path(__file__).resolve().parents[1]
SOURCE=Path(r'C:\Users\linvisxie\.codex\generated_images\01a12374-ae46-7552-ad65-5bdc38457258')
FILES={'ogawa_yui':'exec-eae800ea-e68e-458e-90b5-9ac6d135d260.png','minase_sara':'exec-f4e0cd64-dec4-4682-9986-4c0a8c4a5016.png','shiraishi_chinatsu':'exec-419386d5-bb33-4b58-b5d4-b5ee6264349c.png'}
records=[]
for cid,name in FILES.items():
    raw=ROOT/'tools/source_art/chapter_tail'/f'{cid}_portrait_transparent_revision.png'
    shutil.copy2(SOURCE/name,raw)
    image=Image.open(raw).convert('RGBA')
    assert image.getpixel((0,0))[3]==0,'Expected genuine transparent corner'
    target=ROOT/'assets/art/characters'/cid
    for size,suffix in [(512,'polished'),(256,'256'),(64,'64')]:
        image.resize((size,size),Image.Resampling.LANCZOS).save(target/f'{cid}_portrait_{suffix}.png')
    records.append({'character':cid,'source':str(raw.relative_to(ROOT)),'sha256':hashlib.sha256(raw.read_bytes()).hexdigest(),'alphaCorner':0,'processing':'RGBA conversion and Lanczos resize only; original closeup preserved'})
(ROOT/'docs/transparent_portrait_revision.json').write_text(json.dumps({'tool':'Built-in imagegen background-removal edit of project-owned AI portraits','userArtAcceptance':False,'assets':records},ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(records,ensure_ascii=False))
