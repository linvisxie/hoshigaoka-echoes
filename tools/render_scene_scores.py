"""Eight original scene-specific scores, recorded CC0 instruments, deterministic loops.

Never renders the two user-preserved cues. Each score has its own harmony, meter,
melodic phrases, lead instrument and four-section arrangement, not a tempo variant.
"""
from pathlib import Path
import hashlib, json
import numpy as np
from build_audio import ROOT, SR, save, tone
from render_sampled_score import piano
from render_orchestral_drive import read_sample, BANK

SOURCES={'violin':('LLVln_spic_A4_v2_rr1.wav',69),'cello':('cello_spic_C3.wav',48),
 'horn':('horn_stac_C3.wav',48),'marimba':('marimba_C4.wav',60),
 'harp':('harp_A4.wav',69),'flute':('flute_sus_A4.wav',69)}
raw={};cache={}
for name,(file,root) in SOURCES.items():
    src=read_sample(BANK/file)
    audible=np.flatnonzero(abs(src)>.0007)
    if len(audible):src=src[max(0,audible[0]-int(.003*SR)):]
    raw[name]=(src,root)

def instrument(name,note,length):
    key=(name,note,round(length,4))
    if key in cache:return cache[key]
    src,root=raw[name];pos=np.arange(0,len(src)-1,2**((note-root)/12))
    sound=np.interp(pos,np.arange(len(src)),src)[:int(length*SR)].copy()
    sound*=.30/max(.001,float(abs(sound).max()))
    fade=min(int(.045*SR),len(sound)//4)
    if fade:sound[-fade:]*=np.linspace(1,0,fade)
    cache[key]=sound
    return sound

# Root plus explicitly voiced chord tones; phrases are independently composed.
PROFILES=[
 dict(track='corridor_pressure',title='暮廊追迹',bpm=144,meter=4,lead='piano',texture='violin',
 chords=[(38,[62,65,69]),(46,[62,65,70]),(43,[62,67,70]),(45,[61,64,69]),(41,[60,65,69]),(36,[60,64,67]),(43,[62,65,70]),(45,[61,67,69])],
 phrases=[[74,77,76,74,69,72,73,69],[77,81,79,77,74,72,70,69],[79,77,74,70,74,77,76,74],[73,76,81,79,76,73,69,73]],drums='drive'),
 dict(track='infirmary_light',title='未熄的灯',bpm=142,meter=3,lead='flute',texture='harp',
 chords=[(40,[59,64,67]),(48,[60,64,67]),(43,[59,62,67]),(47,[59,63,66]),(45,[60,64,69]),(42,[57,60,66]),(47,[59,63,66]),(40,[59,64,67])],
 phrases=[[76,79,83,81,79,76],[84,83,79,76,74,76],[79,83,86,83,81,79],[78,75,71,75,78,83]],drums='gallop'),
 dict(track='ranking_pressure',title='名次的齿轮',bpm=152,meter=5,lead='marimba',texture='cello',
 chords=[(42,[61,66,69]),(38,[62,66,69]),(44,[59,64,68]),(49,[61,65,68]),(47,[62,66,71]),(40,[59,64,68]),(44,[60,63,68]),(49,[61,65,71])],
 phrases=[[78,73,81,78,76,73,69,73,76,77],[81,78,74,78,83,81,78,74,73,74],[80,76,71,76,80,83,80,76,75,76],[77,80,85,84,80,77,73,72,73,77]],drums='machine'),
 dict(track='science_resonance',title='折射频率',bpm=158,meter=3.5,lead='harp',texture='marimba',
 chords=[(48,[60,63,67]),(44,[60,63,68]),(41,[60,65,68]),(43,[59,62,67]),(46,[62,65,70]),(39,[58,63,67]),(41,[60,65,68]),(43,[59,65,67])],
 phrases=[[79,75,74,72,74,75,79],[80,79,75,72,75,79,82],[84,80,77,75,77,80,84],[83,79,74,71,74,77,79]],drums='pulse'),
 dict(track='invigilator_exam',title='无声的监考',bpm=156,meter=4,lead='horn',texture='cello',
 chords=[(39,[58,63,66]),(35,[59,63,66]),(44,[59,63,68]),(46,[58,62,65]),(42,[58,61,66]),(37,[56,61,65]),(44,[59,63,68]),(46,[58,62,68])],
 phrases=[[63,66,65,63,58,61,60,58],[66,70,68,66,63,62,59,58],[68,66,63,59,63,66,65,63],[62,65,70,68,65,62,58,62]],drums='march'),
 dict(track='boss_exam_1',title='红笔裁决',bpm=166,meter=4,lead='violin',texture='horn',
 chords=[(37,[61,64,68]),(45,[61,64,69]),(42,[61,66,69]),(44,[60,63,68]),(40,[59,64,68]),(35,[59,63,66]),(42,[61,64,69]),(44,[60,66,68])],
 phrases=[[80,76,73,76,80,83,81,80],[81,80,76,73,76,80,85,83],[85,81,78,76,78,81,85,88],[84,80,75,72,75,78,80,84]],drums='siege'),
 dict(track='boss_exam_2',title='撕裂的满分',bpm=180,meter=3,lead='piano',texture='cello',
 chords=[(43,[62,67,70]),(39,[63,67,70]),(48,[63,67,72]),(38,[62,66,69]),(46,[62,65,70]),(41,[60,65,69]),(45,[60,63,69]),(38,[62,66,72])],
 phrases=[[79,82,86,85,82,79],[82,86,87,86,82,79],[87,86,82,79,75,79],[81,78,74,78,81,86]],drums='storm'),
 dict(track='boss_exam_3',title='为未被听见的声音',bpm=188,meter=4,lead='violin',texture='harp',
 chords=[(47,[62,66,71]),(43,[62,67,71]),(50,[62,66,69]),(45,[61,64,69]),(40,[59,64,67]),(43,[59,62,67]),(42,[61,66,69]),(42,[61,65,71])],
 phrases=[[83,86,85,83,78,81,83,86],[86,90,88,86,83,81,79,78],[90,88,86,85,83,81,78,81],[85,81,78,77,78,81,85,89]],drums='finale'),
]

def render(p):
    beat=60/p['bpm'];meter=p['meter'];bar_len=beat*meter;bars=64
    out=np.zeros((round(bars*bar_len*SR),2));rng=np.random.default_rng(p['bpm']*937)
    def put(sound,when,pan=0,gain=1):
        idx=(np.arange(len(sound))+round(when*SR))%len(out)
        out[idx,0]+=sound*gain*np.sqrt((1-pan)/2)
        out[idx,1]+=sound*gain*np.sqrt((1+pan)/2)
    def note(name,midi,length,when,gain=1,pan=0):
        sound=piano(midi,length) if name=='piano' else instrument(name,midi,length)
        put(sound,when,pan,gain)
    energetic=p['track'].startswith('boss')
    for b in range(bars):
        section=b//16;start=b*bar_len
        root,voices=p['chords'][(b+(2 if section==2 else 0))%8]
        phrase=p['phrases'][(b//2+section)%4]
        # Melody breathes in A, develops B, rises in C, resolves into the loop.
        nsteps=len(phrase);dur=bar_len/nsteps
        for k,midi in enumerate(phrase):
            if section==0 and b%2==1 and k>=nsteps-2:continue
            if p['lead']=='horn':midi-=12
            note(p['lead'],midi,dur*(1.5 if p['lead']=='flute' else 1.05),start+k*dur,.78 if energetic else .66,.05)
            if energetic and section in (1,3):
                note('horn',midi-24,beat*.7,start+k*dur,.29,-.18)
        # Distinct accompaniment by scene: waltz harp, asymmetric machinery,
        # laboratory interlock, strict march, and double-bowed boss strings.
        steps=round(meter*(4 if energetic else 2))
        for k in range(steps):
            t=start+k*bar_len/steps;v=voices[(k+(b%2))%3]
            tex=p['texture'];pitch=v-12 if tex in ('cello','horn') else v
            gain=.48 if k%2==0 else .30
            note(tex,pitch,beat*.44,t,gain,-.40)
            if energetic or section==2:
                note('violin',v+12,beat*.23,t+beat*.06,.30,.40)
        for k in range(int(np.ceil(meter))):
            t=start+k*beat
            if t>=start+bar_len:continue
            put(tone(root,beat*.8,'bass'),t,0,.72)
            note('cello',root+12,beat*.5,t,.40,-.20)
            if k%2==0 or p['drums'] in ('march','finale'):
                tt=np.arange(int(.27*SR))/SR
                kick=np.sin(2*np.pi*(45*tt+1.8*(1-np.exp(-tt*29))))*np.exp(-tt*17)*.28
                put(kick,t,gain=1.2 if energetic else .85)
            if k%2==1 or (meter==3 and k==2):
                tt=np.arange(int(.18*SR))/SR
                snare=(rng.normal(0,1,len(tt))*.08+np.sin(2*np.pi*185*tt)*.055)*np.exp(-tt*24)
                put(snare,t,.16,1.3 if energetic else .7)
        hats=round(meter*(4 if energetic else 2))
        for k in range(hats):
            tt=np.arange(int(.045*SR))/SR
            hat=np.diff(rng.normal(0,1,len(tt)),prepend=0)*np.exp(-tt*85)*.012
            put(hat,start+k*bar_len/hats,.60,.9 if k%2==0 else .55)
        # Wide sustained harmonic layer uses recorded flute and resonant piano.
        if b%2==0:
            for k,v in enumerate(voices):
                note('piano',v,bar_len*1.9,start,.26,k*.28-.28)
            note('flute',voices[0]+12,bar_len*.94,start,.13,.38)
        if energetic and b%4==3:
            for j,v in enumerate([0,2,3,5,7,8,11,12]):
                note('violin',voices[0]+12+v,beat*.22,start+bar_len-beat+j*beat/8,.35,-.3+j*.08)
        if b%8==0:
            tt=np.arange(int(1.8*SR))/SR
            cymbal=np.diff(rng.normal(0,1,len(tt)),prepend=0)*np.exp(-tt*3.4)*.025
            put(cymbal,start,.5,1.3 if energetic else .7)
        out[round(start*SR):round((start+bar_len)*SR)]*= [ .82,1.0,.90,1.05 ][section]
    dry=out.copy()
    for delay,gain in [(.073,.13),(.137,.10),(.211,.065),(.307,.045)]:
        out+=np.roll(dry[:,::-1],round(delay*SR),axis=0)*gain
    out=np.tanh(out*1.16);out*=.85/max(.85,float(abs(out).max()))
    save('bgm/'+p['track'],out)
    return dict(p,seconds=len(out)/SR,peak=float(abs(out).max()),rms=float(np.sqrt((out*out).mean())),sha256=hashlib.sha256((ROOT/'assets/audio/bgm'/f'{p["track"]}.wav').read_bytes()).hexdigest())

if __name__=='__main__':
    kept={name:hashlib.sha256((ROOT/'assets/audio/bgm'/f'{name}.wav').read_bytes()).hexdigest() for name in ('echo_frontline','archive_convergence')}
    records=[]
    for p in PROFILES:
        records.append(render(p));print(p['track'],records[-1]['seconds'],flush=True)
    assert all(hashlib.sha256((ROOT/'assets/audio/bgm'/f'{n}.wav').read_bytes()).hexdigest()==h for n,h in kept.items())
    manifest={'authorship':'Project original scene scores, independently composed harmony/melody/meter and four-section arrangements',
      'samples':'VSCO 2 CE, Sam Gossner / Versilian Studios, CC0-1.0',
      'source':'https://github.com/sgossner/VSCO-2-CE','preserved':kept,'tracks':records,
      'sampleSha256':{file:hashlib.sha256((BANK/file).read_bytes()).hexdigest() for file,_ in SOURCES.values()},
      'acceptance':'Technical and runtime verification recorded separately; subjective listening approval pending'}
    (ROOT/'docs/scene_scores_054.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
    (ROOT/'assets/licenses/VSCO2_SCENE_SCORES_CC0.txt').write_text('VSCO 2 Community Edition, Sam Gossner / Versilian Studios. Piano, solo violin, cello, horn, marimba, harp and flute samples in project-original compositions. Raw samples are not distributed. https://github.com/sgossner/VSCO-2-CE\n\n'+(BANK/'LICENSE').read_text(),encoding='utf8')
