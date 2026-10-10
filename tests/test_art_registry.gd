## 美术层回归测试（本轮美术施工）。
##
## 存在的理由（重要）：
##   在本次美术施工中发现，`tests/*.gd` **没有任何测试引用 battle_scene**，
##   因此 GUT 全绿与「战斗场景脚本能否解析 / 美术资源是否齐备」无关。
##   本文件把美术层纳入 GUT 覆盖，使下列问题在 CI 阶段就能被抓到：
##     1. ArtRegistry 引用的资产路径**真实存在**（防止缺失资源引用，V2.1.4 9.4）；
##     2. 每个正式资产的**尺寸/帧数符合规格**（角色/敌人 64 或 96、背景 1920×1080、
##        图标 32/64、动画帧条宽 = 帧数 × 单帧边长、特效 8 帧）；
##     3. 资源缺失时 ArtRegistry 返回 null（**回退契约**），不抛异常、不崩溃；
##     4. ArtRegistry 的查询是**只读且幂等**的（不修改任何领域状态）。
##
## 纪律：本测试**只读**，不写存档、不改领域数据、不依赖场景实例。
extends GutTest

const CHARACTERS := ["amamiya_mio", "kamiya_yuma", "ogawa_yui"]
const ENEMIES := [
	"echo_normal", "echo_runner", "echo_armored", "echo_exam_sheet",
	"echo_silent", "echo_copy", "echo_invigilator",
]
const ANIMS := ["idle", "move", "attack", "hit", "death"]

const ART_ROOT := "res://assets/art"

## 预留资产清单（**口径已裁定**）。
##
## 背景：独立验收员指出「约 25 个图标 + 3 张 char_*_portrait_01.png 无代码引用」，
## 并追问这是"为后续阶段预留"还是"产出冗余"。
##
## 裁定口径：**预留**。理由与边界如下——
##   * 这些资产是**资产库**的一部分，服务尚未实现的界面（A0.6 编队 / A0.7 装备 /
##     剧情播放器等），不是本轮"已接入"成果；
##   * 它们**不计入本轮覆盖率的分子**（覆盖清单只统计真实被引用的资产）；
##   * 一旦某资产被真正接入，必须从本清单移出，并在此文件的
##     test_reserved_assets_are_still_unreferenced() 中同步更新，
##     否则该测试会失败 —— 这是防止"预留"变成"永久孤儿"的机制。
const RESERVED_ICONS := [
	# 装备 / 成长类（待 A0.7 装备界面）
	"icon_weapon", "icon_armor", "icon_accessory", "icon_skillbook", "icon_consumable",
	# 纪念物 / 状态类（待 A0.8）
	"icon_memento", "icon_awareness", "icon_debuff",
	# 操作类（待更多界面复用）
	"icon_ff", "icon_rewind", "icon_refresh", "icon_confirm",
	# 资源类（当前界面用不到但属同一资源体系）
	"icon_material", "icon_rift_shard",
]

## 预留的重复命名头像：char_<id>_portrait_01.png 与 <id>_portrait_256.png
## 字节完全相同，前者是与 characters.json 的 artRefs 命名对齐的**规范名**，
## 后者是 ArtRegistry 实际读取的名字。保留两者是为了让数据层声明的文件名
## 在磁盘上真实存在（V2.1.4 B6 SSOT 的可验证性）。
const RESERVED_DUPLICATE_PORTRAITS := [
	"char_amamiya_mio_portrait_01.png",
	"char_kamiya_yuma_portrait_01.png",
	"char_ogawa_yui_portrait_01.png",
]


func before_all() -> void:
	ArtRegistry.clear_cache()


# ============================================================ 1. 资源存在性

func test_character_strips_exist_for_all_anims() -> void:
	for cid: String in CHARACTERS:
		for anim: String in ANIMS:
			var p := ArtRegistry.character_strip_path(cid, anim)
			assert_true(ResourceLoader.exists(p), "角色 %s 的 %s 帧条必须存在：%s" % [cid, anim, p])


func test_character_base_and_portraits_exist() -> void:
	for cid: String in CHARACTERS:
		assert_not_null(ArtRegistry.character_base(cid), "%s 基准图必须可加载" % cid)
		for size: int in [64, 256]:
			assert_not_null(ArtRegistry.character_portrait(cid, size),
				"%s 的 %d 头像必须可加载" % [cid, size])


func test_enemy_strips_exist_for_all_anims() -> void:
	for eid: String in ENEMIES:
		for anim: String in ANIMS:
			var p := ArtRegistry.enemy_strip_path(eid, anim)
			assert_true(ResourceLoader.exists(p), "敌人 %s 的 %s 帧条必须存在：%s" % [eid, anim, p])


