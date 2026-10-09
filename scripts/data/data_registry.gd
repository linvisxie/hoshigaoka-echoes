## DataRegistry — 配置加载、ID 索引、校验（L4 Autoload）。
##
## 严格遵循 V2.1.4 B6 SSOT：
##   data/ 下只有 SSOT 表列出的权威文件；
##   关卡为 data/stages/ch1/<stageId>.json，剧情为 data/story/<storyId>.json；
##   不创建同义总表 stages.json 或 story.json；检索索引由本注册表在加载时生成内存索引。
##
## Phase 0 范围：按相对目录加载 + JSON 必填字段校验 + 内存 ID 索引 + 引用关系校验骨架。
## 不含玩法规则；数据文件本身为最小合法占位。
extends Node

const TAG := "DataRegistry"

## B6 SSOT：canonical 单文件数据域（相对 res://）
const CANONICAL_FILES := {
	"terms": "res://data/terms.json",
	"balance": "res://data/balance.json",
	"characters": "res://data/characters.json",
	"skills": "res://data/skills.json",
	"enemies": "res://data/enemies.json",
	"currencies": "res://data/currencies.json",
	"character_growth": "res://data/character_growth.json",
	"upgrade_costs": "res://data/upgrade_costs.json",
	"upgrades": "res://data/upgrades.json",
	"equipment": "res://data/equipment.json",
	"equipment_affixes": "res://data/equipment_affixes.json",
	"mementos": "res://data/mementos.json",
	"stage_rewards": "res://data/stage_rewards.json",
}

## 为「条目数组型」数据域建立 id 索引（Alpha A0.1 新增）。
##
## 背景：`get_entry(domain, id)` 原先只对 stages / story 生效（那两类在 _load_stages /
## _load_story 里各自填了索引），因此 `get_entry("characters", "amamiya_mio")` 会返回空字典——
## 表现层拿不到角色名/职业/面板，只能显示裸 id。本函数把其余 canonical 域也纳入索引。
##
## 纪律：索引只是**内存检索视图**，不复制数据（B6：不另存第二份正文）。
## 数组字段名与域名不一致（characters / skills / enemies / currencies / upgrades /
## equipment / mementos / rewards），故用显式映射而不是猜字段名。
const INDEXED_ARRAY_FIELDS := {
	"characters": "characters",
	"skills": "skills",
	"enemies": "enemies",
	"currencies": "currencies",
	"upgrades": "upgrades",
	"equipment": "equipment",
	"equipment_affixes": "affixes",
	"mementos": "mementos",
	"stage_rewards": "rewards",
	"character_growth": "growthProfiles",
}


func _build_domain_indices() -> void:
	for domain: String in INDEXED_ARRAY_FIELDS.keys():
		var field: String = INDEXED_ARRAY_FIELDS[domain]
		var idx := {}
		var entries: Variant = get_domain(domain).get(field, [])
		if typeof(entries) != TYPE_ARRAY:
			continue
		for entry: Variant in (entries as Array):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var e: Dictionary = entry
			var id := str(e.get("id", ""))
			if id.is_empty():
				continue
			if idx.has(id):
				_load_errors.append("%s: id 重复 '%s'" % [domain, id])
				continue
			idx[id] = e
		_indices[domain] = idx


## 目录型数据域（V2.1.4：分目录，禁止同义总表）
const STAGES_DIR := "res://data/stages/ch1"
const STORY_DIR := "res://data/story"

