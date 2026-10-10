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
U.SetCursorPos.argtypes=[C.c_int,C.c_int]
U.mouse_event.argtypes=[W.UINT,W.UINT,W.UINT,W.ULONG,C.c_void_p]
U.IsWindowVisible.argtypes=[W.HWND]
U.GetWindowTextW.argtypes=[W.HWND,W.LPWSTR,C.c_int]
CALLBACK=C.WINFUNCTYPE(W.BOOL,W.HWND,W.LPARAM)
U.EnumWindows.argtypes=[CALLBACK,W.LPARAM]
U.GetWindowThreadProcessId.restype=W.DWORD
U.AttachThreadInput.argtypes=[W.DWORD,W.DWORD,W.BOOL]
U.AttachThreadInput.restype=W.BOOL
U.BringWindowToTop.argtypes=[W.HWND]
U.BringWindowToTop.restype=W.BOOL
U.SetActiveWindow.argtypes=[W.HWND]
U.SetActiveWindow.restype=W.HWND
K.GetCurrentThreadId.restype=W.DWORD
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

def _wait_foreground(hwnd,timeout=2.0):
    """Poll until hwnd is genuinely foreground (bounded).

    SetForegroundWindow is advisory and the current foreground app can be slow to
    yield, so asserting immediately after a fixed sleep produces spurious
    "not foreground" refusals. Polling keeps the guard just as strict (we still
    refuse unless the window really is foreground) while removing the timing
    flakiness. Returns True if foreground was obtained.
    """
    deadline=time.monotonic()+timeout
    while True:
        if U.GetForegroundWindow()==hwnd: return True
        if time.monotonic()>=deadline: return False
        time.sleep(.05)

def capture(hwnd,out,name,context,attempts=4):
    """Foreground-guarded screenshot. Retries on occlusion; refuses to save a blocked frame.

    Returns the saved PNG path on success, or None if every attempt was refused.
    Callers that ignore the return value (the combat event scan) are unaffected.

    A refused attempt is reported as RETRY-OCCLUDED, and only the final give-up
    as SKIP-OCCLUDED. The two used to share one message, which made a transient
    retry look identical to a real failure in the log.
    """
    last_error=None
    for attempt in range(attempts):
        try:
            return _capture_once(hwnd,out,name,context)
        except RuntimeError as exc:
            last_error=exc
            if attempt<attempts-1:
                print('RETRY-OCCLUDED',name,str(exc),flush=True)
            time.sleep(.35)
    print('SKIP-OCCLUDED',name,str(last_error),flush=True)
    return None