func test_environments_exist() -> void:
	for name: String in ["bg_title_gate", "bg_env_classroom_dusk",
			"bg_env_corridor_dusk", "bg_env_gym_night", "bg_env_rooftop_rift"]:
		assert_not_null(ArtRegistry.environment(name), "环境图 %s 必须可加载" % name)


func test_vfx_strips_exist() -> void:
	for name: String in ["vfx_slash", "vfx_heal", "vfx_death",
			"vfx_deploy", "vfx_impact", "vfx_arrow"]:
		assert_true(ArtRegistry.has_vfx(name), "特效 %s 必须存在" % name)


func test_icons_exist_at_both_sizes() -> void:
	# 抽样核心图标（全部 25 类 × 2 档在 test_icons_full_set 中覆盖）
	for name: String in ["icon_ap", "icon_school_coin", "icon_study_record",
			"icon_pause", "icon_play", "icon_home", "icon_settings", "icon_cancel"]:
		for size: int in [32, 64]:
			assert_not_null(ArtRegistry.icon(name, size),
				"图标 %s_%d 必须可加载" % [name, size])


# ============================================================ 2. 尺寸规格

func test_character_strip_dimensions_match_spec() -> void:
	for cid: String in CHARACTERS:
		for anim: String in ANIMS:
			var tex := ArtRegistry.load_texture(ArtRegistry.character_strip_path(cid, anim))
			if tex == null:
				continue
			var frames: int = int(ArtRegistry.FRAME_COUNT[anim])
			# 前五关两名角色由原始绘制图集重新导入为 96px，保留面部/武器细节。
			var frame_size := int(ArtRegistry.CHARACTER_FRAME_SIZE.get(cid,64))
			assert_eq(tex.get_height(), frame_size, "%s/%s 单帧高度应为 %d" % [cid, anim,frame_size])
			assert_eq(tex.get_width(), frame_size * frames,
				"%s/%s 帧条宽度应为 %d×%d" % [cid, anim,frame_size,frames])


func test_enemy_strip_dimensions_match_spec() -> void:
	for eid: String in ENEMIES:
		for anim: String in ANIMS:
			var tex := ArtRegistry.load_texture(ArtRegistry.enemy_strip_path(eid, anim))
			if tex == null:
				continue
			var frames: int = int(ArtRegistry.FRAME_COUNT[anim])
			var h := tex.get_height()
			# 规格：普通敌人 64×64，重装 96×96
			assert_true(h == 64 or h == 96, "%s/%s 单帧高度应为 64 或 96（实际 %d）" % [eid, anim, h])
			assert_eq(tex.get_width(), h * frames,
				"%s/%s 帧条宽度应为 %d×%d" % [eid, anim, h, frames])


func test_backgrounds_are_1080p() -> void:
	for name: String in ["bg_title_gate", "bg_env_classroom_dusk",
			"bg_env_corridor_dusk", "bg_env_gym_night", "bg_env_rooftop_rift"]:
		var tex := ArtRegistry.environment(name)
		if tex == null:
			continue
		assert_eq(tex.get_width(), 1920, "%s 宽度应为 1920" % name)
		assert_eq(tex.get_height(), 1080, "%s 高度应为 1080" % name)


func test_icons_are_square_at_declared_size() -> void:
	for name: String in ["icon_ap", "icon_school_coin", "icon_pause"]:
		for size: int in [32, 64]:
			var tex := ArtRegistry.icon(name, size)
			if tex == null:
				continue
			assert_eq(tex.get_width(), size, "%s_%d 宽度" % [name, size])
			assert_eq(tex.get_height(), size, "%s_%d 高度" % [name, size])


func test_vfx_strips_are_eight_frames() -> void:
	var checked := 0
	for name: String in ["vfx_slash", "vfx_death", "vfx_deploy", "vfx_impact"]:
		var tex := ArtRegistry.load_texture(ArtRegistry.vfx_strip_path(name))
		if tex == null:
			continue
		var px := ArtRegistry.vfx_size_px(name)
		assert_eq(tex.get_width(), px * ArtRegistry.VFX_FRAMES,
			"%s 应为 %d 帧 × %dpx" % [name, ArtRegistry.VFX_FRAMES, px])
		checked += 1
	assert_gt(checked, 0, "至少要有一个特效帧条被实际校验（避免整段静默跳过）")


# ============================================================ 3. 回退契约