## Prototype 专用关卡目录（P1.0 新增）。
##
## 规格依据与边界（V2.1.4 B6 / L2 / M2 表 114）：
##   B6 与 L2 规定「关卡为 data/stages/ch1/<stageId>.json」，且 data/ 下不得创建同义总表。
##   P1.0 需要一张**独立于第一章主线**的 3～5 分钟 Prototype 演示关（M2 表 114），
##   而 G-十 / 表 54 明确 Prototype 阶段正式主线仍以 1-1 为垂直切片。
##   为避免污染 canonical 的 ch1 关卡集合（tests/test_data_ssot.gd 断言 ch1 恰好 10 关、
##   test_data_registry.gd 断言 stages 索引恰好 10 条），演示关放在独立子目录，
##   并以**独立索引键**加载，因此 canonical 集合与计数完全不变。
##
## 这**不是**第二套数据源：本目录仍只存关卡正文（StageConfig），
## 敌人/角色/平衡数值依旧唯一来自 enemies.json / characters.json / balance.json。
## 该放置方式在 V2.1.4 中无明文规定，属规格未定义区，已登记于 docs/P1.0_验收报告.md。
const PROTOTYPE_STAGES_DIR := "res://data/stages/prototype"
const PROTOTYPE_STAGES_KEY := "prototype_stages"

## 每个数据域必须具备的顶层字段（Phase 0 校验基线）
const REQUIRED_FIELDS := {
	"terms": ["schemaVersion", "domain", "terms"],
	"balance": ["schemaVersion", "domain", "layout", "combat"],
	"characters": ["schemaVersion", "domain", "characters"],
	"skills": ["schemaVersion", "domain", "skills"],
	"enemies": ["schemaVersion", "domain", "enemies"],
	"currencies": ["schemaVersion", "domain", "currencies"],
	"character_growth": ["schemaVersion", "domain", "growthProfiles"],
	"upgrade_costs": ["schemaVersion", "domain", "upgradeCosts"],
	"upgrades": ["schemaVersion", "domain", "upgrades"],
	"equipment": ["schemaVersion", "domain", "equipment"],
	"equipment_affixes": ["schemaVersion", "domain", "affixes"],
	"mementos": ["schemaVersion", "domain", "mementos"],
	"stage_rewards": ["schemaVersion", "domain", "rewards"],
}

const STAGE_REQUIRED_FIELDS := [
	"schemaVersion", "domain", "stageId", "chapter", "mapId", "coreHp",
	"startingAp", "apRegen", "availableCharacters", "enemySpawnTimeline",
	"firstClearRewardId", "repeatRewardId", "storyBefore", "storyAfter",
]

## 已加载的原始数据域：domain -> Dictionary
var _domains: Dictionary = {}

## 内存 ID 索引：domain -> { id_string -> Dictionary(entry) }
var _indices: Dictionary = {}

## 加载过程中的问题记录（不阻断启动，由调用方决定如何呈现）
var _load_errors: Array[String] = []

## 是否已完成加载
var _loaded: bool = false


func _ready() -> void:
	load_all()


## 加载全部数据域。返回是否全部无错。
func load_all() -> bool:
	_domains.clear()
	_indices.clear()
	_load_errors.clear()

	for domain: String in CANONICAL_FILES.keys():
		var path: String = CANONICAL_FILES[domain]
		var data: Variant = _read_json(path)
		if data == null:
			_load_errors.append("%s: 无法加载 %s" % [domain, path])
			continue
		if typeof(data) != TYPE_DICTIONARY:
			_load_errors.append("%s: %s 顶层不是 JSON 对象" % [domain, path])
			continue
		var dict: Dictionary = data
		var missing: Array = []
		for field: String in REQUIRED_FIELDS.get(domain, []):
			if not dict.has(field):
				missing.append(field)
		if not missing.is_empty():
			_load_errors.append("%s: 缺少必填字段 %s" % [domain, ", ".join(missing)])
			continue
		_domains[domain] = dict

	_load_stages()
	_load_prototype_stages()
	_load_story()
	_build_domain_indices()
	_validate_references()

	_loaded = true
	if _load_errors.is_empty():
		GameLog.info(TAG, "数据加载完成：%d 个数据域（含 %d 关、%d Prototype 演示关、%d 剧情）"
			% [_domains.size(), _indices.get("stages", {}).size(),
				_indices.get(PROTOTYPE_STAGES_KEY, {}).size(),
				_indices.get("story", {}).size()])
	else:
		for e: String in _load_errors:
			GameLog.error(TAG, e)
	return _load_errors.is_empty()


