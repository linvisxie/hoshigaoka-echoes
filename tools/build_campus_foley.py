"""Original short campus foley; deterministic synthesis, no third-party samples."""
from pathlib import Path
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
RATE = 44100
rng = np.random.default_rng(513)

def save(name, data):
    pcm = (np.clip(data, -1, 1)*32767).astype('<i2')
    with wave.open(str(ROOT/'assets/audio/sfx'/f'{name}.wav'), 'wb') as w:
        w.setparams((1, 2, RATE, len(pcm), 'NONE', 'not compressed'))
        w.writeframes(pcm.tobytes())

t = np.arange(int(RATE*.46))/RATE
string = sum(np.sin(2*np.pi*196*k*t)*np.exp(-t*(10+k*3))/k**1.6 for k in range(1,7))
save('campus_bow', .15*string*np.minimum(t/.004, 1))
t = np.arange(int(RATE*.24))/RATE
noise = rng.normal(size=len(t))
noise = np.convolve(noise, np.ones(11)/11, mode='same')
save('campus_paper', .18*noise*np.sin(np.pi*t/.24)**2)
print('2 original bounded campus cues')
