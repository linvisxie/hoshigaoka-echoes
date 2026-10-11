"""Render our existing original themes with licensed VSCO 2 CE upright piano.

Source samples stay in D:/星丘基础. Only rendered music and license notices ship.
No external melodies. Requires numpy; see build_audio.py.
"""
from pathlib import Path
import hashlib, json, shutil, wave
import numpy as np
import build_audio as base
import build_ch1_audio as chapter

SAMPLES = Path('D:/星丘基础/downloads/ui-polish/VSCO2')
SR = base.SR
synth = base.tone
bank, cache = {}, {}

def read_sample(path):
    with wave.open(str(path), 'rb') as wav:
        channels, width, rate = wav.getnchannels(), wav.getsampwidth(), wav.getframerate()
        assert width == 3 and channels == 2 and rate == 44100
        raw = np.frombuffer(wav.readframes(wav.getnframes()), dtype=np.uint8).reshape(-1, 3)
    pcm = raw[:,0].astype(np.int32) | (raw[:,1].astype(np.int32)<<8) | (raw[:,2].astype(np.int32)<<16)
    pcm = ((pcm ^ 0x800000) - 0x800000).reshape(-1,channels).mean(axis=1) / 8388608
    # FFT resampling removes above-Nyquist content before reducing sample rate.
    size = round(len(pcm)*SR/rate)
    spectrum = np.fft.rfft(pcm)
    return np.fft.irfft(spectrum[:size//2+1], n=size) * size/len(pcm)

for path in sorted(SAMPLES.glob('Player_dyn2_rr1_*.wav')):
    key = 21 + int(path.stem.rsplit('_',1)[1])*2  # official piano.sfz pitch_keycenter
    bank[key] = read_sample(path)
assert len(bank) == 13

def piano(midi, length, kind='piano'):
    if kind != 'piano':
        return synth(midi, length, kind)
    if midi not in cache:
        root = min(bank, key=lambda note:abs(note-midi))
        ratio = 2**((midi-root)/12)
        source = bank[root]
        positions = np.arange(0, len(source)-1, ratio)
        note = np.interp(positions, np.arange(len(source)), source)
        # Source includes a long quiet lead-in. Preserve transient, remove only silence.
        audible = np.flatnonzero(np.abs(note)>.0004)
        if len(audible): note = note[max(0,int(audible[0]) - int(.002*SR)):]
        peak = max(float(np.max(np.abs(note))), .001)
        cache[midi] = note * min(3.2, .32/peak)
    count = int(SR*length)
    result = np.zeros(count)
    source = cache[midi]
    used = min(count,len(source)); result[:used] = source[:used]
    fade = min(int(.07*SR),count)
    result[-fade:] *= np.linspace(1,0,fade)
    return result

def main():
    base.tone = chapter.tone = piano

    for name,bpm,battle in [('after_school',86,False),('echo_frontline',116,True)]:
        base.score(name,bpm,battle)
        print('Rendered',name,flush=True)
    for name,bpm,dark in [('unheard_memory',72,True),('observation_club',94,False),('corridor_pressure',132,True)]:
        chapter.cue(name,bpm,dark)
        print('Rendered',name,flush=True)

    def resolution(name, notes):
        out = np.zeros((SR*8,2))
        for i,chord in enumerate(notes):
            start=int((.12+i*.85)*SR)
            for n in chord:
                a=piano(n,4.5)*.48
                stop=min(start+len(a),len(out))
                out[start:stop,0]+=a[:stop-start]*.68
                out[start:stop,1]+=a[:stop-start]*.72
        dry=out.copy()
        for delay,gain in [(.14,.19),(.31,.11),(.53,.06)]:
            shift=int(delay*SR);out[shift:]+=dry[:-shift,::-1]*gain
        out[-SR:]*=np.linspace(1,0,SR)[:,None]
        base.save('bgm/'+name,np.tanh(out*2.7)*.8)

    resolution('battle_victory',[(60,64,67),(62,65,69),(64,67,72),(60,67,76)])
    resolution('battle_defeat',[(57,60,64),(55,59,62),(52,55,59)])
    licenses=base.ROOT/'assets/licenses';licenses.mkdir(exist_ok=True)
    shutil.copy2(SAMPLES/'LICENSE',licenses/'VSCO2-CE-CC0.txt')
    shutil.copy2(SAMPLES/'Readme.txt',licenses/'VSCO2-CE-Readme.txt')
    record=base.ROOT/'assets/audio/source_record.json'
    data=json.loads(record.read_text(encoding='utf8'))
    data.update({'renderSource':'tools/render_sampled_score.py',
     'externalSamples':[{'library':'VSCO 2 Community Edition Upright Piano',
     'authors':'Versilian Studios / Sam Gossner; Ivy Audio / Simon Dalzell',
     'url':'https://github.com/sgossner/VSCO-2-CE','license':'CC0-1.0',
     'rawSamplesDistributed':False,
     'samples':[{'name':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(SAMPLES.glob('*.wav'))]}],
     'commercialUse':'Original melodies rendered with CC0-1.0 piano samples; project synthesized accompaniment/SFX; Kenney CC0 UI and combat cues separately recorded',
     'status':'Sampled piano mix; Windows runtime and loopback checked separately; user listening approval pending'})
    data['files']=[p.relative_to(base.ROOT).as_posix() for p in sorted((base.ROOT/'assets/audio').rglob('*.wav'))]
    record.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf8')

if __name__ == '__main__': main()
