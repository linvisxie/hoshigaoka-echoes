"""Register an imagegen four-pose strip to the existing animation's cell boxes.

Import only: connected-component extraction, nearest sampling and cell packing.
No synthesized poses, no interpolation, no palette recolouring.
"""
import argparse
from collections import deque
from pathlib import Path
import json
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--character',required=True)
    parser.add_argument('--recovery',action='store_true')
    args=parser.parse_args()
    source=Image.open(args.source).convert('RGBA')
    pix=source.load(); width,height=source.size
    visited=bytearray(width*height); groups=[]
    for y in range(height):
        for x in range(width):
            idx=y*width+x
            if visited[idx] or pix[x,y][3]<128:continue
            visited[idx]=1; queue=deque([(x,y)]); component=[]
            while queue:
                xx,yy=queue.popleft();component.append((xx,yy))
                for nx,ny in ((xx+1,yy),(xx-1,yy),(xx,yy+1),(xx,yy-1)):
                    if 0<=nx<width and 0<=ny<height:
                        pos=ny*width+nx
                        if not visited[pos] and pix[nx,ny][3]>=128:
                            visited[pos]=1;queue.append((nx,ny))
            if len(component)>2000:groups.append(component)
    count=2 if args.recovery else 4
    if len(groups)!=count:raise ValueError(f'Expected exactly {count} separate poses, got {len(groups)}')
    groups.sort(key=lambda g:min(x for x,y in g))
    path=ROOT/'assets/art/characters'/args.character/(args.character+'_attack.png')
    original=Image.open(path).convert('RGBA')
    if original.size!=(384,96):raise ValueError('Unexpected production cell dimensions')
    output=Image.new('RGBA',(count*96,96))
    report=[]
    for index,component in enumerate(groups):
        xs,ys=zip(*component); box=(min(xs),min(ys),max(xs)+1,max(ys)+1)
        isolated=Image.new('RGBA',(box[2]-box[0],box[3]-box[1])); target=isolated.load()
        for x,y in component:target[x-box[0],y-box[1]]=pix[x,y]
        oldbox=([(8,35,85,91),(10,28,90,91)][index] if args.recovery else
                original.crop((index*96,0,(index+1)*96,96)).getchannel('A').getbbox())
        scaled=isolated.resize((oldbox[2]-oldbox[0],oldbox[3]-oldbox[1]),Image.Resampling.NEAREST)
        output.paste(scaled,(index*96+oldbox[0],oldbox[1]))
        report.append({'frame':index,'generatedBox':box,'productionBox':oldbox})
    if args.recovery:path=path.with_name(args.character+'_recovery.png')
    output.save(path)
    (ROOT/'docs'/('v3_'+args.character+('_recovery' if args.recovery else '_attack')+'_import.json')).write_text(json.dumps({
        'source':str(args.source),'method':'Four distinct imagegen poses, connected-component extraction and nearest-neighbour registration to pre-existing 96px production cells.',
        'output':path.relative_to(ROOT).as_posix(),'frames':report,
        'status':'Imported; dynamic identity, weapon and transition inspection required.'},indent=2),encoding='utf8')
    print(path)

if __name__=='__main__':main()
