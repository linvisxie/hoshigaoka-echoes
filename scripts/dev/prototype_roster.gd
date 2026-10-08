## PrototypeRoster — P0.4 **开发专用入口**：三职业共同出场的 Prototype 场景配置。
##
## 纪律（本轮指令 四）：
##   正式第一章的解锁顺序**不可**为测试方便而改动：
##     1-1 雨宫澪 / 1-3 神谷悠真 / 1-6 小川结衣
##   因此本文件**不写入 data/**、**不修改任何 StageConfig 数据文件**，
##   而是在运行时于内存中克隆一份关卡配置并覆盖 availableCharacters，
##   仅用于开发与实机验收。正式流程（不带开关）永远走 data/stages/ch1/1-1.json 的原始规则。
##
## 用法（Release EXE 同样可用）：
##   HoshigaokaEchoes.exe -- --scene=battle --dev-roster=triple
##
## 该覆盖是**显式开关**：不带 --dev-roster 时行为与 P0.3 完全一致。
class_name PrototypeRoster
extends RefCounted

## 开关名（命令行用户参数）
const ARG_TRIPLE := "--dev-roster=triple"

## 三职业 Prototype 编队（与正式解锁关卡无关，仅开发用）
const TRIPLE_ROSTER: Array[String] = ["amamiya_mio", "kamiya_yuma", "ogawa_yui"]

## 覆盖后的开局 AP：三职业合计费用 10+12+14 = 36 > 上限 30，
## 为了让实机验收能在同一局内把三人全部放下，开发场景把开局 AP 顶到上限 30
## （自然回复仍为 1/秒，仍受 30 上限约束）。
const TRIPLE_STARTING_AP := 30


## 是否请求了三职业开发场景
static func requested_triple() -> bool:
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
