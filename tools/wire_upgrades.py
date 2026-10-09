from pathlib import Path
p = Path(__file__).resolve().parents[1] / 'scripts/domain/battle/stage_runtime.gd'
s = p.read_text(encoding='utf-8')

# 前置检查：新增字段名不得与既有成员冲突
assert s.count('var upgrades: InBattleUpgrades = null') == 1, 'field missing?'
for probe in ['func _atk_mult', 'func _defense_of_target', 'func _heal_mult']:
    assert s.count(probe) == 1, probe

def rep(old, new):
    global s
    assert s.count(old) == 1, (old[:70], s.count(old))
    s = s.replace(old, new, 1)

# ---- 追加两个阶段级 helper ----
rep('''func _apply_upgrades_to_instance(_c: CharacterRuntime) -> void:
	pass''',
'''func _apply_upgrades_to_instance(_c: CharacterRuntime) -> void:
	pass


## AP 自然回复倍率（阶段级；无强化系统时恒为 1.0）。
func _ap_regen_mult() -> float:
	if upgrades == null:
		return 1.0
	return upgrades.ap_regen_multiplier()''')

# ---- 消费点 1：AP 自然回复 ----
rep('''	if ap_regen_per_second > 0.0 and ap < ap_max:
		_ap_accumulator += ap_regen_per_second * step''',
'''	if ap_regen_per_second > 0.0 and ap < ap_max:
		# A0.6：局内强化只乘在回复**速率**上，累积器与取整逻辑完全不变
		_ap_accumulator += ap_regen_per_second * _ap_regen_mult() * step''')

# ---- 消费点 2：角色普攻攻击端 ----
rep('''	var atk := float(c.effective_attack())
	var dmg := combat_math.compute_damage(atk, target.defense, c.damage_type)''',
'''	# A0.6：攻击倍率乘在 effective_attack() 之后（减益夹取仍先生效，
	# 即「先按 L556 算有效攻击，再乘局内强化」，不绕过 40% 下限规则）
	var atk := float(c.effective_attack()) * _atk_mult(c)
	var dmg := combat_math.compute_damage(atk, target.defense, c.damage_type)''')

# ---- 消费点 3/4：敌人打角色（远程 + 阻挡），防御端吃前线防御强化 ----
rep('''		var dmg := combat_math.compute_damage(e.attack, target.defense, e.damage_type)''',
'''		var dmg := combat_math.compute_damage(e.attack, _defense_of_target(target), e.damage_type)''')
rep('''		var dmg := combat_math.compute_damage(e.attack, blocker.defense, e.damage_type)''',
'''		var dmg := combat_math.compute_damage(e.attack, _defense_of_target(blocker), e.damage_type)''')

# ---- 消费点 5：治疗量 ----
rep('''	var amount := c.compute_heal_amount()''',
'''	var amount := int(round(float(c.compute_heal_amount()) * _heal_mult(c)))''')

# ---- 消费点 6：撤退返还比例（只在调用方未显式指定 rate 时叠加）----
rep('''	var effective := retreat_refund_rate if rate < 0.0 else rate''',
'''	var effective := retreat_refund_rate if rate < 0.0 else rate
	# A0.6：「快速换防」提高默认返还比例；调用方显式传入 rate 时以传入值为准
	# （供未来角色天赋/局内强化按来源覆写，见 L2040 撤退比例的覆写设计）。
	if upgrades != null and rate < 0.0:
		effective = upgrades.retreat_refund_rate(retreat_refund_rate)''')

p.write_text(s, encoding='utf-8')
print('StageRuntime upgrade consumption wired (6 points)')
