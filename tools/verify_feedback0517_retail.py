"""Actual Windows acceptance of the approved campus Hub, using an earned save copy."""
from pathlib import Path
import argparse,ctypes,hashlib,json,os,shutil,subprocess,time
import windows_art_capture as win
from PIL import ImageGrab
import numpy as np

p=argparse.ArgumentParser()
p.add_argument('--output',type=Path,required=True)
p.add_argument('--seed-save',type=Path,required=True)
p.add_argument('--exe',type=Path,required=True)
p.add_argument('--verbose',action='store_true')
p.add_argument('--locale',choices=['zh','en'],default='zh')
p.add_argument('--scenario',choices=['feedback','insufficient'],required=True)
a=p.parse_args()
out=a.output.resolve()
assert '_testenv' in out.parts
save_dir=out/'appdata/HoshigaokaEchoes/save'
save_dir.mkdir(parents=True,exist_ok=True)
save_path=save_dir/'savegame.json'
shutil.copy2(a.seed_save,save_path)
settings_dir=out/'appdata/HoshigaokaEchoes/settings'
settings_dir.mkdir(parents=True,exist_ok=True)
(settings_dir/'settings.cfg').write_text('[language]\nlocale="'+a.locale+'"\n',encoding='utf8')
checks=[]
def check(ok,name):
    checks.append({'ok':bool(ok),'name':name})
    assert ok,name
def read_save():return json.loads(save_path.read_text(encoding='utf-8-sig'))
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
win.U.SetThreadDpiAwarenessContext.argtypes=[ctypes.c_void_p]
win.U.SetThreadDpiAwarenessContext(ctypes.c_void_p(-4))
with (out/'game.log').open('w',encoding='utf8') as log:
    proc=subprocess.Popen([str(a.exe)]+(['--verbose'] if a.verbose else [])+['--resolution','1280x720','--position','30,30'],env=dict(os.environ,APPDATA=str(out/'appdata')),stdout=log,stderr=subprocess.STDOUT)
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
        def hover(x,y,ref=(1672,941)):
            foreground();ox,oy,w,h=win.client(hwnd)
            win.U.SetCursorPos(ox+round(x*w/ref[0]),oy+round(y*h/ref[1]));time.sleep(.7)
        def shot(name):
            for attempt in range(3):
                foreground()
                try:
                    if win.capture_forced(hwnd,out,name,{'input':'Actual Windows input','binary':str(a.exe)},seconds=8):break
                except RuntimeError:
                    if attempt==2:raise
            check((out/(name+'.png')).exists(),'capture '+name)
        def logs():return (out/'game.log').read_text(encoding='utf8',errors='replace')
        def route_frames(name):
            means=[]
            for frame in range(24):
                foreground();ox,oy,w,h=win.client(hwnd)
                capture=ImageGrab.grab(bbox=(ox,oy,ox+w,oy+h),all_screens=True)
                assert win.U.GetForegroundWindow()==hwnd,'Capture refused outside owned game'
                capture.save(out/f'{name}_frame_{frame:02d}.png')
                means.append(float(np.asarray(capture).mean()))
                time.sleep(.025)
            check(min(means)>20,name+' actual Windows frames contain no black frame')
            (out/(name+'_metrics.json')).write_text(json.dumps(dict(means=means,minimum=min(means))),encoding='utf8')

        def region():
            foreground();ox,oy,w,h=win.client(hwnd)
            im=ImageGrab.grab(bbox=(ox,oy,ox+w,oy+h),all_screens=True)
            assert win.U.GetForegroundWindow()==hwnd,'Capture refused outside owned game'
            arr=np.asarray(im)
            return arr[round(h*928/1080):round(h*968/1080),round(w*100/1920):round(w*1800/1920),:].copy()
        def enhance():
            click(1000,812,(1920,1080));time.sleep(.15)
            click(1370,830,(1920,1080));time.sleep(.12)
            return time.monotonic()
        def finish():
            click(1635,1007,(1920,1080));time.sleep(.8)
            key(27);time.sleep(.3)
            click(836,617);time.sleep(.3)
            click(991,562);proc.wait(timeout=10)
            check(proc.returncode==0,'normal in-game exit')
        time.sleep(1.8)
        click(300,500,(1920,1080));time.sleep(1.0)
        click(1565,250);time.sleep(.9)
        if a.scenario=='insufficient':
            before=read_save()
            click(1000,812,(1920,1080));time.sleep(.4)
            shot('insufficient_preview')
            click(1370,830,(1920,1080));time.sleep(.2)
            check(read_save()==before,'disabled confirmation cannot spend resources or enhance')
            click(530,830,(1920,1080));time.sleep(.2)
            check(read_save()==before,'cancelled insufficient preview leaves save unchanged')
        else:
            if read_save().get('entitlements',{}).get('pending',[]):
                click(415,852,(1920,1080));time.sleep(.7)
            click(1010,617,(1920,1080));time.sleep(.2)
            click(1370,830,(1920,1080));time.sleep(.7)
            first=enhance()
            shot('feedback_first')
            second=enhance()
            second_pixels=region()
            shot('feedback_second')
            # Same-page category refresh must not restart this deadline.
            click(420,365,(1920,1080));time.sleep(.12)
            time.sleep(max(0,first+3.1-time.monotonic()))
            check(np.array_equal(second_pixels,region()),'old timeout cannot erase the newer enhancement message')
            time.sleep(max(0,second+3.3-time.monotonic()))
            clear=region()
            check(np.count_nonzero(second_pixels!=clear)>50,'enhancement message disappears after its deadline')
            shot('feedback_expired')
            time.sleep(.3)
            check(np.array_equal(clear,region()),'expired feedback stays absent')
            enhance()
            click(1635,1007,(1920,1080));time.sleep(.6)
            click(1565,250);time.sleep(.85)
            check(np.array_equal(clear,region()),'leaving and returning clears the previous message')
            shot('feedback_returned')
            bow=next(i for i in read_save()['inventory']['equipmentInstances'] if i['equipmentId']=='equip_ch1_1_2_fine_weapon')
            check(bow['enhanceLevel']==3,'three real enhancements completed exactly once each')
        finish()
    finally:
        if proc.poll() is None:proc.terminate();proc.wait(timeout=10)
text=logs()
check('SCRIPT ERROR' not in text and 'Parse Error' not in text,'no script or parse errors')
errors=[line for line in text.splitlines() if line.startswith('ERROR:')]
check(all('resources still in use at exit' in line for line in errors),'only separately recorded historical shutdown resource warning')
report={'ok':True,'type':'Final Retail EXE with actual Windows input and isolated earned save copy','checks':checks,'shutdownWarnings':errors,'exeSha256':sha(a.exe),'pckSha256':sha(a.exe.with_suffix('.pck')),'sourceSaveSha256':sha(a.seed_save)}
(out/'retail_hub_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'ok':True,'checks':len(checks),'screenshots':len(list(out.glob('*.png')))},ensure_ascii=False))
