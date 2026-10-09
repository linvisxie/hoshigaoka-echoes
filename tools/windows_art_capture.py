"""Owned-process Windows screenshots. No global DPI changes or process-name kills.
Each PNG includes a sidecar with scene state and measured physical client size.
"""
from pathlib import Path
import argparse, ctypes as C, ctypes.wintypes as W, datetime, json, os, subprocess, time
from PIL import ImageGrab
ROOT=Path(__file__).resolve().parents[1]
U=C.WinDLL('user32', use_last_error=True)
K=C.WinDLL('kernel32', use_last_error=True)
class PROCESSENTRY32(C.Structure):
    _fields_=[('dwSize',W.DWORD),('cntUsage',W.DWORD),('th32ProcessID',W.DWORD),
              ('th32DefaultHeapID',C.c_size_t),('th32ModuleID',W.DWORD),('cntThreads',W.DWORD),
              ('th32ParentProcessID',W.DWORD),('pcPriClassBase',W.LONG),('dwFlags',W.DWORD),('szExeFile',W.WCHAR*260)]
K.CreateToolhelp32Snapshot.argtypes=[W.DWORD,W.DWORD]; K.CreateToolhelp32Snapshot.restype=W.HANDLE
K.Process32FirstW.argtypes=[W.HANDLE,C.POINTER(PROCESSENTRY32)]
K.Process32NextW.argtypes=[W.HANDLE,C.POINTER(PROCESSENTRY32)]
K.CloseHandle.argtypes=[W.HANDLE]
U.GetWindowThreadProcessId.argtypes=[W.HWND,C.POINTER(W.DWORD)]
U.GetClientRect.argtypes=[W.HWND,C.POINTER(W.RECT)]
U.GetWindowRect.argtypes=[W.HWND,C.POINTER(W.RECT)]
U.ClientToScreen.argtypes=[W.HWND,C.POINTER(W.POINT)]
U.SetWindowPos.argtypes=[W.HWND,W.HWND,C.c_int,C.c_int,C.c_int,C.c_int,W.UINT]
U.SetForegroundWindow.argtypes=[W.HWND]
U.GetForegroundWindow.restype=W.HWND
U.ShowWindow.argtypes=[W.HWND,C.c_int]
U.IsWindowVisible.argtypes=[W.HWND]
U.GetWindowTextW.argtypes=[W.HWND,W.LPWSTR,C.c_int]
CALLBACK=C.WINFUNCTYPE(W.BOOL,W.HWND,W.LPARAM)
U.EnumWindows.argtypes=[CALLBACK,W.LPARAM]
try:
    U.SetProcessDpiAwarenessContext.argtypes=[W.HANDLE]
    U.SetProcessDpiAwarenessContext(C.c_void_p(-4))  # only this capture process
except AttributeError:
    pass

def descendants(root, known):
    snap=K.CreateToolhelp32Snapshot(2,0)
    entry=PROCESSENTRY32(); entry.dwSize=C.sizeof(entry)
    rows=[]
    try:
        okay=K.Process32FirstW(snap,C.byref(entry))
        while okay:
            rows.append((int(entry.th32ProcessID),int(entry.th32ParentProcessID),entry.szExeFile))
            okay=K.Process32NextW(snap,C.byref(entry))
    finally:
        K.CloseHandle(snap)
    owned=set(known)|{root}
    for _ in range(4):
        for pid,parent,name in rows:
            if parent in owned and ('godot' in name.lower() or 'hoshigaoka' in name.lower()): owned.add(pid)
    return owned

def find_window(owned):
    hits=[]
    @CALLBACK
    def cb(hwnd, _):
        pid=W.DWORD(); U.GetWindowThreadProcessId(hwnd,C.byref(pid))
        if pid.value in owned and U.IsWindowVisible(hwnd):
            rect=W.RECT(); U.GetClientRect(hwnd,C.byref(rect))
            if rect.right>=320 and rect.bottom>=240: hits.append(hwnd)
        return True
    U.EnumWindows(cb,0)
    return hits[0] if hits else None

def client(hwnd):
    rect=W.RECT(); U.GetClientRect(hwnd,C.byref(rect))
    origin=W.POINT(0,0); U.ClientToScreen(hwnd,C.byref(origin))
    return origin.x,origin.y,rect.right,rect.bottom

