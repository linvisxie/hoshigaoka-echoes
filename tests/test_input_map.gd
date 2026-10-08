## Phase 0 验收测试：InputMap 契约（V2.1.4 L7）
##
## 验证：L7 要求的 Action 全部已注册，且业务层可通过 Action 名查询。
## 注意：本测试只断言 Action 存在性与键位映射，不含任何玩法逻辑。
extends GutTest

## V2.1.4 L7 要求的 Action 列表
const REQUIRED_ACTIONS := [
	"select_slot_1",
	"select_slot_2",
	"select_slot_3",
	"select_slot_4",
	"select_slot_5",
	"select_slot_6",
	"cancel_action",
	"pause_game",
	"confirm_action",
	"unit_skill",
	"unit_retreat",
]


func test_all_l7_actions_are_registered() -> void:
	for action_name: String in REQUIRED_ACTIONS:
		assert_true(
			InputMap.has_action(action_name),
			"L7 要求的 Action 应已注册: %s" % action_name
		)


func test_slot_actions_have_events() -> void:
	for i: int in range(1, 7):
		var action_name := "select_slot_%d" % i
		if not InputMap.has_action(action_name):
			fail_test("缺少 Action: %s" % action_name)
			continue
		assert_gt(
			InputMap.action_get_events(action_name).size(), 0,
			"%s 应至少绑定一个按键事件" % action_name
		)


func test_core_battle_actions_have_events() -> void:
	for action_name: String in ["pause_game", "unit_skill", "unit_retreat", "cancel_action"]:
		if not InputMap.has_action(action_name):
			fail_test("缺少 Action: %s" % action_name)
			continue
		assert_gt(
			InputMap.action_get_events(action_name).size(), 0,
			"%s 应至少绑定一个按键事件" % action_name
		)


## L7 要求：业务层只能查询 Action，不直接判断具体 KeyCode。
## 本测试确认 Action 名与"语义"对应，未来换键位不需改业务逻辑。
func test_slot_actions_use_number_keys_1_to_6() -> void:
	var expected_keycodes := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6]
	for i: int in range(1, 7):
		var action_name := "select_slot_%d" % i
		if not InputMap.has_action(action_name):
			continue
		var events := InputMap.action_get_events(action_name)
		var found := false
		for ev: InputEvent in events:
			if ev is InputEventKey and (ev as InputEventKey).physical_keycode == expected_keycodes[i - 1]:
				found = true
				break
		assert_true(found, "%s 应绑定数字键 %d" % [action_name, i])
