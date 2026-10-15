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

        def settings_text():
            return (out/'appdata/HoshigaokaEchoes/settings/settings.cfg').read_text(encoding='utf8')
        def captured():
            foreground();ox,oy,w,h=win.client(hwnd)
            result=ImageGrab.grab(bbox=(ox,oy,ox+w,oy+h),all_screens=True)
            assert win.U.GetForegroundWindow()==hwnd,'Capture refused outside owned game'
            return np.asarray(result).copy()
        time.sleep(2)
        click(300,500,(1920,1080));route_frames('title_continue');time.sleep(.8)
        hover(1350,451);shot('campus_location_status')
        click(1622,47);time.sleep(.8);shot('settings_added_rows')
        click(1080,727,(1920,1080))
        click(1015,837,(1920,1080));time.sleep(.4)
        check('motion_level=0' in settings_text(),'motion off saved through real input')
        check('auto_delay=4.0' in settings_text() or 'auto_delay=4' in settings_text(),'automatic reading delay saved through real input')
        click(1415,1007,(1920,1080));time.sleep(1.2);hover(800,700)
        first=captured();time.sleep(.4);second=captured()
        diff=np.abs(first.astype(float)-second.astype(float))
        check(float(diff.max())==0,'motion-off campus stays pixel-identical across real frames')
        shot('campus_motion_off')
        click(1622,47);time.sleep(.8)
        click(1015,837,(1920,1080));time.sleep(.4)
        check('motion_level=1' in settings_text(),'gentle motion saved through real input')
        shot('settings_gentle_motion')
        click(1015,837,(1920,1080));time.sleep(.4)
        check('motion_level=2' in settings_text(),'standard motion saved through real input')
        click(1415,1007,(1920,1080));time.sleep(.9)
        click(1565,250);route_frames('equipment');time.sleep(.7)
        if read_save().get('entitlements',{}).get('pending',[]):
            click(415,852,(1920,1080));time.sleep(.8)
        items=read_save()['inventory']['equipmentInstances']
        bow=next(item for item in items if item['equipmentId']=='equip_ch1_1_2_fine_weapon')
        iid=bow['instanceId']
        check(not bow.get('boundCharacterId'),'normal earned bow starts unequipped')
        before=read_save()
        click(1010,617,(1920,1080));time.sleep(.5);shot('equipment_swap_preview')
        check(read_save()==before,'opening swap preview does not save or equip')
        click(530,830,(1920,1080));time.sleep(.3)
        check(read_save()==before,'cancelling swap leaves save unchanged')
        click(1010,617,(1920,1080));time.sleep(.4)
        click(1370,830,(1920,1080));time.sleep(.8)
        check(read_save()['characters']['kamiya_yuma']['equipment']['WEAPON']==iid,'confirm equips actual earned bow')
        before=read_save()
        click(1000,812,(1920,1080));time.sleep(.4);shot('equipment_enhance_preview')
        check(read_save()==before,'opening enhancement preview consumes nothing')
        click(1370,830,(1920,1080));time.sleep(.8)
        after=read_save()
        enhanced=next(item for item in after['inventory']['equipmentInstances'] if item['instanceId']==iid)
        check(enhanced['enhanceLevel']==bow['enhanceLevel']+1,'confirm enhances exactly once')
        check(after['currencies']['school_coin']<before['currencies']['school_coin'] and after['currencies']['equipment_part']==before['currencies']['equipment_part']-1,'confirmed enhancement consumes its actual resources')
        before=read_save()
        click(1290,812,(1920,1080));time.sleep(.4);shot('equipment_unequip_preview')
        check(read_save()==before,'opening unequip preview leaves binding unchanged')
        click(530,830,(1920,1080));time.sleep(.4)
        click(1635,1007,(1920,1080));time.sleep(.8)
        click(1565,370);time.sleep(.8);shot('archive_original')
        click(300,250,(1920,1080));time.sleep(.8);shot('story_original_controls')
        check('scenes/story/story.tscn' in logs(),'original archive replays story')
        click(1655,960,(1920,1080));time.sleep(.2)
        click(325,1035,(1920,1080))
        before_page=captured()[670:697,1025:1225,:]
        time.sleep(1.6)
        early_page=captured()[670:697,1025:1225,:]
        check(np.array_equal(before_page,early_page),'auto reading does not advance before selected dwell')
        time.sleep(12.5)
        late_page=captured()[670:697,1025:1225,:]
        check(not np.array_equal(before_page,late_page),'auto reading eventually advances using real frame output')
        shot('story_auto_advanced')
        click(325,1035,(1920,1080))
        key(27);time.sleep(.4)
        click(960,547,(1920,1080));time.sleep(.8)
        click(300,800,(1920,1080));time.sleep(.4)
        click(1120,630,(1920,1080));proc.wait(timeout=10)
        check(proc.returncode==0,'normal in-game exit')
    finally:
        if proc.poll() is None:proc.terminate();proc.wait(timeout=10)
text=logs()
check('SCRIPT ERROR' not in text and 'Parse Error' not in text,'no script or parse errors')
errors=[line for line in text.splitlines() if line.startswith('ERROR:')]
check(all('resources still in use at exit' in line for line in errors),'only separately recorded historical shutdown resource warning')
report={'ok':True,'type':'Final Retail EXE with actual Windows input and isolated earned save copy','checks':checks,'shutdownWarnings':errors,'exeSha256':sha(a.exe),'pckSha256':sha(a.exe.with_suffix('.pck')),'sourceSaveSha256':sha(a.seed_save)}
(out/'retail_hub_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'ok':True,'checks':len(checks),'screenshots':len(list(out.glob('*.png')))},ensure_ascii=False))
