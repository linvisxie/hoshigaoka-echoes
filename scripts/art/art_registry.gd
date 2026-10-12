## ArtRegistry — 美术资源登记与解析（表现层，无战斗逻辑）。
##
## 职责（本轮美术施工的总入口）：
##   1. 把 assets/art 下的正式美术资产解析成 Texture2D / AtlasTexture；
##   2. 提供按「角色 / 敌人 / 动画 / 帧」取图的统一 API；
##   3. **资源缺失时一律返回 null**，由调用方回退到几何绘制——
##      保证美术资产永远不是游戏可运行的硬依赖（本轮指令 第九章 9.4）。
##
## 分层纪律（V2.1.4 L3）：
##   本类只读资源、不持战斗状态、不修改任何领域数据。
##   战斗逻辑（射程/阻挡/伤害/Wave/胜负）完全不经过这里。
##
## 缓存策略：
##   使用 static var 做进程级缓存。贴图在整个进程生命周期内只加载一次，
##   场景切换不会重复解码；AtlasTexture 按「路径#帧号」缓存，
##   避免每帧新建 Resource 造成 GC 压力。
##
## 资产目录约定（由 art_src/tools 流水线产出，见 docs/美术工具链与自动化使用说明.md）：
##   assets/art/characters/<charId>/<charId>_<anim>.png   （横向帧条）
##   assets/art/characters/<charId>/<charId>_portrait_256.png
##   assets/art/enemies/<enemyId>/<enemyId>_<anim>.png
##   assets/art/environments/<name>.png
##   assets/art/ui/icons/<name>_<size>.png
class_name ArtRegistry
extends RefCounted

const TAG := "ArtRegistry"

const ART_ROOT := "res://assets/art"
const CHARACTER_FRAME_SIZE := {"amamiya_mio": 128, "kamiya_yuma": 128, "fujiwara_rin": 96,"ogawa_yui":128,"minase_sara":128,"shiraishi_chinatsu":128}

## 特效根目录（与 art_src/tools/build_vfx.py 的输出一致）。
## 注意：特效刻意放在 assets/vfx/ 而不是 assets/art/ 下 —— 它是"战斗反馈"
## 而非"美术图集"，与 V2.1.4 L2 目录约定一致。
const VFX_ROOT := "res://assets/vfx"

## 每条动画的帧数（与 art_src/tools/anim.py 的派生规则一致）
const FRAME_COUNT := {
	"idle": 4,
	"move": 4,
	"attack": 4,
	"hit": 2,
	"death": 4,
	"deploy": 4,
	"skill": 4,
	"victory": 4,
}

## 动画播放速率（帧/秒）。保持克制，避免像素动画"抽搐"。
const ANIM_FPS := {
	"idle": 4.0,
	"move": 8.0,
	"attack": 12.0,
	"hit": 10.0,
	"death": 8.0,
}

## 关卡 -> 战斗背景（本轮指令 6.4：复用环境组件，不为每关从零绘制）
const STAGE_ENV := {
	"1-1": "bg_env_classroom_battle",
	"1-2": "bg_env_landing_battle",
	"1-3": "bg_env_classroom_exam",
	"1-4": "bg_env_corridor_battle",
	"1-5": "bg_env_gym_battle",
	"1-6": "bg_env_infirmary_battle",
	"1-7": "bg_env_ranking_battle",
	"1-8": "bg_env_science_battle",
	"1-9": "bg_env_archive_battle",
	"1-10": "bg_env_boss_exam",
	"p1_0_demo": "bg_env_classroom_dusk",
}

const DEFAULT_ENV := "bg_env_classroom_dusk"

static var _tex_cache: Dictionary = {}
static var _atlas_cache: Dictionary = {}
static var _miss_cache: Dictionary = {}


# ============================================================ 基础加载

## 加载一张贴图；不存在或不可解码时返回 null（并记住 miss，避免重复查磁盘）。
static func load_texture(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path] as Texture2D
	if _miss_cache.has(path):
		return null
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			tex = res as Texture2D
	if tex == null:
		_miss_cache[path] = true
	_tex_cache[path] = tex
	return tex


