"""Original score and sound design. No samples, external songs, or model API.
Run with numpy on PYTHONPATH (installed under D:/星丘基础/python-libs).
"""
from pathlib import Path
import json, wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SR = 32000
RNG = np.random.default_rng(20261010)

def save(name, samples):
    path = ROOT / 'assets/audio' / (name + '.wav')
    path.parent.mkdir(parents=True, exist_ok=True)
    peak = np.max(np.abs(samples))
    if peak > .86:
        samples *= .86 / peak
    pcm = (np.clip(samples, -1, 1) * 32767).astype('<i2')
    with wave.open(str(path), 'wb') as out:
        out.setnchannels(2 if samples.ndim == 2 else 1)
        out.setsampwidth(2); out.setframerate(SR); out.writeframes(pcm.tobytes())

def tone(midi, length, kind='piano'):
    t = np.arange(int(SR * length)) / SR
    hz = 440 * 2 ** ((midi - 69) / 12)
    if kind == 'pad':
        a = (np.sin(2*np.pi*hz*t) + .25*np.sin(2*np.pi*hz*2*t)
             + .18*np.sin(2*np.pi*hz*1.003*t))
        env = np.minimum(t/.3, 1)*np.minimum((length-t)/.45, 1)
        return a * env * .13
    if kind == 'bass':
        return (np.sin(2*np.pi*hz*t)+.22*np.sin(2*np.pi*hz*2*t))*np.minimum(t/.02,1)*np.exp(-t*3)*.20
    a = np.zeros_like(t)
    for n in range(1, 7):
        a += np.sin(2*np.pi*hz*n*(1+.00016*n*n)*t) * np.exp(-t*(1.8+n*.8)) / n**1.7
    return a*np.minimum(t/.006,1)*np.minimum((length-t)/.04,1)*.36

def score(name, bpm, battle):
    beat = 60/bpm; seconds = beat*4*32
    out = np.zeros((int(seconds*SR), 2), np.float64)
    def place(a, when, pan=0):
        start = int(when*SR); indices=(np.arange(len(a))+start)%len(out)
        out[indices,0] += a*np.sqrt((1-pan)/2)
        out[indices,1] += a*np.sqrt((1+pan)/2)
    # A minor, F major, C major, G major; original melodic phrases.
    chords = [(45,57,60,64), (41,53,57,60), (48,55,60,64), (43,55,59,62)]
    motifs = [[76,74,72,71,69,72,76,79], [77,76,72,69,72,76,74,72],
              [76,79,81,79,76,74,72,76], [74,71,67,71,74,76,74,71]]
    for bar in range(32):
        chord = chords[bar%4]; base=bar*4*beat
        for note in chord[1:]: place(tone(note, 4*beat+.35, 'pad'),base,-.35+(note%3)*.35)
        for tick in range(8):
            note=chord[1+tick%3]+(12 if tick%4==3 else 0)
            place(tone(note, beat*1.6),base+tick*.5*beat,(-.45 if tick%2 else .45))
        phrase=motifs[bar%4]
        for tick in range(4):
            note=phrase[(tick+4*(bar//4%2))%8]
            if bar>=16 and bar%4==2: note+=12
            place(tone(note, beat*1.8),base+tick*beat,.08)
        for tick in (0,2): place(tone(chord[0],1.3,'bass'),base+tick*beat)
        if battle:
            for tick in (0,2):
                t=np.arange(int(.23*SR))/SR
                kick=np.sin(2*np.pi*(48*t+5*(1-np.exp(-t*25))))*np.exp(-t*25)*.19
                place(kick,base+tick*beat)
            for tick in (1,3):
                t=np.arange(int(.17*SR))/SR
                noise=RNG.normal(0,.10,len(t)); high=noise-np.roll(noise,1)
                place(high*np.exp(-t*28),base+tick*beat,.15)
    # Short stereo room reflections, circular to preserve the exact loop length.
    dry=out.copy()
    for delay,gain in [(.113,.16),(.227,.10),(.359,.06)]:
        out += np.roll(dry,int(delay*SR),axis=0)[:,::-1]*gain
    out=np.tanh(out*1.3)*.72
    save('bgm/'+name,out)

def sfx(name, seconds, frequencies, noise=0, sweep=0):
    t=np.arange(int(seconds*SR))/SR
    env=np.minimum(t/.004,1)*np.exp(-t*(5/seconds))*np.minimum((seconds-t)/.015,1)
    y=np.zeros_like(t)
    for index,hz in enumerate(frequencies):
        y+=np.sin(2*np.pi*(hz*t+sweep*t*t/2))/(index+1)
    if noise: y+=(RNG.uniform(-1,1,len(t))-RNG.uniform(-1,1,len(t)))*noise
    save('sfx/'+name,y*env*.32)

if __name__=='__main__':
    score('after_school',86,False)
    score('echo_frontline',116,True)
    sfx('select',.12,[880,1320])
    sfx('deploy',.50,[440,660,880],sweep=420)
    sfx('retreat',.28,[660,990],sweep=-1200)
    sfx('slash',.19,[170],noise=1.1,sweep=-500)
    sfx('arrow',.15,[1200],noise=.32,sweep=-5000)
    sfx('hit',.12,[120,240],noise=.9)
    sfx('hurt',.20,[180,270],noise=.45,sweep=-400)
    sfx('heal',.65,[659,831,988],sweep=100)
    sfx('upgrade',.80,[523,659,784,1046],sweep=200)
    sfx('wave',.65,[330,440,660])
    sfx('core_hit',.65,[110,165,233],noise=.18,sweep=-80)
    sfx('victory',1.5,[523,659,784,1046])
    sfx('defeat',1.6,[220,261,311],sweep=-80)
    sfx('pause',.18,[440,660],sweep=-400)
    paths=sorted((ROOT/'assets/audio').rglob('*.wav'))
    (ROOT/'assets/audio/source_record.json').write_text(json.dumps({
        'author':'Hoshigaoka Echoes project - original procedural composition and synthesis',
        'source':'tools/build_audio.py', 'seed':20261010, 'externalSamples':[],
        'externalMelodies':[], 'commercialUse':'Project original audio; no external sample license required',
        'status':'First audible mix; listening and mastering approval pending',
        'files':[p.relative_to(ROOT).as_posix() for p in paths]},ensure_ascii=False,indent=2),encoding='utf-8')
