"""Normal-clock final-stage replay through actual Windows input in the Retail binary.
Reads the presentation probe only. Never injects game code or edits earned save state.
"""
from pathlib import Path
import argparse,ctypes,hashlib,json,os,shutil,subprocess,time
import windows_art_capture as win
win.U.SetThreadDpiAwarenessContext.argtypes=[ctypes.c_void_p]
win.U.SetThreadDpiAwarenessContext(ctypes.c_void_p(-4))
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--seed-save',type=Path,required=True);p.add_argument('--exe',type=Path,default=ROOT/'dist/chapter_one_0.5.0_20261011/HoshigaokaEchoes.exe');a=p.parse_args()
out=a.output.resolve();assert '_testenv' in out.parts
save=out/'appdata/HoshigaokaEchoes/save';save.mkdir(parents=True,exist_ok=True)
shutil.copy2(a.seed_save,save/'savegame.json')
exe=a.exe.resolve()
probe_path=save.parent/'art_probe/latest.json'
actions=[];captured=set();boss_frames=0;last_boss_sample=0
with (out/'game.log').open('w',encoding='utf8') as log:
    proc=subprocess.Popen([str(exe),'--resolution','1280x720','--position','30,30'],env=dict(os.environ,APPDATA=str(out/'appdata')),stdout=log,stderr=subprocess.STDOUT)
    try:
        hwnd=None
        for _ in range(100):
            hwnd=win.find_window({proc.pid})
            if hwnd:break
            time.sleep(.1)
        assert hwnd,'Retail window missing'
        def shot(name):
            if name in captured:return
            assert win.capture_forced(hwnd,out,name,{'binary':str(exe),'input':'Actual Windows mouse/keyboard; normal domain clock'},seconds=8)
            captured.add(name)
        def click(x,y,canvas=(1920,1080)):
            assert win.U.GetForegroundWindow()==hwnd,'Refuse input outside owned foreground game'
            ox,oy,w,h=win.client(hwnd);win.U.SetCursorPos(ox+round(x*w/canvas[0]),oy+round(y*h/canvas[1]))
            time.sleep(.04)
            assert win.U.GetForegroundWindow()==hwnd
            win.U.mouse_event(2,0,0,0,None);time.sleep(.035);win.U.mouse_event(4,0,0,0,None);time.sleep(.06)
        def key(code):
            assert win.U.GetForegroundWindow()==hwnd
            win.U.keybd_event(code,0,0,0);time.sleep(.035);win.U.keybd_event(code,0,2,0);time.sleep(.06)
        def probe():
            try:return json.loads(probe_path.read_text(encoding='utf8'))
            except (OSError,ValueError):return None
        def click_rect(rect,state):click(rect[0]+rect[2]/2,rect[1]+rect[3]/2,state['canvas'])
        def cell(column,lane,state):
            entry=next(c for c in state['layout']['cells'] if c['column']==column and c['lane']==lane)
            pts=entry['polygon'];click(sum(v[0] for v in pts)/4,sum(v[1] for v in pts)/4,state['canvas'])
        time.sleep(2);shot('title');key(13);time.sleep(1.2);shot('campus')
        click(1545,590);time.sleep(1);shot('ten_stages');click(740,805);time.sleep(1);shot('briefing');click(1600,1005)
        for _ in range(80):
            if probe():break
            time.sleep(.1)
        state=probe();assert state and state['stage']=='1-10'
        shot('battle_initial')
        # Retry is exercised before the normal run, without granting any resources.
        click(1815,55);time.sleep(.4);shot('pause_retry');click(960,578);time.sleep(.7)
        assert '重试本次调查：1-10' in (out/'game.log').read_text(encoding='utf8',errors='replace')
        shot('retry_initial')
        roster=['amamiya_mio','kamiya_yuma','ogawa_yui','fujiwara_rin','minase_sara']
        slots=[(3,1),(1,1),(2,0),(0,0),(2,1)]
        deadline=time.monotonic()+540;last_action=0
        while time.monotonic()<deadline:
            state=probe()
            if not state:time.sleep(.1);continue
            assert state['stage']=='1-10'
            if state['outcome']!='进行中':break
            if any(c.get('hpRatio',1)<.85 for c in state['characters']):shot('health_depleted')
            if state['upgradeOffer']['active']:
                shot('upgrade_'+str(len(state['gainedUpgrades'])))
                click_rect(state['upgradeOffer']['cardRects'][0],state);time.sleep(.3);continue
            for enemy in state['enemies']:
                if enemy['code']=='boss_model_student':
                    phase=3 if enemy['hp']<2400 else (2 if enemy['hp']<4800 else 1)
                    shot('boss_phase_'+str(phase))
                    if time.monotonic()-last_boss_sample>1 and boss_frames<80:
                        shot('boss_continuous_%03d'%boss_frames);boss_frames+=1;last_boss_sample=time.monotonic()
            if time.monotonic()-last_action<.5:time.sleep(.1);continue
            last_action=time.monotonic()
            present={c['code'] for c in state['characters']}
            for i,cid in enumerate(roster):
                click_rect(state['cardRects'][i],state)
                if cid not in present:
                    cell(*slots[i],state)
                    break
                actor=next(c for c in state['characters'] if c['code']==cid)
                if not actor.get('skillReady',False):continue
                targets=[e for e in state['enemies'] if e['hp']>0 and 0<=e['x']-actor['column']<=3 and abs(e['lane']-actor['lane'])<=1]
                if cid=='kamiya_yuma' and not (len(targets)>=2 or any(e['lane']!=actor['lane'] for e in targets)):continue
                if cid=='amamiya_mio' and not any(e['lane']==actor['lane'] for e in targets):continue
                if cid=='ogawa_yui' and not any(c['hpRatio']<.7 for c in state['characters']):continue
                if cid=='minase_sara' and not any(e['lane']!=1 and e['x']<5 for e in state['enemies']):continue
                key(0x51)
                if cid=='minase_sara':
                    side=[e for e in state['enemies'] if e['lane']!=1 and e['hp']>0]
                    if side:
                        e=min(side,key=lambda e:e['x']);cell(max(0,min(3,int(e['x']))),e['lane'],state)
                    else:key(0x1B)
            actions.append({'clock':state['time'],'characters':sorted(present),'healthRatios':{c['code']:c.get('hpRatio',1) for c in state['characters']},'audio':state['audio']})
            time.sleep(.15)
        state=probe();assert state and state['outcome']=='胜利','Retail final stage did not clear: '+str(state and state['outcome'])
        time.sleep(3.2);shot('victory')
        final=state
        # Return to the campus through the real result button, then quit normally.
        click(1096,905);time.sleep(1.2)
        key(27);time.sleep(.8);key(27);time.sleep(.5);shot('exit_confirmation');click(1125,629)
        proc.wait(timeout=8);assert proc.returncode==0
    finally:
        if proc.poll() is None:proc.terminate();proc.wait(timeout=10)
text=(out/'game.log').read_text(encoding='utf8',errors='replace')
assert 'SCRIPT ERROR' not in text and 'Parse Error' not in text
report=dict(type='Actual Windows Retail binary; automated OS input; normal AP, stats and domain clock; not human play',ok=True,sourceSaveSha256=hashlib.sha256(a.seed_save.read_bytes()).hexdigest(),exeSha256=hashlib.sha256(exe.read_bytes()).hexdigest(),pckSha256=hashlib.sha256(exe.with_suffix('.pck').read_bytes()).hexdigest(),retry=True,normalExit=True,finalProbe=final,actions=actions)
(out/'retail_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'ok':True,'elapsed':final['time'],'screenshots':len(captured)},ensure_ascii=False))