## 取帧条中的一帧（AtlasTexture）。strip 缺失或帧号越界时返回 null。
static func frame_at(path: String, frame: int, count: int) -> AtlasTexture:
	if count <= 0:
		return null
	var f := posmod(frame, count)
	var key := "%s#%d/%d" % [path, f, count]
	if _atlas_cache.has(key):
		return _atlas_cache[key] as AtlasTexture
	var strip := load_texture(path)
	if strip == null or strip.get_width() <= 0:
		_atlas_cache[key] = null
		return null
	var fw := float(strip.get_width()) / float(count)
	var at := AtlasTexture.new()
	at.atlas = strip
	at.region = Rect2(float(f) * fw, 0.0, fw, float(strip.get_height()))
	_atlas_cache[key] = at
	return at


## 按「时间 -> 帧号」取当前帧（供 _draw 内直接使用）。
static func animated(path: String, anim: String, t: float) -> AtlasTexture:
	var count: int = int(FRAME_COUNT.get(anim, 1))
	if count <= 1:
		return frame_at(path, 0, 1)
	var fps: float = float(ANIM_FPS.get(anim, 6.0))
	return frame_at(path, int(floor(t * fps)), count)


## 按**播放进度 0..1** 取帧（用于攻击/受击这类一次性动画）。
## 与 animated() 的区别：一次性动画不能循环，必须按进度线性走完。
static func frame_progress(path: String, anim: String, progress: float) -> AtlasTexture:
	var count: int = int(FRAME_COUNT.get(anim, 1))
	if count <= 1:
		return frame_at(path, 0, 1)
	var p := clampf(progress, 0.0, 0.9999)
	return frame_at(path, int(p * float(count)), count)


# ============================================================ 角色

static func character_strip_path(char_id: String, anim: String) -> String:
	return "%s/characters/%s/%s_%s.png" % [ART_ROOT, char_id, char_id, anim]


static func has_character(char_id: String) -> bool:
	return load_texture(character_strip_path(char_id, "idle")) != null


## 角色动画帧（缺资源返回 null）。
static func character_frame(char_id: String, anim: String, t: float) -> AtlasTexture:
	return animated(character_strip_path(char_id, anim), anim, t)


## 角色一次性动画帧（攻击/受击，按进度取帧不循环）。
static func character_frame_progress(char_id: String, anim: String, progress: float) -> AtlasTexture:
	if char_id in ["amamiya_mio", "kamiya_yuma"] and anim == "attack":
		var recovery := "%s/characters/%s/%s_recovery.png" % [ART_ROOT,char_id,char_id]
		if progress >= 0.72 and load_texture(recovery) != null:
			return frame_at(recovery,mini(1,int((progress-0.72)/0.28*2.0)),2)
		progress = minf(progress/0.72,0.9999)
	return frame_progress(character_strip_path(char_id, anim), anim, progress)


static func character_story(char_id: String) -> Texture2D:
	var texture := load_texture("%s/characters/%s/%s_story.png" % [ART_ROOT,char_id,char_id])
	if texture == null or char_id not in ["ogawa_yui","minase_sara","shiraishi_chinatsu"]:
		return texture
	var key := "story_frame:" + char_id
	if not _atlas_cache.has(key):
		var framed := AtlasTexture.new()
		framed.atlas = texture
		framed.region = Rect2(0,0,texture.get_width(),texture.get_height()*.67)
		_atlas_cache[key] = framed
	return _atlas_cache[key] as AtlasTexture

static func character_base(char_id: String) -> Texture2D:
	return load_texture("%s/characters/%s/%s_base.png" % [ART_ROOT, char_id, char_id])


## 角色头像（size 取 64 / 256）。
static func character_portrait(char_id: String, size: int = 64) -> Texture2D:
	var polished := load_texture("%s/characters/%s/%s_portrait_polished.png" % [ART_ROOT, char_id, char_id])
	if polished != null:
		return polished
	return load_texture("%s/characters/%s/%s_portrait_%d.png" % [
		ART_ROOT, char_id, char_id, size])

static var _body_height_scale: Dictionary = {}

## Normalize the visible idle body, retaining one scale for every action frame.
static func character_body_scale(char_id: String) -> float:
	if not _body_height_scale.has(char_id):
		var texture := load_texture("%s/characters/%s/%s_base.png" % [ART_ROOT,char_id,char_id])
		var ratio := 1.28
		if texture != null:
			var bounds := texture.get_image().get_used_rect()
			if bounds.size.y > 0:
				ratio = float(texture.get_height()) / float(bounds.size.y) * 0.96
		_body_height_scale[char_id] = ratio
	return float(_body_height_scale[char_id])


# ============================================================ 敌人

