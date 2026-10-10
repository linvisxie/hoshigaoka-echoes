"""Slice the reviewed 4x4 Mio atlas; fixed scale/registration, no pose synthesis.
Source is copied into art_src/raw/mio_v3_atlas.png before running.
"""
from pathlib import Path
import json, hashlib, argparse
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--character',choices=['mio','yuma'],default='mio')
parser.add_argument('--frame-size',type=int,default=64,choices=[64,96])
args=parser.parse_args()
size=args.frame_size
character='amamiya_mio' if args.character=='mio' else 'kamiya_yuma'
scale=.25 if args.character=='mio' else .19
x_offset=-15 if args.character=='mio' else 2
scale*=size/64
x_offset=round(x_offset*size/64)
source=ROOT/('tools/source_art/%s_v3_atlas.png' % args.character)
im=Image.open(source).convert('RGBA')
row_edges=[round(im.height*i/4) for i in range(5)] if args.character=='mio' else [0,345,660,963,im.height]
frames=[]
for row in range(4):
    cells=[]
    for col in range(4):
        cell=im.crop((col*im.width//4,row_edges[row],(col+1)*im.width//4,row_edges[row+1]))
        a=cell.getchannel('A').point(lambda v:255 if v>=128 else 0)
        cell.putalpha(a)
        box=a.getbbox()
        assert box is not None
        # Global scale preserves body proportions across idle, sword windup and run.
        small=cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.BOX)
        small.putalpha(small.getchannel('A').point(lambda v:255 if v>=128 else 0))
        canvas=Image.new('RGBA',(size,size))
        baseline=round(box[3]*scale)
        canvas.alpha_composite(small,(x_offset,round(size*60/64)-baseline))
        cells.append(canvas)
    frames.append(cells)

# One shared 48-colour palette, rather than a different palette for each pose.
palette_source=Image.new('RGB',(size*4,size*4),(18,22,40))
for row,cells in enumerate(frames):
    for col,cell in enumerate(cells): palette_source.paste(cell,(col*size,row*size),cell)
palette=palette_source.quantize(colors=48 if size==64 else 80,method=Image.Quantize.MEDIANCUT)
for cells in frames:
    for index,cell in enumerate(cells):
        q=cell.convert('RGB').quantize(palette=palette,dither=Image.Dither.NONE).convert('RGBA')
        q.putalpha(cell.getchannel('A'))
        cells[index]=q
out=ROOT/'assets/art/characters'/character
animations={'idle':frames[0], 'attack':frames[1], 'hit':frames[2][:2],
            'death':[frames[2][0],frames[2][1],frames[2][2],frames[2][3]], 'move':frames[3]}
for name,poses in animations.items():
    strip=Image.new('RGBA',(size*len(poses),size))
    for col,pose in enumerate(poses): strip.alpha_composite(pose,(col*size,0))
    strip.save(out/f'{character}_{name}.png')
frames[0][0].save(out/f'{character}_base.png')
preview=Image.new('RGBA',(4*256,5*256),(18,22,40,255))
for row,(name,poses) in enumerate(animations.items()):
    for col,pose in enumerate(poses): preview.alpha_composite(pose.resize((256,256),Image.Resampling.NEAREST),(col*256,row*256))
preview.save(ROOT/('docs/art_screenshots/%s_v3_registered.png' % args.character))
(ROOT/('docs/%s_v3_source_record.json' % args.character)).write_text(json.dumps({
    'source':str(source), 'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
    'provider':'Built-in image_gen; exact model identity not exposed by tool',
    'reference':'meishu/Hoshigaoka_Art_Preview_Pack/' + ('03_p0_asset_sheet_amamiya_mio.png' if args.character=='mio' else '02_visual_bible_overview.png'),
    'transforms':[f'4 columns; reviewed row bounds {row_edges}','alpha threshold 128',f'uniform scale {scale}',f'shared {48 if size==64 else 80}-colour palette',f'fixed x offset {x_offset}',f'feet alignment y={round(size*60/64)}'],
    'terms':'https://openai.com/policies/terms-of-use/',
    'termsChecked':'2026-10-10', 'inputReferenceRights':'User confirms the three supplied concept images were generated with GPT on 2026-10-10',
    'releaseStatus':'Internal integrated candidate; visual approval and reference rights verification pending',
    'frameSize':size,
    'notes':'16 drawn poses; uniform registration. Deployment, skill and victory are separate drawn strips. User confirmed GPT reference provenance.'},ensure_ascii=False,indent=2),encoding='utf-8')
