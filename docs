# 《星丘残响》当前可见界面美术覆盖清单

> 生成时间：2026-10-10（六小时无人值守美术施工）
> 施工前基线：`689dbc0` / `a0.5-baseline`
> **续工轮**（03:10–06:45 窗口内）：`art-pass-1-baseline` → 见 §7 Git 记录
> **本清单的分母是实际扫描出的、玩家当前真实可到达的界面与资产**，不是生成图片数量。
> 最终数字已由独立验收员 `art-verifier` 在隔离 worktree 中逐文件核验。

## 0. 扫描方法

对 `hoshigaoka_echoes` 工程做静态扫描 + 实机启动确认：

1. `SceneRouter.SCENES` 登记项与实际 `scenes/**/*.tscn` 文件比对；
2. `data/characters.json` / `data/enemies.json` 的 `artRefs` / `spriteFramePx` 字段；
3. `data/stages/**/*.json` 的实际可玩关卡与 `availableCharacters`；
4. 实际启动游戏逐屏截图确认（`_testenv/artshot.ps1`，真实窗口 `CopyFromScreen`）。

## 1. 界面可达性盘点（施工前）

| # | 界面 | 场景文件 | 施工前是否可达 | 说明 |
|---|---|---|---|---|
| 1 | 启动诊断场景 | `scenes/bootstrap/bootstrap.tscn` | 是（`--scene=bootstrap`） | 空白 Node2D，仅诊断，非玩家界面 |
| 2 | **战斗场景** | `scenes/battle/battle_scene.tscn` | **是**（无参数双击即进） | 唯一玩家主界面；全部几何占位绘制 |
| 3 | **角色培养界面** | `scenes/menus/character_screen.tscn` | **是**（`--scene=character`） | 纯文字+色块 |
| 4 | 标题画面 | `scenes/title/title.tscn` | **否 — 文件不存在** | 仅登记在 `SceneRouter.SCENES` |
| 5 | 校园 Hub | `scenes/home/home.tscn` | **否 — 文件不存在** | 仅登记在 `SceneRouter.SCENES` |
| 6 | 设置页 | — | **否 — 未实现** | 不列入覆盖目标 |
| 7 | 装备界面 | — | **否 — 未实现** | A0.5 只有领域层 API，无 UI |
| 8 | 剧情播放器 | — | **否 — 未实现** | StoryRunner 属 A0.7 |

**结论：施工前玩家真实可到达的界面只有 2 个（战斗、角色培养）。**

## 2. 资产可达性盘点（施工前）

| 类别 | 实际需要 | 施工前已有 | 覆盖率 |
|---|---|---|---|
| 可部署角色战斗 Sprite | 3（澪/悠真/结衣） | **0** | 0% |
| 角色头像 | 3 | **0** | 0% |
| 已出现敌人 Sprite | 7（普通/疾走/装甲/试卷飞灵/沉默学生/作弊纸偶/监考者） | **0** | 0% |
| 战斗背景 | 5 个环境（1-1～1-5 + 演示关 + 1-10） | **0** | 0% |
| UI 图标 | 资源/状态/操作 共 25 类 | **0** | 0% |
| 战斗特效 | 6 类事件反馈 | **0** | 0% |
| 标题画面背景 | 1 | **0** | 0% |

**整个工程此前 `assets/art/**` 下无任何图片文件 —— 所有画面都是 `battle_scene.gd` 的 `_draw()` 立即模式几何图元。**

## 3. 施工后覆盖状态

### 3.1 资产层（已完成）

| 资产 | 数量 | 规格 | 状态 | 证据 |
|---|---|---|---|---|
| 角色战斗 Sprite | 3 角色 × 5 动画 = 15 帧条 | 64×64 | `INTEGRATED` | 实机截图 `art_1-1_02_deployed.png` |
| 敌人 Sprite | 7 种 × 5 动画 = 35 帧条 | 64 / 96 | `INTEGRATED` | 实机截图 `art_1-1_01_start.png` |
| 战斗背景 | 5 张 | 1920×1080 | `INTEGRATED` | 实机截图（教室黄昏/体育馆夜） |
| 角色头像 | 3 套 × 2 档 | 256 / 64 | `FINAL_CANDIDATE` | `char_after_03_loaded.png` |
| UI 图标 | 25 类 × 2 档 = 50 | 32 / 64 | 11 类 `INTEGRATED` + 14 类预留 | HUD / 角色界面 |
| 战斗特效 | 6 组 × 8 帧 = 48 帧 | 96 / 128 | `INTEGRATED` | `vfx_01_combat.png` |
| 标题画面背景 | 1 | 1920×1080 | `INTEGRATED` | `title_01_default.png` |

**实际导入游戏资产：`assets/art` 124 文件 / 16.06 MB + `assets/vfx` 6 文件 / 238.9 KB。**
（独立验收员逐文件核验：尺寸 0 项不符、0 损坏、0 空文件。）

### 3.2 界面层

| 界面 | 施工前 | 施工后 | 状态 |
|---|---|---|---|
| 战斗场景 | 全几何占位 | 背景贴图 + 角色/敌人 Sprite + 6 类特效 + 面板化 HUD | `INTEGRATED` |
| 角色培养 | 纯文字色块 | 背景 + 256 头像 + 图标 + 进度条 + 突破节点 + 按钮三态 | `INTEGRATED` |
| 标题画面 | 不存在 | 新建场景 + 4 行菜单 + 背景 | `INTEGRATED` |

**覆盖率：3 / 3 真实可达界面具备统一基础美术。**
（施工前为 0 / 3 —— 因为一个贴图都没有。）

## 4. 状态标记定义

