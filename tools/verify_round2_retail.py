"""Real OS clicks through an exported Retail game. No developer entry or gameplay overrides."""
from pathlib import Path
import json,os,shutil,subprocess,time
import windows_art_capture as win
import ctypes
win.U.SetThreadDpiAwarenessContext.argtypes=[ctypes.c_void_p]
win.U.SetThreadDpiAwarenessContext(ctypes.c_void_p(-4))
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT.parent/'_testenv/v3-round2/retail_battle'
OUT.mkdir(parents=True,exist_ok=True)
save=OUT/'appdata/HoshigaokaEchoes/save'
save.mkdir(parents=True,exist_ok=True)
shutil.copy2(ROOT.parent/'_testenv/v3-round2/campaign_final/appdata/HoshigaokaEchoes/save/savegame.json',save/'savegame.json')
exe=ROOT/'dist/v3_ui_polish_20261010/HoshigaokaEchoes.exe'
with (OUT/'game.log').open('w',encoding='utf8') as log:
    proc=subprocess.Popen([str(exe),'--resolution','1280x720','--position','30,30'],env=dict(os.environ,APPDATA=str(OUT/'appdata')),stdout=log,stderr=subprocess.STDOUT)
    try:
        hwnd=None
        for _ in range(80):
            hwnd=win.find_window({proc.pid})
            if hwnd:break
            time.sleep(.1)
        if not hwnd:raise RuntimeError('No Retail window')
        time.sleep(2)
        def shot(name):
            if win.capture_forced(hwnd,OUT,name,{'binary':str(exe),'input':'real Windows mouse/keyboard; automated'},seconds=8) is None:raise RuntimeError('Foreground screenshot failed')
        def click(x,y):
            ox,oy,w,h=win.client(hwnd)
            if win.U.GetForegroundWindow()!=hwnd:raise RuntimeError('Refuse click outside owned foreground window')
            win.real_click((ox+round(x*w/1920),oy+round(y*h/1080)))
            time.sleep(.7)
        def reached(fragment):
            current=(OUT/'game.log').read_text(encoding='utf8',errors='replace')
            if fragment not in current:raise RuntimeError('Expected scene/action absent: '+fragment)
        shot('title')
        win.U.keybd_event(0x0D,0,0,0);win.U.keybd_event(0x0D,0,2,0)
        time.sleep(1)
        reached('res://scenes/home/home.tscn')
        shot('campus')
        click(380,835) # Replay unlocked stages
        reached('res://scenes/menus/stage_select.tscn')
        shot('stage_cards')
        click(960,720) # Fifth stage card
        reached('res://scenes/menus/briefing.tscn')
        shot('briefing')
        click(1600,1005) # Start battle
        time.sleep(2)
        reached('stage=1-5')
        shot('battle_initial')
        win.U.keybd_event(0x31,0,0,0);win.U.keybd_event(0x31,0,2,0)
        time.sleep(.2)
        shot('deployment_preview')
        click(926,506) # Mio at middle lane, column 2
        time.sleep(.5)
        shot('battle_deployed')
        click(1815,55) # Native pause button
        shot('pause')
    finally:
        proc.terminate();proc.wait(timeout=10)
text=(OUT/'game.log').read_text(encoding='utf8',errors='replace')
assert 'SCRIPT ERROR' not in text and 'Parse Error' not in text
assert 'stage=1-5' in text and '玩家部署 雨宫澪' in text and '战斗已暂停' in text
(OUT/'retail_report.json').write_text(json.dumps({'binary':str(exe),'realWindowsInput':True,'stage':'1-5','deployment':True,'pause':True,'saveIsolated':True},ensure_ascii=False,indent=2),encoding='utf8')
print('Retail title -> campus -> stage select -> briefing -> battle -> deployment -> pause verified')
