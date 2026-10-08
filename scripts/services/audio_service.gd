## AudioService — BGM/SFX 总线控制（L4 Autoload）。
##
## Phase 0 范围：总线音量管理 + 设置持久化骨架。
## 不含实际音频资源（首发资产见 J9/K 章，属后续阶段）。
extends Node

const TAG := "AudioService"

const BUS_MASTER := "Master"
const BUS_BGM := "BGM"
const BUS_SFX := "SFX"
## K-二十八：音量设置范围 0～100
const VOLUME_MIN := 0.0
const VOLUME_MAX := 100.0

## 逻辑总线名 -> 音量(0~100)
var _volumes: Dictionary = {
	BUS_MASTER: 100.0,
	BUS_BGM: 100.0,
	BUS_SFX: 100.0,
}


func _ready() -> void:
	_apply_all()


## 设置某总线音量（0～100）。
func set_volume(bus_name: String, value: float) -> void:
	_volumes[bus_name] = clampf(value, VOLUME_MIN, VOLUME_MAX)
	_apply_bus(bus_name)


## 读取某总线音量。
func get_volume(bus_name: String) -> float:
	return float(_volumes.get(bus_name, 100.0))


## 导出全部音量设置，供 SaveService/设置界面持久化。
func to_dict() -> Dictionary:
	return _volumes.duplicate()


## 从字典恢复音量设置。
func from_dict(data: Dictionary) -> void:
	for k: String in data.keys():
		if _volumes.has(k):
			_volumes[k] = clampf(float(data[k]), VOLUME_MIN, VOLUME_MAX)
	_apply_all()


func _apply_all() -> void:
	for bus_name: String in _volumes.keys():
		_apply_bus(bus_name)


func _apply_bus(bus_name: String) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		# Phase 0 未创建自定义总线，静默跳过（总线在音频阶段一并建立）。
		return
	var linear := float(_volumes.get(bus_name, 100.0)) / 100.0
	var db := linear_to_db(linear) if linear > 0.0 else -80.0
	AudioServer.set_bus_volume_db(idx, db)
