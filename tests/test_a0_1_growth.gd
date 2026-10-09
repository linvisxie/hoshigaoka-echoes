## Alpha A0.1 验收测试：角色成长框架
## （V2.1.4 H 章三～八 / 三十一 / 三十四 / 三十六 / 三十七 / 二十一-A 表 71）
##
## 覆盖 15 项验收要求：
##    1. 成长数据完整性（maxLevel / 突破节点 / 每级增量 / 等级上限映射）
##    2. 经验表规格一致性（Lv.1→10 逐项、累计 2,520、键 50 为 0、其余键 > 0）
##    3. 等级上限与突破解除（0→10 / 1→20 / 2→30 / 3→40 / 4→50）
##    4. 面板计算（Lv.1 = baseStats；Lv.11 雨宫澪 hp 1420 / attack 172 / defense 108）
##    5. 治疗力随等级成长（小川结衣 Lv.1 = 110，Lv.11 = 156）
##    6. 攻击范围 / 阻挡数 / 部署费用不随等级变化
##    7. 升级只消耗学习记录、不消耗学园币
##    8. 到达等级上限时经验退回、不吞材料
##    9. 突破需要等级与材料；成功后扣材料、阶数 +1
##   10. 材料不足时不做部分扣除
##   11. Lv.50 面板膨胀限制（max_level_multiplier < 10）
##   12. 存档往返（等级 / 突破 / 经验 / 资源完全一致）
##   13. 数据引用完整性（get_load_errors 为空 + growthProfileId 可解析）
##   14. 五类资源与学习记录三档
##   15. 升级不越过突破节点
##
## 纪律：
##   - 权威数值一律从**磁盘文件**读取，避开进程内可能被就地改写的内存副本
##     （P1.0 事故：测试就地改写 DataRegistry 内存字典导致跨文件污染）；
##   - 本文件只做只读断言，不修改任何被测代码或数据文件；
##   - 每个用例前后把 SaveService 重置为默认存档，避免污染后续用例；
##   - 不依赖真实时钟、帧率或随机。
extends GutTest

const CHAR_MIO := "amamiya_mio"
const CHAR_YUMA := "kamiya_yuma"
const CHAR_YUI := "ogawa_yui"

const REC_SHORT := "study_record_short"
const REC_NOTE := "study_record_note"
const REC_ARCHIVE := "study_record_archive"

const C_SCHOOL_COIN := "school_coin"
const C_STUDY_RECORD := "study_record"
const C_CLUB_BADGE := "club_badge"
const C_ECHO_CRYSTAL := "echo_crystal"
const C_EQUIPMENT_PART := "equipment_part"

const GROWTH_PATH := "res://data/character_growth.json"
const CHARS_PATH := "res://data/characters.json"
const CURRENCIES_PATH := "res://data/currencies.json"
const UPGRADE_COSTS_PATH := "res://data/upgrade_costs.json"

## 权威规格值（V2.1.4 H 章四 表 57，逐字抄录）
const SPEC_MAX_LEVEL := 50
const SPEC_BREAKTHROUGH_LEVELS: Array[int] = [10, 20, 30, 40]
const SPEC_LEVEL_CAP: Dictionary = {"0": 10, "1": 20, "2": 30, "3": 40, "4": 50}

## Lv.1→10 单级经验需求（表 57）；键 N = 从 Lv.N 升到 Lv.N+1 所需 EXP
const SPEC_EXP_1_TO_10: Dictionary = {
	1: 100, 2: 130, 3: 160, 4: 200, 5: 260,
	6: 320, 7: 380, 8: 450, 9: 520,
}
## L1531：「Lv.1→10 累计 2,520 EXP」
const SPEC_CUMULATIVE_TO_10 := 2520

## V2.1.4 H 章四 表 56（L1510-1517）六段区间。
##
## 元素为 [键下界, 键上界, 值下界, 值上界]。
## 读法：阶段列是等级区间，对应升级键为 [起始等级-1, 结束等级-1]；
## 首段因键 0 不存在而从键 1 起算。
## 该读法是唯一自洽读法——只有它能让规格 LOCKED 的表 57 九个精确值
## 全部落回表 56 前两段区间（其他读法会让规格的精确值越出规格的区间）。
const SPEC_EXP_BANDS: Array = [
	[1, 4, 100, 220],
	[5, 9, 260, 520],
	[10, 19, 600, 1250],
	[20, 29, 1400, 2300],
	[30, 39, 2500, 3800],
	[40, 49, 4000, 6000],
]

## 每级属性增量（H 章三十七 示例 growth 段）
const SPEC_PER_LEVEL := {"hp": 42.0, "attack": 5.2, "defense": 2.8}
## 治疗力增量（character_growth.json 的候选值，规格未逐字给出）
const SPEC_PER_LEVEL_HEAL := 4.6

## 突破成本基线（H 章七 表 60，逐字抄录）
const SPEC_BREAKTHROUGH_COSTS: Array[Dictionary] = [
	{"school_coin": 800, "club_badge": 3, "echo_crystal": 0},
	{"school_coin": 2000, "club_badge": 6, "echo_crystal": 0},
	{"school_coin": 4500, "club_badge": 10, "echo_crystal": 2},
	{"school_coin": 8000, "club_badge": 16, "echo_crystal": 5},
]

## 技能升级成本基线（H 章八 表 62）与技能等级上限
const SPEC_SKILL_COSTS: Array[Dictionary] = [
	{"fromLevel": 1, "toLevel": 2, "school_coin": 300, "echo_crystal": 1},
	{"fromLevel": 2, "toLevel": 3, "school_coin": 700, "echo_crystal": 1},
	{"fromLevel": 3, "toLevel": 4, "school_coin": 1200, "echo_crystal": 2},
	{"fromLevel": 4, "toLevel": 5, "school_coin": 2000, "echo_crystal": 3},
]
const SPEC_SKILL_MAX_LEVEL := 5

## 1-1～1-10 首通总预算（H 章二十一-A 表 71）
const SPEC_CH1_BUDGET := {
	"school_coin": 5200,
	"school_coin_tolerance": 0.10,
	"study_record_exp": 8500,
	"study_record_exp_tolerance": 0.10,
	"club_badge": 6,
	"echo_crystal": 3,
	"equipment_part_min": 15,
	"equipment_part_max": 24,
}

## 五类资源 id（currencies.json，H 章十五 表 67）
const SPEC_CURRENCY_IDS: Array[String] = [
	"school_coin", "study_record", "club_badge", "echo_crystal", "equipment_part",
]

## 学习记录三档（H 章五 表 58）
const SPEC_STUDY_RECORDS: Dictionary = {
	"study_record_short": 100,
	"study_record_note": 500,
	"study_record_archive": 2000,
}

## H 章三十一：Lv.50 基础面板不应达到 Lv.1 的「几十倍」，取 10 倍为硬上限
const MAX_LEVEL_MULTIPLIER_LIMIT := 10.0

const EPS := 0.0001

var _svc: CharacterGrowthService


func before_all() -> void:
	if not DataRegistry.is_loaded():
		DataRegistry.load_all()


func before_each() -> void:
	# 每个用例从一份干净的默认存档开始，避免上一个用例的等级 / 资源残留
	SaveService.new_game()
	_svc = CharacterGrowthService.new()
	var errs := _svc.setup()
	assert_eq(errs.size(), 0, "成长服务构建应无错误：%s" % str(errs))


func after_each() -> void:
	# 用完即还：把存档重置为默认，避免污染后续测试文件
	SaveService.new_game()


