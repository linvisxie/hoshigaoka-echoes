"""Actual Windows acceptance of the approved campus Hub, using an earned save copy."""
from pathlib import Path
import argparse,ctypes,hashlib,json,os,shutil,subprocess,time
import windows_art_capture as win

p=argparse.ArgumentParser()
p.add_argument('--output',type=Path,required=True)
p.add_argument('--seed-save',type=Path,required=True)
p.add_argument('--exe',type=Path,required=True)
a=p.parse_args()
out=a.output.resolve()
assert '_testenv' in out.parts
save_dir=out/'appdata/HoshigaokaEchoes/save'
save_dir.mkdir(parents=True,exist_ok=True)
save_path=save_dir/'savegame.json'
shutil.copy2(a.seed_save,save_path)
checks=[]
def check(ok,name):
    checks.append({'ok':bool(ok),'name':name})
    assert ok,name
def read_save():return json.loads(save_path.read_text(encoding='utf-8-sig'))
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
win.U.SetThreadDpiAwarenessContext.argtypes=[ctypes.c_void_p]
win.U.SetThreadDpiAwarenessContext(ctypes.c_void_p(-4))
with (out/'game.log').open('w',encoding='utf8') as log:
    proc=subprocess.Popen([str(a.exe),'--resolution','1280x720','--position','30,30'],env=dict(os.environ,APPDATA=str(out/'appdata')),stdout=log,stderr=subprocess.STDOUT)
    try:
        hwnd=None
        for _ in range(100):
            hwnd=win.find_window({proc.pid})
            if hwnd:break
            time.sleep(.1)
        check(hwnd is not None,'owned Retail window')
        def foreground():
            deadline=time.monotonic()+8
            while win.U.GetForegroundWindow()!=hwnd and time.monotonic()<deadline:
                win._force_foreground(hwnd);time.sleep(.1)
            assert win.U.GetForegroundWindow()==hwnd,'Input refused outside owned game'
        def click(x,y,ref=(1672,941)):
            foreground();ox,oy,w,h=win.client(hwnd)
            win.U.SetCursorPos(ox+round(x*w/ref[0]),oy+round(y*h/ref[1]))
            win.U.mouse_event(2,0,0,0,None);time.sleep(.04);win.U.mouse_event(4,0,0,0,None);time.sleep(.18)
        def key(code):
            foreground();win.U.keybd_event(code,0,0,0);time.sleep(.04);win.U.keybd_event(code,0,2,0);time.sleep(.18)
        def shot(name):
            for attempt in range(3):
                foreground()
                try:
                    if win.capture_forced(hwnd,out,name,{'input':'Actual Windows input','binary':str(a.exe)},seconds=8):break
                except RuntimeError:
                    if attempt==2:raise
            check((out/(name+'.png')).exists(),'capture '+name)
        def logs():return (out/'game.log').read_text(encoding='utf8',errors='replace')
        time.sleep(2);key(13);time.sleep(1)
        shot('campus_completed')
        baseline=read_save()
        click(145,593);time.sleep(.4);shot('board_collapsed')
        check('调查公告板：收起' in logs(),'physical board collapses native investigation')
        click(145,593);time.sleep(.4);shot('board_restored')
        check('调查公告板：展开' in logs(),'physical board restores native investigation')
        click(840,394);time.sleep(.6);shot('campus_roam')
        check('打开地点：校园漫游' in logs(),'central region-travel entry works')
        key(27);time.sleep(.4)
        click(1060,438);time.sleep(.5);shot('archery_location')
        check('打开地点：弓道场' in logs(),'archery doorway opens location')
        key(27);time.sleep(.4)
        click(1350,451);time.sleep(.5);shot('infirmary_location')
        click(1070,331);time.sleep(.7)
        check(read_save()['flow_state']['current_story_id']=='hub_ch1_yui','infirmary enters actual unlocked Yui story')
        shot('yui_conversation')
        for _ in range(80):
            if read_save()['flow_state'].get('mode')=='hub':break
            click(1655,960,(1920,1080))
        check(read_save()['story']['flags'].get('done:hub_ch1_yui',False),'conversation saved as read')
        check(read_save()['currencies']==baseline['currencies'] and read_save()['stages']==baseline['stages'],'conversation grants no currency or stage progress')
        time.sleep(.7);shot('campus_after_conversation')
        click(650,296);time.sleep(.5);shot('academic_location');key(27);time.sleep(.4)
        click(300,550);time.sleep(.5);shot('mio_location');key(27);time.sleep(.4)
        click(1565,190);time.sleep(.8);shot('cultivation')
        click(185,718,(1920,1080));time.sleep(.8)
        click(1565,250);time.sleep(.7);shot('character_equipment')
        click(1635,1007,(1920,1080));time.sleep(.7)
        click(1565,370);time.sleep(.7);shot('story_archive');key(27);time.sleep(.6)
        click(1622,47);time.sleep(.7);shot('settings');key(27);time.sleep(.6)
        click(1545,435);time.sleep(.7);shot('completed_investigation_revisit')
        check('场景切换 -> res://scenes/menus/stage_select.tscn' in logs(),'main investigation shortcut revisits cleared stages after chapter completion')
        key(27);time.sleep(.6)
        # Return to the campus menu and quit through its actual confirmation.
        key(27);time.sleep(.5);shot('campus_menu')
        check('打开校园菜单' in logs(),'Escape opens campus menu')
        click(836,617);time.sleep(.5);shot('quit_confirmation')
        check('打开退出确认' in logs(),'campus menu opens quit confirmation')
        click(991,562)
        proc.wait(timeout=10)
        check(proc.returncode==0,'normal in-game exit')
    finally:
        if proc.poll() is None:proc.terminate();proc.wait(timeout=10)
text=logs()
check('SCRIPT ERROR' not in text and 'Parse Error' not in text,'no script or parse errors')
errors=[line for line in text.splitlines() if line.startswith('ERROR:')]
allowed=('RID allocations','Texture with GL ID','resources still in use at exit')
check(all(any(kind in line for kind in allowed) for line in errors),'only separately recorded shutdown resource warnings')
report={'ok':True,'type':'Final Retail EXE with actual Windows input and isolated earned save copy','checks':checks,'shutdownWarnings':errors,'exeSha256':sha(a.exe),'pckSha256':sha(a.exe.with_suffix('.pck')),'sourceSaveSha256':sha(a.seed_save)}
(out/'retail_hub_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'ok':True,'checks':len(checks),'screenshots':len(list(out.glob('*.png')))},ensure_ascii=False))
