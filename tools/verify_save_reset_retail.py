"""Verify old-save -> confirmed new game in the exported EXE via Windows input.
Uses only an isolated copy of the previously earned campaign save.
"""
from pathlib import Path
import argparse, ctypes, hashlib, json, os, re, shutil, subprocess, time
import windows_art_capture as win

p = argparse.ArgumentParser()
p.add_argument('--output', type=Path, required=True)
p.add_argument('--seed-save', type=Path, required=True)
p.add_argument('--exe', type=Path, required=True)
p.add_argument('--pack', type=Path)
a = p.parse_args()
out = a.output.resolve()
assert '_testenv' in out.parts
save_dir = out/'appdata/HoshigaokaEchoes/save'
save_dir.mkdir(parents=True, exist_ok=True)
save_path = save_dir/'savegame.json'
shutil.copy2(a.seed_save, save_path)
checks = []
def check(ok, name):
    checks.append(dict(ok=bool(ok), name=name))
    assert ok, name
def read_save(): return json.loads(save_path.read_text(encoding='utf-8-sig'))
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
win.U.SetThreadDpiAwarenessContext.argtypes = [ctypes.c_void_p]
win.U.SetThreadDpiAwarenessContext(ctypes.c_void_p(-4))
with (out/'game.log').open('w', encoding='utf8') as log:
    command = [str(a.exe), '--resolution', '1280x720', '--position', '30,30']
    if a.pack: command += ['--verbose']
    if a.pack: command += ['--main-pack', str(a.pack)]
    proc = subprocess.Popen(command, env=dict(os.environ, APPDATA=str(out/'appdata')), stdout=log, stderr=subprocess.STDOUT)
    try:
        hwnd = None
        owned = {proc.pid}
        for _ in range(100):
            owned = win.descendants(proc.pid, owned)
            hwnd = win.find_window(owned)
            if hwnd: break
            time.sleep(.1)
        check(hwnd is not None, 'owned Retail window available')
        def foreground():
            deadline = time.monotonic()+8
            while win.U.GetForegroundWindow()!=hwnd and time.monotonic()<deadline:
                win._force_foreground(hwnd); time.sleep(.1)
            check(win.U.GetForegroundWindow()==hwnd, 'input confined to owned foreground window')
        def click(x, y):
            foreground()
            ox,oy,w,h = win.client(hwnd)
            win.U.SetCursorPos(ox+round(x*w/1920),oy+round(y*h/1080))
            win.U.mouse_event(2,0,0,0,None); time.sleep(.04); win.U.mouse_event(4,0,0,0,None)
            time.sleep(.12)
        def key(code):
            foreground(); win.U.keybd_event(code,0,0,0); time.sleep(.04); win.U.keybd_event(code,0,2,0); time.sleep(.12)
        def shot(name):
            check(win.capture_forced(hwnd,out,name,{'input':'Actual Windows mouse and keyboard', 'binary':str(a.exe)},seconds=8), 'capture '+name)
        time.sleep(2)
        key(13); time.sleep(1)
        click(1545,475); time.sleep(1); shot('old_save_growth')
        check(max(c['level'] for c in read_save()['progression']['characters'].values())>1, 'old earned growth remains intact on continue')
        click(185,718); time.sleep(.8); key(27); time.sleep(.5)
        click(960,572); time.sleep(.8)
        key(40); key(13); time.sleep(.8)
        click(800,490)
        for code in (53,53,53): key(code)
        old_hash = sha(save_path)
        click(1115,780); time.sleep(.6); shot('overwrite_confirmation')
        check(sha(save_path)==old_hash, 'first confirmation does not overwrite save')
        click(1115,780); time.sleep(.8); shot('new_prologue')
        data = read_save()
        check(data['profile']['playerName']=='555', 'new name persisted')
        check(not data['progression'].get('characters', {}), 'new save clears old growth')
        check(not data['currencies'] and not data['stages'], 'new save clears resources and stage clears')
        check(not data['inventory'].get('equipmentInstances',[]) and not data['entitlements']['pending'], 'new save clears equipment and pending rewards')
        # Read the prologue through its normal next-line button; no save edits.
        for _ in range(100):
            if read_save()['flow_state'].get('mode')=='pre_battle': break
            click(1655,960)
        check(read_save()['flow_state'].get('mode')=='pre_battle', 'prologue reaches first briefing normally')
        time.sleep(.8); click(280,1007); time.sleep(.8)
        click(1545,475); time.sleep(.8); shot('new_save_growth')
        click(470,718); time.sleep(.8); shot('empty_backpack')
        click(400,500); time.sleep(.5); click(400,630); time.sleep(.5); shot('empty_categories')
        key(27); time.sleep(.6); shot('growth_after_backpack_return')
        click(185,718); time.sleep(.8); key(27); time.sleep(.4)
        click(960,672); time.sleep(.4); click(1125,629)
        proc.wait(timeout=10)
        check(proc.returncode==0, 'normal exit')
    finally:
        if proc.poll() is None: proc.terminate(); proc.wait(timeout=10)
text = (out/'game.log').read_text(encoding='utf8')
growth = re.findall(r'成长系统就绪：6 名角色（([^\r\n]+)）', text)
check(bool(growth) and re.findall(r'Lv\.(\d+)', growth[-1])==['1']*6, 'six displayed growth levels rebuilt from the new save')
check('SCRIPT ERROR' not in text and 'Parse Error' not in text, 'no script or parse errors in final binary')
errors = [line for line in text.splitlines() if line.startswith('ERROR:')]
known_exit = ('RID allocations', 'Texture with GL ID', 'resources still in use at exit')
check(all(any(kind in line for kind in known_exit) for line in errors), 'no errors beyond recorded shutdown resource warnings')
check('Retail' in text, 'Retail build mode')
report = dict(ok=True, type='Exported EXE with actual Windows input, isolated earned save copy; shutdown warnings recorded separately', checks=checks, shutdownWarnings=errors, exeSha256=sha(a.exe), pckSha256=sha(a.pack or a.exe.with_suffix('.pck')), sourceSaveSha256=sha(a.seed_save), finalSave=read_save())
(out/'retail_reset_report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
print(json.dumps(dict(ok=True, checks=len(checks)), ensure_ascii=False))