## 是否已完成加载。
func is_loaded() -> bool:
	return _loaded


## 取某个数据域的原始字典。
func get_domain(domain: String) -> Dictionary:
	return _domains.get(domain, {})


## 按 ID 取某域条目。
func get_entry(domain: String, id: String) -> Dictionary:
	var idx: Dictionary = _indices.get(domain, {})
	return idx.get(id, {})


## 取某域的全部 ID。
func get_ids(domain: String) -> Array:
	var idx: Dictionary = _indices.get(domain, {})
	return idx.keys()


## 加载期问题列表。
func get_load_errors() -> Array[String]:
	return _load_errors


## 依据 balance.json 计算逻辑格坐标 -> 参考画布像素（V2.1.4 LOCKED 律）。
## Phase 0 只提供纯函数与参数读取；调用方负责给 boardOrigin。
func get_layout() -> Dictionary:
	return get_domain("balance").get("layout", {})


# ---------- 内部 ----------

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
		_load_errors.append("%s: JSON 解析失败（第 %d 行）: %s"
			% [path, parser.get_error_line(), parser.get_error_message()])
		return null
	return parser.data


func _load_stages() -> void:
	_indices["stages"] = {}
	var dir := DirAccess.open(STAGES_DIR)
	if dir == null:
		_load_errors.append("stages: 无法打开目录 %s" % STAGES_DIR)
		return
	var files := dir.get_files()
	files.sort()  # 保证 1-1, 1-2 ... 顺序稳定，便于测试复现
	for fname: String in files:
		if not fname.ends_with(".json"):
			continue
		var path := "%s/%s" % [STAGES_DIR, fname]
		var data: Variant = _read_json(path)
		if data == null or typeof(data) != TYPE_DICTIONARY:
			_load_errors.append("stages: %s 加载失败" % path)
			continue
		var dict: Dictionary = data
		var missing: Array = []
		for field: String in STAGE_REQUIRED_FIELDS:
			if not dict.has(field):
				missing.append(field)
		if not missing.is_empty():
			_load_errors.append("stages: %s 缺少必填字段 %s" % [fname, ", ".join(missing)])
			continue
		var sid: String = str(dict.get("stageId", ""))
		if sid.is_empty():
			_load_errors.append("stages: %s 的 stageId 为空" % fname)
			continue
		if _indices["stages"].has(sid):
			_load_errors.append("stages: stageId 重复 %s" % sid)
			continue
		_indices["stages"][sid] = dict


## Prototype 专用关卡加载（P1.0）。
## 与 _load_stages 使用**完全相同**的字段校验与索引规则，只是写入独立索引键，
## 因此 ch1 canonical 关卡集合与计数不受影响。
func _load_prototype_stages() -> void:
	_indices[PROTOTYPE_STAGES_KEY] = {}
	var dir := DirAccess.open(PROTOTYPE_STAGES_DIR)
	if dir == null:
		# 目录不存在不视为错误：正式零售构建可以不带 Prototype 演示关。
		return
	var files := dir.get_files()
	files.sort()
	for fname: String in files:
		if not fname.ends_with(".json"):
			continue
		var path := "%s/%s" % [PROTOTYPE_STAGES_DIR, fname]
		var data: Variant = _read_json(path)
		if data == null or typeof(data) != TYPE_DICTIONARY:
			_load_errors.append("prototype_stages: %s 加载失败" % path)
			continue
		var dict: Dictionary = data
		var missing: Array = []
		for field: String in STAGE_REQUIRED_FIELDS:
			if not dict.has(field):
				missing.append(field)
		if not missing.is_empty():
			_load_errors.append("prototype_stages: %s 缺少必填字段 %s" % [fname, ", ".join(missing)])
			continue
		var sid: String = str(dict.get("stageId", ""))
		if sid.is_empty():
			_load_errors.append("prototype_stages: %s 的 stageId 为空" % fname)
			continue
		if _indices[PROTOTYPE_STAGES_KEY].has(sid):
			_load_errors.append("prototype_stages: stageId 重复 %s" % sid)
			continue
		# 与 canonical 关卡同名视为冲突：两个索引键指向同一 stageId 会让取关不确定。
		if _indices.get("stages", {}).has(sid):
			_load_errors.append(
				"prototype_stages: stageId '%s' 与 ch1 正式关卡重名，禁止" % sid)
			continue
		_indices[PROTOTYPE_STAGES_KEY][sid] = dict


