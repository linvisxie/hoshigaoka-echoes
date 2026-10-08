## App — 启动、全局流程与版本信息（L4 Autoload）。
##
## Phase 0 范围：记录启动信息、暴露版本/阶段常量、提供退出入口。
## 不含玩法逻辑、不做场景推进（场景推进归 SceneRouter）。
extends Node

const TAG := "App"

## 与 project.godot 的 config/version 保持一致
const APP_VERSION := "0.1.0-prototype"
const APP_NAME := "HoshigaokaEchoes"

## 当前开发阶段（V2.1.4 B4 阶段术语：Prototype / Alpha / Beta / RC / Release）
const PHASE := "Prototype"

## 当前 Prototype 子阶段（V2.1.4 M2 表 114 的退出标准逐级对应）
## P0.1 战场与移动 / P0.2 部署与战斗 / P0.3 撤退·再部署·Wave·完整一局
## P0.4 神谷悠真 + 小川结衣 + 三职业基础战斗（前线 / 远程 / 治疗）
const PROTOTYPE_STAGE := "P0.4"

## 规格版本（唯一权威总规格）
const SPEC_VERSION := "V2.1.4 CLEAN MASTER"


func _ready() -> void:
	GameLog.info(TAG, "%s %s (%s %s) 启动"
		% [APP_NAME, APP_VERSION, PHASE, PROTOTYPE_STAGE])
	GameLog.info(TAG, "权威规格: %s" % SPEC_VERSION)
	GameLog.info(TAG, "引擎: %s" % Engine.get_version_info().get("string", "unknown"))
	GameLog.info(TAG, "用户数据目录: %s" % OS.get_user_data_dir())


## 返回版本信息字典，供 UI / 诊断 / 测试使用。
func get_version_info() -> Dictionary:
	return {
		"appName": APP_NAME,
		"appVersion": APP_VERSION,
		"phase": PHASE,
		"prototypeStage": PROTOTYPE_STAGE,
		"specVersion": SPEC_VERSION,
		"engine": Engine.get_version_info().get("string", "unknown"),
	}


## 界面用阶段标识（单一来源：不散落在各场景里手写 P0.x）
func stage_label() -> String:
	return "%s %s" % [PHASE, PROTOTYPE_STAGE]


## 请求退出（Hub 的 Esc 菜单二次确认后调用；二次确认 UI 属 Alpha A0.7）。
func request_quit() -> void:
	GameLog.info(TAG, "收到退出请求，正在退出")
	get_tree().quit()