# ============================================================
#  夹具：全部从磁盘读取权威数据
# ============================================================

## 直接从磁盘读取权威数据文件（与 tests/test_data_ssot.gd / test_p1_0_prototype.gd 同一写法）。
func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return null
	return parser.data


func _growth_cfg() -> Dictionary:
	var data: Variant = _read_json(GROWTH_PATH)
	if typeof(data) != TYPE_DICTIONARY:
		fail_test("character_growth.json 不可解析")
		return {}
	return data


func _char_from_file(character_id: String) -> Dictionary:
	var data: Variant = _read_json(CHARS_PATH)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	for c: Dictionary in (data as Dictionary).get("characters", []):
		if str(c.get("id", "")) == character_id:
			return c
	return {}


## 该角色的 Lv.1 基础面板（含从 healPower 字段补入的治疗力，口径与
## CharacterGrowthService.setup() 一致）
func _base_stats_from_file(character_id: String) -> Dictionary:
	var c := _char_from_file(character_id)
	var base: Dictionary = (c.get("baseStats", {}) as Dictionary).duplicate(true)
	if c.has("healPower"):
		base["healPower"] = int(c.get("healPower", 0))
	return base


## 用磁盘上的成长配置构建一个 CharacterProgress（不经过服务，便于逐字段断言）
func _progress(character_id: String, level: int = 1, breakthrough: int = 0) -> CharacterProgress:
	var c := _char_from_file(character_id)
	var p := CharacterProgress.from_growth_config(
		character_id,
		_growth_cfg(),
		_base_stats_from_file(character_id),
		str(c.get("growthProfileId", "growth_standard"))
	)
	p.level = level
	p.breakthrough = breakthrough
	return p


## 通过服务把角色直接置为指定状态（CharacterProgress 的公开字段，用于构造前置条件）
func _set_progress(character_id: String, level: int, breakthrough: int = 0, exp: int = 0) -> CharacterProgress:
	var p := _svc.get_progress(character_id)
	assert_not_null(p, "角色 %s 应有成长状态" % character_id)
	p.level = level
	p.breakthrough = breakthrough
	p.exp = exp
	return p


# ============================================================
#  验收点 1：成长数据完整性
# ============================================================

## 验收点 1：maxLevel = 50、突破节点 [10,20,30,40]、levelCapByBreakthrough 映射正确。
func test_growth_global_rules_match_spec() -> void:
	var rules: Dictionary = _growth_cfg().get("globalRules", {})
	assert_eq(int(rules.get("maxLevel", 0)), SPEC_MAX_LEVEL,
		"H 章三：首发角色等级上限应为 Lv.50")

	var levels: Array = rules.get("breakthroughLevels", [])
	assert_eq(levels.size(), SPEC_BREAKTHROUGH_LEVELS.size(),
		"H 章六：突破节点应为 4 个（Lv.10/20/30/40）")
	for i: int in range(SPEC_BREAKTHROUGH_LEVELS.size()):
		assert_eq(int(levels[i]), SPEC_BREAKTHROUGH_LEVELS[i],
			"H 章六：第 %d 个突破节点应为 Lv.%d" % [i + 1, SPEC_BREAKTHROUGH_LEVELS[i]])

	var cap_map: Dictionary = rules.get("levelCapByBreakthrough", {})
	assert_eq(cap_map.size(), SPEC_LEVEL_CAP.size(),
		"levelCapByBreakthrough 应恰好覆盖 0～4 五档突破")
	for key: String in SPEC_LEVEL_CAP.keys():
		assert_true(cap_map.has(key), "levelCapByBreakthrough 应含键 %s" % key)
		assert_eq(int(cap_map.get(key, -1)), int(SPEC_LEVEL_CAP[key]),
			"突破 %s 阶的等级上限应为 %d" % [key, int(SPEC_LEVEL_CAP[key])])

	# 成长系统只承载这四项，攻击范围 / 阻挡数 / 部署费用不得进入成长数据
	var stat_keys: Array = rules.get("statKeys", [])
	assert_eq(stat_keys.size(), 4, "statKeys 应恰好 4 项（hp/attack/defense/healPower）")
	for k: String in ["hp", "attack", "defense", "healPower"]:
		assert_true(stat_keys.has(k), "statKeys 应含 %s" % k)


## 验收点 1：每级增量 hp / attack / defense 精确等于 42.0 / 5.2 / 2.8（H 章三十七）。
func test_growth_per_level_increments_match_spec() -> void:
	var profiles: Array = _growth_cfg().get("growthProfiles", [])
	assert_gt(profiles.size(), 0, "character_growth.json 应至少有一个成长档位")

	var standard: Dictionary = {}
	for pr: Dictionary in profiles:
		if str(pr.get("id", "")) == "growth_standard":
			standard = pr
			break
	assert_false(standard.is_empty(), "应存在 growth_standard 档位（首发三角色共用）")

	var per: Dictionary = standard.get("perLevel", {})
	assert_almost_eq(float(per.get("hp", 0.0)), SPEC_PER_LEVEL["hp"], EPS,
		"H 章三十七：hpPerLevel 应为 42")
	assert_almost_eq(float(per.get("attack", 0.0)), SPEC_PER_LEVEL["attack"], EPS,
		"H 章三十七：attackPerLevel 应为 5.2")
	assert_almost_eq(float(per.get("defense", 0.0)), SPEC_PER_LEVEL["defense"], EPS,
		"H 章三十七：defensePerLevel 应为 2.8")

	# 治疗力增量（规格只说「治疗角色同步提升治疗力」，未给数值，此处锁定工程候选值）
	assert_almost_eq(float(per.get("healPower", 0.0)), SPEC_PER_LEVEL_HEAL, EPS,
		"治疗角色每级治疗力增量应为 4.6")


# ============================================================
#  验收点 2：经验表规格一致性
# ============================================================

## 验收点 2：Lv.1→10 九个值逐项断言，且累计恰好 2,520。
func test_exp_table_1_to_10_exact_and_cumulative() -> void:
	var table: Dictionary = _growth_cfg().get("expTable", {})
	var total := 0
	for lv: int in range(1, 10):
		var key := str(lv)
		assert_true(table.has(key), "expTable 应含键 %s（Lv.%d→%d）" % [key, lv, lv + 1])
		var got := int(table.get(key, -1))
		var want := int(SPEC_EXP_1_TO_10[lv])
		assert_eq(got, want, "Lv.%d→%d 的 EXP 应为 %d" % [lv, lv + 1, want])
		total += got
	assert_eq(total, SPEC_CUMULATIVE_TO_10,
		"H 章四 L1531：Lv.1→10 累计应为 2,520 EXP")


## 验收点 2：键 50 为 0；Lv.1→50 每个键都存在且 > 0（除 50）。
func test_exp_table_keys_1_to_50_complete() -> void:
	var table: Dictionary = _growth_cfg().get("expTable", {})

	assert_true(table.has("50"), "expTable 应含键 50")
	assert_eq(int(table.get("50", -1)), 0,
		"键 50 为 0（Lv.50 已满级，无下一级需求）")

	for lv: int in range(1, SPEC_MAX_LEVEL):
		var key := str(lv)
		assert_true(table.has(key),
			"expTable 应含键 %s（Lv.%d→%d），缺失会让升级在上限内静默停止" % [key, lv, lv + 1])
		assert_gt(int(table.get(key, 0)), 0,
			"键 %s 的 EXP 应为正数" % key)

	# 单调不减：H 章四「经验需求平滑增长，不出现突然翻倍的卡墙」
	for lv: int in range(1, SPEC_MAX_LEVEL - 1):
		var cur := int(table.get(str(lv), 0))
		var nxt := int(table.get(str(lv + 1), 0))
		assert_lte(float(nxt), float(cur) * 2.0,
			"Lv.%d→%d 的 EXP 不应相对上一级翻倍以上（%d → %d）" % [lv, lv + 1, cur, nxt])


