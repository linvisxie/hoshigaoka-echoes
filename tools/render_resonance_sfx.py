"""Original soft campus/fantasy combat palette; deterministic, no external samples.

Air, felt-like transients and pentatonic resonances replace dry glass/metal hits.
Offline band limiting and short stereo reflections leave room for the piano score.
"""
from pathlib import Path
import json
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SR = 32000
RNG = np.random.default_rng(20261011)

def filtered_noise(n, cutoff):
    frequencies = np.fft.rfftfreq(n, 1 / SR)
    spectrum = np.fft.rfft(RNG.normal(0, 1, n))
    spectrum *= np.exp(-(frequencies / cutoff) ** 4)
    return np.fft.irfft(spectrum, n)

def render(name, length, notes, air=.0, body=.0, brightness=2200, sweep=0):
    t = np.arange(int(SR * length)) / SR
    attack = np.minimum(t / .014, 1) ** 1.5
    tail = np.minimum((length - t) / .08, 1)
    sound = np.zeros_like(t)
    for i, note in enumerate(notes):
        hz = 440 * 2 ** ((note - 69) / 12)
        onset = .018 * i
        local = np.maximum(t - onset, 0)
        envelope = np.minimum(local / .012, 1) * np.exp(-local * (7 + i) / length)
        # Soft resonator: no sharp saw waves or exposed high sine sweeps.
        sound += (np.sin(2*np.pi*(hz*local+sweep*local**2/2))
                  + .12*np.sin(2*np.pi*hz*2*local)) * envelope * .16 / (1 + i*.65)
    sound += filtered_noise(len(t), brightness) * air * attack * np.exp(-t * 8 / length)
    sound += np.sin(2*np.pi*78*t) * body * attack * np.exp(-t*36)
    sound *= tail
    stereo = np.column_stack((sound, sound))
    for delay, gain in [(.043,.16),(.087,.10),(.149,.055)]:
        shift = int(delay * SR)
        stereo[shift:, 0] += sound[:-shift] * gain
        stereo[shift:, 1] += sound[:-shift] * gain * .8
    stereo *= np.minimum(t/.006,1)[:,None]
    stereo -= stereo.mean(axis=0)
    peak = float(np.abs(stereo).max())
    stereo *= min(1., .42 / max(peak, .001))
    path = ROOT / 'assets/audio/sfx' / (name + '.wav')
    with wave.open(str(path),'wb') as output:
        output.setnchannels(2); output.setsampwidth(2); output.setframerate(SR)
        output.writeframes((stereo*32767).astype('<i2').tobytes())
    return {'asset':path.relative_to(ROOT).as_posix(),'peak':round(float(np.abs(stereo).max()),5),
            'rms':round(float(np.sqrt(np.mean(stereo**2))),5),'duration':length}

def main():
    files=[]
    for i in range(3):
        files.append(render('resonance_hit_%02d'%(i+1),.28,[57+i*2,69+i*2],air=.15,body=.16,brightness=1700))
    for i in range(2):
        files.append(render('resonance_blade_%02d'%(i+1),.36,[74+i*2],air=.48,body=.045,brightness=2800,sweep=-120))
        files.append(render('resonance_armor_%02d'%(i+1),.38,[62+i*2,74+i*2,81],air=.08,body=.19,brightness=2100))
        files.append(render('resonance_dissolve_%02d'%(i+1),.65,[81+i*2,86+i*2,93],air=.09,brightness=2400))
    for name,length,notes,air,body,cut,sweep in [
        ('arrow',.28,[81],.26,.02,2600,-210),
        ('hurt',.33,[50,57],.10,.16,1300,-25),
        ('deploy',.65,[69,74,81],.06,.02,2100,0),
        ('retreat',.42,[81,74,69],.05,0,1900,-12),
        ('heal',.82,[74,81,86],.02,0,2000,0),
        ('upgrade',.95,[69,74,81,86],.04,.03,2200,0),
        ('wave',.64,[62,69,74],.04,.06,1800,0),
        ('core_hit',.75,[45,57,64],.12,.23,1500,-20),
        ('pause',.25,[74,81],.0,0,1800,0),
        ('mio_skill',.85,[69,81,86],.38,.14,3000,-85),
        ('yuma_skill',.78,[74,81,93],.25,.12,2800,-160),
        ('status',.52,[57,64,69],.06,0,1600,-15),
    ]:
        files.append(render(name,length,notes,air,body,cut,sweep))
    (ROOT/'docs/v3_resonance_sfx_record.json').write_text(json.dumps({
        'author':'Hoshigaoka Echoes project original synthesis', 'externalSamples':[],
        'generator':'tools/render_resonance_sfx.py', 'seed':20261011,
        'design':'Soft air, pentatonic resonance, rounded impact, short stereo room; no raw metal or glass in combat routes.',
        'status':'Rendered; actual Windows playback and listening assessment tracked separately.',
        'files':files},ensure_ascii=False,indent=2),encoding='utf8')
    print('Rendered',len(files),'original cues')

if __name__=='__main__': main()
