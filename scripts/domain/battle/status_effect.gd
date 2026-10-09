## StatusEffect — 通用状态效果容器（V2.1.4 L556～557 Debuff 结算规则的承载层）。
##
## 规格依据（LOCKED，v214_ordered.txt L556～557 原文）：
##   「同一 effectId 的减益不可无限叠层，重复施加默认只刷新持续时间；不同 effectId 的
##     攻击、攻击速度、技能 CD 恢复速度减益以"相对基础值的百分数"先相加，再与增益统一
##     结算，最后夹取下限。有效攻击力、有效攻击频率、有效技能冷却恢复速度均不得低于
##     各自基础值的 40%（首轮可配置下限）。……控制类沉默仅禁止主动技能，不改变普通
##     攻击频率，除非该效果另有明确配置。」
##   「持续时间、来源 ID、stackPolicy、属性系数归属于技能/敌人配置，不在 UI 或状态显示层
##     另存规则。」
##
## 设计纪律：
##   ① 本类**不含任何敌人专属逻辑**，也不含任何数值常量；全部参数由构造方从 enemies.json
##      的 mechanic 段读出后传入（数据驱动）。
##   ② 只按 effectId 做叠加裁决（L556「同一 effectId」），不做跨 effectId 的合并——
##      合并发生在 CharacterRuntime 汇总侧。
##   ③ 纯逻辑、RefCounted，不依赖场景节点。
class_name StatusEffect
extends RefCounted

## 叠层策略（L556 默认「重复施加只刷新持续时间」）
enum StackPolicy {
	REFRESH_DURATION = 0,  ## 重复施加只把 expiresAt 重置为 now + duration，不新增条目
	IGNORE = 1,            ## 已有同名效果时，新的施加被忽略
}

## 作用属性分类。SILENCE 不参与百分数求和（L557：沉默不改变普通攻击频率）。
const CATEGORY_ATTACK := "ATTACK"
const CATEGORY_ATTACK_SPEED := "ATTACK_SPEED"
const CATEGORY_CD_RECOVERY := "CD_RECOVERY"
const CATEGORY_SILENCE := "SILENCE"
const CATEGORY_MOVE_SPEED := "MOVE_SPEED"

## 唯一效果 ID（叠加裁决的依据）。例："invigilator_gaze" / "silent_student_mute"。
var effect_id: String = ""
## 来源 ID（施加者）。例："echo_invigilator" / "echo_silent"。仅作登记，不参与判定。
var source_id: String = ""
## 作用属性分类（见上方 CATEGORY_* 常量）。
var category: String = ""
## 相对基础值的百分数：减益为负、增益为正。SILENCE 恒为 0（不改变任何数值）。
var pct: float = 0.0
## 单次施加的持续时长（秒）。刷新时用它重算 expiresAt。
var duration: float = 0.0
## 叠层策略
var stack_policy: int = StackPolicy.REFRESH_DURATION
## 施加时刻与到期时刻（逻辑秒，来自 StageRuntime.elapsed_seconds）
var applied_at: float = 0.0
var expires_at: float = 0.0


## 从 enemies.json 的 mechanic 段条目构建（数据驱动：所有字段都来自配置）。
## 缺字段时保持默认值，由调用方负责校验；本类不做静默兜底以外的推断。
static func from_config(cfg: Dictionary, now: float) -> StatusEffect:
	var e := StatusEffect.new()
	e.effect_id = str(cfg.get("effectId", ""))
	e.source_id = str(cfg.get("sourceId", ""))
	e.category = str(cfg.get("category", ""))
	e.pct = float(cfg.get("pct", 0.0))
	e.duration = float(cfg.get("durationSeconds", 0.0))
	e.stack_policy = parse_stack_policy(str(cfg.get("stackPolicy", "REFRESH_DURATION")))
	e.applied_at = now
	e.expires_at = now + e.duration
	return e


## 把配置里的 stackPolicy 字符串解析为枚举；未知值回落到规格默认 REFRESH_DURATION（L556）。
static func parse_stack_policy(text: String) -> int:
	match text:
		"IGNORE":
			return StackPolicy.IGNORE
		"REFRESH_DURATION":
			return StackPolicy.REFRESH_DURATION
		_:
			return StackPolicy.REFRESH_DURATION


## 是否已到期（到期时刻 ≤ now）。到期边界按「到点即失效」处理。
func is_expired(now: float) -> bool:
	return now >= expires_at


## 剩余秒数（已到期返回 0）
func remaining(now: float) -> float:
	return maxf(0.0, expires_at - now)


## 是否为控制类（沉默）。控制类不参与百分数求和，也不受 40% 下限夹取（L557）。
func is_control() -> bool:
	return category == CATEGORY_SILENCE


## 刷新持续时间（L556「重复施加默认只刷新持续时间」）。
## 不改变 pct / duration / 来源，只把 appliedAt 与 expiresAt 前移。
func refresh(now: float) -> void:
	applied_at = now
	expires_at = now + duration


func to_debug_dict(now: float = -1.0) -> Dictionary:
	var out := {
		"effectId": effect_id,
		"sourceId": source_id,
		"category": category,
		"pct": pct,
		"duration": duration,
		"appliedAt": snappedf(applied_at, 0.001),
		"expiresAt": snappedf(expires_at, 0.001),
	}
	if now >= 0.0:
		out["remaining"] = snappedf(remaining(now), 0.001)
		out["expired"] = is_expired(now)
	return out
