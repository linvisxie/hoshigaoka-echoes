# takeover 证据集：命名与来源映射

生成：2026-10-10 接管轮。**每张图片都有同名 `.json` sidecar，内含真实捕获时刻、
实测客户区尺寸、当时的游戏状态快照（在场敌人/角色、活跃特效、实际绘制账本）。**

证据类型统一为：**真实 Windows 客户区截图 + OS 级合成输入驱动的自动操作**，
**不是真人试玩**；sidecar 的 `evidenceType` 字段已逐份标注。

## 归档改名映射（重要）
归档时为了可读性改过部分文件名，**sidecar 内的 `image` 字段仍指向捕获时的原始文件名**。
两者对应关系如下（未改动任何 sidecar 内容，避免伪造元数据）：

| 归档名 | 原始捕获名 | 采集运行 |
|---|---|---|
| `armored_1-5.png` | `enemy_present_echo_armored.png` | `shot/capture-1-5b` |
| `invigilator_1-5_wave2.png` | `enemy_present_echo_invigilator.png` | `capture-1-5b` |
| `exam_sheet_1-3_wave2.png` | `enemy_present_echo_exam_sheet.png` | `shot-1-3d` |
| `victory_1-3_result.png` | `outcome_胜利.png` | `shot-1-3d` |
| `card_sel0_hover1_stacked_tutorial.png` | `card_sel0_hover1.png` | `shot-stack2`（教学卡堆叠修复后） |
| 其余 | 同名 | `shot-demo` / `shot-hover3` / `capture-1-3b` |

`card_sel0_hover1.png`（修复前）与 `card_sel0_hover1_stacked_tutorial.png`（修复后）
**两张都保留**，用于对照教学卡纵向堆叠修复的实际效果。
`capture_summary.json` 不对应单张图片，是整轮采集的标签与进程树清单。

## 证伪与撤回记录（不隐藏）
- `accept12/08_exam_sheet_attack.png`、`accept12/09_invigilator.png` 经逐张核对
  实为**失败结算面板**，命名不实 → 已在覆盖清单 §9.1 撤回。
- 接管轮曾一度把一张**其他应用遮挡画面**当作试卷飞灵证据归档，复核后删除 →
  见提交「撤回无效证据」。
- 教训已固化进取证工具：必须**事件驱动**（探针确认实体在场才拍）+
  前台归属校验 + 被遮挡即拒拍 + 逐张 `read_image` 目视复核。
  固定秒数盲拍在本轮三次产出不实证据，不得再用。
