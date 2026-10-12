from pathlib import Path
import json
R=Path(__file__).resolve().parents[1]
def read(p):return json.loads((R/p).read_text(encoding='utf8'))
def write(p,d):(R/p).write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
# Rebuild from the reviewed previous release's source data to avoid accumulating additions.
import subprocess
for n in range(6,11):
    path=f'data/stages/ch1/1-{n}.json'
    d=json.loads(subprocess.check_output(['git','show','647a51ab2ea2fcfc118f2536e63d50aae5a45976:'+path],cwd=R).decode('utf8'))
    d['sequentialWaves']=True;timeline=d['enemySpawnTimeline'];extra=[]
    for wave in sorted(set(e['wave'] for e in timeline)):
        entries=[e for e in timeline if e['wave']==wave and e['enemy']!='boss_model_student']
        if not entries:continue
        fractions=[.70] if n<8 else [.45,.85]
        for k,f in enumerate(fractions):
            t=entries[0]['time']+(entries[-1]['time']-entries[0]['time'])*f
            if wave==1:t=max(t,30+k*14)
            for lane in range(3):extra.append({'time':round(t+lane*.15,2),'lane':lane,'enemy':'echo_normal','wave':wave})
    d['enemySpawnTimeline']=sorted(timeline+extra,key=lambda e:(e['wave'],e['time']))
    if n==10:d['bossConfig'].update(standardInterval=16,finalSummonInterval=12,finalMovePct=.15,summonAllPhases=True)
    d['_encounterRevision']='0.5.3: sequential waves; coordinated multi-lane surges, 8 second redeploy, cross-lane piercing skill'
    d['tutorialTriggers'].append({'at':26,'id':f'TUT_SURGE_{n}','text':'三路残响即将协同接近。保留悠真的破空箭清理密集目标；受压时治疗，或撤退后换线再部署。'})
    write(path,d)
d=read('data/skills.json')
for s in d['skills']:
    if s['id']=='yuma_piercing_arrow':
        s['maxLaneDelta']=1
        s['description']='下次攻击造成300%伤害，贯穿前方及相邻路线最多3名敌人；适合截断多路残响的协同攻势。'
write('data/skills.json',d)
p=R/'scripts/domain/battle/stage_runtime.gd';s=p.read_text(encoding='utf8')
s=s.replace('if not enemy.is_active() or enemy.lane != character.lane:\n\t\t\tcontinue\n\t\tvar distance := enemy.logical_x - float(character.column)','if not enemy.is_active() or absi(enemy.lane-character.lane) > int(cfg.get("maxLaneDelta",0)):\n\t\t\tcontinue\n\t\tvar distance := enemy.logical_x - float(character.column)')
p.write_text(s,encoding='utf8')
print('Pressure and cross-lane active skill revised')
