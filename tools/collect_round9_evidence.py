"""Retain unmodified Windows captures; separate revisions explicitly."""
from pathlib import Path
import hashlib, json, shutil

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent / '_testenv/v3-round9'
OUT = ROOT / 'docs/art_screenshots/v3_perspective_polish_20261011'
OUT.mkdir(parents=True, exist_ok=True)
records = []

def retain(source, name):
    assert source.is_file(), str(source)
    target = OUT / name
    shutil.copy2(source, target)
    records.append({'file': name, 'source': str(source),
                    'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})

for prefix, folder in [
    ('campaign', BASE/'campaign/appdata/HoshigaokaEchoes/campaign_shots'),
    ('dynamic', BASE/'dynamic_final/appdata/HoshigaokaEchoes/p0.3_shots'),
    ('rin', BASE/'rin_replay_final/appdata/HoshigaokaEchoes/p0.3_shots'),
    ('retail', BASE/'retail_final_single_hint'),
]:
    for p in sorted(folder.glob('*.png')):
        if prefix == 'dynamic' and not p.name.startswith('v3_'): continue
        if prefix == 'rin' and not p.name.startswith(('rin_', 'replay_', 'elite_')): continue
        retain(p, prefix+'_'+p.name)
        sidecar = p.with_suffix('.png.json')
        if sidecar.exists(): retain(sidecar, prefix+'_'+sidecar.name)

for i in range(1,6):
    for p in sorted((BASE/f'layout_stage_{i}').rglob('*.png')):
        retain(p, f'layout_{i}_'+p.name)

for name, path in {
    'campaign_report.json': 'campaign/appdata/HoshigaokaEchoes/campaign_report.json',
    'dynamic_report.json': 'dynamic_final/appdata/HoshigaokaEchoes/visual_slice_report.json',
    'dynamic_actual_draw_ledger.json': 'dynamic_final/appdata/HoshigaokaEchoes/art_probe/latest.json',
    'rin_report.json': 'rin_replay_final/appdata/HoshigaokaEchoes/rin_replay_report.json',
    'regression_report.json': 'regression_final/result.json',
    'final_hint_regression.txt': 'regression_hint/gut.log',
    'retail_report.json': 'retail_final_single_hint/retail_report.json',
    'layout_report.json': 'layout_report.json',
    'elite_audio_report.json': 'audio_elite_final/audio_report.json',
    'elite_windows_loopback.wav': 'audio_elite_final/windows_loopback.wav',
}.items(): retain(BASE/path, name)

(OUT/'evidence_manifest.json').write_text(json.dumps({
    'version':'0.4.6', 'type':'Original Windows captures; automated, not human acceptance',
    'campaignRevision':'Full five-stage ordinary-clock progression; before final font, punctuation and single-hint polish',
    'dynamicRevision':'Projection, Yuma recovery and elite cues; before final fonts and sampled-piano rendering',
    'rinRevision':'Actual AP support, zero attack damage, two replay upgrade choices; before final presentation-only changes',
    'audioRevision':'Final VSCO CC0 sampled piano; WASAPI output, not human listening',
    'retailRevision':'Final exported binary including single-hint correction; real OS mouse and keyboard',
    'layoutRevision':'Actual five-stage identical core, cell polygons and HUD rectangles; before single-hint correction',
    'files':records}, ensure_ascii=False,indent=2),encoding='utf8')
print(f'Retained {len(records)} original evidence files in {OUT}')
