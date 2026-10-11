"""Original chapter variants using the existing CC0 VSCO piano bank."""
import json
from build_audio import SR, ROOT, save, np
from render_sampled_score import piano
from render_resonance_sfx import filtered_noise, render

def score(name,bpm,intensity):
    beat=60/bpm;bars=24
    out=np.zeros((int(bars*4*beat*SR),2))
    def put(sound,when,pan=0):
        ids=(np.arange(len(sound))+int(when*SR))%len(out)
        out[ids,0]+=sound*np.sqrt((1-pan)/2)
        out[ids,1]+=sound*np.sqrt((1+pan)/2)
    chords=[(45,57,60,64),(41,53,57,60),(43,55,59,62),(40,52,55,59)]
    tune=[(76,72,71,69),(77,76,72,69),(74,71,67,62),(71,67,64,59)]
    for bar in range(bars):
        t=bar*4*beat;c=chords[bar%4]
        for note in c[1:]:put(piano(note,beat*4+.2,'pad')*.4,t,(note%3-1)*.3)
        for k in range(8):put(piano(c[1+k%3],beat*1.6)*.24,t+k*.5*beat,(-.35 if k%2 else .35))
        for k,note in enumerate(tune[bar%4]):put(piano(note+(12 if intensity>1 and bar>=12 else 0),beat*1.9)*.48,t+k*beat,.1)
        for k in [0,2]:
            put(piano(c[0],beat*1.6)*(.35+intensity*.1),t+k*beat)
            hit=np.arange(int(.15*SR))/SR
            put(np.sin(2*np.pi*(55*hit-12*hit*hit))*np.exp(-hit*24)*.12*intensity,t+k*beat)
        if intensity>0:
            hiss=filtered_noise(int(.09*SR),1800)*np.exp(-np.arange(int(.09*SR))/SR*40)*.035*intensity
            for k in [1,3]:put(hiss,t+k*beat,-.1)
    out=np.tanh(out)*.65
    save('bgm/'+name,out)
    return dict(track=name,seconds=len(out)/SR,bpm=bpm,peak=float(abs(out).max()),rms=float(np.sqrt((out*out).mean())))

if __name__=='__main__':
    records=[score('infirmary_light',100,.35),score('ranking_pressure',128,.8),score('science_resonance',132,.9),score('archive_convergence',136,1.1)]
    from render_boss_drive import render as render_boss
    records += [render_boss(i) for i in range(1,4)]
    records.append(score('chapter_one_coda',90,0))
    render('yui_skill',1.2,[72,79,84,88],.025,.035,2200,0)
    render('sara_skill',.95,[57,69,76,81],.06,.05,2400,20)
    render('chinatsu_skill',1.1,[64,71,76,83],.03,.055,2000,0)
    (ROOT/'docs/chapter_tail_audio.json').write_text(json.dumps({'origin':'Original score; existing legally recorded CC0 VSCO2 bank, original synthesis','tracks':records},ensure_ascii=False,indent=2),encoding='utf8')