def capture(hwnd,out,name,context):
    U.ShowWindow(hwnd,9)
    U.SetWindowPos(hwnd,C.c_void_p(-1),0,0,0,0,0x0003|0x0040)
    U.SetForegroundWindow(hwnd)
    time.sleep(.08)
    if U.GetForegroundWindow()!=hwnd:
        raise RuntimeError('Owned window is not foreground; refused occluded screenshot')
    x,y,w,h=client(hwnd)
    if w<320 or h<240: raise RuntimeError('Client not ready; refused blank capture')
    image=ImageGrab.grab(bbox=(x,y,x+w,y+h),all_screens=True)
    if image.size != (w,h): raise RuntimeError('Screenshot clipped')
    path=out/(name+'.png'); image.save(path)
    record={'evidenceType':'real Windows client screenshot, automated operation (not human playtest)',
            'captured':datetime.datetime.now().isoformat(),'clientPhysicalPixels':[w,h],
            'context':context,'image':str(path)}
    path.with_suffix('.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
    print(name,w,h,flush=True)

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--scene',default='battle',choices=['battle','title','character'])
    p.add_argument('--stage',default='1-3');p.add_argument('--duration',type=float,default=180)
    p.add_argument('--autoplay',action='store_true')
    a=p.parse_args(); out=a.output.resolve()
    if '_testenv' not in out.parts: raise SystemExit('Refuse non-isolated output')
    out.mkdir(parents=True,exist_ok=True)
    env=dict(os.environ,APPDATA=str(out/'appdata'))
    args=[r'D:\星丘基础\godot\Godot_v4.7.2-stable_win64_console.exe','--path',str(ROOT),
          '--resolution','1280x720','--position','30,60','--','--scene='+a.scene,'--stage='+a.stage]
    if a.autoplay: args.append('--autoplay')
    owned=set(); seen=set(); begin=time.monotonic()
    with (out/'stdout.log').open('w',encoding='utf-8') as so, (out/'stderr.log').open('w',encoding='utf-8') as se:
        proc=subprocess.Popen(args,env=env,stdout=so,stderr=se)
        try:
            hwnd=None
            while time.monotonic()-begin<30:
                owned=descendants(proc.pid,owned); hwnd=find_window(owned)
                if hwnd: break
                time.sleep(.2)
            if not hwnd: raise RuntimeError('No window in owned process tree')
            wr=W.RECT();U.GetWindowRect(hwnd,C.byref(wr))
            _,_,w,h=client(hwnd)
            U.SetWindowPos(hwnd,0,30,60,1280+(wr.right-wr.left-w),720+(wr.bottom-wr.top-h),0x0040)
            time.sleep(1)
            capture(hwnd,out,'initial',{'scene':a.scene,'stage':a.stage})
            probe=out/'appdata/HoshigaokaEchoes/art_probe/latest.json'
            while time.monotonic()-begin<a.duration:
                state={}
                try: state=json.loads(probe.read_text(encoding='utf-8'))
                except (OSError,ValueError): pass
                labels=[]
                for unit in state.get('characters',[]): labels.append('deployed_'+unit['code'])
                for enemy in state.get('enemies',[]): labels.append('enemy_present_'+enemy['code'])
                for effect in state.get('activeVfx',[]): labels.append('active_'+effect)
                outcome=state.get('outcome','')
                if outcome in ('胜利', '失败'): labels.append('outcome_'+outcome)
                for label in labels:
                    if label not in seen:
                        seen.add(label); capture(hwnd,out,label,state)
                if any(x.startswith('outcome_') for x in seen):
                    time.sleep(.6);capture(hwnd,out,'result_settled',state);break
                if a.scene!='battle': break
                time.sleep(.07)
            (out/'capture_summary.json').write_text(json.dumps({'labels':sorted(seen),
                'ownedPids':sorted(owned),'duration':time.monotonic()-begin},ensure_ascii=False,indent=2),encoding='utf-8')
        finally:
            # Only PIDs proved to belong to this launched process tree are touched.
            owned=descendants(proc.pid,owned)
            for pid in sorted(owned,reverse=True):
                try: os.kill(pid,15)
                except (OSError,ProcessLookupError): pass
            try: proc.wait(timeout=5)
            except subprocess.TimeoutExpired: proc.kill();proc.wait()
    text=(out/'stderr.log').read_text(encoding='utf-8',errors='replace')
    if 'SCRIPT ERROR' in text or 'Parse Error' in text: raise SystemExit('Scene runtime failed; inspect stderr.log')
if __name__=='__main__': main()
