## PrototypeRoster — P0.4 **开发专用入口**：三职业共同出场的 Prototype 场景配置。
##
## 纪律（本轮指令 四）：
##   正式第一章的解锁顺序**不可**为测试方便而改动：
##     1-1 雨宫澪 / 1-3 神谷悠真 / 1-6 小川结衣
##   因此本文件**不写入 data/**、**不修改任何 StageConfig 数据文件**，
##   而是在运行时于内存中克隆一份关卡配置并覆盖 availableCharacters，
##   仅用于开发与实机验收。正式流程（不带开关）永远走 data/stages/ch1/1-1.json 的原始规则。
##
## 用法（**仅非 Retail 构建**）：
##   HoshigaokaEchoes.exe -- --scene=battle --dev-roster=triple
##
## 该覆盖是**显式开关**：不带 --dev-roster 时行为与 P0.3 完全一致。
##
## P1.0 构建隔离（本轮指令 四）：
##   本文件是**开发专用入口**，只在**非 Retail 构建**（Prototype / 编辑器运行）生效。
##   正式零售构建（export_presets.cfg preset.1 "Windows Retail"，custom_features="retail"）
##   下 requested_triple() 一律返回 false，并打印一条明确的拒绝告警——
##   正式构建不得通过开发参数绕过角色解锁条件（1-1 澪 / 1-3 悠真 / 1-6 结衣）。
##   准入判定统一走 BuildMode.allows_dev_entries()，不在此处各自读 feature tag。
##
##   注意：apply_triple() 是**供测试与开发工具直接调用**的纯函数，不受构建模式限制
##   （测试需要在任何构建下验证副本语义），它只作用于传入字典的深拷贝，
##   不回写 DataRegistry、不影响任何已构建的运行时。
class_name PrototypeRoster
extends RefCounted

const TAG := "PrototypeRoster"

## 开关名（命令行用户参数）
const ARG_TRIPLE := "--dev-roster=triple"

## 三职业 Prototype 编队（与正式解锁关卡无关，仅开发用）
const TRIPLE_ROSTER: Array[String] = ["amamiya_mio", "kamiya_yuma", "ogawa_yui"]

## 覆盖后的开局 AP：三职业合计费用 10+12+14 = 36 > 上限 30，
## 为了让实机验收能在同一局内把三人全部放下，开发场景把开局 AP 顶到上限 30
## （自然回复仍为 1/秒，仍受 30 上限约束）。
const TRIPLE_STARTING_AP := 30


## 是否请求了三职业开发场景。
##
## Retail 构建（BuildMode.allows_dev_entries() 为 false）直接返回 false，
## 并打印明确告警：正式零售构建不得用 --dev-roster=triple 绕过解锁条件。
static func requested_triple() -> bool:
	if not BuildMode.allows_dev_entries():
		for arg: String in OS.get_cmdline_user_args():
			if arg == ARG_TRIPLE:
				GameLog.warn(TAG, "Retail 构建拒绝开发专用入口 --dev-roster=triple")
				break
		return false
	for arg: String in OS.get_cmdline_user_args():
		if arg == ARG_TRIPLE:
			return true
	return false


## 在**内存副本**上应用三职业覆盖；原字典不被修改。
## 返回新的配置字典（未请求时原样返回传入字典）。
static func apply_if_requested(stage_config: Dictionary) -> Dictionary:
	if not requested_triple():
		return stage_config
	return apply_triple(stage_config)


## 强制应用三职业覆盖（供测试与开发工具直接调用，不依赖命令行）。
static func apply_triple(stage_config: Dictionary) -> Dictionary:
	var cfg := stage_config.duplicate(true)
	cfg["availableCharacters"] = TRIPLE_ROSTER.duplicate()
	cfg["startingAp"] = TRIPLE_STARTING_AP
	cfg["_devRoster"] = "triple"
	cfg["_devRoster_note"] = "开发专用覆盖：仅内存生效，未写入任何 data 文件，不影响正式章节解锁顺序。"
	return cfg
