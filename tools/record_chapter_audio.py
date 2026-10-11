"""Bounded speaker-only recording of an already running owned test game."""
from pathlib import Path
import argparse,json,wave
import soundcard as sc
import numpy as np
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--seconds',type=int,default=20);a=p.parse_args()
out=a.output.resolve()
assert '_testenv' in out.parts and 1<=a.seconds<=30
out.mkdir(parents=True,exist_ok=True)
speaker=sc.default_speaker();loop=sc.get_microphone(id=speaker.id,include_loopback=True)
assert loop.isloopback
with loop.recorder(samplerate=48000,channels=2) as rec:data=rec.record(numframes=48000*a.seconds)
with wave.open(str(out/'windows_loopback.wav'),'wb') as w:
    w.setnchannels(2);w.setsampwidth(2);w.setframerate(48000);w.writeframes((np.clip(data,-1,1)*32767).astype('<i2').tobytes())
report=dict(evidenceType='Actual Windows WASAPI speaker loopback from running campaign; not human listening',physicalMicrophoneUsed=False,speaker=speaker.name,seconds=a.seconds,rms=float(np.sqrt(np.mean(data**2))),peak=float(np.max(np.abs(data))),clippedSamples=int(np.sum(np.abs(data)>=.999)),sourceAttributionLimit='System mix may include other applications; correlate with campaign audio track evidence')
(out/'audio_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(report,ensure_ascii=False))
assert report['rms']>.0001
