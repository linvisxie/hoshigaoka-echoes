# A0.6 局内强化三选一 · 真机证据归档

本目录是 A0.6「局内强化三选一」的**真机截图证据**归档。
全部图片为**真实 Windows 窗口客户区截图**（非 headless、非合成），
由 `tools/windows_art_capture.py` 在**隔离 APPDATA** 下采集，
对应 sidecar JSON 同目录存放。

- 采集日期：2026-10-10
- 采集环境：Godot 4.7.2-stable（真实窗口 1280×720 客户区）
- 关卡：`1-5`（教学固定三选一），全程 `--autoplay --autoplay-hold-upgrade`
- 输入方式：**真实 OS 鼠标**（`SetCursorPos` + `mouse_event`），非合成输入
- 证据性质：**自动化操作取证，不是真人试玩**（见每条 sidecar 的 `evidenceType`）

---

## 1. 归档名 → 原始捕获名 → 采集运行 映射

| 归档文件名 | 原始捕获名 | 采集运行 | 说明 |
| --- | --- | --- | --- |
| `run_final/a06_A_upgrade_panel_offered.png` | `upgrade_panel_offered.png` | A | 面板刚出现，光标已移开（未悬停任何卡） |
| `run_final/a06_A_upgrade_card_hover_0.png` | `upgrade_card_hover_0.png` | A | 真实光标停在第 0 张卡（会心准备） |
| `run_final/a06_A_upgrade_chosen.png` | `upgrade_chosen.png` | A | 真实点击后：面板关闭、战斗恢复、反馈「已获得强化：会心准备（攻击 +15%）」 |
| `run_final/a06_A_result_settled.png` | `result_settled.png` | A | 结算界面，含「本局构筑」区块 |
| `run_final/a06_A_outcome_胜利.png` | `outcome_胜利.png` | A | 胜利帧（与 result_settled 同帧） |
| `run_reroll/a06_B_upgrade_panel_offered.png` | `upgrade_panel_offered.png` | B | 同 A，独立第二次运行 |
| `run_reroll/a06_B_upgrade_card_hover_0.png` | `upgrade_card_hover_0.png` | B | 同上 |
| `run_reroll/a06_B_upgrade_rerolled.png` | `upgrade_rerolled.png` | B | **真实点击「重掷」后**：剩余重掷 0，反馈「已重掷：重新生成 3 个选项（剩余重掷 0）」 |
| `run_reroll/a06_B_upgrade_chosen.png` | `upgrade_chosen.png` | B | 重掷之后再真实点击第 0 张卡 |
| `run_reroll/a06_B_result_settled.png` | `result_settled.png` | B | 结算界面，含「本局构筑」区块 |
| `run_reroll/a06_B_outcome_胜利.png` | `outcome_胜利.png` | B | 胜利帧 |

- **运行 A**：`--stage 1-5 --autoplay --autoplay-hold-upgrade --choose-upgrade 0 --upgrade-shots --duration 240`
- **运行 B**：运行 A 的参数 + `--reroll-upgrade`

每次运行的完整账本与日志一并归档，便于独立复核：

- `run_final/capture_summary.json`、`run_final/stdout.log`、`run_final/stderr.log`
- `run_reroll/capture_summary.json`、`run_reroll/stdout.log`、`run_reroll/stderr.log`

> 原始未改名文件（含 `initial`/`deployed_*`/`active_vfx_*` 等过程帧）保留在
> `_testenv/a06_capture/final/` 与 `_testenv/a06_capture/final_reroll/`。
> 归档时**只改名、不重新编码、不编辑像素**；SHA256 可直接与原始文件比对。

---

## 2. 采集完整性（实测账本，非人工声称）

两次运行的 `capture_summary.json` 均给出**基于文件系统**的核验结果
（不是"最后一次尝试的返回值"）：

| 运行 | upgradeEvidenceComplete | upgradeMissing | labelsClaimedButNotSaved |
| --- | --- | --- | --- |
| A（final） | `true` | `[]` | `[]` |
| B（final_reroll） | `true` | `[]` | `[]` |

即：期望的每一张证据图都**确实存在于磁盘**；没有任何"声称拍到但实际没落盘"的标签。
采集过程 **0 次 SKIP-OCCLUDED**（前台归属校验每次通过；一次被拒拍都没有）。

---

## 3. 逐张目视核对（read_image，逐张真看过）