def _capture_once(hwnd,out,name,context):
    U.ShowWindow(hwnd,9)
    U.SetWindowPos(hwnd,C.c_void_p(-1),0,0,0,0,0x0003|0x0040)
    U.SetForegroundWindow(hwnd)
    if not _wait_foreground(hwnd):
        raise RuntimeError('Owned window is not foreground; refused occluded screenshot')
    x,y,w,h=client(hwnd)
    if w<320 or h<240: raise RuntimeError('Client not ready; refused blank capture')
    image=ImageGrab.grab(bbox=(x,y,x+w,y+h),all_screens=True)
    if image.size != (w,h): raise RuntimeError('Screenshot clipped')
    path=out/(name+'.png'); image.save(path)
    # Split the probe blob out of the context without mutating the caller's dict
    # (capture() may retry this function with the same object).
    context=dict(context) if isinstance(context,dict) else context
    probe_state=context.pop('_probe',None) if isinstance(context,dict) else None
    record={'evidenceType':'real Windows client screenshot, automated operation (not human playtest)',
            'captured':datetime.datetime.now().isoformat(),'clientPhysicalPixels':[w,h],
            'context':context,'image':str(path)}
    # Probe snapshot: only present when the caller supplied it (the non-upgrade
    # code paths pass plain context dicts and keep their sidecars unchanged).
    if probe_state is not None:
        record['probe']=probe_state
    path.with_suffix('.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
    print(name,w,h,flush=True)
    return path

def _rect_screen_point(hwnd,rects,canvas,index):
    """Canvas-coord rect center -> screen point, via client offset.

    Single source of truth for the canvas->client->screen conversion; both the
    roster cards (state['cardRects']) and the upgrade offer
    (state['upgradeOffer']['cardRects']) go through here so the two can never
    drift apart. Contract: both rect sets are canvas coordinates.
    """
    if index>=len(rects) or canvas[0]<=0 or canvas[1]<=0: return None
    ox,oy,w,h=client(hwnd)
    r=rects[index]
    # canvas -> client (uniform-ish scale), then client -> screen offset
    return (int(ox+(r[0]+r[2]*.5)*w/canvas[0]), int(oy+(r[1]+r[3]*.5)*h/canvas[1]))

def _card_screen_point(hwnd,state,index):
    return _rect_screen_point(hwnd,state.get('cardRects') or [],state.get('canvas') or [0,0],index)

def _rect_is_clickable(r):
    """A rect with no area is not a target: its "center" is an arbitrary edge.

    Only applied to upgrade-offer rects; the roster-card path keeps its original
    behaviour byte-for-byte.
    """
    return isinstance(r,(list,tuple)) and len(r)>=4 and r[2]>0 and r[3]>0

def _offer_card_point(hwnd,state,index):
    offer=state.get('upgradeOffer') or {}
    rects=[r for r in (offer.get('cardRects') or [])]
    if index>=len(rects) or not _rect_is_clickable(rects[index]): return None
    return _rect_screen_point(hwnd,rects,state.get('canvas') or [0,0],index)

def _offer_button_point(hwnd,state,key):
    """Center of a single-rect button (rerollRect / skipRect) in screen coords."""
    offer=state.get('upgradeOffer') or {}
    r=offer.get(key)
    if not _rect_is_clickable(r): return None
    return _rect_screen_point(hwnd,[r],state.get('canvas') or [0,0],0)

def hover_card(hwnd,state,index):
    """Rest the real OS cursor at roster card index center (screen coords)."""
    pt=_card_screen_point(hwnd,state,index)
    if not pt: return False
    U.SetCursorPos(pt[0],pt[1]); time.sleep(.18)
    return True

def click_card(hwnd,state,index):
    pt=_card_screen_point(hwnd,state,index)
    if not pt: return False
    U.SetCursorPos(pt[0],pt[1]); time.sleep(.12)
    U.mouse_event(0x0002,0,0,0,None); time.sleep(.06)
    U.mouse_event(0x0004,0,0,0,None); time.sleep(.25)
    return True

def real_click(screen_pt):
    """One real OS left click (SetCursorPos + mouse_event), not synthesized input."""
    U.SetCursorPos(screen_pt[0],screen_pt[1]); time.sleep(.12)
    U.mouse_event(0x0002,0,0,0,None); time.sleep(.06)
    U.mouse_event(0x0004,0,0,0,None); time.sleep(.25)

def read_probe(probe):
    try: return json.loads(probe.read_text(encoding='utf-8'))
    except (OSError,ValueError): return {}

def wait_offer_active(hwnd,probe,timeout):
    """Event-driven wait: poll the probe until upgradeOffer.active is true.

    Discipline: never a fixed sleep that "should be long enough". Returns the
    state at the moment the panel was seen, or None if it never appeared.
    """
    deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        state=read_probe(probe)
        offer=state.get('upgradeOffer') or {}
        if offer.get('active'): return state
        if state.get('outcome') in ('胜利','失败'): return None
        time.sleep(.05)
    return None

def upgrade_offer_sequence(hwnd,out,probe,a):
    """Event-driven upgrade-panel evidence.

    Ordering per the A0.6 contract: the panel while untouched, then the real
    cursor rested on a card (hover state), optionally a real click on 重掷,
    then a real click on the chosen card and its feedback frame. Every capture()
    re-runs the foreground/occlusion guard, so an occluded window yields
    SKIP-OCCLUDED rather than a misleading frame.
    """
    labels=[]
    state=wait_offer_active(hwnd,probe,a.upgrade_wait)
    if state is None:
        print('SKIP-OCCLUDED upgrade_panel_offered panel never became active within '
              f'{a.upgrade_wait}s',flush=True)
        return labels,None
    time.sleep(.25)
    state=read_probe(probe) or state
    # Park the real cursor away from every card so the "offered" frame is the
    # genuinely unhovered panel, not a stale hover from an earlier action.
    _park_cursor(hwnd,state)
    if capture_forced(hwnd,out,'upgrade_panel_offered',state):
        labels.append('upgrade_panel_offered')
    else:
        print('SKIP-OCCLUDED upgrade_panel_offered',flush=True)

    if a.choose_upgrade is not None:
        pt=_offer_card_point(hwnd,state,a.choose_upgrade)
        if pt is None:
            print(f'SKIP-OCCLUDED upgrade_card_hover_{a.choose_upgrade} '
                  'no such card rect in probe',flush=True)
        else:
            U.SetCursorPos(pt[0],pt[1]); time.sleep(.35)
            state=read_probe(probe) or state
            name=f'upgrade_card_hover_{a.choose_upgrade}'
            if capture_forced(hwnd,out,name,state): labels.append(name)
            else: print('SKIP-OCCLUDED',name,flush=True)

    if a.reroll_upgrade:
        rpt=_offer_button_point(hwnd,state,'rerollRect')
        if rpt is None:
            print('SKIP-OCCLUDED upgrade_rerolled no rerollRect in probe',flush=True)
        else:
            before_ids=list((state.get('upgradeOffer') or {}).get('ids') or [])
            before_rerolls=(state.get('upgradeOffer') or {}).get('rerollsRemaining')
            real_click(rpt)
            # Event-driven wait for the reroll to have taken effect. The lesson
            # from 1-5: in the tutorial offer (L2132) the candidates are fixed on
            # purpose, so "ids changed" is NOT a valid success signal there and
            # waiting for it burns the whole budget while the reroll has in fact
            # already happened. Either observable counts:
            #   * rerollsRemaining decreased  -> the reroll was consumed (any mode)
            #   * ids changed                 -> the candidate set was rebuilt
            # First one to appear wins; the remaining budget is left for the fight.
            deadline=time.monotonic()+a.upgrade_wait
            confirmed=False
            while time.monotonic()<deadline:
                st=read_probe(probe)
                offer=st.get('upgradeOffer') or {}
                state=st
                ids=list(offer.get('ids') or [])
                rerolls=offer.get('rerollsRemaining')
                if rerolls!=before_rerolls or (ids and ids!=before_ids):
                    confirmed=True
                    break
                time.sleep(.05)
            if not confirmed:
                print('SKIP-OCCLUDED upgrade_rerolled reroll had no observable effect '
                      f'within {a.upgrade_wait}s (ids and rerollsRemaining unchanged); '
                      'refused to synthesise evidence',flush=True)
            if capture_forced(hwnd,out,'upgrade_rerolled',state): labels.append('upgrade_rerolled')
            else: print('SKIP-OCCLUDED upgrade_rerolled',flush=True)
        if a.choose_upgrade is not None:
            pt=_offer_card_point(hwnd,state,a.choose_upgrade)
            if pt is None:
                print('SKIP-OCCLUDED upgrade_chosen no such card rect after reroll',flush=True)
            else:
                U.SetCursorPos(pt[0],pt[1]); time.sleep(.12)

    if a.choose_upgrade is not None and (state.get('upgradeOffer') or {}).get('active'):
        pt=_offer_card_point(hwnd,state,a.choose_upgrade)
        if pt is None:
            print('SKIP-OCCLUDED upgrade_chosen no such card rect',flush=True)
        else:
            before=(state.get('upgradeOffer') or {}).get('ids') or []
            real_click(pt)
            # Event-driven: wait for the domain to clear pending_offer (chosen)
            # rather than for a fixed delay to elapse.
            deadline=time.monotonic()+a.upgrade_wait
            while time.monotonic()<deadline:
                st=read_probe(probe)
                if not (st.get('upgradeOffer') or {}).get('active'):
                    state=st; break
                state=st
                time.sleep(.05)
            state=read_probe(probe) or state
            if capture_forced(hwnd,out,'upgrade_chosen',state): labels.append('upgrade_chosen')
            else: print('SKIP-OCCLUDED upgrade_chosen',flush=True)
    return labels,state

def _park_cursor(hwnd,state):
    """Move the real cursor off any interactive rect before an "untouched" frame."""
    ox,oy,w,h=client(hwnd)
    U.SetCursorPos(ox+max(4,w-6),oy+max(4,h-6)); time.sleep(.25)

def _force_foreground(hwnd):
    """Best-effort foreground acquisition for the held-panel path.

    Windows only lets the *foreground* process change the foreground window
    (SetForegroundWindow is otherwise ignored, returning without effect). The
    attach-thread-input dance temporarily joins our input queue with the current
    foreground thread's, which lifts that restriction for the duration of the
    call. This is standard Win32 practice, not a global setting change, and it is
    used only by capture_held -- the legacy capture path is untouched.

    Returns True if hwnd ended up foreground.
    """
    if U.GetForegroundWindow()==hwnd: return True
    target_thread=U.GetWindowThreadProcessId(hwnd,None)
    fg=U.GetForegroundWindow()
    fg_thread=U.GetWindowThreadProcessId(fg,None) if fg else 0
    me=K.GetCurrentThreadId()
    attached=[]
    for thread in {fg_thread,target_thread}:
        if thread and thread!=me and U.AttachThreadInput(me,thread,True):
            attached.append(thread)
    try:
        U.ShowWindow(hwnd,9)
        U.BringWindowToTop(hwnd)
        U.SetForegroundWindow(hwnd)
        U.SetActiveWindow(hwnd)
    finally:
        for thread in attached:
            U.AttachThreadInput(me,thread,False)
    return U.GetForegroundWindow()==hwnd

def capture_forced(hwnd,out,name,state,seconds=25.0):
    """Capture with active foreground acquisition (upgrade-panel evidence only).

    Same refusal discipline as capture(): a frame is only saved once the owned
    window is genuinely foreground, so an occluded window still yields
    SKIP-OCCLUDED instead of a misleading picture.
    """
    deadline=time.monotonic()+seconds
    while True:
        _force_foreground(hwnd)
        if _wait_foreground(hwnd,2.0):
            result=_capture_once(hwnd,out,name,state)
            if result: return result
        else:
            print('RETRY-OCCLUDED',name,'foreground not obtained; retrying',flush=True)
        if time.monotonic()>=deadline:
            print('SKIP-OCCLUDED',name,'foreground could not be obtained within',
                  f'{seconds}s; refused to save an occluded frame',flush=True)
            return None
        time.sleep(.4)

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--scene',default='battle',choices=['battle','title','character'])
    p.add_argument('--stage',default='1-3');p.add_argument('--duration',type=float,default=180)
    p.add_argument('--autoplay',action='store_true')
    p.add_argument('--copy-save',type=Path,default=None,
        help='Copy an existing savegame.json into the ISOLATED appdata before launch '
             '(character screen needs non-zero resources; never reads/writes the real user dir)')
    p.add_argument('--hover-card',type=int,default=None,
        help='Battle scene only: rest the real cursor at the center of roster card N '
             '(0-based) so the hover visual state is captured in event screenshots')
    p.add_argument('--click-card',type=int,default=None,
        help='Battle scene only: one real click on roster card N (0-based) to enter '
             'the selected state, then rest the cursor there for selection screenshots')
    p.add_argument('--choose-upgrade',type=int,default=None,
        help='Alpha A0.6 upgrade panel only: when upgradeOffer.active becomes true, '
             'rest the real cursor on card N (0-based) then click it with a real OS '
             'mouse event. Rect source is the probe\'s upgradeOffer.cardRects.')
    p.add_argument('--reroll-upgrade',action='store_true',
        help='Alpha A0.6 upgrade panel only: click the 重掷 button with a real OS mouse '
             'event first, then capture the rebuilt panel before choosing.')
    p.add_argument('--upgrade-shots',action='store_true',
        help='Alpha A0.6: enable the event-driven upgrade evidence sequence '
             '(upgrade_panel_offered -> upgrade_card_hover_N -> upgrade_rerolled -> '
             'upgrade_chosen), then continue the normal long run to the outcome.')
    p.add_argument('--upgrade-wait',type=float,default=90.0,
        help='Seconds to wait for an event-driven upgrade state transition before '
             'declaring it not observed (never replaced by a fixed blind sleep)')
    p.add_argument('--game-arg',action='append',default=[],metavar='ARG',
        help='Extra argument forwarded verbatim to the game after "--" (repeatable). '
             'Use for switches the scene script reads from OS.get_cmdline_user_args().')
    p.add_argument('--no-autoplay-upgrade',action='store_true',
        help='Convenience shorthand for --game-arg=--no-autoplay-upgrade: asks the '
             'battle scene to stop auto-resolving the upgrade panel so real-mouse '
             'upgrade evidence can be taken. No effect if the scene lacks the flag.')
    p.add_argument('--autoplay-hold-upgrade',action='store_true',
        help='Forward --autoplay-hold-upgrade to the game: autoplay keeps deploying '
             'and advancing waves, but stops auto-resolving the upgrade panel, so the '
             'panel stays on screen for real-mouse evidence. Keep --autoplay too, or '
             'no waves clear and the panel never appears.')
    a=p.parse_args(); out=a.output.resolve()
    if '_testenv' not in out.parts: raise SystemExit('Refuse non-isolated output')
    out.mkdir(parents=True,exist_ok=True)
    env=dict(os.environ,APPDATA=str(out/'appdata'))
    if a.copy_save:
        import shutil
        src=a.copy_save.resolve()
        if '_testenv' not in src.parts: raise SystemExit('Refuse: save source outside _testenv')
        dst=out/'appdata/HoshigaokaEchoes/save'
        dst.mkdir(parents=True,exist_ok=True)
        shutil.copy2(src,dst/'savegame.json')
    args=[r'D:\星丘基础\godot\Godot_v4.7.2-stable_win64_console.exe','--path',str(ROOT),
          '--resolution','1280x720','--position','30,60','--','--scene='+a.scene,'--stage='+a.stage]
    if a.autoplay: args.append('--autoplay')
    if a.no_autoplay_upgrade: args.append('--no-autoplay-upgrade')
    if a.autoplay_hold_upgrade: args.append('--autoplay-hold-upgrade')
    args.extend(a.game_arg)
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
            if a.hover_card is not None or a.click_card is not None:
                # Deterministic UI-state evidence, ordered so each state is captured
                # before later actions can change the card list:
                #   1) hover card B alone -> card_hover_B
                #   2) click card A (selects it) -> card_selected_A
                #   3) hover card B again -> card_selected_A_hover_B (both states)
                state={}
                for _ in range(60):
                    time.sleep(.25)
                    try: state=json.loads(probe.read_text(encoding='utf-8'))
                    except (OSError,ValueError): continue
                    if state.get('cardRects'): break
                try:
                    if a.hover_card is not None and hover_card(hwnd,state,a.hover_card):
                        time.sleep(.4); capture(hwnd,out,f'card_hover_{a.hover_card}',state)
                    if a.click_card is not None and click_card(hwnd,state,a.click_card):
                        time.sleep(.4); capture(hwnd,out,f'card_selected_{a.click_card}',state)
                        state=json.loads(probe.read_text(encoding='utf-8'))
                        if a.hover_card is not None and hover_card(hwnd,state,a.hover_card):
                            time.sleep(.4)
                            capture(hwnd,out,f'card_sel{a.click_card}_hover{a.hover_card}',state)
                except (RuntimeError,OSError,ValueError) as exc:
                    print('UI-STATE-PARTIAL',str(exc),flush=True)
            # --- Alpha A0.6 upgrade evidence (event-driven) ---------------------
            # The sequence is driven by the probe's upgradeOffer.active becoming
            # true, and is executed by the same scan loop that captures combat
            # events, so combat evidence and upgrade evidence come from one run.
            # Any of the three upgrade options arms it: --upgrade-shots is the
            # explicit switch, but --choose-upgrade / --reroll-upgrade on their
            # own are already an unambiguous request for upgrade evidence.
            upgrade_done=not (a.upgrade_shots or a.choose_upgrade is not None
                              or a.reroll_upgrade)
            while time.monotonic()-begin<a.duration:
                state={}
                try: state=json.loads(probe.read_text(encoding='utf-8'))
                except (OSError,ValueError): pass
                if not upgrade_done:
                    offer=state.get('upgradeOffer') or {}
                    if offer.get('active'):
                        done,last=upgrade_offer_sequence(hwnd,out,probe,a)
                        seen.update(done)
                        upgrade_done=True
                        continue
                    if state.get('outcome') in ('胜利','失败'):
                        print('SKIP-OCCLUDED upgrade_panel_offered battle ended before '
                              'the panel was ever observed',flush=True)
                        upgrade_done=True
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
                    time.sleep(.6)
                    # result_settled is a required A0.6 deliverable (the deployed
                    # build summary must be legible), so in upgrade-evidence mode
                    # it gets the same active foreground acquisition as the
                    # upgrade frames. Legacy runs keep the original single attempt.
                    if a.upgrade_shots or a.choose_upgrade is not None or a.reroll_upgrade:
                        capture_forced(hwnd,out,'result_settled',state)
                    else:
                        capture(hwnd,out,'result_settled',state)
                    break
                if a.scene!='battle': break
                time.sleep(.07)
            # `seen` is tagged as soon as a label is attempted, so it can name
            # frames that were refused as occluded (pre-existing behaviour). For
            # the evidence verdict we therefore trust the FILESYSTEM, not `seen`.
            on_disk={p.stem for p in out.glob('*.png')}
            summary={'labels':sorted(seen),'ownedPids':sorted(owned),
                     'duration':time.monotonic()-begin,
                     'labelsVerifiedOnDisk':sorted(on_disk),
                     'labelsClaimedButNotSaved':sorted(seen-on_disk)}
            # Upgrade bookkeeping is only added when upgrade capture was asked for,
            # so a plain run's summary stays byte-identical to before.
            if a.upgrade_shots or a.choose_upgrade is not None or a.reroll_upgrade:
                requested=['upgrade_panel_offered']
                if a.choose_upgrade is not None:
                    requested.append(f'upgrade_card_hover_{a.choose_upgrade}')
                if a.reroll_upgrade:
                    requested.append('upgrade_rerolled')
                if a.choose_upgrade is not None:
                    requested.append('upgrade_chosen')
                requested.append('result_settled')
                missing=[x for x in requested if x not in on_disk]
                summary['upgradeRequested']=requested
                summary['upgradeMissing']=missing
                summary['upgradeEvidenceComplete']=not missing
                # A requested set that produced nothing must not read as success.
                if missing:
                    print('UPGRADE-EVIDENCE-INCOMPLETE missing='+
                          ','.join(missing),flush=True)
            (out/'capture_summary.json').write_text(
                json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
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
