"""Real OS clicks through an exported Retail game. No developer entry or gameplay overrides."""
from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess,time
import windows_art_capture as win
import ctypes
win.U.SetThreadDpiAwarenessContext.argtypes=[ctypes.c_void_p]
win.U.SetThreadDpiAwarenessContext(ctypes.c_void_p(-4))
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--exe',type=Path,default=ROOT/'dist/v3_ui_polish_20261010/HoshigaokaEchoes.exe')
parser.add_argument('--output',type=Path,default=ROOT.parent/'_testenv/v3-round2/retail_battle')
parser.add_argument('--seed-save',type=Path,default=ROOT.parent/'_testenv/v3-round2/campaign_final/appdata/HoshigaokaEchoes/save/savegame.json')
parser.add_argument('--campus-left',action='store_true',help='Verify the primary replay button instead of handbook navigation')
parser.add_argument('--party-size',type=int,default=2,choices=[2,3])
parser.add_argument('--projected',action='store_true',help='0.4.6 slanted battlefield coordinates')
parser.add_argument('--round10',action='store_true',help='0.4.7 growth hovers, horizontal lanes and retry')
args=parser.parse_args()
OUT=args.output.resolve()
if '_testenv' not in OUT.parts:raise SystemExit('Refuse non-isolated output')
OUT.mkdir(parents=True,exist_ok=True)
save=OUT/'appdata/HoshigaokaEchoes/save'
save.mkdir(parents=True,exist_ok=True)
shutil.copy2(args.seed_save,save/'savegame.json')
exe=args.exe.resolve()
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
            point=(ox+round(x*w/1920),oy+round(y*h/1080))
            win.U.SetCursorPos(*point)
            time.sleep(.12)
            actual=win.W.POINT();win.U.GetCursorPos(ctypes.byref(actual))
            if (actual.x,actual.y)!=point:raise RuntimeError('Windows cursor did not reach intended point')
            if win.U.GetForegroundWindow()!=hwnd:raise RuntimeError('Owned game lost focus before mouse press')
            win.U.mouse_event(0x0002,0,0,0,None);time.sleep(.06)
            win.U.mouse_event(0x0004,0,0,0,None);time.sleep(.25)
            print('Clicked',x,y,'at physical',point,flush=True)
            time.sleep(.7)
        def move(x,y):
            ox,oy,w,h=win.client(hwnd)
            if win.U.GetForegroundWindow()!=hwnd:raise RuntimeError('Refuse move outside owned foreground window')
            point=(ox+round(x*w/1920),oy+round(y*h/1080))
            win.U.SetCursorPos(*point)
            actual=win.W.POINT();win.U.GetCursorPos(ctypes.byref(actual))
            if (actual.x,actual.y)!=point:raise RuntimeError('Windows cursor did not reach tooltip target')
        def reached(fragment):
            current=(OUT/'game.log').read_text(encoding='utf8',errors='replace')
            if fragment not in current:raise RuntimeError('Expected scene/action absent: '+fragment)
        shot('title')
        win.U.keybd_event(0x0D,0,0,0);win.U.keybd_event(0x0D,0,2,0)
        time.sleep(1)
        reached('res://scenes/home/home.tscn')
        shot('campus')
        if args.round10:
            click(1545,475)
            reached('res://scenes/menus/character_screen.tscn')
            shot('growth_layout')
            for cid,x in [('school_coin',770),('study_record',1015),('club_badge',1275),('echo_crystal',1530),('equipment_part',1785)]:
                move(x,75);time.sleep(.6);shot('resource_'+cid)
            click(518,720)
            reached('res://scenes/menus/equipment.tscn')
            shot('equipment_bow_only')
            click(1630,1015)
            reached('res://scenes/home/home.tscn')
        click(380,835) if args.campus_left else click(1545,590)
        reached('res://scenes/menus/stage_select.tscn')
        shot('stage_cards')
        click(960,720) # Fifth stage card
        reached('res://scenes/menus/briefing.tscn')
        shot('briefing')
        click(1145,845) # Rotate deployment order through real UI
        shot('briefing_reordered')
        for _ in range(args.party_size-1): click(1145,845) # Restore original order
        click(1600,1005) # Start battle
        time.sleep(2)
        reached('stage=1-5')
        shot('battle_initial')
        win.U.keybd_event(0x31,0,0,0);win.U.keybd_event(0x31,0,2,0)
        time.sleep(.2)
        shot('deployment_preview')
        click(970,590) if args.round10 else (click(970,562) if args.projected else click(926,506))
        time.sleep(.5)
        shot('battle_deployed')
        time.sleep(3)
        shot('battle_context_hint')
        move(90,930)
        time.sleep(1)
        shot('deployed_card_tooltip')
        click(1815,55) # Native pause button
        shot('pause')
        if args.round10:
            click(960,578)
            reached('重试本次调查：1-5')
            time.sleep(.7)
            shot('retry_fresh_battle')
            for index in range(8):
                shot('core_turn_%02d'%index);time.sleep(.17)
            click(1815,55)
        click(960,713) # End current investigation
        shot('leave_confirmation')
        click(1205,668) # Confirm return to campus
        click(1670,832) # Campus -> title
        time.sleep(.5)
        win.U.keybd_event(0x1B,0,0,0);win.U.keybd_event(0x1B,0,2,0)
        time.sleep(.5)
        shot('exit_confirmation')
        click(1125,629) # Actual title confirmation -> App.request_quit
        proc.wait(timeout=8)
        assert proc.returncode==0,'Normal exit failed'
    finally:
        if proc.poll() is None:proc.terminate();proc.wait(timeout=10)
text=(OUT/'game.log').read_text(encoding='utf8',errors='replace')
assert 'SCRIPT ERROR' not in text and 'Parse Error' not in text
assert 'stage=1-5' in text and '玩家部署 雨宫澪' in text and '战斗已暂停' in text
assert '收到退出请求' in text
(OUT/'retail_report.json').write_text(json.dumps({'binary':str(exe),'realWindowsInput':True,'stage':'1-5','deployment':True,'pause':True,'round10GrowthHoversAndRetry':args.round10,'saveIsolated':True,'normalExit':True,'binarySha256':hashlib.sha256(exe.read_bytes()).hexdigest(),'pckSha256':hashlib.sha256(exe.with_suffix('.pck').read_bytes()).hexdigest()},ensure_ascii=False,indent=2),encoding='utf8')
print('Retail title -> campus -> stage select -> briefing -> battle -> deployment -> pause -> leave -> normal exit verified')
