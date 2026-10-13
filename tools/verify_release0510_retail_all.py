"""Sequential actual Windows acceptance; one owned game window at a time."""
from pathlib import Path
import subprocess, sys

root=Path(__file__).resolve().parents[1]
base=root.parent/'_testenv/release0510'
exe=root/'dist/chapter_one_0.5.10_20261014/HoshigaokaEchoes.exe'
earned=root.parent/'_testenv/release054/fresh3/appdata/HoshigaokaEchoes/save/savegame.json'
player=root/'dist/chapter_one_0.5.9_20261014/_testenv/player/appdata/HoshigaokaEchoes/save/savegame.json'
for script,folder,seed in [
    ('verify_player_journey.py','journey_final',earned),
    ('verify_boss0510_retail.py','boss_final',earned),
    ('verify_hub059_retail.py','retail_final',earned),
    ('verify_navigation058_retail.py','navigation_delivery',player),
]:
    print('Running '+script,flush=True)
    subprocess.run([sys.executable,str(root/'tools'/script),'--output',str(base/folder),
                    '--seed-save',str(seed),'--exe',str(exe)],cwd=root,check=True)
print('All final 0.5.10 Windows checks passed.',flush=True)