static func enemy_strip_path(enemy_id: String, anim: String) -> String:
	return "%s/enemies/%s/%s_%s.png" % [ART_ROOT, enemy_id, enemy_id, anim]


static func has_enemy(enemy_id: String) -> bool:
	return load_texture(enemy_strip_path(enemy_id, "idle")) != null


static func enemy_frame(enemy_id: String, anim: String, t: float) -> AtlasTexture:
	return animated(enemy_strip_path(enemy_id, anim), anim, t)


## 敌人一次性动画帧（攻击/受击，按进度取帧不循环）。
static func enemy_frame_progress(enemy_id: String, anim: String, progress: float) -> AtlasTexture:
	return frame_progress(enemy_strip_path(enemy_id, anim), anim, progress)


static func enemy_base(enemy_id: String) -> Texture2D:
	return load_texture("%s/enemies/%s/%s_base.png" % [ART_ROOT, enemy_id, enemy_id])


# ============================================================ 特效（VFX）

## 特效帧条均为 8 帧，单帧边长见下表（与 art_src/tools/build_vfx.py 一致）。
const VFX_FRAMES := 8
const VFX_FRAME_PX := {
	"vfx_slash": 96,
	"vfx_heal": 96,
	"vfx_death": 96,
	"vfx_deploy": 96,
	"vfx_impact": 96,
	"vfx_arrow": 128,
}


## 特效单帧（按播放进度 progress 0..1 取帧）。
## 与角色/敌人动画不同，特效是**一次性播放**，因此用进度而非循环时间。
static func vfx_frame(name: String, progress: float) -> AtlasTexture:
	var p := clampf(progress, 0.0, 0.9999)
	var idx := int(p * float(VFX_FRAMES))
	return frame_at(vfx_strip_path(name), idx, VFX_FRAMES)


## 特效帧条路径（唯一来源，避免各处拼字符串拼错）。
static func vfx_strip_path(name: String) -> String:
	return "%s/%s.png" % [VFX_ROOT, name]


static func has_vfx(name: String) -> bool:
	return load_texture(vfx_strip_path(name)) != null


static func vfx_size_px(name: String) -> int:
	return int(VFX_FRAME_PX.get(name, 96))


# ============================================================ 背景 / UI

## 关卡背景贴图（未知关卡退回默认环境，绝不返回 null 造成黑屏）。
static func stage_background(stage_id: String) -> Texture2D:
	var env: String = str(STAGE_ENV.get(stage_id, DEFAULT_ENV))
	var tex := load_texture("%s/environments/%s.png" % [ART_ROOT, env])
	if tex == null:
		tex = load_texture("%s/environments/%s.png" % [ART_ROOT, DEFAULT_ENV])
	return tex


static func environment(name: String) -> Texture2D:
	return load_texture("%s/environments/%s.png" % [ART_ROOT, name])


static func title_background() -> Texture2D:
	return load_texture("%s/environments/bg_title_gate.png" % [ART_ROOT])


## UI 图标（size 取 32 / 64）。
static func icon(name: String, size: int = 32) -> Texture2D:
	if name == "icon_necklace": return load_texture("res://assets/art/ui/icons/icon_necklace.svg")
	return load_texture("%s/ui/icons/%s_%d.png" % [ART_ROOT, name, size])


# ============================================================ 诊断

## 返回当前已解析的资源统计（供验收脚本与报告使用）。
static func stats() -> Dictionary:
	var loaded := 0
	var missing := 0
	for k: String in _tex_cache.keys():
		if _tex_cache[k] == null:
			missing += 1
		else:
			loaded += 1
	return {"loaded": loaded, "missing": missing, "missPaths": _miss_cache.keys()}


## Clear at explicit application shutdown, or when resetting an isolated test.
static func clear_cache() -> void:
	_tex_cache.clear()
	_atlas_cache.clear()
	_miss_cache.clear()


# ============================================================ 状态 -> 动画选择

## 依据战斗运行时的角色状态选择动画名。
## 纯表现层映射，不读取也不修改任何领域规则。
static func character_anim_for(c: CharacterRuntime, t: float) -> String:
	if c == null:
		return "idle"
	if c.is_incapacitated():
		return "death"
	if c.has_method("is_attacking") and c.is_attacking():
		return "attack"
	return "idle"


## 依据敌人运行时状态选择动画名。
static func enemy_anim_for(e: EnemyRuntime, t: float) -> String:
	if e == null:
		return "idle"
	if not e.is_active():
		return "death"
	return "move"