## Prototype 演示关的全部 ID（无则返回空数组）
func get_prototype_stage_ids() -> Array:
	return get_ids(PROTOTYPE_STAGES_KEY)


func _load_story() -> void:
	_indices["story"] = {}
	var dir := DirAccess.open(STORY_DIR)
	if dir == null:
		_load_errors.append("story: 无法打开目录 %s" % STORY_DIR)
		return
	var files := dir.get_files()
	files.sort()
	for fname: String in files:
		if not fname.ends_with(".json"):
			continue
		var path := "%s/%s" % [STORY_DIR, fname]
		var data: Variant = _read_json(path)
		if data == null or typeof(data) != TYPE_DICTIONARY:
			_load_errors.append("story: %s 加载失败" % path)
			continue
		var dict: Dictionary = data
		if not dict.has("storyId") or not dict.has("nodes"):
			_load_errors.append("story: %s 缺少 storyId 或 nodes" % fname)
			continue
		var sid: String = str(dict.get("storyId", ""))
		if sid.is_empty():
			_load_errors.append("story: %s 的 storyId 为空" % fname)
			continue
		_indices["story"][sid] = dict


## 引用完整性校验（V2.1.4 B6：角色 skillId -> skills.json；
## 关卡 storyBefore/storyAfter -> story/*.json；关卡 rewardId -> stage_rewards.json）。
## Phase 0 数据为占位，故仅校验"非空引用必须存在"；空串视为未配置，跳过。
func _validate_references() -> void:
	var skill_ids := {}
	for s: Dictionary in get_domain("skills").get("skills", []):
		skill_ids[str(s.get("id", ""))] = true

	for c: Dictionary in get_domain("characters").get("characters", []):
		for sid: String in c.get("skillIds", []):
			if not sid.is_empty() and not skill_ids.has(sid):
				_load_errors.append("引用错误: 角色 %s 的 skillId '%s' 不在 skills.json"
					% [c.get("id", "?"), sid])

	var story_ids: Dictionary = _indices.get("story", {})
	var reward_ids := {}
	for r: Dictionary in get_domain("stage_rewards").get("rewards", []):
		reward_ids[str(r.get("id", ""))] = true

	for stage_id: String in _indices.get("stages", {}).keys():
		var st: Dictionary = _indices["stages"][stage_id]
		for key: String in ["storyBefore", "storyAfter"]:
			var v: String = str(st.get(key, ""))
			if not v.is_empty() and not story_ids.has(v):
				_load_errors.append("引用错误: 关卡 %s 的 %s '%s' 不在 story/ 中"
					% [stage_id, key, v])
		for key: String in ["firstClearRewardId", "repeatRewardId"]:
			var v: String = str(st.get(key, ""))
			if not v.is_empty() and not reward_ids.has(v):
				_load_errors.append("引用错误: 关卡 %s 的 %s '%s' 不在 stage_rewards.json"
					% [stage_id, key, v])
		_validate_stage_enemy_refs(stage_id, st)

	for stage_id: String in _indices.get(PROTOTYPE_STAGES_KEY, {}).keys():
		_validate_stage_enemy_refs(stage_id, _indices[PROTOTYPE_STAGES_KEY][stage_id])

	_validate_growth_references()
	_validate_core_hp_against_balance()
	_validate_reward_references()