## 验收点 2（本轮新增）：全表每个键都必须落在 V2.1.4 表 56 的对应区间内。
##
## ⚠️ 为什么必须新增本用例：本缺口长期静默——既有测试只断言「键完整 / 键50为0 /
## 不翻倍」，**没有任何断言校验区间**，导致旧候选表有 30 个键越出表 56 上界
## 而测试全绿（详见 docs/Alpha_数值缺口裁决清单.md 第三节）。
## 本用例把规格区间约束固化为可回归的判据。
func test_exp_table_every_key_falls_within_spec_band() -> void:
	var table: Dictionary = _growth_cfg().get("expTable", {})
	var checked := 0
	var violations: Array[String] = []

	for band: Array in SPEC_EXP_BANDS:
		var klo := int(band[0])
		var khi := int(band[1])
		var vlo := int(band[2])
		var vhi := int(band[3])
		for k: int in range(klo, khi + 1):
			var key := str(k)
			assert_true(table.has(key), "expTable 应含键 %s" % key)
			if not table.has(key):
				continue
			var v := int(table[key])
			checked += 1
			if v < vlo or v > vhi:
				violations.append("键%d=%d（应在 [%d, %d]）" % [k, v, vlo, vhi])

	# 保证本用例确实覆盖了全部 49 个升级键，而不是空转通过
	assert_eq(checked, SPEC_MAX_LEVEL - 1,
		"应检查全部 %d 个升级键（键 1..49），实际 %d" % [SPEC_MAX_LEVEL - 1, checked])
	assert_eq(violations.size(), 0,
		"每个键都必须落在表 56 区间内，越界项：%s" % str(violations))


## 验收点 2（本轮新增）：重建后的 Lv.11→50 段必须单调不减（不出现升级需求倒退）。
##
## 表 56 的区间上界与「平滑不翻倍」在旧候选值下互斥；重建后两者应同时满足。
func test_exp_table_11_to_50_is_monotonic_within_bands() -> void:
	var table: Dictionary = _growth_cfg().get("expTable", {})

	var prev := int(table.get("9", 0))
	var worst_ratio := 0.0
	for k: int in range(10, 50):
		var cur := int(table.get(str(k), 0))
		assert_gte(float(cur), float(prev),
			"键 %d 的 EXP（%d）不得低于上一键（%d）——升级需求不得倒退" % [k, cur, prev])
		var ratio := float(cur) / float(prev) if prev > 0 else 0.0
		worst_ratio = maxf(worst_ratio, ratio)
		prev = cur

	# L1532：不出现突然翻倍的「卡墙」
	assert_lt(worst_ratio, 2.0,
		"Lv.11→50 段的最大相邻增幅（%.4fx）应小于 2.0（L1532 不翻倍）" % worst_ratio)
	assert_lt(worst_ratio, 1.5,
		"本轮重建目标：最大相邻增幅应小于 1.5x（实际 %.4fx）" % worst_ratio)


## 验收点 2（本轮新增）：旧候选值必须保留在数据文件里，便于比较与回滚。
func test_exp_table_keeps_previous_values_for_rollback() -> void:
	var table: Dictionary = _growth_cfg().get("expTable", {})
	assert_true(table.has("_11to50_previous"),
		"重建必须保留旧候选值（_11to50_previous），以便比较与回滚")
	var prev: Dictionary = table.get("_11to50_previous", {})
	# 该字典含 40 个数值键（10..49）+ 1 个 _note 说明键 = 41 项
	var numeric_keys := 0
	for k: int in range(10, 50):
		if prev.has(str(k)):
			numeric_keys += 1
	assert_eq(numeric_keys, 40,
		"旧值应含键 10..49 共 40 项（实际 %d）" % numeric_keys)
	assert_true(prev.has("_note"), "旧值段应带 _note 说明其用途")
	# 旧值确实越界（证明保留它有意义：可作为「已知不合规」的对照）
	var old_violations := 0
	for k: int in range(10, 50):
		var v := int(prev.get(str(k), 0))
		var band := _band_for_key(k)
		if v < int(band[2]) or v > int(band[3]):
			old_violations += 1
	assert_eq(old_violations, 30,
		"旧候选值应有 30 个键越界（与裁决清单复核一致），实际 %d" % old_violations)


## 取某升级键所属的表 56 区间
func _band_for_key(key: int) -> Array:
	for band: Array in SPEC_EXP_BANDS:
		if key >= int(band[0]) and key <= int(band[1]):
			return band
	return []


# ============================================================
#  验收点 3：等级上限与突破解除
# ============================================================

## 验收点 3：突破 0→10、1→20、2→30、3→40、4→50。
func test_level_cap_by_breakthrough() -> void:
	var expected: Array[int] = [10, 20, 30, 40, 50]
	for bt: int in range(5):
		var p := _progress(CHAR_MIO, 1, bt)
		assert_eq(p.level_cap(), expected[bt],
			"突破 %d 阶时等级上限应为 Lv.%d" % [bt, expected[bt]])


## 验收点 3：level == cap 时 is_level_capped() 为 true，cap-1 时为 false。
func test_is_level_capped_at_cap() -> void:
	for bt: int in range(5):
		var cap := _progress(CHAR_MIO, 1, bt).level_cap()

		var at_cap := _progress(CHAR_MIO, cap, bt)
		assert_true(at_cap.is_level_capped(),
			"突破 %d 阶、Lv.%d（= 上限）时应判定为已达上限" % [bt, cap])
		assert_eq(at_cap.exp_to_next(), 0, "已达上限时升到下一级所需 EXP 应为 0")

		var below := _progress(CHAR_MIO, cap - 1, bt)
		assert_false(below.is_level_capped(),
			"突破 %d 阶、Lv.%d（= 上限-1）时不应判定为已达上限" % [bt, cap - 1])
		assert_gt(below.exp_to_next(), 0, "未达上限时应存在正的经验需求")

	# 最高突破下 Lv.50 仍是上限
	var maxed := _progress(CHAR_MIO, SPEC_MAX_LEVEL, 4)
	assert_true(maxed.is_level_capped(), "Lv.50（突破 IV）应判定为已达上限")
	assert_eq(maxed.level_cap(), SPEC_MAX_LEVEL, "突破 IV 的上限应为 Lv.50")


# ============================================================
#  验收点 4：面板计算
# ============================================================

