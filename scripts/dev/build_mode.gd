## BuildMode — Prototype / Retail 构建模式判定（P1.0）。
##
## 判定依据（V2.1.4 L9 导出 / 本轮指令 四）：
##   Godot 导出预设 export_presets.cfg 的 custom_features 会作为 feature tag
##   暴露给 OS.has_feature()，因此不需要任何运行时配置或外部文件即可区分两种构建：
##     preset.0 "Windows Desktop" -> custom_features="prototype"（演示 / 试玩构建）
##     preset.1 "Windows Retail"  -> custom_features="retail"   （正式零售构建）
##   编辑器内直接运行、或未打任何 tag 时按 Prototype 处理（开发态）。
##
## 纪律（本轮指令 四 明文）：
##   1. 开发验证可保留：开发专用入口（--dev-roster=*、--stage=*、--autoplay）
##      在 Prototype 构建下照常可用。
##   2. **不允许**把测试阵容覆盖误认为正式解锁。
##   3. 正式零售构建**不得**通过开发参数绕过解锁条件——因此所有开发专用入口的
##      准入判断一律以 allows_dev_entries() 为准，不得各自散落读 feature tag。
class_name BuildMode
extends RefCounted

## 正式零售构建的 feature tag（export_presets.cfg 的 preset.1.custom_features）
const FEATURE_RETAIL := "retail"

## 演示 / 试玩构建的 feature tag（export_presets.cfg 的 preset.0.custom_features）
const FEATURE_PROTOTYPE := "prototype"


## 是否正式零售构建。
static func is_retail() -> bool:
	return OS.has_feature(FEATURE_RETAIL)


## 是否 Prototype（演示 / 试玩 / 开发）构建。与 is_retail() 严格互补。
static func is_prototype() -> bool:
	return not is_retail()


## 构建模式名（日志与界面标识用）。
static func mode_name() -> String:
	return "Retail" if is_retail() else "Prototype"


## 是否允许开发专用入口（--dev-roster=*、--stage=*、--autoplay）。
##
## 所有开发专用入口的准入判断必须走这里：Retail 构建下一律为 false，
## 从机制上保证正式零售构建无法用开发参数绕过角色解锁条件。
static func allows_dev_entries() -> bool:
	return not is_retail()
