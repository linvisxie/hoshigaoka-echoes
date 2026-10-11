"""Original soft paper/echo cast and phase cues; no external audio or samples."""
import json
from render_resonance_sfx import render, ROOT

files=[render('boss_cast',.9,[57,64,76],.035,.035,1500,-8),
       render('boss_phase',1.45,[45,57,69,76],.06,.09,1700,-12)]
(ROOT/'docs/boss_polish_audio.json').write_text(json.dumps({
    'origin':'Original deterministic synthesis; no external samples',
    'generator':'tools/render_boss_cues.py',
    'design':'Rounded low resonance and soft paper-like air; distinct from wave notification',
    'files':files,'userListeningAcceptance':False},ensure_ascii=False,indent=2),encoding='utf8')