- `FINAL_CANDIDATE`：质量较完整，尚待用户最终审美确认
- `INTEGRATED`：已真实接入游戏并通过技术验收（实机截图 + 回归测试）
- `NEEDS_POLISH`：已能使用但明显需要精修
- `PLACEHOLDER`：仍是占位
- `BLOCKED`：有客观阻塞及证据

**本轮所有资产均未获得用户审美批准**（用户在授权窗口内不参与开发）。

## 5. 尚未覆盖 / 待人工精修

1. **角色攻击/受击/死亡动画未按战斗事件逐帧切换** —— ✅ **本轮已闭合**。
   新增 `scripts/art/anim_state.gd`（AnimState 状态机），并把
   `attack / hit / death / move / idle` 全部接入真实战斗事件。
   **量化证据**（1-3 真实自动战斗，非合成）：
   ```
   char_anim:attack×9742, hit×662, death×1600, idle×5015
   enemy_anim:move×43091, attack×1400, hit×260, idle×8
   vfx:deploy×138, vfx:impact×1654
   ```
   18 项 GUT 用例覆盖（含「死亡不被受击覆盖」「状态机零副作用」两条硬性契约）。
2. **4K 与 Windows 125% / 150% 缩放未做实机验证**——代码走 `_px()` 同比缩放，
   理论上成立，但**没有实机证据，不声称已验证**。
3. **角色 Sprite 武器摆动幅度较小**——"单底图派生"策略的代价
   （收益是帧间零漂移）。**未改进，如实保留。**
4. **战斗 HUD 的角色卡悬停态未取到实机画面**——代码已实现，但自动化脚本
   难以稳定触发（需真实鼠标停留）。**未验证即未验证。**
   （胜利金色结算已在本轮取到：`accept12/10_victory_result.png`。）
5. **装备界面 / 校园 Hub / 剧情播放器 / 设置页均不存在**，**未虚构**。
6. **规格首发 6 名角色，工程当前只有 3 名角色有数据** ⇒ 只做了 3 名。
7. **`--autoplay` 部署未真正落下** —— ✅ **本轮已修复**。
   根因：`Input.parse_input_event()` 的合成事件被引擎当作真实 OS 输入，
   `stretch(canvas_items)` 的窗口→画布变换会再施加一次，而
   `_cell_screen_pos()` 返回的已是画布坐标 ⇒ 落点被缩放两次跑到战场外。
   修复后日志出现 `玩家部署 雨宫澪 于 (col2, lane1)`。
8. **`artshot.ps1 -Scene character` 偶发 `CLIENT 0x0`** —— ✅ **本轮已修复**。
   新增客户区就绪等待 + 截图非空断言；character 连跑 3 次全部 `SHOT-OK`。

## 6. 预留资产口径（已裁定）

独立验收员指出约 14 类图标 + 3 张 `char_*_portrait_01.png` 无代码引用。
**裁定为「预留资产库」**，并已用测试用例把口径变成可执行约束：

- `RESERVED_ICONS`：14 类（装备/纪念物/操作/资源体系），服务尚未实现的界面。
- `char_*_portrait_01.png` ×3：与 `characters.json` 的 `artRefs` 命名对齐的**规范名**，
  保证数据层声明的文件名在磁盘上真实存在（V2.1.4 B6 SSOT 可验证性）。
- **它们不计入覆盖率分子。**
- `test_all_icons_accounted_for()` 守卫：磁盘上每个图标**要么被引用、要么在预留清单里**，
  杜绝"既没接入、也没登记"的孤儿资产。

## 7. Git 记录

| 提交 | 内容 |
|---|---|
| `62935e0` | 美术资产：10 实体像素 Sprite + 5 背景 + 50 图标 + 3 头像 |
| `e22874b` | 战斗画面美术接入：背景/角色/敌人贴图 + 几何回退 |
| `c07655e` | 6 组战斗特效帧条 + ArtRegistry VFX API |
| `7a447cd` | 标题画面场景 + 角色培养界面美术接入 |
| `476b354` | 战斗 HUD 精修 + 特效接入真实事件 + 美术层纳入 GUT 覆盖 |
| `a18b90d` | 预留资产口径裁定 + 孤儿资产守卫 |
| `fea99d5` | 美术施工交付文档四件套 + 资产生成清单（← `art-pass-1-baseline`） |
| `62f1946` | **动画状态机接入战斗事件 + 美术可达性检查** |
| `4965ff9` | **修复 --autoplay 部署不落下 + 截图脚本 CLIENT 0x0** |
| `f23b77e` | **可达性正面证据清单 + 12 张实机验收截图集** |

**原有 12 个标签全部未移动**（完整 hash 逐一核对）。

## 8. 续工轮实机验收截图集（12 张，全部真实窗口）

目录：`docs/art_screenshots/accept12/`

| 文件 | 内容 |
|---|---|
| `01_title.png` | 标题画面 |
| `02_character.png` | 角色培养界面 |
| `03_stage_1-1_start.png` | 1-1 初始（含新敌人教学卡） |
| `04_mio_deployed.png` | 雨宫澪部署后 |
| `05_yuma_deployed.png` | 神谷悠真部署后 |
| `06_crosslane_attack.png` | 跨线攻击（悠真在 1-3） |
| `07_enemy_hit.png` | 敌人受击 |
| `08_exam_sheet_attack.png` | 试卷飞灵（1-3） |
| `09_invigilator.png` | 监考者（1-5） |
| `10_victory_result.png` | **胜利金色结算**（上轮缺失项，本轮补齐） |
| `11_after_result.png` | 结算停留态 |
| `12_paused.png` | 暂停面板 |

**概念图对比集**：`docs/art_screenshots/concept_compare/`（5 张，左=概念图 / 右=实机）