## 校验关卡引用的奖励 ID 与奖励表引用的资源 ID（Alpha A0.4）。
##
## 覆盖三类：
##   ① 关卡的 firstClearRewardId / repeatRewardId 必须存在于 stage_rewards.json；
##   ② 奖励条目 currencies 里的每个资源 id 必须存在于 currencies.json（含学习记录三档）；
##   ③ 同一 stageId 不得出现两条 FIRST_CLEAR 奖励（否则「首通只发一次」的语义会被破坏）。
func _validate_reward_references() -> void:
	var currency_ids := {}
	for c: Dictionary in get_domain("currencies").get("currencies", []):
		currency_ids[str(c.get("id", ""))] = true
	for item: Dictionary in get_domain("currencies").get("studyRecordItems", []):
		currency_ids[str(item.get("id", ""))] = true

	var rewards: Array = get_domain("stage_rewards").get("rewards", [])
	var reward_ids := {}
	var first_clear_by_stage := {}
	for r: Dictionary in rewards:
		var rid := str(r.get("id", ""))
		if rid.is_empty():
			_load_errors.append("stage_rewards: 存在 id 为空的奖励条目")
			continue
		if reward_ids.has(rid):
			_load_errors.append("stage_rewards: 奖励 id 重复 '%s'" % rid)
			continue
		reward_ids[rid] = true

		for cid: String in (r.get("currencies", {}) as Dictionary).keys():
			if not currency_ids.has(cid):
				_load_errors.append("stage_rewards: 奖励 %s 引用了不存在的资源 '%s'" % [rid, cid])

		if str(r.get("kind", "")) == "FIRST_CLEAR":
			var sid := str(r.get("stageId", ""))
			if sid.is_empty():
				_load_errors.append("stage_rewards: 首通奖励 %s 缺少 stageId" % rid)
			elif first_clear_by_stage.has(sid):
				_load_errors.append(
					"stage_rewards: 关卡 %s 有两条首通奖励（%s 与 %s），「首通只发一次」语义不成立"
					% [sid, first_clear_by_stage[sid], rid])
			else:
				first_clear_by_stage[sid] = rid

	var all_stages := {}
	for sid: String in _indices.get("stages", {}).keys():
		all_stages[sid] = _indices["stages"][sid]
	for sid: String in _indices.get(PROTOTYPE_STAGES_KEY, {}).keys():
		all_stages[sid] = _indices[PROTOTYPE_STAGES_KEY][sid]

	for sid: String in all_stages.keys():
		var st: Dictionary = all_stages[sid]
		for key: String in ["firstClearRewardId", "repeatRewardId"]:
			var v := str(st.get(key, ""))
			if not v.is_empty() and not reward_ids.has(v):
				_load_errors.append("引用错误: 关卡 %s 的 %s '%s' 不在 stage_rewards.json"
					% [sid, key, v])


## 校验关卡 coreHp 与 balance.json 声明的默认值一致（Alpha A0.3 新增）。
##
## 为什么需要：`balance.combat.coreHpDefault` / `coreHpStage1_1` 此前是**死数据**——
## 全项目无任何引用，关卡核心值各自硬编码，规格声明无法被验证。
## 本校验让「普通关默认 3、1-1 放宽为 5」这条规则**可执行**：
##   允许两种情形 —— ① coreHp 等于默认值；② 在关卡内用 `_coreHp_spec` 显式声明偏离理由。
## 二者皆不满足即报错，避免「某关悄悄把核心改成 9」这类无声偏离规格。
func _validate_core_hp_against_balance() -> void:
	var combat: Dictionary = get_domain("balance").get("combat", {})
	if not combat.has("coreHpDefault"):
		return
	var default_hp := int(combat["coreHpDefault"])

	var all_stages := {}
	for sid: String in _indices.get("stages", {}).keys():
		all_stages[sid] = _indices["stages"][sid]
	for sid: String in _indices.get(PROTOTYPE_STAGES_KEY, {}).keys():
		all_stages[sid] = _indices[PROTOTYPE_STAGES_KEY][sid]

	for sid: String in all_stages.keys():
		var st: Dictionary = all_stages[sid]
		if not st.has("coreHp"):
			continue
		# 只校验**已填充内容**的关卡。
		# 1-6～1-10 仍是 Phase 0 占位（enemySpawnTimeline 为空、coreHp=0），
		# 它们的内容由后续 Alpha 阶段填充，此处不应报错——否则「占位」会被当成「违规」。
		var timeline: Variant = st.get("enemySpawnTimeline", [])
		if typeof(timeline) != TYPE_ARRAY or (timeline as Array).is_empty():
			continue
		var hp := int(st["coreHp"])
		if hp == default_hp:
			continue
		if st.has("_coreHp_spec") and not str(st["_coreHp_spec"]).strip_edges().is_empty():
			continue
		_load_errors.append(
			"关卡 %s 的 coreHp=%d 偏离 balance.combat.coreHpDefault=%d，但未提供 _coreHp_spec 说明理由"
			% [sid, hp, default_hp])