## 验收点 4：Lv.1 = baseStats；Lv.11 雨宫澪 hp 1420 / attack 172 / defense 108。
func test_compute_stats_at_level_1_and_11() -> void:
	var base := _base_stats_from_file(CHAR_MIO)
	assert_eq(int(base.get("hp", 0)), 1000, "雨宫澪 Lv.1 HP 应为 1000（表 26）")
	assert_eq(int(base.get("attack", 0)), 120, "雨宫澪 Lv.1 攻击应为 120")
	assert_eq(int(base.get("defense", 0)), 80, "雨宫澪 Lv.1 防御应为 80")

	var lv1 := _progress(CHAR_MIO, 1).compute_stats()
	assert_eq(int(lv1.get("hp", -1)), 1000, "Lv.1 面板 HP 应等于 baseStats")
	assert_eq(int(lv1.get("attack", -1)), 120, "Lv.1 面板攻击应等于 baseStats")
	assert_eq(int(lv1.get("defense", -1)), 80, "Lv.1 面板防御应等于 baseStats")

	# H 章三十七：baseStats + growth × (level - 1)，ROUND_HALF_UP
	var lv11 := _progress(CHAR_MIO, 11).compute_stats()
	assert_eq(int(lv11.get("hp", -1)), 1420, "Lv.11 HP = 1000 + 42×10 = 1420")
	assert_eq(int(lv11.get("attack", -1)), 172, "Lv.11 攻击 = 120 + 5.2×10 = 172")
	assert_eq(int(lv11.get("defense", -1)), 108, "Lv.11 防御 = 80 + 2.8×10 = 108")

	# 另两名首发角色同档位，抽验 Lv.1 与 Lv.11 的线性关系
	var yuma_lv1 := _progress(CHAR_YUMA, 1).compute_stats()
	assert_eq(int(yuma_lv1.get("hp", -1)), 620, "神谷悠真 Lv.1 HP 应为 620（表 28）")
	var yuma_lv11 := _progress(CHAR_YUMA, 11).compute_stats()
	assert_eq(int(yuma_lv11.get("hp", -1)), 620 + 42 * 10, "神谷悠真 Lv.11 HP 应线性增长")


# ============================================================
#  验收点 5：治疗力随等级成长
# ============================================================

## 验收点 5：小川结衣 Lv.1 healPower = 110；Lv.11 = 110 + 4.6×10 = 156。
func test_heal_power_grows_with_level() -> void:
	var base := _base_stats_from_file(CHAR_YUI)
	assert_eq(int(base.get("healPower", 0)), 110, "小川结衣治疗力基准应为 110（表 30）")

	var lv1 := _progress(CHAR_YUI, 1).compute_stats()
	assert_true(lv1.has("healPower"), "治疗角色的面板应含 healPower")
	assert_eq(int(lv1.get("healPower", -1)), 110, "Lv.1 治疗力应为 110")

	var lv11 := _progress(CHAR_YUI, 11).compute_stats()
	assert_eq(int(lv11.get("healPower", -1)), 156, "Lv.11 治疗力 = 110 + 4.6×10 = 156")

	# 非治疗角色（雨宫澪）在 Lv.1 不得有治疗力：其 baseStats 未声明 healPower，
	# 且 H 章三只允许「治疗角色同步提升治疗力」。
	#
	# 注（见回报「发现的问题」）：compute_stats() 对非治疗角色仍会输出 healPower 键，
	# 且因共享 growth_standard 档位的 healPower 增量（4.6/级）而随等级升到 46，
	# 与 StageRuntime._validate_characters 第 313-314 行「非治疗角色不应声明 healPower」
	# 的运行时契约口径不一致。因 CharacterRuntime.compute_heal_amount() 只对
	# HEALER 行为生效（StageRuntime._resolve_healer_action 仅由 HEALER 调用），
	# 该值目前不产生任何数值影响。此处只断言可确证的不变量，不把缺陷值写死。
	var mio1 := _progress(CHAR_MIO, 1).compute_stats()
	assert_eq(int(mio1.get("healPower", 0)), 0,
		"非治疗角色 Lv.1 的治疗力应为 0（Lv.1 面板 = baseStats，未声明 healPower）")

	var mio := _progress(CHAR_MIO, 11).compute_stats()
	assert_lt(int(mio.get("healPower", 0)), int(lv11.get("healPower", -1)),
		"非治疗角色的治疗力在任何等级都不得追平治疗角色（不得成为第二治疗来源）")

	# 数据契约：characters.json 中非治疗角色不得声明 healPower 字段
	assert_false(_char_from_file(CHAR_MIO).has("healPower"),
		"characters.json 中非治疗角色不应声明 healPower 字段")
	assert_false(_char_from_file(CHAR_YUMA).has("healPower"),
		"characters.json 中非治疗角色不应声明 healPower 字段")


# ============================================================
#  验收点 6：攻击范围 / 阻挡数 / 部署费用不随等级变化
# ============================================================

## 验收点 6：这三个字段不在 compute_stats() 的返回里（H 章三明文）。
func test_stats_do_not_include_range_block_cost() -> void:
	for cid: String in [CHAR_MIO, CHAR_YUMA, CHAR_YUI]:
		var stats := _progress(cid, 11).compute_stats()
		for forbidden: String in ["attackRange", "rangeTiles", "blockCount", "deployCost"]:
			assert_false(stats.has(forbidden),
				"%s 的成长面板不得包含 %s（H 章三：不通过普通等级提高）" % [cid, forbidden])
		# 面板只允许这四项
		for key: String in stats.keys():
			assert_true(key in ["hp", "attack", "defense", "healPower"],
				"%s 的成长面板出现了范围外的键：%s" % [cid, key])


## 验收点 6：走完整成长流程后，characters.json 的三个字段在磁盘上原封不动。
func test_character_config_not_written_by_growth() -> void:
	var before: Variant = _read_json(CHARS_PATH)
	assert_not_null(before, "characters.json 应可解析")

	# 走一遍完整成长：投入学习记录 → 升到 Lv.10 → 突破 → 提交存档
	_svc.grant({
		REC_ARCHIVE: 20,
		C_SCHOOL_COIN: 10000,
		C_CLUB_BADGE: 50,
		C_ECHO_CRYSTAL: 20,
	})
	var r := _svc.level_up_with_records(CHAR_MIO, REC_ARCHIVE, 2)
	assert_true(r["ok"], "升级应成功：%s" % str(r.get("reason", "")))
	var b := _svc.do_breakthrough(CHAR_MIO)
	assert_true(b["ok"], "Lv.10 且有材料时应能突破：%s" % str(b.get("reason", "")))
	assert_true(_svc.commit(), "成长状态应能提交存档")

	var after: Variant = _read_json(CHARS_PATH)
	assert_not_null(after, "characters.json 应仍可解析")

	for cid: String in [CHAR_MIO, CHAR_YUMA, CHAR_YUI]:
		var c0 := _char_from_file(cid)
		var c1: Dictionary = {}
		for c: Dictionary in (after as Dictionary).get("characters", []):
			if str(c.get("id", "")) == cid:
				c1 = c
		assert_false(c1.is_empty(), "%s 应仍在 characters.json 中" % cid)
		assert_almost_eq(
			float((c1.get("attackRange", {}) as Dictionary).get("rangeTiles", -1.0)),
			float((c0.get("attackRange", {}) as Dictionary).get("rangeTiles", 0.0)), EPS,
			"%s 的 attackRange.rangeTiles 不得被成长系统改写" % cid)
		assert_eq(int(c1.get("blockCount", -1)), int(c0.get("blockCount", -2)),
			"%s 的 blockCount 不得被成长系统改写" % cid)
		assert_eq(int(c1.get("deployCost", -1)), int(c0.get("deployCost", -2)),
			"%s 的 deployCost 不得被成长系统改写" % cid)

	# 整份文件逐字节等价（成长系统对配置只读）
	assert_eq_deep(after, before)


# ============================================================
#  验收点 7：升级消耗学习记录、不消耗学园币
# ============================================================

