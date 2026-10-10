"""Collect already-rendered evidence, preserving original frames and metadata.
Comparison/GIF are explicitly derived inspection media, never game screenshots.
Uses existing Python with Pillow; does not run or modify the game.
"""
from pathlib import Path
import hashlib
import json
import shutil
from PIL import Image, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT.parent
TEST = WORK / '_testenv'
OUT = ROOT / 'docs/art_screenshots/v3_20261010'
OUT.mkdir(parents=True, exist_ok=True)
shots = TEST / 'v3-final-visual/appdata/HoshigaokaEchoes/p0.3_shots'
for file in shots.glob('v3_*'):
    shutil.copy2(file, OUT / file.name)
shutil.copy2(shots.parent / 'visual_slice_report.json', OUT)
for source, target in [
    (TEST / 'v3-final-regression/result.json', 'regression_result.json'),
    (TEST / 'v3-export-audio/audio_report.json', 'export_audio_report.json'),
    (ROOT / 'dist/v3_visual_preview/export_report.json', 'export_report.json'),
    (TEST / 'v3-export-audio/appdata/HoshigaokaEchoes/p0.3_shots/draw_char_anim_attack.png', 'exported_exe_attack.png'),
    (TEST / 'v3-export-audio/appdata/HoshigaokaEchoes/p0.3_shots/draw_char_anim_attack.png.json', 'exported_exe_attack.png.json'),
    (TEST / 'v3-baseline-20261010/appdata/HoshigaokaEchoes/p0.3_shots/deployed_kamiya_yuma.png', 'before.png'),
]:
    shutil.copy2(source, OUT / target)

panels = [
    ('BEFORE - actual Windows viewport', OUT / 'before.png'),
    ('CURRENT - actual Windows viewport; not approved', OUT / 'v3_battle_60s.png'),
    ('REFERENCE - user supplied concept; target only', WORK / 'meishu/D2A45AA08F6F8D96E6A170921EAFD594.png'),
]
comparison = Image.new('RGB', (960, 3 * 580), '#111520')
draw = ImageDraw.Draw(comparison)
for i, (label, file) in enumerate(panels):
    draw.text((16, i * 580 + 8), label, fill='white')
    with Image.open(file) as frame:
        fitted = ImageOps.contain(frame.convert('RGB'), (960, 540))
        comparison.paste(fitted, ((960 - fitted.width) // 2, i * 580 + 36))
comparison.save(OUT / 'comparison_inspection.png')

frames, durations, metadata = [], [], []
for file in sorted(OUT.glob('v3_attack_??.png')):
    meta = json.loads(file.with_suffix('.png.json').read_text(encoding='utf-8'))
    metadata.append(meta)
    with Image.open(file) as frame:
        fitted = ImageOps.contain(frame.convert('RGB'), (960, 540))
        canvas = Image.new('RGB', (960, 570), '#111520')
        canvas.paste(fitted, ((960 - fitted.width) // 2, 30))
        ImageDraw.Draw(canvas).text((12, 8), 'ACTUAL VIEWPORT SEQUENCE - automated input - scaled inspection copy', fill='white')
        frames.append(canvas)
for i, meta in enumerate(metadata):
    delta = metadata[i + 1]['logicalTime'] - meta['logicalTime'] if i + 1 < len(metadata) else 0.05
    durations.append(max(20, round(delta * 1000)))
frames[0].save(OUT / 'attack_sequence.gif', save_all=True, append_images=frames[1:], duration=durations, loop=0)

source = ROOT / 'tools/source_art/gym_v3_floor.png'
record = {
    'source': str(source), 'sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'provider': 'Built-in image_gen; exact model identity not exposed',
    'reference': 'Existing assets/art/environments/bg_env_gym_night.png; user supplied gym combat concept',
    'purpose': '1-5 visual test only; expanded walkable floor, 1920x1080',
    'terms': 'https://openai.com/policies/terms-of-use/', 'termsChecked': '2026-10-10',
    'releaseStatus': 'Internal integrated candidate; reference rights and visual approval pending',
    'narrativeConflict': '1-5 canonical map is corridor; no narrative/map data changed',
}
(ROOT / 'docs/gym_v3_source_record.json').write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf-8')
manifest = {
    'source': str(shots), 'originalsUnedited': True,
    'derivedMedia': ['comparison_inspection.png', 'attack_sequence.gif'],
    'gifDurationsMsFromLogicalTimes': durations,
    'note': 'Native viewport captures, not desktop screenshots or human play; no visual acceptance claim',
    'files': {file.name: hashlib.sha256(file.read_bytes()).hexdigest() for file in OUT.iterdir() if file.is_file() and file.name != 'manifest.json'},
}
(OUT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
print(str(OUT))
