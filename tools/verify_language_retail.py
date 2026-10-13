"""Final EXE language settings and restart, using only its owned Windows window."""
from pathlib import Path
import argparse,ctypes,hashlib,json,os,re,shutil,subprocess,time
import windows_art_capture as win

p=argparse.ArgumentParser()
p.add_argument('--exe',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
p.add_argument('--seed-save',type=Path,required=True)
a=p.parse_args();out=a.output.resolve();assert '_testenv' in out.parts
folder=out/'appdata/HoshigaokaEchoes';(folder/'save').mkdir(parents=True,exist_ok=True)
save=folder/'save/savegame.json';shutil.copy2(a.seed_save,save)
cfg=folder/'settings/settings.cfg';cfg.parent.mkdir(parents=True,exist_ok=True)
cfg.write_text('[language]\nlocale="zh"\n',encoding='utf8')
original=json.loads(save.read_text(encoding='utf-8-sig'))
checks=[];proc=None;error=None
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def check(ok,name):
    checks.append(dict(ok=bool(ok),name=name));print(name,bool(ok),flush=True);assert ok,name
win.U.SetThreadDpiAwarenessContext.argtypes=[ctypes.c_void_p]
win.U.SetThreadDpiAwarenessContext(ctypes.c_void_p(-4))
with (out/'game.log').open('w',encoding='utf8') as log:
    try:
        def start():
            global proc,hwnd
            previous=(out/'game.log').read_text(encoding='utf8',errors='replace').count('标题画面就绪')
            proc=subprocess.Popen([str(a.exe),'--resolution','1280x720','--position','30,30'],env=dict(os.environ,APPDATA=str(out/'appdata')),stdout=log,stderr=subprocess.STDOUT)
            hwnd=None;deadline=time.monotonic()+20
            while time.monotonic()<deadline:
                hwnd=win.find_window({proc.pid})
                if hwnd and (out/'game.log').read_text(encoding='utf8',errors='replace').count('标题画面就绪')>previous:break
                time.sleep(.1)
            check(bool(hwnd) and proc.poll() is None,'Owned EXE title ready')
            time.sleep(.4)
        def foreground():
            deadline=time.monotonic()+8
            while win.U.GetForegroundWindow()!=hwnd and time.monotonic()<deadline:
                win._force_foreground(hwnd);time.sleep(.1)
            assert win.U.GetForegroundWindow()==hwnd,'Input refused outside owned game'
        def click(x,y,ref=(1920,1080)):
            foreground();ox,oy,w,h=win.client(hwnd);win.U.SetCursorPos(ox+round(x*w/ref[0]),oy+round(y*h/ref[1]))
            win.U.mouse_event(2,0,0,0,None);time.sleep(.05);win.U.mouse_event(4,0,0,0,None);time.sleep(.7)
        def key(code):
            foreground();win.U.keybd_event(code,0,0,0);time.sleep(.05);win.U.keybd_event(code,0,2,0);time.sleep(.5)
        def shot(name):
            foreground();check(win.capture_forced(hwnd,out,name,{'binary':str(a.exe),'input':'Actual Windows input; isolated earned-save copy'},seconds=8),'Capture '+name)
        def quit_campus():
            key(27);click(836,617,(1672,941));click(991,562,(1672,941));proc.wait(timeout=10)
            check(proc.returncode==0,'Confirmed normal game exit')
        start();key(40);key(40);key(13);shot('settings_zh')
        click(1015,440);click(1015,842);shot('settings_en')
        saved=cfg.read_text(encoding='utf8');check('locale="en"' in saved,'UI switch persists English')
        bgm=re.search(r'BGM=([^\r\n]+)',saved);check(bgm and 40<float(bgm[1])<60,'Switch preserves changed music volume')
        click(1415,997);key(13);shot('campus_en')
        foreground();ox,oy,w,h=win.client(hwnd);win.U.SetCursorPos(ox+round(1060*w/1672),oy+round(438*h/941));time.sleep(1);shot('english_archery_tooltip')
        click(1565,190,(1672,941));shot('resource_bar_fits')
        click(185,718);quit_campus()
        start();key(40);key(40);key(13);shot('settings_en_after_restart')
        check('locale="en"' in cfg.read_text(encoding='utf8'),'English survives a new EXE process')
        click(1015,842);shot('settings_zh_restored')
        check('locale="zh"' in cfg.read_text(encoding='utf8'),'Can switch back to Chinese after restart')
        click(1415,997);key(13);shot('campus_zh_restored');quit_campus()
        current=json.loads(save.read_text(encoding='utf-8-sig'))
        for field in ('currencies','stages','inventory','progression','story'):
            check(current[field]==original[field],'Language-only operation preserves '+field)
    except Exception as exc:error=str(exc);print('FAILED',error,flush=True)
    finally:
        if proc and proc.poll() is None:proc.terminate();proc.wait(timeout=10)
report=dict(ok=error is None,error=error,checks=checks,type='Final Retail EXE; actual Windows input; settings and fresh-process persistence; isolated earned save',exeSha256=sha(a.exe),pckSha256=sha(a.exe.with_suffix('.pck')))
(out/'retail_language_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
raise SystemExit(0 if error is None else 1)
