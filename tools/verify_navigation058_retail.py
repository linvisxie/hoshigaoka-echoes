"""Actual Windows acceptance of the resume, briefing-return and empty-party UI, using a live-save copy."""
from pathlib import Path
import argparse,ctypes,hashlib,json,os,re,shutil,subprocess,time
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
            assert win.U.GetForegroundWindow()==hwnd,('Input refused outside owned game; process status='+str(proc.poll())+'; owned window valid='+str(bool(win.U.IsWindow(hwnd))))
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
        def last_scene():return re.findall(r'场景切换 -> (res://[^\r\n]+)',logs())[-1]
        time.sleep(2);key(13);time.sleep(1)
        baseline=read_save()
        check('场景切换 -> res://scenes/home/home.tscn' in logs(),'title Continue enters campus')
        shot('continue_lands_in_campus')
        click(1545,435);time.sleep(.6)
        for _ in range(80):
            if read_save()['flow_state'].get('mode')=='pre_battle':break
            click(1655,960,(1920,1080))
        check(read_save()['flow_state'].get('mode')=='pre_battle','main investigation reaches briefing')
        shot('main_investigation_briefing')
        key(27);time.sleep(.6);shot('main_escape_campus')
        check(last_scene().endswith('res://scenes/home/home.tscn'),'main briefing Escape returns campus')
        click(1565,310);time.sleep(.5)
        click(275,350,(1920,1080));time.sleep(.7)
        check(read_save()['flow_state'].get('pending_stage_id')=='1-1','records open completed first investigation')
        shot('records_briefing')
        click(1145,450,(1920,1080))
        click(1610,1005,(1920,1080));time.sleep(.2);shot('empty_party_hint')
        check(read_save()['flow_state'].get('party_selected')==[],'zero selected characters cannot start battle')
        time.sleep(2.8);shot('empty_party_hint_expired')
        key(27);time.sleep(.6);shot('records_escape_records')
        check(last_scene().endswith('res://scenes/menus/stage_select.tscn'),'record briefing Escape returns records')
        key(27);time.sleep(.5)
        key(27);time.sleep(.4)
        click(836,517);time.sleep(.7);shot('return_to_title')
        key(13);time.sleep(.6);shot('second_continue_campus')
        check(last_scene().endswith('res://scenes/home/home.tscn'),'title Continue still lands in campus after incomplete briefing')
        check(read_save()['currencies']==baseline['currencies'] and read_save()['stages']==baseline['stages'],'navigation and empty-party rejection grant no rewards or clears')
        key(27);time.sleep(.3);click(836,617);time.sleep(.3);click(991,562)
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
