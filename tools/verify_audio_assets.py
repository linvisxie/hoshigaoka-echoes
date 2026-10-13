"""Read-only PCM integrity/headroom audit; does not claim subjective listening QA."""
from pathlib import Path
import argparse, hashlib, json, wave
import numpy as np

p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1];results=[]
tracks=['echo_frontline','corridor_pressure','infirmary_light','ranking_pressure','science_resonance',
        'archive_convergence','invigilator_exam','boss_exam_1','boss_exam_2','boss_exam_3']
for name in tracks:
    path=root/'assets/audio/bgm'/(name+'.wav')
    with wave.open(str(path),'rb') as f:
        assert f.getsampwidth()==2
        sr=f.getframerate();channels=f.getnchannels()
        audio=np.frombuffer(f.readframes(f.getnframes()),dtype='<i2').astype(np.float64)/32768
        audio=audio.reshape(-1,channels)
    peak=float(np.abs(audio).max());rms=float(np.sqrt(np.mean(audio*audio)))
    results.append(dict(track=name,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),seconds=len(audio)/sr,
        peak=peak,rms=rms,fullScaleSamples=int(np.count_nonzero(np.abs(audio)>=32767/32768)),
        loopBoundaryMaxStep=float(np.abs(audio[-1]-audio[0]).max())))
assert len(set(r['sha256'] for r in results))==len(results),'Unexpected identical music assets'
assert all(r['seconds']>20 and r['rms']>.005 and r['fullScaleSamples']==0 for r in results)
report=dict(ok=True,scope='PCM files only: distinct assets, duration, signal level, clipping and loop edge; not human listening or runtime mix',tracks=results)
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(report,ensure_ascii=False))
