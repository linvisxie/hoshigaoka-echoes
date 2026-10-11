"""Original boss-theme arrangement: CC0 piano plus original synthesized rhythm.
No downloaded songs or external melodies. Three phases share the chapter motif.
"""
import json
from build_audio import SR, ROOT, save, np
from render_sampled_score import piano

def render(phase):
    rng=np.random.default_rng(20261012+phase)
    bpm=140+phase*8; beat=60/bpm; bars=24
    out=np.zeros((int(bars*4*beat*SR),2))
    def put(sound,when,pan=0):
        ids=(np.arange(len(sound))+int(when*SR))%len(out)
        out[ids,0]+=sound*np.sqrt((1-pan)/2)
        out[ids,1]+=sound*np.sqrt((1+pan)/2)
    chords=[(45,57,60,64),(41,53,57,60),(43,55,59,62),(40,52,55,59)]
    tune=[(76,72,71,69),(77,76,72,69),(74,71,67,62),(71,67,64,59)]
    for bar in range(bars):
        start=bar*4*beat;c=chords[bar%4]
        for n in c[1:]: put(piano(n,beat*4+.1,'pad')*.22,start,(n%3-1)*.4)
        for k in range(16):
            t=np.arange(int(beat*.8*SR))/SR;hz=440*2**((c[0]+(12 if k%4==3 else 0)-69)/12)
            bass=np.tanh((np.sin(2*np.pi*hz*t)+.22*np.sin(2*np.pi*hz*2*t))*1.7)*np.exp(-t*11)*.15
            put(bass,start+k*beat/4)
            if k%2==0: put(piano(c[1+(k//2)%3],beat*.8)*.27,start+k*beat/4,(-.35 if k%4 else .35))
            hat=rng.normal(0,1,int(.035*SR));hat=np.diff(hat,prepend=0)*np.exp(-np.arange(len(hat))/SR*110)*.018
            put(hat,start+k*beat/4,.3)
        for k,n in enumerate(tune[bar%4]): put(piano(n+(12 if phase==3 and bar>=12 else 0),beat*1.5)*.5,start+k*beat,-.08)
        for k in range(4):
            t=np.arange(int(.20*SR))/SR
            kick=np.sin(2*np.pi*(48*t+1.6*(1-np.exp(-t*35))))*np.exp(-t*22)*.38
            put(kick,start+k*beat)
            if k%2:
                noise=rng.normal(0,1,len(t));snare=(noise*.075+np.sin(2*np.pi*180*t)*.09)*np.exp(-t*28)
                put(snare,start+k*beat,-.12)
        if bar%4==0:
            t=np.arange(int(1.2*SR))/SR
            crash=np.diff(rng.normal(0,1,len(t)),prepend=0)*np.exp(-t*5)*.025
            put(crash,start,.4)
    out=np.tanh(out*1.1)
    out*=.86/max(.86,float(abs(out).max()))
    save('bgm/boss_exam_'+str(phase),out)
    return {'phase':phase,'bpm':bpm,'seconds':len(out)/SR,'peak':float(abs(out).max()),'rms':float(np.sqrt((out*out).mean()))}

if __name__=='__main__':
    records=[render(i) for i in range(1,4)]
    (ROOT/'docs/boss_drive_audio.json').write_text(json.dumps({'origin':'Original chapter motif arrangement; original synthesized drums and bass; existing CC0 VSCO2 piano','tracks':records},indent=2),encoding='utf8')