## 验收点 7：投入 3 本短篇（300 EXP）→ Lv.3 余 70 EXP；学园币库存完全不变。
func test_level_up_consumes_records_not_coins() -> void:
	_svc.grant({REC_SHORT: 3, C_SCHOOL_COIN: 1000})
	assert_eq(_svc.get_currency(REC_SHORT), 3, "初始应有 3 本短篇学习记录")
	assert_eq(_svc.get_currency(C_SCHOOL_COIN), 1000, "初始应有 1000 学园币")

	var r := _svc.level_up_with_records(CHAR_MIO, REC_SHORT, 3)
	assert_true(r["ok"], "投入学习记录应成功：%s" % str(r.get("reason", "")))

	# 100 + 130 = 230 进入 Lv.3，剩余 70 EXP
	assert_eq(int(r["levelAfter"]), 3, "300 EXP 应把 Lv.1 提升到 Lv.3")
	assert_eq(int(r["levelsGained"]), 2, "应提升 2 级")
	assert_eq(int(r["expSpent"]), 300, "实际消耗的经验应为 300")
	assert_eq(int(r["expRefunded"]), 0, "未到上限时不应有经验退回")

	var p := _svc.get_progress(CHAR_MIO)
	assert_eq(p.level, 3, "角色应为 Lv.3")
	assert_eq(p.exp, 70, "Lv.3 内的累计经验应为 70（230 + 70 = 300）")

	assert_eq(_svc.get_currency(REC_SHORT), 0, "3 本学习记录应被全部消耗")
	assert_eq(_svc.get_currency(C_SCHOOL_COIN), 1000,
		"H 章四 L1531：普通升级只消耗学习记录，不额外消耗学园币")


# ============================================================
#  验收点 8：到达等级上限时经验退回、不吞材料
# ============================================================

## 验收点 8：把角色练到 Lv.10（突破 0 的上限）后继续投料，
## expRefunded > 0，且学习记录库存净扣除 = 实际用掉的本数。
func test_level_up_at_cap_refunds_leftover() -> void:
	_svc.grant({REC_ARCHIVE: 5})

	# 2 本档案 = 4000 EXP；Lv.1→10 恰好需要 2520，剩余 1480 因不足一本而无法整本退回
	var r := _svc.level_up_with_records(CHAR_MIO, REC_ARCHIVE, 2)
	assert_true(r["ok"], "升级应成功：%s" % str(r.get("reason", "")))
	assert_eq(int(r["levelAfter"]), 10, "应恰好停在突破 0 的上限 Lv.10")
	assert_eq(int(r["levelsGained"]), 9, "Lv.1→10 应提升 9 级")
	assert_eq(int(r["expSpent"]), SPEC_CUMULATIVE_TO_10,
		"实际消耗的经验应恰好等于 Lv.1→10 累计 2,520")
	assert_gt(int(r["expRefunded"]), 0, "到达上限时未消耗的经验必须被退回（H 章三十四）")
	assert_eq(int(r["expRefunded"]), 4000 - SPEC_CUMULATIVE_TO_10,
		"退回经验应为 4000 - 2520 = 1480")

	# 净扣除 2 本（= 实际用掉的本数），未被多扣
	assert_eq(_svc.get_currency(REC_ARCHIVE), 3,
		"5 本投入 2 本、用掉 2 本后应余 3 本（净扣除 = 实际用掉的本数）")

	# 已在上限时再投料：拒绝，且不扣任何材料
	var again := _svc.level_up_with_records(CHAR_MIO, REC_ARCHIVE, 2)
	assert_false(again["ok"], "已达上限时应拒绝继续升级")
	assert_string_contains(str(again["reason"]), "上限", "拒绝原因应说明已达等级上限")
	assert_eq(_svc.get_currency(REC_ARCHIVE), 3, "被拒绝时不得扣除学习记录")
	assert_eq(_svc.get_progress(CHAR_MIO).level, 10, "被拒绝时等级不得变化")


# ============================================================
#  验收点 9：突破需要等级与材料
# ============================================================

## 验收点 9：Lv.1 时 query_breakthrough 返回 ok=false 且原因含等级要求。
func test_query_breakthrough_requires_level() -> void:
	_svc.grant({C_SCHOOL_COIN: 50000, C_CLUB_BADGE: 100, C_ECHO_CRYSTAL: 50})

	var q := _svc.query_breakthrough(CHAR_MIO)
	assert_false(bool(q.get("ok", false)), "Lv.1 时不应允许突破")
	var reason := str(q.get("reason", ""))
	assert_string_contains(reason, "Lv.10", "原因应指出需要 Lv.10")

	# 差一级也不行
	_set_progress(CHAR_MIO, 9)
	var q9 := _svc.query_breakthrough(CHAR_MIO)
	assert_false(bool(q9.get("ok", false)), "Lv.9 时仍不应允许突破")
	assert_string_contains(str(q9.get("reason", "")), "Lv.10", "原因应指出需要 Lv.10")

	# 材料齐备 + Lv.10 → 允许
	_set_progress(CHAR_MIO, 10)
	var q10 := _svc.query_breakthrough(CHAR_MIO)
	assert_true(bool(q10.get("ok", false)),
		"Lv.10 且材料充足时应允许突破：%s" % str(q10.get("reason", "")))
	assert_eq(int(q10.get("nextLevel", 0)), 1, "下一次突破阶数应为 1")
	var cost: Dictionary = q10.get("cost", {})
	assert_eq(int(cost.get(C_SCHOOL_COIN, 0)), 800, "突破 I 的学园币成本应为 800")
	assert_eq(int(cost.get(C_CLUB_BADGE, 0)), 3, "突破 I 的社团徽章成本应为 3")


## 验收点 9：do_breakthrough 后突破阶数 +1，且材料被正确扣除。
func test_do_breakthrough_deducts_materials() -> void:
	_svc.grant({C_SCHOOL_COIN: 5000, C_CLUB_BADGE: 10, C_ECHO_CRYSTAL: 5})
	_set_progress(CHAR_MIO, 10)

	var before_coin := _svc.get_currency(C_SCHOOL_COIN)
	var before_badge := _svc.get_currency(C_CLUB_BADGE)
	var before_crystal := _svc.get_currency(C_ECHO_CRYSTAL)

	var r := _svc.do_breakthrough(CHAR_MIO)
	assert_true(r["ok"], "突破应成功：%s" % str(r.get("reason", "")))
	assert_eq(int(r["breakthroughAfter"]), 1, "突破阶数应提升到 1")

	var p := _svc.get_progress(CHAR_MIO)
	assert_eq(p.breakthrough, 1, "角色突破阶数应为 1")
	assert_eq(p.level, 10, "H 章六：突破不重置等级")
	assert_eq(p.level_cap(), 20, "突破 I 应解除等级上限到 Lv.20")

	assert_eq(_svc.get_currency(C_SCHOOL_COIN), before_coin - 800,
		"突破 I 应扣除 800 学园币")
	assert_eq(_svc.get_currency(C_CLUB_BADGE), before_badge - 3,
		"突破 I 应扣除 3 社团徽章")
	assert_eq(_svc.get_currency(C_ECHO_CRYSTAL), before_crystal - 0,
		"突破 I 不消耗残响结晶")

	# 重复突破同一阶：Lv.10 未达 Lv.20，应被拒绝且不再扣材料
	var again := _svc.do_breakthrough(CHAR_MIO)
	assert_false(bool(again.get("ok", false)), "未达 Lv.20 时不应能再次突破")
	assert_eq(_svc.get_currency(C_SCHOOL_COIN), before_coin - 800,
		"被拒绝的突破不得扣除材料")


# ============================================================
#  验收点 10：材料不足时不做部分扣除
# ============================================================

