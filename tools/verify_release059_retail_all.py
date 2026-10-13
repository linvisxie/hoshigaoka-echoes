"""Run owned-window checks sequentially; never compete for Windows input."""
from pathlib import Path
import json, subprocess, sys

root = Path(__file__).resolve().parents[1]
base = root.parent/'_testenv/release059'
exe = root/'dist/chapter_one_0.5.9_20261014/HoshigaokaEchoes.exe'
earned = root.parent/'_testenv/release054/fresh3/appdata/HoshigaokaEchoes/save/savegame.json'
player = root/'dist/chapter_one_0.5.8_20261014/_testenv/player/appdata/HoshigaokaEchoes/save/savegame.json'
jobs = [('verify_hub059_retail.py','retail_final',earned),
        ('verify_navigation058_retail.py','navigation_delivery',player),
        ('verify_save_reset059_retail.py','reset_delivery',earned)]
for script, folder, seed in jobs:
    subprocess.run([sys.executable,str(root/'tools'/script),'--output',str(base/folder),
                    '--seed-save',str(seed),'--exe',str(exe)],cwd=root,check=True)
log = (base/'reset_delivery/game.log').read_text(encoding='utf8')
resources = [line for line in log.splitlines() if line.startswith('Resource still in use:')]
assert len(resources)==16 and all(line.endswith('(GDScript)') for line in resources), resources
assert not any(term in log for term in ['Texture with GL ID','RID allocations','Leaked instance: AudioStream','Leaked instance: FontFile'])
(base/'shutdown_report.json').write_text(json.dumps({'ok':True,'remainingResources':resources,
    'scope':'Final Retail normal exit after old-save/new-game navigation; GDScript residue remains'},ensure_ascii=False,indent=2),encoding='utf8')
print('All final-binary Windows-input checks passed.',flush=True)
