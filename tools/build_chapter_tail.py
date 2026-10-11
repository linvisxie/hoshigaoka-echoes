"""Chapter one content tables. Original dialogue; existing SSOT retained."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def read(p): return json.loads((ROOT/p).read_text(encoding='utf-8-sig'))
def write(p,obj): (ROOT/p).write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

chars=read('data/characters.json')
for c in chars['characters']:
    if c['id']=='ogawa_yui':
        c['skillIds']=['yui_small_light'];c['weaponType']='MEDICAL'
def ranged(cid,name,hp,atk,defense,interval,reach,cost,redep,skill,talent,weapon,unlock):
    return dict(id=cid,name=name,nameShort=name[-2:],grade='高一',club='科学部' if 'sara' in cid else '轻音部',classType=weapon,behavior='RANGED',roleTags=['RANGED','SUPPORT'],baseStats=dict(hp=hp,attack=atk,defense=defense),growthProfileId='growth_standard',attackInterval=interval,attackRange=dict(shape='lane_band',direction='forward',rangeTiles=reach,maxLaneDelta=0),blockCount=0,deployCost=cost,redeployTime=redep,damageType='SPECIAL',skillIds=[skill],talentIds=[talent],weaponType=weapon,unlockStage=unlock,spriteFramePx=96)
new=[ranged('minase_sara','水濑纱良',650,115,25,1.8,3.5,18,22,'sara_experiment','sara_analysis','DEVICE','1-8'),ranged('shiraishi_chinatsu','白石千夏',700,75,35,1.6,3,15,20,'chinatsu_beat','chinatsu_presence','GUITAR','1-10')]
for c in new:
    chars['characters']=[old for old in chars['characters'] if old['id']!=c['id']]+[c]
write('data/characters.json',chars)
skills=read('data/skills.json')
newskills=[dict(id='yui_small_light',name='不熄的灯',type='ACTIVE',effect='AREA_HEAL',cooldownSeconds=20,initialCooldownSeconds=20,healMultiplier=2.5,rangeTiles=3,maxLaneDelta=1,description='为治疗范围内所有友军恢复250%治疗力的生命。'),dict(id='sara_experiment',name='临时实验装置',type='ACTIVE',effect='DEVICE',cooldownSeconds=24,initialCooldownSeconds=24,durationSeconds=12,deviceHp=480,deviceDefense=60,deviceBlock=1,description='选择一个空部署格放置12秒实验装置；阻挡1，不能治疗，不占角色名额。'),dict(id='chinatsu_beat',name='放课后节拍',type='ACTIVE',effect='AREA_BUFF',cooldownSeconds=22,initialCooldownSeconds=22,durationSeconds=10,rangeTiles=2,maxLaneDelta=1,attackSpeedPct=.2,cdRecoveryPct=.1,description='附近友军10秒内攻速+20%、技能冷却恢复+10%。')]
skills['skills']=[s for s in skills['skills'] if s['id'] not in [x['id'] for x in newskills]]+newskills
talents=[dict(id='sara_analysis',name='分析完成',effect='ARMORED_SPECIAL',defenseThreshold=80,damageBonusPct=.15,splashRange=.75,splashMultiplier=.7,description='对防御≥80敌人特殊伤害+15%；普攻对同路0.75格内其他敌人溅射70%。'),dict(id='chinatsu_presence',name='不冷场',effect='AREA_SPEED',rangeTiles=2,maxLaneDelta=1,attackSpeedPct=.08,description='附近友军常驻攻速+8%，不包含自身。')]
skills['talents']=[s for s in skills['talents'] if s['id'] not in [x['id'] for x in talents]]+talents
write('data/skills.json',skills)
enemies=read('data/enemies.json')
def enemy(eid,name,hp,atk,defense,speed,interval,mechanic):
    return dict(id=eid,name=name,tier=2,tags=['MECHANISM'],weightClass='HEAVY',spriteFramePx=96,hp=hp,attack=atk,defense=defense,moveSpeed=speed,attackInterval=interval,attackRange='MELEE',coreDamage=1,abilityIds=[],mechanic=mechanic)
newenemies=[enemy('echo_anxiety','焦虑团块',520,55,30,.4,1.4,dict(kind='ANXIETY_AURA',radiusTiles=2,attackSpeedPct=-.15,cdRecoveryPct=-.1)),enemy('echo_rank','排名幽灵',380,45,20,.5,1.6,dict(kind='RANK_COMPARE',rangeTiles=3.5,intervalSeconds=8,durationSeconds=5,attackPct=-.15)),enemy('boss_model_student','无名优等生',8000,150,70,.18,2,dict(kind='CHAPTER_BOSS'))]
newenemies[0]['weightClass']='MEDIUM';newenemies[0]['spriteFramePx']=64
newenemies[1]['weightClass']='LIGHT';newenemies[1]['spriteFramePx']=64
newenemies[-1]['coreDamage']=3
newenemies[-1]['weightClass']='BOSS'
newenemies[-1]['spriteFramePx']=160
enemies['enemies']=[e for e in enemies['enemies'] if e['id']!='echo_ranking']
for e in newenemies: enemies['enemies']=[x for x in enemies['enemies'] if x['id']!=e['id']]+[e]
write('data/enemies.json',enemies)

names={6:'保健室的灯',7:'谁在第几名',8:'说不出口',9:'满分的复制品',10:'无名优等生'}
env={6:'bg_env_infirmary_battle',7:'bg_env_ranking_battle',8:'bg_env_science_battle',9:'bg_env_archive_battle',10:'bg_env_boss_exam'}
brief={6:'结衣的治疗跨越相邻路线。焦虑领域降低攻速和技能恢复，让结衣守在澪身后。',7:'排名幽灵每8秒削弱范围内攻击最高的角色。凛负责资源调度，悠真兼顾旁路。',8:'沉默只封锁主动技能。纱良用特殊伤害处理装甲，并用实验装置短暂补住旁路。',9:'作弊纸偶低生命时分裂一次。先处理远程与排名幽灵，为体育馆调查做好准备。',10:'无名优等生有三个阶段。红色错题预警持续3秒，可撤退或用治疗应对；核心被Boss触及即失败。'}
for n in range(6,11):
    roster=['amamiya_mio','kamiya_yuma','ogawa_yui','fujiwara_rin']
    if n==6:roster.remove('fujiwara_rin')
    if n>=8: roster+=['minase_sara']
    pool={6:['echo_normal','echo_anxiety','echo_runner','echo_exam_sheet'],7:['echo_normal','echo_rank','echo_armored','echo_runner'],8:['echo_silent','echo_armored','echo_normal','echo_exam_sheet'],9:['echo_copy','echo_rank','echo_silent','echo_armored','echo_exam_sheet'],10:['echo_normal','echo_armored','echo_exam_sheet','echo_silent']}[n]
    timeline=[]
    for wave in range(1,6):
        start=6+(wave-1)*38
        count=5 if wave<5 else 7
        for j in range(count):
            eid=pool[(j+wave-1)%len(pool)]
            # Heavy/special threats stay on the permanent front line. Alternating
            # side scouts are sparse enough for cross-lane Yuma, no second tank.
            lane=1
            if j==count-1 and wave>=2:
                eid='echo_normal';lane=0 if wave%2==0 else 2
            timeline.append(dict(time=round(start+j*3.4,2),lane=lane,enemy=eid,wave=wave))
    if n==10:
        timeline=[]
        for wave,count,start in [(1,20,6),(2,24,110),(3,26,220)]:
            for j in range(count):
                time=(6+j*4 if j<2 else 40+(j-2)*3.5) if wave==1 else start+j*4
                eid=['echo_normal','echo_armored','echo_normal','echo_exam_sheet'][j%4]
                lane=1
                if j>=4 and j%8==7:eid='echo_normal';lane=0 if (j//8+wave)%2 else 2
                timeline.append(dict(time=time,lane=lane,enemy=eid,wave=wave))
        timeline.append(dict(time=360,lane=1,enemy='boss_model_student',wave=4))
    cfg=dict(schemaVersion='1.0.0-v3-tail',domain='stage',stageId=f'1-{n}',chapter=1,stageName=names[n],mapId=env[n],coreHp=3,startingAp=10,apRegen=1,availableCharacters=roster,enemySpawnTimeline=timeline,tutorialTriggers=[dict(at=0,id=f'TUT_TAIL_{n}',text=brief[n])],specialRules=[],firstClearRewardId=f'reward_1_{n}_first',repeatRewardId='reward_repeat_standard',storyBefore=f'ch1_1_{n}_before',storyAfter=f'ch1_1_{n}_after',bossConfig={},battleRewards=dict(school_coin=160,study_record_short=2,equipment_part=2),briefing=brief[n],waves=[dict(number=i,label=['观测','异常加深','短暂喘息','核心残响','最终波'][i-1],clearCondition='ALL_ENEMIES_DEFEATED') for i in range(1,5 if n==10 else 6)])
    if n==10: cfg['bossConfig']=dict(enemyId='boss_model_student',phaseThresholds=[.6,.3],standardInterval=12,warningSeconds=3,comparisonInterval=15,comparisonDuration=5,comparisonPct=-.15,anxietyInterval=12,anxietyDuration=6,anxietySpeedPct=.3,mistakeInterval=18,mistakeDamage=220,mistakeRadius=1,rankingInterval=15,rankingDuration=6,rankingPct=-.25,finalMovePct=.4,finalAttackSpeedPct=.2,enrageSeconds=480)
    if n==10: cfg['bossConfig'].update(skillInherit='replace',phaseFirstCastSeconds=3,firstStandardSeconds=3,firstComparisonSeconds=5,finalSummonInterval=12)
    write(f'data/stages/ch1/1-{n}.json',cfg)
up=read('data/upgrades.json')
for n in range(6,11): up['openByStage'][f'1-{n}']=dict(opens=3 if n==10 else 2,triggerWaves=[1,2,3] if n==10 else [1,3])
write('data/upgrades.json',up)

# Original chapter dialogue, consistent with locked events and identities.
dialogue={
6:([
('','保健室的灯没有熄。窗外已经入夜，白色床帘却映着不属于月亮的紫光。'),('小川结衣','请先坐下。雨宫同学，你握刀的手在发抖。'),('雨宫澪','外面还有人。等调查结束再——'),('小川结衣','我也总这样说。等所有人都没事了，再想自己。'),('神谷悠真','床下的影子在往门口聚。这里恐怕也不是安全的地方。'),('小川结衣','那就让我和你们一起。至少这一次，不要有人独自撑着。'),('藤原凛','调整记录。结衣负责治疗，澪建立防线，悠真观察旁路。'),('{player}','门外还有声音。我们把灯留着。')],[('','最后一团影子散去，吊灯终于停止摇晃。'),('小川结衣','原来被人照顾的时候，也可以不用说对不起。'),('雨宫澪','你刚才也是。自己的伤口，还没包扎。'),('小川结衣','……被发现了。那可以请你帮我拿一下绷带吗？'),('藤原凛','观测会的紧急联络表，还缺一位保健委员。'),('小川结衣','写我的名字吧。但也要把你们自己的名字留在“需要帮助的人”那一栏。'),('','结衣关好药柜，没有熄灯。窗台上，一张无署名的排名表缓缓卷起。')]),
7:([('','成绩榜前没有学生，却有一排排影子在交换位置。每个名字上方，都压着另一个名字。'),('藤原凛','匿名比较帖已经传遍全年级。最初只有一张截图，现在连不参加测验的人也在转发。'),('神谷悠真','把人放在一列里，看起来就像只有一个方向可以走。'),('水濑纱良','异常频率和转发次数并不成正比。被反复删掉的留言，波形反而更高。'),('雨宫澪','你是科学部的？'),('水濑纱良','水濑纱良。我在找一个无法被平均值解释的东西。'),('藤原凛','先把榜前的残响清掉。我负责调度，别让那些名次替我们决定站位。')],[('','排名幽灵消散后，榜单上露出被胶带遮住的一行小字：缺考。'),('藤原凛','我一直以为，只要安排得够好，就不会有人掉队。'),('小川结衣','可有时候，大家需要的只是停下来等一等。'),('水濑纱良','有一段频率没有消失。它来自旧实验楼，不像在求一个答案。'),('{player}','像在等有人把问题听完。'),('','凛合上时间表，在下一栏写下了一个没有截止时间的任务。')]),
8:([('','实验楼的走廊异常安静。门后的玻璃器皿明明在震动，却没有发出声音。'),('水濑纱良','我尝试把频率转成文字。结果全是省略号。'),('神谷悠真','你刚才说向左，我听成了留在这里。'),('雨宫澪','所以那道门……是我们一起错过的。'),('小川结衣','别急着决定是谁的错。现在，我们再说一遍。'),('水濑纱良','我会加入战斗。这台装置可以撑住一小会儿，但不能代替雨宫前辈。'),('藤原凛','沉默封锁技能时，普通攻击仍然有效。留意装置的剩余时间。'),('{player}','这次，我会确认每一个人都听见。')],[('','封住门缝的黑色胶带一寸寸裂开。空教室里，终于传来椅子轻轻挪动的声音。'),('水濑纱良','我以为说得足够准确，就一定会被理解。'),('神谷悠真','有时候需要再问一句。'),('水濑纱良','那……刚才你们害怕吗？'),('雨宫澪','害怕。所以才需要告诉彼此。'),('水濑纱良','这一项，我不能用仪器代测。下次会直接问。'),('','纱良收好实验装置，把“情绪噪声”四个字划掉，改成了“尚未听懂的声音”。')]),
9:([('','旧档案室的抽屉全部打开。同一张满分答卷从不同年份里不断涌出，姓名栏却一片空白。'),('水濑纱良','笔迹来自不同的人，异常却只有一个中心。所有路径最后都指向体育馆。'),('藤原凛','历年的成绩档案都曾在那里公示。我们不是在追一个学生。'),('白石千夏','我从轻音部搬来一个小音箱。要是广播又把你们的声音盖住，就用这个。'),('小川结衣','千夏，你留在安全的出口等我们。不要一个人进异常里。'),('白石千夏','嗯。可是回来的时候，要记得叫我的名字。'),('{player}','我们会一起回来。先把通往体育馆的路清出来。')],[('','最后一个纸偶折成了普通的试卷。姓名栏里浮出一道橡皮擦过的痕迹。'),('水濑纱良','不是复制满分的人，是把不满分的部分一遍遍删掉。'),('雨宫澪','最后连名字也不要了吗。'),('藤原凛','体育馆的通行记录已经恢复。下一次调查，由我们全员一起去。'),('神谷悠真','别追着那个“第一”走。看着彼此就好。'),('','档案室门外，远处的考试铃响了。一次，接着一次，始终没有结束。')]),
10:([('','体育馆里的课桌排到了看不见的地方。成绩环在舞台上空旋转，每一次批改，都抹去一个名字。'),('无名优等生','再好一点。第一。满分。不能失败。'),('雨宫澪','它说话的时候……为什么听起来这么累。'),('水濑纱良','这些声音没有唯一来源。是所有人的期待，挤成了一个轮廓。'),('藤原凛','别被它的节奏带走。三秒红色预警，先看站位，再决定治疗或撤退。'),('小川结衣','如果撑不住，就告诉我。'),('神谷悠真','后方交给我。'),('白石千夏','出口的灯还亮着。我在这里等你们。'),('{player}','我们不是来交一张满分答卷。我们来把大家带回去。')],[('','红色圆环停止转动。试卷落在地上，没有燃烧，也没有碎裂。'),('无名优等生','如果……不是第一……'),('雨宫澪','也可以留下。'),('','层层成绩单之间，显出一个普通学生的剪影。没有名次，也没有奖状。'),('小川结衣','可以休息了。今天已经做得够多了。'),('水濑纱良','频率正在降低。不是归零……是重新分开，回到每个人身上。'),('藤原凛','调查结束。全员返回。'),('白石千夏','我听见啦！你们每个人的声音，我都听见了。'),('神谷悠真','那下次社团活动，也给你留个位子。'),('白石千夏','说好了。不要把我当作只有热闹的时候才需要的人。'),('{player}','欢迎加入，千夏。'),('','晨光穿过体育馆的高窗。走廊里，新一届文化祭的海报轻轻晃动。'),('','学生手册多出一页夹纸。背面只有一句话：你听见的，真的都是今天的声音吗？'),('','第一章 · 新学期的残响　完。\n放课后观测会的记录，还将继续。')])}
ids={'雨宫澪':'amamiya_mio','神谷悠真':'kamiya_yuma','小川结衣':'ogawa_yui','藤原凛':'fujiwara_rin','水濑纱良':'minase_sara','白石千夏':'shiraishi_chinatsu'}
for n,(before,after) in dialogue.items():
    for suffix,lines in [('before',before),('after',after)]:
        sid=f'ch1_1_{n}_{suffix}'
        cfg=dict(schemaVersion='1.0.0',domain='story',storyId=sid,chapterId='ch1',title=f'1-{n} · {names[n]}',background=env[n],music='observation_club' if suffix=='after' else 'corridor_pressure',authorship='Project original dialogue adapted from V2.1.4 locked chapter events.',completionFlags=['chapter_one_complete'] if n==10 and suffix=='after' else [],nodes=[dict(id=str(i),speaker=s,character=ids.get(s,''),text=t) for i,(s,t) in enumerate(lines)])
        if n==10 and suffix=='after':
            cfg['music']='chapter_one_coda'
            cfg['nodes'][3]['background']='bg_env_chapter_one_coda'
        cfg['title']+=' · 调查前' if suffix=='before' else ' · 调查后'
        write(f'data/story/{sid}.json',cfg)
print('Chapter tail tables written: 5 stages, 10 stories, 6 characters, 10 enemy types.')