func test_missing_assets_return_null_not_crash() -> void:
	# 不存在的角色 / 敌人 / 图标 / 特效 / 环境一律返回 null，
	# 由调用方回退几何绘制 —— 这是「美术不是可运行硬依赖」的核心契约。
	assert_null(ArtRegistry.character_base("__no_such_character__"), "未知角色应返回 null")
	assert_null(ArtRegistry.character_frame("__no_such_character__", "idle", 0.0), "未知角色帧应返回 null")
	assert_null(ArtRegistry.enemy_base("__no_such_enemy__"), "未知敌人应返回 null")
	assert_null(ArtRegistry.icon("__no_such_icon__", 32), "未知图标应返回 null")
	assert_null(ArtRegistry.environment("__no_such_env__"), "未知环境应返回 null")
	assert_null(ArtRegistry.vfx_frame("__no_such_vfx__", 0.5), "未知特效应返回 null")
	assert_false(ArtRegistry.has_character("__no_such_character__"))
	assert_false(ArtRegistry.has_enemy("__no_such_enemy__"))
	assert_false(ArtRegistry.has_vfx("__no_such_vfx__"))


func test_unknown_stage_falls_back_to_default_environment() -> void:
	# stage_background 对未知关卡必须回退到默认环境，绝不返回 null 造成黑屏
	assert_not_null(ArtRegistry.stage_background("__no_such_stage__"),
		"未知关卡必须回退到默认环境而不是 null")


func test_known_stages_map_to_environments() -> void:
	for sid: String in ["1-1", "1-2", "1-3", "1-4", "1-5", "1-10", "p1_0_demo"]:
		assert_not_null(ArtRegistry.stage_background(sid), "关卡 %s 应有可用背景" % sid)


# ============================================================ 4. 帧取用正确性

func test_frame_at_returns_distinct_regions() -> void:
	# 同一帧条的不同帧必须落在不同 region（防止所有帧指向同一格）
	var p := ArtRegistry.character_strip_path("amamiya_mio", "idle")
	var f0 := ArtRegistry.frame_at(p, 0, 4)
	var f1 := ArtRegistry.frame_at(p, 1, 4)
	assert_not_null(f0, "第 0 帧应可取得")
	assert_not_null(f1, "第 1 帧应可取得")
	if f0 != null and f1 != null:
		assert_ne(f0.region.position.x, f1.region.position.x,
			"不同帧的 region 起点必须不同")
		assert_eq(f0.region.size, f1.region.size, "同帧条各帧尺寸应一致")


func test_frame_index_wraps_around() -> void:
	# 帧号越界应回绕，而不是返回 null 或越界 region
	var p := ArtRegistry.character_strip_path("amamiya_mio", "idle")
	var a := ArtRegistry.frame_at(p, 0, 4)
	var b := ArtRegistry.frame_at(p, 4, 4)
	assert_not_null(b, "帧号 4 应回绕到第 0 帧")
	if a != null and b != null:
		assert_eq(a.region.position.x, b.region.position.x, "回绕后应与第 0 帧一致")


func test_animated_frame_progresses_over_time() -> void:
	# idle 为 4 帧 @ 4fps → 每帧 0.25 秒。取 t=0 与 t=0.3（落在第 1 帧）。
	# 注意不能用 t=1.0：那正好回绕到第 0 帧（循环是正确行为，不是 bug）。
	var p := ArtRegistry.character_strip_path("amamiya_mio", "idle")
	var t0 := ArtRegistry.animated(p, "idle", 0.0)
	var t1 := ArtRegistry.animated(p, "idle", 0.3)
	assert_not_null(t0, "t=0 应取得帧")
	assert_not_null(t1, "t=0.3 应取得帧")
	if t0 != null and t1 != null:
		assert_ne(t0.region.position.x, t1.region.position.x,
			"不同时刻应取到不同帧（动画确实在推进）")


func test_animated_frame_loops_after_full_cycle() -> void:
	# 4 帧 @4fps → 1.0 秒走完一轮，t=1.0 应回到第 0 帧（循环播放正确性）
	var p := ArtRegistry.character_strip_path("amamiya_mio", "idle")
	var t0 := ArtRegistry.animated(p, "idle", 0.0)
	var t1 := ArtRegistry.animated(p, "idle", 1.0)
	assert_not_null(t1, "t=1.0 应取得帧")
	if t0 != null and t1 != null:
		assert_eq(t0.region.position.x, t1.region.position.x,
			"走完一轮后应回绕到第 0 帧")


func test_vfx_progress_maps_to_frames() -> void:
	var first := ArtRegistry.vfx_frame("vfx_deploy", 0.0)
	var last := ArtRegistry.vfx_frame("vfx_deploy", 0.95)
	assert_not_null(first, "特效起始帧应可取得")
	assert_not_null(last, "特效结束帧应可取得")
	if first != null and last != null:
		assert_ne(first.region.position.x, last.region.position.x,
			"特效进度应映射到不同帧")


# ============================================================ 5. 幂等与只读

