"""Launch the exported Windows build with isolated storage and capture its actual client."""
from pathlib import Path
import argparse, json, os, shutil, subprocess, time
import windows_art_capture as win

ROOT = Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--continue-save',action='store_true')
args=parser.parse_args()
OUT = ROOT.parent / ('_testenv/v3-twohour/release_continue' if args.continue_save else '_testenv/v3-twohour/release')
OUT.mkdir(parents=True, exist_ok=True)
if args.continue_save:
    destination=OUT/'appdata/HoshigaokaEchoes/save'
    destination.mkdir(parents=True,exist_ok=True)
    shutil.copy2(ROOT.parent/'_testenv/v3-twohour/campaign5/appdata/HoshigaokaEchoes/save/savegame.json',destination/'savegame.json')
exe = ROOT / 'dist/v3_first_five_20261010/HoshigaokaEchoes.exe'
with (OUT/'game.log').open('w', encoding='utf-8') as log:
    proc = subprocess.Popen([str(exe), '--resolution', '1280x720', '--position', '30,30'],
        env=dict(os.environ, APPDATA=str(OUT/'appdata')), stdout=log, stderr=subprocess.STDOUT)
    try:
        hwnd = None
        for _ in range(100):
            if proc.poll() is not None: raise RuntimeError('Release exited before title')
            hwnd = win.find_window({proc.pid})
            if hwnd: break
            time.sleep(.1)
        if not hwnd: raise RuntimeError('No exported game window')
        time.sleep(3)
        path = win.capture_forced(hwnd, OUT, 'retail_title', {'binary':str(exe),'isolatedSave':True},seconds=10)
        if path is None: raise RuntimeError('Title screenshot unavailable')
        if args.continue_save:
            win.U.keybd_event(0x0D,0,0,0)
            win.U.keybd_event(0x0D,0,2,0)
            time.sleep(3)
            path=win.capture_forced(hwnd,OUT,'retail_continue_campus',{'binary':str(exe),'isolatedSave':True},seconds=10)
            if path is None: raise RuntimeError('Continue screenshot unavailable')
    finally:
        proc.terminate()
        proc.wait(timeout=10)
text = (OUT/'game.log').read_text(encoding='utf-8',errors='replace')
assert 'SCRIPT ERROR' not in text and 'Parse Error' not in text
assert '标题画面就绪' in text
if args.continue_save: assert 'res://scenes/home/home.tscn' in text
(OUT/'release_report.json').write_text(json.dumps({'binary':str(exe), 'realWindowsLaunch':True,
    'titleReached':True,'continueCampusReached':args.continue_save,'scriptErrors':False,'isolatedSave':True},ensure_ascii=False,indent=2),encoding='utf-8')
print('Exported Windows title verified')
