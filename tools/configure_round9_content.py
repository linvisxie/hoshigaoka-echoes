"""Apply this round's explicit content decisions, idempotently."""
from pathlib import Path
import json
ROOT = Path(__file__).resolve().parents[1]
def load(name):
    return json.loads((ROOT/name).read_text(encoding='utf8'))
def save(name, data):
    (ROOT/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
def main():
    chars=load('data/characters.json')
    chars['characters']=[c for c in chars['characters'] if c['id']!='fujiwara_rin']
    chars['characters'].append({
        'id':'fujiwara_rin','name':'藤原凛','nameShort':'凛','grade':'高三','club':'学生会副会长',
        'classType':'STUDENT_COUNCIL','behavior':'RANGED','roleTags':['SUPPORT','AP'],
        'baseStats':{'hp':680,'attack':0,'defense':40},'growthProfileId':'growth_standard',
        'attackInterval':1.0,'attackRange':{'shape':'lane_band','direction':'forward','rangeTiles':0,'maxLaneDelta':0},
        'blockCount':0,'deployCost':16,'redeployTime':25.0,'damageType':'PHYSICAL',
        'normalAttackEnabled':False,'apRegenBonusPct':0.15,'skillIds':['rin_emergency_dispatch'],'talentIds':['rin_process_optimization'],
        'unlockStage':'1-7','spriteFramePx':96,
        '_spec':'V2.1.4 table 47: no normal attack, global AP support. RANGED is the legacy non-blocking runtime category, not an offensive role.',
        '_replayDecision':'2026-10-11: after first-clearing 1-5 and reading its ending, Rin can join replays of 1-3 to 1-5. First-clear teaching sequence remains unchanged.'})
    save('data/characters.json',chars)
    skills=load('data/skills.json')
    skills['skills']=[s for s in skills['skills'] if s['id']!='rin_emergency_dispatch']
    skills['talents']=[s for s in skills['talents'] if s['id']!='rin_process_optimization']
    skills['skills'].append({'id':'rin_emergency_dispatch','name':'紧急调度','type':'ACTIVE','effect':'AP_GAIN',
        'initialCooldownSeconds':24,'cooldownSeconds':24,'apGain':6,
        'description':'立即获得6 AP，不超过上限。凛在场时全队自然AP回复+15%，不进行普通攻击。'})
    skills['talents'].append({'id':'rin_process_optimization','name':'流程优化','effect':'NEXT_DEPLOY_DISCOUNT',
        'durationSeconds':10,'apDiscount':2,'description':'每次部署后10秒内，下一名友军部署费用−2 AP，最低1 AP；成功部署后消耗。'})
    save('data/skills.json',skills)
    balance=load('data/balance.json');balance['combat']['apRegenBonusCap']=.5;save('data/balance.json',balance)
    upgrades=load('data/upgrades.json')
    upgrades['_deferred']['items']=[i for i in upgrades['_deferred']['items'] if i['id']!='CD_REDUCE']
    upgrades['upgrades']=[u for u in upgrades['upgrades'] if u['id']!='upgrade_cd_recovery']
    upgrades['upgrades'].append({'id':'upgrade_cd_recovery','specId':'CD_REDUCE','name':'共鸣协奏',
        'description':'全队技能冷却恢复速度 +15%','tier':'ADVANCED','category':'技能型',
        'icon':'icon_skillbook','tags':['SKILL'],'appliesTo':'ALL','maxStacks':2,
        'effect':{'type':'STAT_MOD','stat':'CD_RECOVERY','value':.15},
        'guidance':'缩短技能等待\n适合依靠一闪与破空箭解围'})
    # The original fixed first-five tutorial remains one offer. Replays receive
    # a second choice via an isolated in-memory domain copy in the scene.
    upgrades['_designNotes'].append('2026-10-11: CD_RECOVERY now consumed by real skill clocks. First-clear 1-5 remains fixed one offer; club replays receive an additional wave-3 offer.') if not any('CD_RECOVERY now' in x for x in upgrades['_designNotes']) else None
    save('data/upgrades.json',upgrades)
    story=load('data/story/ch1_1_5_after.json')
    for node in story['nodes']:
        if node['id']=='10':node['text']='放课后观测会。暂时挂在学生会的内部记录项目下。我来整理路线和物资，你们别再独自调查。'
        if node['id']=='13':node['text']='包括我。联络表第一行，我写自己的号码。再去核查旧记录时，我会一起去。'
    save('data/story/ch1_1_5_after.json',story)
    # Redistribute existing light units, never add a second permanent blocker
    # requirement. One ranged defender must alternate support and main-lane fire.
    changes={3:{117:2},4:{90:2},5:{94.8:2,146.5:1,146.6:1}}
    for stage, assignments in changes.items():
        name=f'data/stages/ch1/1-{stage}.json'; data=load(name)
        for entry in data['enemySpawnTimeline']:
            if entry['time'] in assignments:
                entry['lane']=assignments[entry['time']]
        data['_round9Tactics']='2026-10-11: redistribute existing normal echoes into alternating side-lane pressure; total counts and heavy-unit lanes unchanged. Normal two-person clear must be revalidated.'
        save(name,data)
    print('Configured Rin support, replay choice, corrected internal-project story fact')
if __name__=='__main__':main()