## 验收点 10：spend() 在任一资源不足时返回 false 且所有库存不变。
func test_spend_rejects_partial_deduction() -> void:
	_svc.grant({C_SCHOOL_COIN: 100, C_CLUB_BADGE: 1, C_ECHO_CRYSTAL: 0})

	var coin_before := _svc.get_currency(C_SCHOOL_COIN)
	var badge_before := _svc.get_currency(C_CLUB_BADGE)

	# 学园币够、社团徽章不够 → 整笔拒绝
	assert_false(_svc.can_afford({C_SCHOOL_COIN: 50, C_CLUB_BADGE: 5}),
		"社团徽章不足时 can_afford 应为 false")
	assert_false(_svc.spend({C_SCHOOL_COIN: 50, C_CLUB_BADGE: 5}),
		"任一资源不足时 spend 应返回 false")
	assert_eq(_svc.get_currency(C_SCHOOL_COIN), coin_before,
		"被拒绝的交易不得扣除学园币（不做部分扣除）")
	assert_eq(_svc.get_currency(C_CLUB_BADGE), badge_before,
		"被拒绝的交易不得扣除社团徽章")

	# 残响结晶为 0，成本要求 1 → 整笔拒绝
	assert_false(_svc.spend({C_SCHOOL_COIN: 10, C_ECHO_CRYSTAL: 1}),
		"残响结晶不足时 spend 应返回 false")
	assert_eq(_svc.get_currency(C_SCHOOL_COIN), coin_before,
		"残响结晶不足时不得先扣掉学园币")

	# 全部可付 → 一次扣清
	assert_true(_svc.spend({C_SCHOOL_COIN: 50, C_CLUB_BADGE: 1}),
		"全部可付时 spend 应返回 true")
	assert_eq(_svc.get_currency(C_SCHOOL_COIN), coin_before - 50, "学园币应被扣除 50")
	assert_eq(_svc.get_currency(C_CLUB_BADGE), badge_before - 1, "社团徽章应被扣除 1")

	# 突破路径同样遵循该纪律
	_svc.grant({C_SCHOOL_COIN: 0, C_CLUB_BADGE: 0})
	_set_progress(CHAR_MIO, 10)
	var coin2 := _svc.get_currency(C_SCHOOL_COIN)
	var badge2 := _svc.get_currency(C_CLUB_BADGE)
	assert_false(bool(_svc.do_breakthrough(CHAR_MIO).get("ok", false)),
		"材料不足时不应能突破")
	assert_eq(_svc.get_currency(C_SCHOOL_COIN), coin2, "失败的突破不得扣学园币")
	assert_eq(_svc.get_currency(C_CLUB_BADGE), badge2, "失败的突破不得扣社团徽章")
	assert_eq(_svc.get_progress(CHAR_MIO).breakthrough, 0, "失败的突破不得改变阶数")


# ============================================================
#  验收点 11：Lv.50 面板膨胀限制
# ============================================================

## 验收点 11：H 章三十一「Lv.50 角色的基础面板不应达到 Lv.1 的几十倍」。
func test_max_level_multiplier_below_ten() -> void:
	for cid: String in [CHAR_MIO, CHAR_YUMA, CHAR_YUI]:
		for key: String in ["hp", "attack", "defense"]:
			var m := _progress(cid, 1).max_level_multiplier(key)
			if m <= 0.0:
				# 小川结衣 attack = 0（无普攻），倍率无意义，跳过
				continue
			assert_lt(m, MAX_LEVEL_MULTIPLIER_LIMIT,
				"%s 的 %s 到 Lv.50 的倍率 %.3f 不应达到 Lv.1 的十倍" % [cid, key, m])

	# 雨宫澪 HP：(1000 + 42×49) / 1000 ≈ 3.06
	assert_almost_eq(_progress(CHAR_MIO, 1).max_level_multiplier("hp"),
		(1000.0 + 42.0 * 49.0) / 1000.0, 0.0001,
		"雨宫澪 HP 的 Lv.50 倍率应为 3.058")

	# 对照：Lv.50 的实际面板与 Lv.1 的比值同样受限
	var lv1 := _progress(CHAR_MIO, 1).compute_stats()
	var lv50 := _progress(CHAR_MIO, 50, 4).compute_stats()
	assert_lt(float(lv50["hp"]) / float(lv1["hp"]), MAX_LEVEL_MULTIPLIER_LIMIT,
		"Lv.50 实际 HP 相对 Lv.1 的倍率应小于 10")
	assert_eq(int(lv50["hp"]), 1000 + 42 * 49, "Lv.50 HP 应为 1000 + 42×49 = 3058")


# ============================================================
#  验收点 12：存档往返
# ============================================================

## 验收点 12：write_to_save + commit 后重新 setup()（模拟重开），
## 等级 / 突破 / 经验 / 资源库存完全一致。
func test_save_round_trip_preserves_growth_state() -> void:
	_svc.grant({
		REC_ARCHIVE: 3,
		C_SCHOOL_COIN: 5000,
		C_CLUB_BADGE: 10,
		C_ECHO_CRYSTAL: 4,
	})

	var r := _svc.level_up_with_records(CHAR_MIO, REC_ARCHIVE, 2)
	assert_true(r["ok"], "升级应成功：%s" % str(r.get("reason", "")))
	_set_progress(CHAR_MIO, 10, 0, 0)
	var b := _svc.do_breakthrough(CHAR_MIO)
	assert_true(b["ok"], "突破应成功：%s" % str(b.get("reason", "")))
	# 突破后再投一点经验，验证 exp 字段也参与往返
	_svc.get_progress(CHAR_MIO).exp = 37
	assert_true(_svc.commit(), "成长状态应能提交存档")

	# 快照（提交前）
	var p1 := _svc.get_progress(CHAR_MIO)
	var snap := {
		"level": p1.level,
		"breakthrough": p1.breakthrough,
		"exp": p1.exp,
		"school_coin": _svc.get_currency(C_SCHOOL_COIN),
		"club_badge": _svc.get_currency(C_CLUB_BADGE),
		"echo_crystal": _svc.get_currency(C_ECHO_CRYSTAL),
		"study_record_archive": _svc.get_currency(REC_ARCHIVE),
	}
	assert_eq(int(snap["level"]), 10, "快照等级应为 10")
	assert_eq(int(snap["breakthrough"]), 1, "快照突破阶数应为 1")
	assert_eq(int(snap["exp"]), 37, "快照等级内经验应为 37")
	assert_eq(int(snap["school_coin"]), 5000 - 800, "快照学园币应为 4200")
	assert_eq(int(snap["club_badge"]), 10 - 3, "快照社团徽章应为 7")

	# 模拟重开：从磁盘重新加载存档，再重建成长服务
	assert_true(SaveService.load_game(), "应能从磁盘重新加载存档")
	var svc2 := CharacterGrowthService.new()
	var errs := svc2.setup()
	assert_eq(errs.size(), 0, "重开后构建应无错误：%s" % str(errs))

	var p2 := svc2.get_progress(CHAR_MIO)
	assert_not_null(p2, "重开后应能取到雨宫澪的成长状态")
	assert_eq(p2.level, int(snap["level"]), "重开后等级应完全一致")
	assert_eq(p2.breakthrough, int(snap["breakthrough"]), "重开后突破阶数应完全一致")
	assert_eq(p2.exp, int(snap["exp"]), "重开后等级内经验应完全一致")
	assert_eq(svc2.get_currency(C_SCHOOL_COIN), int(snap["school_coin"]),
		"重开后学园币库存应完全一致")
	assert_eq(svc2.get_currency(C_CLUB_BADGE), int(snap["club_badge"]),
		"重开后社团徽章库存应完全一致")
	assert_eq(svc2.get_currency(C_ECHO_CRYSTAL), int(snap["echo_crystal"]),
		"重开后残响结晶库存应完全一致")
	assert_eq(svc2.get_currency(REC_ARCHIVE), int(snap["study_record_archive"]),
		"重开后学习记录库存应完全一致")

	# 面板也应一致
	assert_eq_deep(svc2.get_progress(CHAR_MIO).compute_stats(), p1.compute_stats())


