"""Pack the generated 4 x 6 pose sheet without inventing or recolouring poses.

Every source cell shares the same scale and origin; kneeling frames retain
their shorter silhouette. Low-alpha export residue is removed, not keyed.
"""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'tools/source_art/rin_full_motion_v3.png'

def main():
    source = Image.open(SOURCE).convert('RGBA')
    if source.size != (1024, 1536):
        raise ValueError('Expected 4 x 6 registered 256px cells')
    folder = ROOT / 'assets/art/characters/fujiwara_rin'
    records = []
    for row, animation in enumerate(['idle', 'move', 'attack', 'hit', 'death', 'skill']):
        columns = [0, 2] if animation == 'hit' else range(4)
        strip = Image.new('RGBA', (96 * len(columns), 96))
        for frame, col in enumerate(columns):
            cell = source.crop((col*256, row*256, (col+1)*256, (row+1)*256))
            alpha = cell.getchannel('A').point(lambda value: 0 if value < 16 else value)
            cell.putalpha(alpha)
            cell = cell.resize((86, 86), Image.Resampling.NEAREST)
            strip.paste(cell, (frame*96+5, 5))
        path = folder / ('fujiwara_rin_' + animation + '.png')
        strip.save(path)
        records.append({'animation': animation, 'sourceRow': row, 'sourceColumns': list(columns),
                        'output': path.relative_to(ROOT).as_posix()})
    # Deployment borrows the actual casting poses with the runtime summoning ring.
    Image.open(folder/'fujiwara_rin_skill.png').save(folder/'fujiwara_rin_deploy.png')
    Image.open(folder/'fujiwara_rin_idle.png').crop((0,0,96,96)).save(folder/'fujiwara_rin_base.png')
    Image.open(folder/'fujiwara_rin_portrait_256.png').resize((64,64), Image.Resampling.LANCZOS).save(folder/'fujiwara_rin_portrait_64.png')
    (ROOT/'docs/v3_rin_motion_import.json').write_text(json.dumps({
        'source': SOURCE.relative_to(ROOT).as_posix(), 'sourceSHA256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        'provenance': 'OpenAI image generation; existing project Rin identity and Yuma pixel style references',
        'method': 'Uniform nearest-neighbour 256 to 86; fixed 5px origin in 96px cells; alpha <16 export residue removed',
        'deployment': 'Reuses four casting poses, with runtime ground ring; not a separately generated motion',
        'frames': records, 'status': 'Imported; real runtime inspection tracked separately'
    }, ensure_ascii=False, indent=2), encoding='utf8')
    print('Rin: six distinct motions imported, fixed registration')

if __name__ == '__main__':
    main()
