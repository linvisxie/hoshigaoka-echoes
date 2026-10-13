"""Normal-clock player journey via owned-window Windows input; no save injection."""
from pathlib import Path
import argparse, ctypes, hashlib, json, os, re, shutil, subprocess, time
import windows_art_capture as win

p=argparse.ArgumentParser()
p.add_argument('--exe',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
p.add_argument('--seed-save',type=Path,required=True)
a=p.parse_args();out=a.output.resolve();assert '_testenv' in out.parts
folder=out/'appdata/HoshigaokaEchoes';(folder/'save').mkdir(parents=True,exist_ok=True)
save=folder/'save/savegame.json';shutil.copy2(a.seed_save,save)
probe_file=folder/'art_probe/latest.json'
if probe_file.exists():probe_file.unlink()
checks=[];samples=[];proc=None;error=None
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def data():return json.loads(save.read_text(encoding='utf-8-sig'))
def check(ok,name):
    checks.append(dict(ok=bool(ok),name=name));print(name, bool(ok),flush=True)
    assert ok,name
def probe():
    try:return json.loads(probe_file.read_text(encoding='utf8'))
    except (OSError,ValueError):return None
win.U.SetThreadDpiAwarenessContext.argtypes=[ctypes.c_void_p]
win.U.SetThreadDpiAwarenessContext(ctypes.c_void_p(-4))
with (out/'game.log').open('w',encoding='utf8') as log:
    proc=subprocess.Popen([str(a.exe),'--resolution','1280x720','--position','30,30','--verbose'],
        env=dict(os.environ,APPDATA=str(out/'appdata')),stdout=log,stderr=subprocess.STDOUT)
    try:
        hwnd=None
        for _ in range(100):
            hwnd=win.find_window({proc.pid})
            if hwnd:break
            time.sleep(.1)
        check(hwnd is not None,'Owned Retail window available')
        def foreground():
            deadline=time.monotonic()+8
            while win.U.GetForegroundWindow()!=hwnd and time.monotonic()<deadline:
                win._force_foreground(hwnd);time.sleep(.1)
            assert win.U.GetForegroundWindow()==hwnd,'Input refused outside owned game'
        def click(x,y,ref=(1920,1080)):
            foreground();ox,oy,w,h=win.client(hwnd)
            win.U.SetCursorPos(ox+round(x*w/ref[0]),oy+round(y*h/ref[1]))
            win.U.mouse_event(2,0,0,0,None);time.sleep(.04);win.U.mouse_event(4,0,0,0,None);time.sleep(.12)
        def key(code):
            foreground();win.U.keybd_event(code,0,0,0);time.sleep(.04);win.U.keybd_event(code,0,2,0);time.sleep(.12)
        def shot(name):
            foreground();check(win.capture_forced(hwnd,out,name,{'binary':str(a.exe),'input':'Actual Windows input; normal clock; isolated earned-save copy'},seconds=8),'Capture '+name)
        def read_story():
            for _ in range(100):
                if data()['flow_state'].get('mode')=='pre_battle':break
                click(1655,960)
            time.sleep(.7)
        def wait_battle(play=False):
            deadline=time.monotonic()+180
            while time.monotonic()<deadline:
                s=probe()
                if not s:time.sleep(.1);continue
                if s['outcome']!='进行中':return s
                samples.append({'clock':s['time'],'audio':s['audio'],'characters':s['characters'],'vfx':s['activeVfx']})
                if play:
                    if not s['characters']:
                        r=s['cardRects'][0];click(r[0]+r[2]/2,r[1]+r[3]/2,s['canvas'])
                        target=next(c for c in s['layout']['cells'] if c['column']==3 and c['lane']==1)
                        pts=target['polygon'];click(sum(v[0] for v in pts)/4,sum(v[1] for v in pts)/4,s['canvas'])
                    elif s['characters'][0]['skillReady'] and any(e['hp']>0 and e['lane']==1 for e in s['enemies']):
                        r=s['cardRects'][0];click(r[0]+r[2]/2,r[1]+r[3]/2,s['canvas']);key(0x51)
                time.sleep(.3)
            raise AssertionError('Normal battle did not resolve within 180 seconds')
        def quit_from_campus():
            key(27);time.sleep(.4);click(836,617,(1672,941));time.sleep(.4);click(991,562,(1672,941))
            proc.wait(timeout=10);check(proc.returncode==0,'Normal confirmed in-game exit')
        time.sleep(2);key(13);time.sleep(.8)
        # Spend only actually earned resources through visible controls.
        before=data();click(1565,190,(1672,941));time.sleep(.7);shot('old_cultivation')
        click(1355,827);time.sleep(.3);click(960,895);time.sleep(.7)
        after=data();check(after['currencies'].get('study_record_short',0)<before['currencies'].get('study_record_short',0),'Cultivation consumes an earned study record')
        check(after['progression']['characters']!=before['progression']['characters'],'Cultivation progress persists to disk')
        shot('cultivation_saved');click(185,718);time.sleep(.6)
        click(1565,250,(1672,941));time.sleep(.7);click(415,853);time.sleep(.8);shot('claimed_equipment')
        instances=data()['inventory']['equipmentInstances'];check(bool(instances),'Earned equipment rewards can be claimed')
        click(1010,617);time.sleep(.6);click(1000,813);time.sleep(.7);shot('equipped_and_enhanced')
        check(any(i.get('boundCharacterId') and i.get('enhanceLevel',0)==1 for i in data()['inventory']['equipmentInstances']),'Equipment binding and enhancement persist')
        click(1635,1015);time.sleep(.6);key(27);time.sleep(.4)
        for _ in range(3):key(9)
        key(13);time.sleep(.4);shot('keyboard_closed_campus_menu')
        check(re.findall(r'场景切换 -> (res://[^\r\n]+)',(out/'game.log').read_text(encoding='utf8'))[-1].endswith('home.tscn'),'Campus dialog keyboard traversal stays within its buttons')
        key(27);time.sleep(.4);click(836,517,(1672,941));time.sleep(.6)
        key(40);key(13);time.sleep(.5);click(800,490)
        for k in [56,56,56]:key(k)
        click(1115,780);time.sleep(.3);click(1115,780);time.sleep(.7);read_story()
        check(not data()['stages'] and not data()['currencies'],'Fresh campaign has no inherited clears or currencies')
        click(1610,1005);time.sleep(.8)
        check(probe() and probe()['stage']=='1-1','Fresh campaign launches first battle')
        # Pause, retry and defeat without deployment, with no accelerated clock.
        key(32);time.sleep(.4);t=probe()['time'];time.sleep(1.5)
        check(abs(probe()['time']-t)<.05,'Pause freezes combat clock')
        shot('paused')
        for _ in range(4):key(9)
        key(13);time.sleep(.6)
        check(probe()['time']>t+.3,'Pause dialog keyboard loop returns to resume')
        key(32);time.sleep(.3);click(960,578);time.sleep(.8)
        check(probe()['time']<2,'Pause retry resets combat clock')
        fresh=data();lost=wait_battle();check(lost['outcome']=='失败','No-deployment battle genuinely loses')
        time.sleep(1);shot('defeat');time.sleep(3)
        check(data()['currencies']==fresh['currencies'] and data()['stages']==fresh['stages'],'Defeat grants no rewards or clears')
        check(not data()['flow_state'].get('pending_story_after'),'First defeat cannot schedule after-story')
        click(1096,905);time.sleep(.7);shot('campus_after_defeat')
        click(1565,310,(1672,941));time.sleep(.7);shot('records_after_defeat');key(27);time.sleep(.6)
        check(not data()['stages'],'Defeat return and records visit preserve locked progression')
        click(1545,435,(1672,941));time.sleep(.6);click(1610,1005);time.sleep(.7)
        won=wait_battle(True);check(won['outcome']=='胜利','Normal deployment and skills win first battle')
        time.sleep(3.3);shot('victory');paid=data();time.sleep(4);shot('victory_waiting')
        check(data()['currencies']==paid['currencies'] and data()['stages']==paid['stages'],'Waiting on settlement does not repeat rewards')
        pending=paid['flow_state'].get('pending_story_after');check(bool(pending),'First victory schedules required after-story')
        click(824,905);time.sleep(.7)
        check(data()['currencies']==paid['currencies'],'Victory retry does not grant extra rewards')
        lost=wait_battle();check(lost['outcome']=='失败','Retry can genuinely lose after a settled victory')
        time.sleep(1);shot('defeat_after_victory');click(1096,905);time.sleep(.7)
        check(data()['flow_state'].get('pending_story_after')==pending,'Losing a replay preserves the previously earned unread after-story')
        shot('campus_pending_story');quit_from_campus()
        # A new owned process must resume the same disk progress and story.
        proc=subprocess.Popen([str(a.exe),'--resolution','1280x720','--position','30,30'],env=dict(os.environ,APPDATA=str(out/'appdata')),stdout=log,stderr=subprocess.STDOUT)
        hwnd=None
        for _ in range(100):
            hwnd=win.find_window({proc.pid})
            if hwnd:break
            time.sleep(.1)
        check(hwnd is not None,'Restarted owned Retail window available');time.sleep(1);key(13);time.sleep(.7);shot('restart_campus')
        check(data()['currencies']==paid['currencies'] and data()['stages']==paid['stages'],'Exit and restart preserve settled rewards exactly once')
        check(data()['flow_state'].get('pending_story_after')==pending,'Restart preserves required story')
        click(1545,435,(1672,941));time.sleep(.7)
        check(data()['flow_state'].get('current_story_id')==pending,'Continue investigation opens the preserved required story')
        shot('recovered_after_story')
        for _ in range(100):
            if not data()['flow_state'].get('pending_story_after'):break
            click(1655,960)
        time.sleep(.7)
        check(data()['story']['flags'].get('done:'+pending,False),'Preserved story can be completed normally after restart')
        check(data()['currencies']==paid['currencies'] and data()['stages']==paid['stages'],'Completing recovered story grants no duplicate battle rewards')
        quit_from_campus()
    except Exception as exc:
        error=str(exc);print('FAILED:',error,flush=True)
    finally:
        if proc and proc.poll() is None:proc.terminate();proc.wait(timeout=10)
report=dict(ok=error is None,error=error,type='Final Retail EXE; actual Windows input; normal clock; earned old-save copy then new campaign',checks=checks,samples=samples,exeSha256=sha(a.exe),pckSha256=sha(a.exe.with_suffix('.pck')),sourceSaveSha256=sha(a.seed_save))
(out/'journey_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
raise SystemExit(0 if error is None else 1)