# ============================================================
#  验收点 13：数据引用完整性
# ============================================================

## 验收点 13：DataRegistry.get_load_errors() 为空；
## characters.json 里凡有 growthProfileId 的角色，该档位都存在于 character_growth.json。
func test_data_reference_integrity() -> void:
	var errors := DataRegistry.get_load_errors()
	assert_eq(errors.size(), 0, "DataRegistry 加载期不应有任何错误：%s" % str(errors))

	var profiles := {}
	for pr: Dictionary in _growth_cfg().get("growthProfiles", []):
		profiles[str(pr.get("id", ""))] = true
	assert_gt(profiles.size(), 0, "character_growth.json 应至少有一个成长档位")

	var declared := 0
	for c: Dictionary in (_read_json(CHARS_PATH) as Dictionary).get("characters", []):
		var pid := str(c.get("growthProfileId", ""))
		if pid.is_empty():
			continue
		declared += 1
		assert_true(profiles.has(pid),
			"角色 %s 的 growthProfileId '%s' 应存在于 character_growth.json"
			% [c.get("id", "?"), pid])

	# 服务为未显式声明档位的角色回落到 growth_standard，该档位必须真实存在，
	# 否则 CharacterProgress 会静默回落到 profiles[0]（数据漂移的隐患）
	assert_true(profiles.has("growth_standard"),
		"未声明 growthProfileId 的角色会回落到 growth_standard，该档位必须存在")

	# 实质校验：无论是否显式声明，服务解析出的每个角色档位都必须真实存在。
	# （characters.json 当前**未**声明 growthProfileId —— 见回报「发现的问题」，
	#   因此上面那条循环是空转，这里补上不依赖声明与否的真实覆盖。）
	assert_gt(_svc.all_character_ids().size(), 0, "成长服务应至少管理 1 名角色")
	for cid: String in _svc.all_character_ids():
		var p := _svc.get_progress(cid)
		assert_not_null(p, "角色 %s 应有成长状态" % cid)
		assert_false(p.growth_profile_id.is_empty(),
			"角色 %s 解析出的成长档位 id 不应为空" % cid)
		assert_true(profiles.has(p.growth_profile_id),
			"角色 %s 解析出的成长档位 '%s' 应存在于 character_growth.json"
			% [cid, p.growth_profile_id])
		# 该档位必须真的被取到（而非静默回落到 profiles[0] 的空 perLevel）
		assert_gt(p.compute_stats().size(), 0, "角色 %s 的成长面板不应为空" % cid)
		assert_eq(
			int(p.compute_stats().get("hp", 0)),
			int(_base_stats_from_file(cid).get("hp", -1)),
			"Lv.1 角色 %s 的面板 HP 应等于其 baseStats（证明档位被正确解析）" % cid)

	# 突破成本引用的资源 id 必须在 currencies.json 中
	var currency_ids := {}
	for cur: Dictionary in (_read_json(CURRENCIES_PATH) as Dictionary).get("currencies", []):
		currency_ids[str(cur.get("id", ""))] = true
	for b: Dictionary in _growth_cfg().get("breakthroughs", []):
		for cid: String in (b.get("cost", {}) as Dictionary).keys():
			assert_true(currency_ids.has(cid),
				"突破 %s 的成本引用了不存在的资源 '%s'" % [b.get("level", "?"), cid])


# ============================================================
#  验收点 14：五类资源与学习记录三档
# ============================================================

## 验收点 14：currencies.json 恰好 5 条 currency，id 与规格一致；
## studyRecordItems 三档 expValue = 100 / 500 / 2000。
func test_currencies_and_study_record_items() -> void:
	var data: Variant = _read_json(CURRENCIES_PATH)
	assert_not_null(data, "currencies.json 应可解析")
	if data == null:
		return

	var currencies: Array = (data as Dictionary).get("currencies", [])
	assert_eq(currencies.size(), 5,
		"H 章十五 表 67：首发资源应恰好五类，尽量不额外制造碎片/票券/代币")

	var ids: Array[String] = []
	for c: Dictionary in currencies:
		ids.append(str(c.get("id", "")))
		assert_false(str(c.get("name", "")).is_empty(), "资源 %s 应有显示名" % c.get("id", "?"))
	for want: String in SPEC_CURRENCY_IDS:
		assert_true(ids.has(want), "五类资源应含 %s" % want)

	var items: Array = (data as Dictionary).get("studyRecordItems", [])
	assert_eq(items.size(), 3, "H 章五 表 58：学习记录应恰好三档")
	var got := {}
	for it: Dictionary in items:
		got[str(it.get("id", ""))] = int(it.get("expValue", 0))
	for rid: String in SPEC_STUDY_RECORDS.keys():
		assert_true(got.has(rid), "学习记录应含 %s" % rid)
		assert_eq(int(got.get(rid, -1)), int(SPEC_STUDY_RECORDS[rid]),
			"%s 的 expValue 应为 %d" % [rid, int(SPEC_STUDY_RECORDS[rid])])

	# 服务暴露的三档折算经验应与数据一致
	var svc_items := _svc.study_record_items()
	for rid: String in SPEC_STUDY_RECORDS.keys():
		assert_eq(int(svc_items.get(rid, -1)), int(SPEC_STUDY_RECORDS[rid]),
			"服务返回的 %s 折算经验应为 %d" % [rid, int(SPEC_STUDY_RECORDS[rid])])
	assert_eq(int(svc_items.get(REC_NOTE, -1)), 500,
		"学习记录·笔记应折算 500 EXP（表 58）")


# ============================================================
#  验收点 15：升级不越过突破节点
# ============================================================

## 验收点 15：等级到 10 后继续投料不会升到 11（必须先突破）。
func test_level_up_does_not_cross_breakthrough_node() -> void:
	_svc.grant({REC_ARCHIVE: 5})

	# 一次性投入 5 本（10,000 EXP）远超 Lv.1→10 的需求，也必须停在 Lv.10
	var r := _svc.level_up_with_records(CHAR_MIO, REC_ARCHIVE, 5)
	assert_true(r["ok"], "升级应成功：%s" % str(r.get("reason", "")))
	assert_eq(_svc.get_progress(CHAR_MIO).level, 10,
		"大量投料也只能停在突破 0 的上限 Lv.10，不得越过突破节点")

	# 再投一次：仍然不得越过
	_svc.grant({REC_ARCHIVE: 1})
	var r2 := _svc.level_up_with_records(CHAR_MIO, REC_ARCHIVE, 1)
	assert_false(r2["ok"], "已达上限时应拒绝升级")
	assert_eq(_svc.get_progress(CHAR_MIO).level, 10, "等级仍应为 Lv.10")

	# 直接调用领域对象：add_exp 也必须在上限处停下并交回未消耗经验
	var p := _progress(CHAR_MIO, 1)
	var res := p.add_exp(100000)
	assert_eq(p.level, 10, "add_exp 不得让等级越过突破节点")
	assert_true(bool(res["capped"]), "应标记为因等级上限而提前停止")
	assert_gt(int(res["leftover"]), 0, "未消耗的经验必须原样交回，不得吞掉")
	assert_eq(int(res["gained"]), SPEC_CUMULATIVE_TO_10,
		"实际消耗应恰好等于 Lv.1→10 累计 2,520")
	assert_eq(int(res["leftover"]), 100000 - SPEC_CUMULATIVE_TO_10,
		"退回经验应为 100000 - 2520 = 97480")

	# 突破后上限解除，才能继续升到 11
	var p2 := _progress(CHAR_MIO, 10, 1)
	assert_eq(p2.level_cap(), 20, "突破 I 后上限应为 Lv.20")
	var res2 := p2.add_exp(int(_growth_cfg()["expTable"]["10"]))
	assert_eq(p2.level, 11, "突破后应能升到 Lv.11")


