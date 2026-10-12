"""Asset checks only; no claim about subjective musical quality or listening."""
from pathlib import Path
import argparse,hashlib,json,wave
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args()
assert '_testenv' in a.output.resolve().parts
manifest=json.loads((ROOT/'docs/scene_scores_054.json').read_text(encoding='utf8'))
checks=[]
for name,expected in manifest['preserved'].items():
    path=ROOT/'assets/audio/bgm'/f'{name}.wav'
    checks.append({'check':'preserved byte-for-byte '+name,'ok':hashlib.sha256(path.read_bytes()).hexdigest()==expected})
tracks=[]
for item in manifest['tracks']:
    path=ROOT/'assets/audio/bgm'/f"{item['track']}.wav"
    with wave.open(str(path),'rb') as w:
        channels=w.getnchannels();rate=w.getframerate();width=w.getsampwidth()
        samples=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').reshape(-1,channels)/32768
    info={'track':item['track'],'seconds':len(samples)/rate,'channels':channels,'rate':rate,
          'peak':float(np.abs(samples).max()),'rms':float(np.sqrt(np.mean(samples**2))),
          'clippedSamples':int((np.abs(samples)>=.999).sum()),
          'loopBoundaryJump':float(np.abs(samples[-1]-samples[0]).max()),
          'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    tracks.append(info)
    checks.append({'check':'stereo non-silent unclipped score '+item['track'],
                   'ok':channels==2 and width==2 and info['seconds']>=60 and info['peak']<.999 and info['rms']>.01})
checks.append({'check':'eight independent rendered files','ok':len({x['sha256'] for x in tracks})==8})
checks.append({'check':'independent musical motifs','ok':len({json.dumps(x['phrases']) for x in manifest['tracks']})==8})
result={'type':'Static PCM and score-structure checks; not human listening','ok':all(x['ok'] for x in checks),'checks':checks,'tracks':tracks}
a.output.parent.mkdir(parents=True,exist_ok=True)
a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'ok':result['ok'],'tracks':len(tracks),'checks':len(checks)}))
assert result['ok']