## 关卡出怪与可用角色的引用完整性（V2.1.4 B6：引用关系必须可验证）。
## 出怪引用了不存在的敌人、或 availableCharacters 引用了不存在的角色，
## 都会在战斗构建期才暴露；这里提前到加载期报错，避免"能进关但打不起来"。
func _validate_stage_enemy_refs(stage_id: String, st: Dictionary) -> void:
	var enemy_ids := {}
	for e: Dictionary in get_domain("enemies").get("enemies", []):
		enemy_ids[str(e.get("id", ""))] = true
	var char_ids := {}
	for c: Dictionary in get_domain("characters").get("characters", []):
		char_ids[str(c.get("id", ""))] = true

	for entry: Variant in st.get("enemySpawnTimeline", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var eid := str((entry as Dictionary).get("enemy", ""))
		if not eid.is_empty() and not enemy_ids.has(eid):
			_load_errors.append("引用错误: 关卡 %s 出怪引用了不存在的敌人 '%s'"
				% [stage_id, eid])
	for cid: Variant in st.get("availableCharacters", []):
		var id := str(cid)
		if not id.is_empty() and not char_ids.has(id):
			_load_errors.append("引用错误: 关卡 %s 的 availableCharacters 引用了不存在的角色 '%s'"
				% [stage_id, id])


## 成长系统引用校验（Alpha A0.1）。
##   - characters.json 的 growthProfileId 必须存在于 character_growth.json；
##   - character_growth.json 的突破成本里引用的 currencyId 必须存在于 currencies.json；
##   - upgrade_costs.json 的技能成本同理。
func _validate_growth_references() -> void:
	var currency_ids := {}
	for c: Dictionary in get_domain("currencies").get("currencies", []):
		currency_ids[str(c.get("id", ""))] = true
	for item: Dictionary in get_domain("currencies").get("studyRecordItems", []):
		currency_ids[str(item.get("id", ""))] = true

	var growth: Dictionary = get_domain("character_growth")
	var profile_ids := {}
	for p: Dictionary in growth.get("growthProfiles", []):
		profile_ids[str(p.get("id", ""))] = true

	for c: Dictionary in get_domain("characters").get("characters", []):
		var pid := str(c.get("growthProfileId", ""))
		if not pid.is_empty() and not profile_ids.has(pid):
			_load_errors.append("引用错误: 角色 %s 的 growthProfileId '%s' 不在 character_growth.json"
				% [c.get("id", "?"), pid])

	for b: Dictionary in growth.get("breakthroughs", []):
		var cost: Dictionary = b.get("cost", {})
		for cid: String in cost.keys():
			if not currency_ids.has(cid):
				_load_errors.append("引用错误: 突破 %s 的成本引用了不存在的资源 '%s'"
					% [b.get("level", "?"), cid])

	var upgrade: Dictionary = get_domain("upgrade_costs").get("upgradeCosts", {})
	for row: Dictionary in upgrade.get("skill", []):
		for cid: String in row.keys():
			if cid in ["fromLevel", "toLevel"]:
				continue
			if not currency_ids.has(cid):
				_load_errors.append("引用错误: 技能升级成本引用了不存在的资源 '%s'" % cid)