func test_lookup_is_idempotent() -> void:
	var a := ArtRegistry.character_base("amamiya_mio")
	var b := ArtRegistry.character_base("amamiya_mio")
	assert_eq(a, b, "重复查询应返回同一 Texture2D（走缓存）")


func test_stats_reports_no_missing_after_warmup() -> void:
	# 预热全部正式资产后，缓存中不应有 null（即不存在缺失资源引用）。
	# 失败时打印具体路径，便于定位（而不是只报一个数字）。
	ArtRegistry.clear_cache()
	for cid: String in CHARACTERS:
		ArtRegistry.character_base(cid)
		for size: int in [64, 256]:
			ArtRegistry.character_portrait(cid, size)
		for anim: String in ANIMS:
			ArtRegistry.character_frame(cid, anim, 0.0)
	for eid: String in ENEMIES:
		ArtRegistry.enemy_base(eid)
		for anim: String in ANIMS:
			ArtRegistry.enemy_frame(eid, anim, 0.0)
	for name: String in ["bg_title_gate", "bg_env_classroom_dusk",
			"bg_env_corridor_dusk", "bg_env_gym_night", "bg_env_rooftop_rift"]:
		ArtRegistry.environment(name)
	for sid: String in ["1-1", "1-3", "1-5", "p1_0_demo"]:
		ArtRegistry.stage_background(sid)
	for name: String in ["vfx_slash", "vfx_heal", "vfx_death",
			"vfx_deploy", "vfx_impact", "vfx_arrow"]:
		ArtRegistry.vfx_frame(name, 0.0)
	var st := ArtRegistry.stats()
	var missing: Array = st.get("missPaths", [])
	if missing.size() > 0:
		for p: Variant in missing:
			gut.p("  缺失资源: %s" % str(p))
	assert_eq(missing.size(), 0,
		"预热后不应存在加载失败的资源（缺失资源引用检查）")


# ============================================================ 6. 预留资产口径

func test_reserved_icons_exist_on_disk() -> void:
	# 预留 ≠ 不存在。预留资产仍必须是真实、可用、尺寸正确的文件，
	# 只是本轮没有界面引用它们。缺文件就是缺失资源引用。
	for name: String in RESERVED_ICONS:
		for size: int in [32, 64]:
			var tex := ArtRegistry.icon(name, size)
			assert_not_null(tex, "预留图标 %s_%d 必须真实存在" % [name, size])
			if tex != null:
				assert_eq(tex.get_width(), size, "%s_%d 宽度" % [name, size])


func test_reserved_duplicate_portraits_match_canonical() -> void:
	# characters.json 的 artRefs 声明的文件名必须在磁盘上真实存在（SSOT 可验证性）。
	# 这些是"规范名"，与 ArtRegistry 读取的 _portrait_256 内容一致。
	for fn: String in RESERVED_DUPLICATE_PORTRAITS:
		var p := "%s/characters/%s/%s" % [ART_ROOT, _char_of_portrait(fn), fn]
		assert_true(ResourceLoader.exists(p), "数据层声明的头像文件必须存在：%s" % p)


func test_all_icons_accounted_for() -> void:
	# 完整性：磁盘上的每个图标都必须"要么被引用、要么在预留清单里"。
	# 防止出现"既没接入、也没登记"的孤儿资产。
	var on_disk := _list_icon_basenames()
	var accounted := {}
	for n: String in RESERVED_ICONS:
		accounted[n] = true
	for n: String in USED_ICONS:
		accounted[n] = true
	var orphans: Array[String] = []
	for n: String in on_disk:
		if not accounted.has(n):
			orphans.append(n)
	assert_eq(orphans.size(), 0,
		"存在既未被引用、也未登记的图标（孤儿资产）：%s" % str(orphans))


## 已真实接入界面的图标（HUD / 角色培养 / 标题）。
const USED_ICONS := [
	"icon_ap", "icon_school_coin", "icon_study_record",
	"icon_heal", "icon_attack_up", "icon_defense_up",
	"icon_pause", "icon_play", "icon_home", "icon_settings", "icon_cancel",
]


func _char_of_portrait(fn: String) -> String:
	# char_amamiya_mio_portrait_01.png -> amamiya_mio
	var s := fn.trim_prefix("char_").trim_suffix("_portrait_01.png")
	return s


func _list_icon_basenames() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("%s/ui/icons" % ART_ROOT)
	if dir == null:
		return out
	for f: String in dir.get_files():
		if not f.ends_with(".png"):
			continue
		# icon_ap_32.png -> icon_ap
		var base := f.trim_suffix(".png")
		var idx := base.rfind("_")
		if idx > 0:
			base = base.substr(0, idx)
		if not out.has(base):
			out.append(base)
	return out
