"""Record bounded Windows speaker loopback when the owned Retail Boss is audible."""
from pathlib import Path
import json,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'_testenv/interaction-revision'
probe=BASE/'retail_final/appdata/HoshigaokaEchoes/art_probe/latest.json'
deadline=time.monotonic()+360
while time.monotonic()<deadline:
    try:
        state=json.loads(probe.read_text(encoding='utf8'))
        if state['audio'].get('track','').startswith('boss_exam_') and state['audio'].get('musicPlaying'):
            out=BASE/'audio';out.mkdir(exist_ok=True)
            (out/'source_probe.json').write_text(json.dumps(state,ensure_ascii=False,indent=2),encoding='utf8')
            subprocess.run([sys.executable,str(ROOT/'tools/record_chapter_audio.py'),'--output',str(out),'--seconds','20'],check=True)
            break
    except (OSError,ValueError,KeyError):pass
    time.sleep(1)
else:raise RuntimeError('Owned Retail Boss music did not start within bounded wait')
