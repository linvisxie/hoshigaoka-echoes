"""Retain original Windows renderer evidence, without compositing or modifying saves."""
from pathlib import Path
import hashlib, json, shutil

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent / '_testenv/v3-round8'
OUT = ROOT / 'docs/art_screenshots/v3_resonance_polish_20261011'
OUT.mkdir(parents=True, exist_ok=True)
records = []

def retain(source, name):
    assert source.is_file(), str(source)
    target = OUT / name
    shutil.copy2(source, target)
    records.append({'file': name, 'source': str(source),
                    'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})

campaign = BASE / 'campaign_dense_final/appdata/HoshigaokaEchoes'
dynamic = BASE / 'dynamic_fanned/appdata/HoshigaokaEchoes'
for prefix, folder in [('campaign', campaign / 'campaign_shots'),
                       ('dynamic', dynamic / 'p0.3_shots'),
                       ('retail', BASE / 'retail_hint_final')]:
    for source in sorted(folder.glob('*.png')):
        if prefix == 'dynamic' and not source.name.startswith('v3_'): continue
        if prefix == 'campaign' and not (source.stem == 'title' or
            source.stem.startswith(('battle_', 'briefing_', 'ch1_1_4_', 'ch1_1_5_', 'campus_after_5'))): continue
        retain(source, prefix + '_' + source.name)
        sidecar = source.with_suffix('.png.json')
        if sidecar.exists(): retain(sidecar, prefix + '_' + sidecar.name)

for name, path in {
    'campaign_report.json': campaign / 'campaign_report.json',
    'dynamic_report.json': dynamic / 'visual_slice_report.json',
    'dynamic_actual_draw_ledger.json': dynamic / 'art_probe/latest.json',
    'regression_report.json': BASE / 'regression_final/result.json',
    'retail_report.json': BASE / 'retail_hint_final/retail_report.json',
    'battle_audio_report.json': BASE / 'audio_battle_final/audio_report.json',
    'title_audio_report.json': BASE / 'audio_retail_final/audio_report.json',
    'battle_windows_loopback.wav': BASE / 'audio_battle_final/windows_loopback.wav',
}.items(): retain(path, name)

(OUT / 'evidence_manifest.json').write_text(json.dumps({
    'version': '0.4.5', 'evidenceType': 'Original Windows game captures; automated, not human play/listening',
    'campaignRevision': '26/25/24 enemies, ordinary clock and production flow; before final pack offset and compact toast styling',
    'dynamicRevision': 'Final pack offset, compact toast, recovery frames and actual draw ledger; before the final hint padding correction verified in Retail',
    'retailRevision': 'Final exported binary; real OS mouse/keyboard, earned campaign save copied into isolated test directory',
    'files': records}, ensure_ascii=False, indent=2), encoding='utf8')
print(f'Retained {len(records)} original evidence files in {OUT}')
