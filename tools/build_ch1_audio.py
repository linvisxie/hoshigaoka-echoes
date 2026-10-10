"""Additional original score cues and distinct skill / status sound design."""
from build_audio import SR, ROOT, save, tone, sfx, np, RNG
import json

def cue(name, bpm, dark=False):
 beat=60/bpm
 length=beat*4*24
 out=np.zeros((int(length*SR),2),np.float64)
 def put(note,when,duration,kind='piano',gain=1,pan=0):
  a=tone(note,duration,kind)*gain
  indices=(np.arange(len(a))+int(when*SR))%len(out)
  out[indices,0]+=a*np.sqrt((1-pan)/2)
  out[indices,1]+=a*np.sqrt((1+pan)/2)
 chords=[(45,57,60,64),(43,55,58,62),(41,53,57,60),(40,52,55,59)] if dark else [(48,60,64,67),(45,57,60,64),(41,57,60,65),(43,55,62,67)]
 melody=[[76,72,71,69],[74,70,67,62],[69,72,77,76],[71,67,64,59]] if dark else [[79,76,74,72],[76,72,69,72],[77,76,72,69],[74,79,76,74]]
 for bar in range(24):
  base=bar*4*beat; chord=chords[bar%4]
  for n in chord[1:]:put(n,base,beat*4+.4,'pad',.8,-.3+(n%3)*.3)
  put(chord[0],base,beat*3,'bass',.75)
  if bar%4<3:
   for n in range(4):put(melody[bar%4][n]+(12 if bar>=16 and not dark else 0),base+n*beat,beat*2,'piano',.65,.15)
  for n in range(8):put(chord[1+n%3],base+n*.5*beat,beat*1.3,'piano',.24,-.4 if n%2 else .4)
 dry=out.copy()
 for delay,gain in [(.13,.16),(.31,.09),(.49,.04)]:out+=np.roll(dry,int(delay*SR),axis=0)[:,::-1]*gain
 save('bgm/'+name,np.tanh(out)*.8)

if __name__ == '__main__':
 cue('unheard_memory',72,True)
 cue('observation_club',94,False)
 cue('corridor_pressure',132,True)
 sfx('mio_skill',.9,[330,660,1320],noise=.45,sweep=950)
 sfx('yuma_skill',.75,[880,1760],noise=.25,sweep=1800)
 sfx('status',.45,[196,277,392],noise=.16,sweep=-230)
 record=ROOT/'assets/audio/source_record.json'
 data=json.loads(record.read_text(encoding='utf8'))
 data['additionalSource']='tools/build_ch1_audio.py'
 data['files']=[p.relative_to(ROOT).as_posix() for p in sorted((ROOT/'assets/audio').rglob('*.wav'))]
 record.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf8')
