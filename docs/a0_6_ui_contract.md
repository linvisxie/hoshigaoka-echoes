# A0.6 局内强化「可玩」冻结接口契约

本轮目标（唯一）：玩家打开 **1-5**，在真实战斗中看到三选一强化面板，
点击选择或使用 1 次免费重掷，效果立即作用于战斗，战斗正常打完并展示本局构筑。

本文件是**并行施工的接口冻结件**。三条工作线各自只碰自己列出的写域，
不得跨线改文件。任何一方要改本契约，先在此文件里改并通知其他两方。

---

## 1. 领域层新增 API（`scripts/domain/battle/stage_runtime.gd`）

由「领域线」实现；「表现线」只调用，不改实现。

```gdscript
## 当前待处理的三选一请求。{} = 无请求。
## 非空时字段：
##   candidates: Array[String]   当前候选（1~3 项）
##   isTutorial: bool            是否为 1-5 首次固定教学三选一
##   offerIndex: int             本次是第几次开放（1 起）
##   rerollsRemaining: int       剩余免费重掷次数
var pending_offer: Dictionary

func has_pending_offer() -> bool
## 玩家选定一项。成功: 应用效果 + 计入 selections_used + 清空 pending + 战斗恢复。
## 失败（无 pending / id 非法 / 次数用尽 / 战斗已结束）返回 false，且**不清空** pending。
func resolve_offer(upgrade_id: String) -> bool
## 消耗 1 次免费重掷并就地重建候选（保持 pending）。无次数或无效时 false。
func reroll_offer() -> bool
## 跳过本次强化（L2051 允许）。计入已用开放次数并清空 pending。
func skip_offer() -> bool
## 1-5 首次通关时启用固定教学三选一（是否「首次」由表现/存档层判定后注入）。
func set_tutorial_offer_enabled(value: bool) -> void
## 本局已获得强化（按获得顺序），供 HUD 与结算展示。条目：
##   {id, name, description, stacks, maxStacks, tier, category, icon}
func upgrade_summary() -> Array[Dictionary]
```

冻结语义：

- **触发时机**：波次清空时（`_complete_current_wave` 之后）。数据 `openByStage.<stage>.triggerWaves`
  列出**允许触发的已完成波号**；剩余开放次数 > 0 且当前波号命中且战斗未结束才触发。
- **1-5 数据**：`opens = 1`、`triggerWaves = [1]`、`rerollsPerBattle = 1`。
- **冻结战斗**：`pending_offer` 非空期间 `advance()` 不推进任何计时器（返回空数组），
  且**不得**把 `paused` 置为 true（用户暂停是另一套状态，两者不可混用）。
  这样「选择界面不计入技能 CD 或敌人移动时间」（L1972）成立。
- **战斗已结束时**：resolve / reroll / skip 一律返回 false；pending 不得再产生。
- **教学回落**：`tutorial_offer_enabled == false` 或教学项不可用（缺失/满叠）→ 走随机候选。
- **重掷确定性**：候选仍由 `_upgrade_seed()` 派生，重掷次数参与种子，帧率无关性不得破坏。

## 2. 数据层（`data/upgrades.json`）

每条强化新增两个字段，`InBattleUpgrades.from_data()` 校验其存在与合法：

```json
"category": "攻击型",
"icon": "icon_attack_up"
```

- `category` ∈ {攻击型, 防御型, 资源型, 技能型, 职业型}（L1979 表 79 类别名）。
- `icon` 必须是 `assets/art/ui/icons/<icon>_64.png` 真实存在的图标名。
- 校验失败 → 进 `load_errors`（沿用既有纪律：宁可不开，不带坏数据跑）。

## 3. 表现层探针契约（`user://art_probe/latest.json`）

取证工具依赖此结构；键名不得改动（可新增键）。

```json
"upgradeOffer": {
  "active": true,
  "ids": ["upgrade_ranged_atk", "upgrade_def_front", "upgrade_ap_regen"],
  "isTutorial": true,
  "rerollsRemaining": 1,
  "cardRects": [[x, y, w, h], ...],   // 画布坐标，与既有 cardRects 同口径
  "rerollRect": [x, y, w, h],
  "skipRect": [x, y, w, h]
},
"gainedUpgrades": [{"id": "...", "name": "...", "stacks": 1}]
```

`upgradeOffer.active = false` 时 `ids`/`cardRects` 为空数组。

## 4. 表现层交互（`scenes/battle/battle_scene.gd`）

- 面板：战斗暂停后中央弹出三张横向卡片；每卡显示**名称 / 类别 / 作用对象 / 效果描述 / 可叠加上限 / 图标**。
- 底部一行：`剩余重掷：N` + 重掷按钮 + 跳过按钮 + 本局已获得强化列表。
- 鼠标：左键点卡片 = 选择；点重掷 = 重掷；点跳过 = 跳过。
- 键盘：`1/2/3` 选择对应卡片；`R` 重掷。
- 面板激活期间：`Esc` 不取消、暂停按钮与 `Space` 不改变暂停态（给反馈「先完成强化选择」）。
- 选择反馈：卡片高亮 + 屏幕反馈文案（含生效数值）+ 领域层日志。
- 结算界面：在主要结算数据后加一行「本局构筑」，列出全部已选强化（名称 + 层数）。
- autoplay：面板激活时自动选第一项（仅自动化，日志标注不得当作真人证据），保证长跑仍能完成。

## 5. 写域（并行施工不得越界）

| 线 | 允许写 |
| --- | --- |
| 领域线 | `scripts/domain/battle/stage_runtime.gd`、`scripts/domain/battle/in_battle_upgrades.gd`、`data/upgrades.json`、`tests/test_a0_6_*.gd` |
| 表现线（Lead） | `scenes/battle/battle_scene.gd` |
| 取证线 | `tools/*.py`、`dist/a0_6/**`、`docs/art_screenshots/a0_6/**` |
| 验证线 | 只读；产物写 `_testenv/**` |

`scenes/battle/battle_scene.gd` 由表现线独占；领域线若要新增纯逻辑函数，放
`scripts/domain/battle/` 下，不要在场景脚本里落域层规则。
