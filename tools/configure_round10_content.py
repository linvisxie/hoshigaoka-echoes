from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]
def update(file, edit):
 path=ROOT/file
 value=json.loads(path.read_text(encoding='utf8'))
 edit(value)
 path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
def characters(data):
 for c in data['characters']:
  if c['id']=='kamiya_yuma': c['weaponType']='BOW'
  if c['id']=='amamiya_mio': c['weaponType']='SWORD'
def equipment(data):
 for t in data['equipment']:
  if t['id']=='equip_ch1_1_2_fine_weapon': t['allowedWeaponTypes']=['BOW']
copy={
 'school_coin':('用于角色突破与装备强化。','把黄昏攒进口袋，留给明日的约定。'),
 'study_record':('投入学习记录，为角色积累成长经验。','纸页记得的微光，终会照亮前行的你。'),
 'club_badge':('用于角色突破，拓展成长上限。','别在胸前的星花，是我们并肩的证明。'),
 'echo_crystal':('角色高阶突破所需的残响材料。','碎裂的时间里，仍有未曾熄灭的回声。'),
 'equipment_part':('用于装备强化，提升装备属性。','将散落的齿轮，拼成守护日常的力量。'),
}
def currencies(data):
 for c in data['currencies']:
  c['uiDescription'],c['flavorText']=copy[c['id']]
update('data/characters.json',characters)
update('data/equipment.json',equipment)
update('data/currencies.json',currencies)
