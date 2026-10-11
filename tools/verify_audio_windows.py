"""Bounded Windows speaker loopback evidence; never opens the physical microphone.
Needs SoundCard/numpy in D:/星丘基础/python-libs. Writes only under _testenv.
"""
from pathlib import Path
import argparse, json, os, subprocess, time, wave
import numpy as np
import soundcard as sc

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--exe',type=Path)
parser.add_argument('--start-delay',type=int,default=0,choices=range(91),help='Discard normal-clock startup audio before measuring, e.g. 44 seconds for elite arrival')
args=parser.parse_args(); out=args.output.resolve()
if '_testenv' not in out.parts: raise SystemExit('Refuse non-isolated output')
out.mkdir(parents=True,exist_ok=True)
speaker=sc.default_speaker()
loop=sc.get_microphone(id=speaker.id,include_loopback=True)
assert loop.isloopback, 'Refuse physical microphone recording'
sr=48000
with loop.recorder(samplerate=sr,channels=2) as rec:
    silence=rec.record(numframes=sr*2)
    env=dict(os.environ,APPDATA=str(out/'appdata'))
    command=([str(args.exe)] if args.exe else [r'D:\星丘基础\godot\Godot_v4.7.2-stable_win64_console.exe','--path',str(ROOT)])
    command+=['--resolution','1280x720']
    if not args.exe:command+=['--','--scene=battle','--stage=1-5','--autoplay']
    with (out/'game.log').open('w',encoding='utf-8') as log:
        proc=subprocess.Popen(command,env=env,stdout=log,stderr=subprocess.STDOUT)
        try:
            for _ in range(args.start_delay): rec.record(numframes=sr)
            chunks=[]
            for i in range(16): chunks.append(rec.record(numframes=sr))
            data=np.concatenate(chunks)
        finally:
            proc.terminate()
            try: proc.wait(timeout=5)
            except subprocess.TimeoutExpired: proc.kill();proc.wait()
pcm=(np.clip(data,-1,1)*32767).astype('<i2')
with wave.open(str(out/'windows_loopback.wav'),'wb') as wav:
    wav.setnchannels(2);wav.setsampwidth(2);wav.setframerate(sr);wav.writeframes(pcm.tobytes())
rms=lambda a:float(np.sqrt(np.mean(a.astype(float)**2)))
report={'evidenceType':'Windows WASAPI default speaker loopback; automated, not human listening',
        'requestedScene':'Retail title (no developer scene entry)' if args.exe else 'Development fifth-stage battle',
        'normalClockDelaySeconds':args.start_delay,
        'speaker':speaker.name,'physicalMicrophoneUsed':False,'sampleRate':sr,
        'baselineRms':rms(silence),'gameRms':rms(data),'peak':float(np.max(np.abs(data))),
        'clippedSamples':int(np.sum(np.abs(data)>=.999)),
        'nonSilent':rms(data)>.0001,'sourceAttributionLimit':'System mix may contain other applications'}
(out/'audio_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
if not report['nonSilent']: raise SystemExit('No audible signal captured')