| 归档图 | 目视核对结论 |
| --- | --- |
| A `upgrade_panel_offered` | 面板标题「残响强化」，教学行可见；三张卡（攻击型/防御型/资源型）名称、图标、效果、作用对象、叠加上限均清晰无重叠；「剩余重掷：1」；底部「本局已获得强化：暂无——这是本局第一次强化」。**三张卡视觉互不相同**（图标分别为箭/盾/星），非同一张图叠三次 |
| A `upgrade_card_hover_0` | 第 0 张卡出现明显悬停高亮（亮边框 + 「点击选择」提示），第 1/2 张卡无高亮 → 悬停确实是"第 0 张" |
| A `upgrade_chosen` | 面板已关闭、战斗已恢复（可见敌我单位与 AP 12/30）；底部反馈「已获得强化：会心准备（攻击 +15%）」 |
| A `result_settled` | 「胜利」结算界面；**「本局构筑」区块存在**：「会心准备 ×1 —— 远程攻击 +15%」「构筑方向：攻击型」；8/8 击杀、核心 3/3、无重叠 |
| B `upgrade_rerolled` | **「剩余重掷：0」**（点击前为 1）；反馈「已重掷：重新生成 3 个选项（剩余重掷 0）」；候选**仍为原来三项** |
| B `result_settled` | 同 A，含「本局构筑」区块 |

### 关于「重掷后候选不变」——这是设计，不是缺陷

域层日志（`run_reroll/stdout.log`）原文：

```
教学态重掷：候选保持固定 ["upgrade_ranged_atk", "upgrade_def_front", "upgrade_ap_regen"]
（L2132 首次固定三选一，不切换为随机）；剩余重掷 0 次
```

1-5 是**首次固定教学三选一**，按 L2132 重掷**刻意保持候选固定**，
只消耗重掷次数。因此"候选没换"是正确行为；本次取证证明的是
**重掷按钮被真实点到了**（剩余次数 1 → 0，且日志出现该行），而非候选被随机重建。

---

## 4. 同一构建的确定性（诚实说明，避免误读）

运行 A 与运行 B 的 `upgrade_panel_offered` / `upgrade_card_hover_0` / `upgrade_chosen`
三张图 **SHA256 完全相同**（例如 `upgrade_panel_offered` 两次均为 `DFA592795C4A3CDD…`）。

这不是"同一张图被复制两次"：两次运行的 sidecar `captured` 时间戳不同
（A `08:53:47`、B `09:01:46`），且各自是当场真实截屏。
相同的原因是**该构建在固定教学候选 + 相同部署路径下是确定性的**，
同一逻辑状态渲染出同一帧像素。

因此：**不要**把 A、B 的这三张图当作"两次独立确认"。真正由运行 B 独有/不同的是：

- `upgrade_rerolled`（仅 B 有）
- `result_settled` / `outcome_胜利`（两次 SHA 不同：`64C88351…` vs `FBFB0B9D…`，内容为时间等运行差异）

另外，`upgrade_chosen` 内容为**战斗已恢复**的画面而**不是强化面板**——
这是刻意的：它记录的是"点击之后"的选择反馈帧，而非面板本身。

---

## 5. 复核方法

```powershell
# 1) 比对归档图与原始图逐字节一致（只改名，未改内容）
Get-FileHash "docs\art_screenshots\a0_6\run_final\a06_A_upgrade_chosen.png" -Algorithm SHA256
Get-FileHash "_testenv\a06_capture\final\upgrade_chosen.png" -Algorithm SHA256

# 2) 看某张图的社会证据（探针状态、客户区像素、采集时间）
Get-Content "docs\art_screenshots\a0_6\run_final\a06_A_upgrade_chosen.json"

# 3) 复现同一条命令（注意：输出目录必须在 _testenv 下，工具会拒绝其它路径）
python tools\windows_art_capture.py --output _testenv\a06_capture\repro `
  --stage 1-5 --autoplay --autoplay-hold-upgrade --choose-upgrade 0 --upgrade-shots --duration 240
```

---

## 6. 已知边界（不夸大）

- 证据均为**自动化操作**，`evidenceType` 明确写为
  `real Windows client screenshot, automated operation (not human playtest)`。
  它证明"真实窗口在真实鼠标事件下呈现出正确画面"，**不等于**真人试玩体验验收。
- `stderr.log`（442 B）是**正确告警**：1-5 无治疗角色上阵，故 `vfx_heal` 从未触发；
  非缺陷，与既有 A0.6 结论一致。
- 本轮**未**重新导出 EXE（源码未冻结）；构建与包内容核验见
  `tools/a0_6_export.py` 与 `dist/a0_6/export_report.json`。
