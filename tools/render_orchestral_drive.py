"""Original chapter motifs with CC0 VSCO solo violin; no third-party melodies."""
from pathlib import Path
import json, wave, hashlib
import numpy as np
from build_audio import SR, ROOT, save
from render_sampled_score import piano
BANK=Path('D:/星丘基础/downloads/ui-polish/VSCO2-orchestra')
def read_sample(path):
    with wave.open(str(path),'rb') as w:
        width=w.getsampwidth();channels=w.getnchannels();rate=w.getframerate();data=w.readframes(w.getnframes())
    if width==3:
        b=np.frombuffer(data,dtype=np.uint8).reshape(-1,3)
        x=b[:,0].astype(np.int32)|(b[:,1].astype(np.int32)<<8)|(b[:,2].astype(np.int32)<<16)
        x=((x^0x800000)-0x800000)/8388608
    else:
        assert width in (2,4)
        x=np.frombuffer(data,dtype='<i2' if width==2 else '<i4').astype(float)/(32768 if width==2 else 2147483648)
    x=x.reshape(-1,channels).mean(axis=1)
    size=round(len(x)*SR/rate)
    return np.fft.irfft(np.fft.rfft(x)[:size//2+1],n=size)*size/len(x)
raw={n:read_sample(BANK/f'LLVln_spic_A{o}_v2_rr1.wav') for n,o in [(57,3),(69,4),(81,5)]}
cache={}
def violin(note,duration):
    key=(note,round(duration,4))
    if key in cache:return cache[key]
    root=min(raw,key=lambda n:abs(n-note));src=raw[root]
    audible=np.flatnonzero(abs(src)>.001)
    if len(audible):src=src[max(0,audible[0]-int(.003*SR)):]
    pos=np.arange(0,len(src)-1,2**((note-root)/12))
    data=np.interp(pos,np.arange(len(src)),src)
    data=data[:int(duration*SR)].copy()
    data*=.30/max(.001,float(abs(data).max()))
    fade=min(int(.025*SR),len(data)//4)
    data[-fade:]*=np.linspace(1,0,fade)
    cache[key]=data
    return data
def score(name,bpm,intensity,phase=0):
    rng=np.random.default_rng(12000+phase+int(bpm))
    beat=60/bpm;bars=24;out=np.zeros((int(bars*4*beat*SR),2))
    def put(sound,when,pan=0):
        idx=(np.arange(len(sound))+int(when*SR))%len(out)
        out[idx,0]+=sound*np.sqrt((1-pan)/2);out[idx,1]+=sound*np.sqrt((1+pan)/2)
    chords=[(45,57,60,64),(41,53,57,60),(43,55,59,62),(40,52,55,59)]
    tune=[(76,72,71,69),(77,76,72,69),(74,71,67,62),(71,67,64,59)]
    for bar in range(bars):
        start=bar*4*beat;c=chords[bar%4]
        for n in c[1:]:put(piano(n,beat*4+.15,'pad')*.22,start,(n%3-1)*.3)
        # Antiphonal eighth/sixteenth bowing makes tension rhythmic rather than merely loud.
        steps=16 if phase else 8
        for k in range(steps):
            n=c[1+k%3]+12+(12 if phase==3 and bar>=16 else 0)
            put(violin(n,beat*.45)*(.65 if phase else .45),start+k*4*beat/steps,-.35)
            if phase>=2 or (bar%4>=2):
                put(violin(c[1+(k+1)%3],beat*.5)*.32,start+k*4*beat/steps+beat*.08,.38)
        for k,n in enumerate(tune[bar%4]):
            put(piano(n,beat*1.4)*.40,start+k*beat,.12)
            if phase:put(violin(n,beat*.8)*.45,start+k*beat,-.1)
        for k in range(8):
            put(piano(c[0],beat*.7)*.55,start+k*beat*.5)
            t=np.arange(int(.22*SR))/SR
            kick=np.sin(2*np.pi*(46*t+1.5*(1-np.exp(-t*32))))*np.exp(-t*19)*.27*intensity
            if k%2==0:put(kick,start+k*beat*.5)
            if k%4==2:
                snare=(rng.normal(0,1,len(t))*.065+np.sin(2*np.pi*190*t)*.08)*np.exp(-t*22)*intensity
                put(snare,start+k*beat*.5,.08)
            hat=np.diff(rng.normal(0,1,int(.045*SR)),prepend=0)*np.exp(-np.arange(int(.045*SR))/SR*90)*.018*intensity
            put(hat,start+k*beat*.5,.45)
        if phase and bar%4==3:
            for j in range(8):put(violin(69+[0,2,3,5,7,8,11,12][j],beat*.25)*.5,start+3*beat+j*beat/8,-.25+j*.07)
        if bar%4==0:
            t=np.arange(int(1.4*SR))/SR
            put(np.diff(rng.normal(0,1,len(t)),prepend=0)*np.exp(-t*4)*.035*intensity,start,.35)
    # Short stereo room, deterministic peak headroom; no clipping-normalization race.
    delayed=np.zeros_like(out);lag=int(.11*SR)
    delayed[lag:]=out[:-lag,::-1]*.12;out+=delayed
    out=np.tanh(out*1.05)
    out*=.88/max(.88,float(abs(out).max()))
    save('bgm/'+name,out)
    return dict(track=name,bpm=bpm,seconds=len(out)/SR,peak=float(abs(out).max()),rms=float(np.sqrt((out*out).mean())))
if __name__=='__main__':
    tracks=[score(n,b,i) for n,b,i in [('echo_frontline',138,.85),('corridor_pressure',146,1),('infirmary_light',140,.9),('ranking_pressure',148,1),('science_resonance',152,1.05),('archive_convergence',156,1.1)]]
    tracks += [score('boss_exam_'+str(p),160+p*8,1.15+p*.1,p) for p in range(1,4)]
    manifest={'composition':'Original project chapter motif; piano, recorded spiccato violin, layered strings, bass and percussion','samples':'VSCO 2 CE, Sam Gossner/Versilian Studios, CC0-1.0','source':'https://github.com/sgossner/VSCO-2-CE','tracks':tracks,'sampleSha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in BANK.glob('*.wav')}}
    (ROOT/'docs/orchestral_drive_audio.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')
    (ROOT/'assets/licenses/VSCO2_ORCHESTRA_CC0.txt').write_text('VSCO 2 Community Edition. Sam Gossner / Versilian Studios. Recorded violin samples used in original compositions. https://github.com/sgossner/VSCO-2-CE\n\n'+(BANK/'LICENSE').read_text(),encoding='utf8')
    print(json.dumps(tracks))