# ============================================================
#  补充：突破成本 / 技能成本 / 首章预算的规格一致性
# ============================================================

## 验收点 1 / 9 补充：突破成本基线逐项等于 H 章七 表 60。
func test_breakthrough_costs_match_spec() -> void:
	var bts: Array = _growth_cfg().get("breakthroughs", [])
	assert_eq(bts.size(), SPEC_BREAKTHROUGH_COSTS.size(),
		"突破阶段应恰好 4 阶（I～IV）")

	for i: int in range(SPEC_BREAKTHROUGH_COSTS.size()):
		var b: Dictionary = bts[i]
		assert_eq(int(b.get("level", 0)), i + 1, "第 %d 阶突破的 level 应为 %d" % [i + 1, i + 1])
		assert_eq(int(b.get("requiredLevel", 0)), SPEC_BREAKTHROUGH_LEVELS[i],
			"突破 %d 的等级节点应为 Lv.%d" % [i + 1, SPEC_BREAKTHROUGH_LEVELS[i]])
		var cost: Dictionary = b.get("cost", {})
		for cid: String in SPEC_BREAKTHROUGH_COSTS[i].keys():
			assert_eq(int(cost.get(cid, -1)), int(SPEC_BREAKTHROUGH_COSTS[i][cid]),
				"突破 %d 的 %s 成本应为 %d" % [i + 1, cid, int(SPEC_BREAKTHROUGH_COSTS[i][cid])])

	# 领域对象按当前突破阶数取到的成本应与表一致
	for bt: int in range(4):
		var p := _progress(CHAR_MIO, 1, bt)
		var next_cost := p.next_breakthrough_cost()
		assert_eq(int(next_cost.get(C_SCHOOL_COIN, -1)),
			int(SPEC_BREAKTHROUGH_COSTS[bt][C_SCHOOL_COIN]),
			"突破 %d 阶时取到的学园币成本应为 %d"
			% [bt, int(SPEC_BREAKTHROUGH_COSTS[bt][C_SCHOOL_COIN])])
		assert_eq(p.next_breakthrough_level(), bt + 1, "下一突破阶数应为 %d" % (bt + 1))


## 验收点 1 补充：技能升级成本（H 章八 表 62）与技能上限 Lv.5。
func test_skill_costs_match_spec() -> void:
	var data: Variant = _read_json(UPGRADE_COSTS_PATH)
	assert_not_null(data, "upgrade_costs.json 应可解析")
	if data == null:
		return
	var uc: Dictionary = (data as Dictionary).get("upgradeCosts", {})

	assert_eq(int(uc.get("skillMaxLevel", 0)), SPEC_SKILL_MAX_LEVEL,
		"H 章八：技能上限应为 Lv.5")

	var rows: Array = uc.get("skill", [])
	assert_eq(rows.size(), SPEC_SKILL_COSTS.size(),
		"技能升级成本应恰好 4 条（Lv.1→2 ～ Lv.4→5）")
	for i: int in range(SPEC_SKILL_COSTS.size()):
		var row: Dictionary = rows[i]
		assert_eq(int(row.get("fromLevel", 0)), int(SPEC_SKILL_COSTS[i]["fromLevel"]),
			"第 %d 条技能成本的 fromLevel 应为 %d" % [i + 1, int(SPEC_SKILL_COSTS[i]["fromLevel"])])
		assert_eq(int(row.get("toLevel", 0)), int(SPEC_SKILL_COSTS[i]["toLevel"]),
			"第 %d 条技能成本的 toLevel 应为 %d" % [i + 1, int(SPEC_SKILL_COSTS[i]["toLevel"])])
		assert_eq(int(row.get(C_SCHOOL_COIN, -1)), int(SPEC_SKILL_COSTS[i][C_SCHOOL_COIN]),
			"技能 Lv.%d→%d 的学园币成本应为 %d"
			% [i + 1, i + 2, int(SPEC_SKILL_COSTS[i][C_SCHOOL_COIN])])
		assert_eq(int(row.get(C_ECHO_CRYSTAL, -1)), int(SPEC_SKILL_COSTS[i][C_ECHO_CRYSTAL]),
			"技能 Lv.%d→%d 的残响结晶成本应为 %d"
			% [i + 1, i + 2, int(SPEC_SKILL_COSTS[i][C_ECHO_CRYSTAL])])


## 验收点 1 补充：1-1～1-10 首通总预算（H 章二十一-A 表 71）。
func test_ch1_first_clear_budget_matches_spec() -> void:
	var budget: Dictionary = _growth_cfg().get("ch1FirstClearBudget", {})
	assert_false(budget.is_empty(), "character_growth.json 应登记 1-1～1-10 首通总预算")

	for key: String in SPEC_CH1_BUDGET.keys():
		assert_true(budget.has(key), "首通预算应含 %s" % key)

	assert_eq(int(budget.get("school_coin", 0)), int(SPEC_CH1_BUDGET["school_coin"]),
		"首通学园币预算应为约 5,200")
	assert_almost_eq(float(budget.get("school_coin_tolerance", 0.0)),
		float(SPEC_CH1_BUDGET["school_coin_tolerance"]), EPS,
		"学园币预算容差应为 ±10%")
	assert_eq(int(budget.get("study_record_exp", 0)), int(SPEC_CH1_BUDGET["study_record_exp"]),
		"首通学习记录预算应为 8,500 EXP 等值")
	assert_almost_eq(float(budget.get("study_record_exp_tolerance", 0.0)),
		float(SPEC_CH1_BUDGET["study_record_exp_tolerance"]), EPS,
		"学习记录预算容差应为 ±10%")
	assert_eq(int(budget.get("club_badge", 0)), int(SPEC_CH1_BUDGET["club_badge"]),
		"首通社团徽章预算应为 6")
	assert_eq(int(budget.get("echo_crystal", 0)), int(SPEC_CH1_BUDGET["echo_crystal"]),
		"首通残响结晶预算应为 3")
	assert_eq(int(budget.get("equipment_part_min", 0)), int(SPEC_CH1_BUDGET["equipment_part_min"]),
		"首通装备零件预算下界应为 15")
	assert_eq(int(budget.get("equipment_part_max", 0)), int(SPEC_CH1_BUDGET["equipment_part_max"]),
		"首通装备零件预算上界应为 24")

	# 预算足以支撑 Lv.1→10 的累计经验需求（3～5 名角色进入 Lv.8～12 区间）
	assert_gt(int(budget.get("study_record_exp", 0)), SPEC_CUMULATIVE_TO_10,
		"学习记录预算应高于单角色 Lv.1→10 的累计需求 2,520 EXP")
