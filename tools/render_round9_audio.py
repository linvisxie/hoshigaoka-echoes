"""Original sample-free dispatch and elite cues, sharing the campus motif."""
import json
from build_audio import SR, ROOT, save, np
from render_sampled_score import piano as tone
from render_resonance_sfx import render, filtered_noise

def main():
    records=[]
    for name,seconds,notes,air,body,cut,sweep in [
        ('rin_skill',.95,[69,76,81,88],.045,.03,1900,0),
        ('elite_arrival',1.35,[45,57,64,69],.10,.10,1500,-20),
        ('elite_gaze',.62,[69,70,81],.045,.02,1600,-35),
        ('elite_time_up',.95,[57,64,69,76],.13,.14,2100,30),
    ]: records.append(render(name,seconds,notes,air,body,cut,sweep))
    beat=60/140
    out=np.zeros((int(32*4*beat*SR),2))
    def put(sound,when,pan=0):
        indices=(np.arange(len(sound))+int(when*SR))%len(out)
        out[indices,0]+=sound*np.sqrt((1-pan)/2)
        out[indices,1]+=sound*np.sqrt((1+pan)/2)
    chords=[(45,57,60,64),(43,55,58,62),(41,53,57,60),(40,52,55,59)]
    melody=[[76,72,71,69],[74,70,67,62],[69,72,77,76],[71,67,64,59]]
    for bar in range(32):
        base=bar*4*beat; chord=chords[bar%4]
        for n in chord[1:]:put(tone(n,4*beat+.3,'pad')*.55,base,(n%3-1)*.3)
        for tick in range(8):
            put(tone(chord[1+tick%3],beat*1.4)*.28,base+tick*.5*beat,(-.4 if tick%2 else .4))
        for tick in range(4):
            put(tone(melody[bar%4][tick]+(12 if bar>=16 else 0),beat*1.8)*.55,base+tick*beat,.08)
        for tick in [0,2]:
            put(tone(chord[0],beat*1.4,'bass')*.7,base+tick*beat)
            t=np.arange(int(.22*SR))/SR
            put(np.sin(2*np.pi*(52*t+3*(1-np.exp(-t*24))))*np.exp(-t*23)*.12,base+tick*beat)
        for tick in range(8):
            t=np.arange(int(.09*SR))/SR
            put(filtered_noise(len(t),2800)*np.exp(-t*65)*(.055 if tick%2 else .025),base+tick*.5*beat,.2)
    dry=out.copy()
    for delay,gain in [(.071,.12),(.153,.08),(.307,.045)]:out+=np.roll(dry,int(delay*SR),axis=0)[:,::-1]*gain
    save('bgm/invigilator_exam',np.tanh(out)*.7)
    (ROOT/'docs/v3_round9_audio_record.json').write_text(json.dumps({
        'author':'Hoshigaoka Echoes project original melodies and synthesized event cues',
        'externalSamples':[{'library':'VSCO 2 Community Edition Upright Piano','license':'CC0-1.0','rawSamplesDistributed':False,'appliesTo':'elite music piano only','localLicense':'assets/licenses/VSCO2-CE-CC0.txt'}],
        'generator':'tools/render_round9_audio.py','cues':records,
        'music':'assets/audio/bgm/invigilator_exam.wav',
        'design':'Existing corridor theme, 140 BPM and a restrained pulse; event-bound elite entrance, gaze, time-up and dispatch cues.',
        'status':'Rendered; Windows playback verification tracked separately'
    },ensure_ascii=False,indent=2),encoding='utf8')
    print('Four original cues and elite theme rendered')
if __name__=='__main__':main()
