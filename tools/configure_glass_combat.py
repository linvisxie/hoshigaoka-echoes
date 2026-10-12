"""Idempotent 0.5.3 tuning pass. Encounter additions rebuild from pinned 0.5.2."""
from pathlib import Path
import json,subprocess,sys
R=Path(__file__).resolve().parents[1]
def read(p):return json.loads((R/p).read_text(encoding='utf-8-sig'))
def write(p,d):(R/p).write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
d=read('data/characters.json')
for c in d['characters']:
 c.pop('redeployCooldown',None)
 c['redeployTime']=10 if c['id']=='fujiwara_rin' else 8
write('data/characters.json',d)
d=read('data/enemies.json')
for e in d['enemies']:
 if e['id']=='boss_model_student':e['moveSpeed']=.055
write('data/enemies.json',d)
subprocess.run([sys.executable,str(R/'tools/tune_glass_pressure.py')],check=True)
stages=[]
for n in range(1,11):
 d=read(f'data/stages/ch1/1-{n}.json')
 stages.append({'stage':d['stageId'],'plannedEnemies':len(d['enemySpawnTimeline']),'sequentialWaves':bool(d.get('sequentialWaves',False))})
write('docs/glass_combat_balance.json',{'stages':stages,'bossMoveSpeed':.055,'redeploySeconds':{'default':8,'rin':10},'validation':'611 unit tests; isolated normal-AP simulation and actual Windows campaign reports are separate evidence','regenerationBaseline':'647a51ab2ea2fcfc118f2536e63d50aae5a45976'})
