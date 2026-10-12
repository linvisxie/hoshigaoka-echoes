"""Record bounded Windows speaker loopback when the owned Retail Boss is audible."""
from pathlib import Path
import argparse,json,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--base',type=Path,default=ROOT.parent/'_testenv/glass-combat-revision');a=p.parse_args()
BASE=a.base.resolve()
assert '_testenv' in BASE.parts
probe=BASE/'retail_final/appdata/HoshigaokaEchoes/art_probe/latest.json'
deadline=time.monotonic()+720
while time.monotonic()<deadline:
    try:
        state=json.loads(probe.read_text(encoding='utf8'))
        if time.time()-probe.stat().st_mtime<3 and state.get('outcome')=='进行中' and state['audio'].get('track','').startswith('boss_exam_') and state['audio'].get('musicPlaying'):
            out=BASE/'audio';out.mkdir(exist_ok=True)
            (out/'source_probe.json').write_text(json.dumps(state,ensure_ascii=False,indent=2),encoding='utf8')
            subprocess.run([sys.executable,str(ROOT/'tools/record_chapter_audio.py'),'--output',str(out),'--seconds','20'],check=True)
            break
    except (OSError,ValueError,KeyError):pass
    time.sleep(1)
else:raise RuntimeError('Owned Retail Boss music did not start within bounded wait')
