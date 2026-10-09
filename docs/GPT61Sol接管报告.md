# 《星丘残响》GPT-6.1 Sol 接管报告

> 接管时间：2026-10-10 04:46 起。原六小时窗口 00:45:24–06:45:24，本工作在其内继续，不重新计时。
> 接管基线：实际 `master/e314de6`（**不是** `art-pass-1-baseline`，那是 `fea99d5`）+ 一份未提交的 `battle_scene.gd` 改动。

## 一、接管时真实状态（先核实再动手）
- 未提交差异已存 `_testenv/takeover-20261010-sol/interrupted.patch` 与源码快照，**未 reset、未丢弃**。
- 无残留游戏进程；Godot 4.7.2 stable；权威 `Xingqiu_V214.docx` SHA256 `6EBED498…AA36C` 未变。
- 仓库 `docs` 是**误提交的普通文件**（9261 字节，内容为覆盖清单），非目录。已保全至 `documentation_archive/legacy_docs_as_file.md` 后建真目录。前任"文档四件套已提交"的说法不成立。

## 二、审计发现并修复的真实缺陷（前任报告未覆盖）
| # | 缺陷 | 后果 | 修复 |
|---|---|---|---|
| 1 | `damage_events` 裁剪到 200 条后，表现层仍按数组下标累加 `_damage_cursor` | 长局第 200 条后**伤害数字/命中特效/受击动画永久停止** | 领域层每条附单调 `seq`；新增 `DamageEventCursor` 按 seq 消费，裁剪丢批显式计 `missed_events` |
| 2 | 敌人死亡即 `is_active()=false` 被绘制过滤、角色失能下一逻辑步移出数组 | **death 帧条实际无绘制路径**（仅极窄窗口） | 从 `removals` 建纯表现层离场快照 `_departures`，独立绘制+限寿命，不复活领域实体 |
| 3 | death 非 one-shot，走绝对时间取帧 | 死亡动画**循环播放** | DEATH 入 one-shot + 0.5s + `finished()` 释放 |
| 4 | hit 与 attack 同帧时 attack 被永久吞 | 出手动画丢失 | 有界 `pending_attack`，hit 后补播；死亡清空 |
| 5 | VFX 出手按"最近角色"推断来源 | **归错攻击者**、给未出手者放特效 | `_record_damage_event` 增 sourceKind/sourceId/sourcePos/targetPos（纯元数据）；未知源不播 |
| 6 | 可达性把"状态选中/队列存在"当"已绘制" | **假阳性**（前任报告的触发计数虚高） | 仅在 `draw_*` 实际执行后按资源路径记账；专项测试断言"未绘制则账本空" |
| 7 | autoplay 未确认部署就递增、结果阶段被 AP 等待遮蔽、单槽截图名互覆 | 假成功截图 | 点击→确认→点击→确认 FSM；decided 优先；墙钟超时；截图绑名字 |
| 8 | 测试可直接删正式存档（`test_save_service` 等删 `user://` 主档/备份，实例隔离≠磁盘隔离） | **可摧毁真实玩家进度** | 三层封堵：App 退出门 + `SaveService._write_json` 咽喉 + `TestDataGuard` 原始读写守卫 |

## 三、验收数字（隔离，本批次实测）
- **GUT：23 脚本 / 485 项 / 485 通过 / 8866 断言 / exit 0**（Orphans 5 为既有值）。
- **未隔离防护实测**：假 TEMP 目录跑 GUT → exit 86，**写出存档文件数 = 0**（修复前该场景会落盘 savegame.json）。
- **六组 VFX 实机截图**（`docs/art_screenshots/takeover/`，p1_0_demo 真实战斗帧，非合成）：
  deploy / impact / slash / death / arrow / heal **全部捕获到真实画面**，含伤害数字 100/125、治疗 +108、"部署成功：小川结衣 (-14 AP)"。
- **Windows Retail 重导**（`dist/retail2/`，当前 HEAD）：pack 14.33MB；
  `assets/vfx`=12、`anim_state`=5、`damage_event_cursor`=5 入包；
  `test_takeover`=0、`addons/gut`=0（测试与 GUT 未入发行包）；实机启动 stderr 0 字节。

## 四、存档历史审计结论（只读，未恢复/删除用户数据）
前任"空目录=无事故、仅日志污染"结论**被推翻**：
- `_testenv/title_gut_baseline.log` 明确记录正式目录读取存档成功后连续重置提交；
- 历史正式 660 学园币档哈希 `34C9…5C03C8` 曾存在，当前正式 save/settings 为空；
- 测试清理代码具备删除主档+备份且不恢复的能力。
**未决**：精确首次破坏 `34C9` 原件的运行/时刻/操作者无法判定；限定扫描外是否有不可变副本未知。详见 `docs/接管_存档安全复核.md`。

## 五、DSH Skills 状态（严格区分）
- **已加载且实际参与本轮**：`mem-skill-godot-gut`、`mem-skill-windows-godot-appdata`、`office-docx`、`mem-skill-dsh-asar`。
- **四项项目专用 Skill**：`create_skill` 四次均被宿主拒绝（`user rejected`），**未绕过、未安装、不宣称生效**。配套脚本 `tools/xingqiu_acceptance.py`、`tools/windows_art_capture.py` 已实现并运行。
- **OSS 候选**（固定版本+许可，未安装）：awesome-gamedev 的 godot-gdscript / create-game-assets（Apache-2.0+NOTICE）为可适配文本；Godot-Skill 缺许可正文不复制；pixel-art 脚本丢 alpha 不自动执行。详见 `docs/DSH_Skills核验与接入状态.md`。新增支出 0 元。

## 六、仍需人工决定 / 未达标
- 三路防守是否自然、素材审美是否合格 —— 需真人试玩，自动化不冒充。
- 125%/150% DPI 与真 4K 无真实显示器验收（等效分辨率≠DPI 证据）。
- 藤原凛/水濑纱良/白石千夏无角色数据，未扩建；A0.6 编队/局内构筑、1-6~1-10 timeline、装备UI/Hub/StoryRunner 均未实现，**未虚构**。
- 相邻路 3.0 格、经验 Lv11-50、装备数值均为候选待调表。
- C-6/C-4/C-5/C-9 及装备口径仍登记于 `docs/Alpha_数值缺口裁决清单.md`。

## 七、下一步（可直接执行）
```powershell
# 复现回归（隔离）
$env:APPDATA='D:\星丘残响\_testenv\<run>'
& 'C:\Users\linvisxie\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe' `
  tools\xingqiu_acceptance.py --output 'D:\星丘残响\_testenv\<run>' --minimum-tests 485
# 实机取证（前台归属校验，遮挡即拒拍）
& <python> tools\windows_art_capture.py --output 'D:\星丘残响\_testenv\<run>' --stage 1-3 --autoplay
```
