# DSH 游戏 Skills：核验与接入状态

接管日期 2026-10-10。状态严分“发现/加载/使用/候选/安装受阻”。

## 本机机制（实际实现核验）
DSH_HOME 实测 `C:\Users\linvisxie\.dsh`。从 `D:\dsh\resources\app.asar` 只读抽查 `@deepseek-ai/dsh-skill-filesystem/lib/index.js`：
- 项目根的 `.dsh/skills`、`.agents/skills`；
- 自定义 skillDirs；
- DSH_HOME/skills、agentsHome/skills；
- bundledSkillDir。
扫描一级 Markdown 或 `<skill-name>/SKILL.md`，带文件监听及目录优先级。不是猜测一个目录后放文件便宣布可用。普通 Windows 文件工具无法把 app.asar 当目录访问，故读取归档头部索引核查，没有改DSH源码。

## 已存在且实际参与本轮
- `mem-skill-godot-gut-8e9db6e5d790`：skill工具加载成功；用于类缓存刷新、GUT、防静默跳过。以 tools/xingqiu_acceptance.py 执行本项目具体门禁；483/483，磁盘23脚本=实际23。
- `mem-skill-windows-godot-appdata-68fce18e4808`：加载成功；复用隔离/客户区取证原则。修正“按父PID找窗口”的局限，新驱动只匹配拥有的进程树，不按全部Godot名称Kill。
- `office-docx`：加载成功；用内置python-docx读取V2.1.4（未改文件，SHA256不变）。
- `mem-skill-dsh-asar-f35b75241f87`：加载成功，用于本机分发实现只读核查。

## 四项项目专用技能：安装未完成
尝试 create_skill 创建 `xingqiu-art-director`、`xingqiu-player-experience`、`xingqiu-acceptance-gate`、`xingqiu-story-bible`，四次均返回 **`Error: the user rejected tool "create_skill"`**。
未以其他工具绕过该拒绝，未往发现目录手写激活项；当前完整会话catalog仍没有这些名字。因此不能宣称已安装、正确任务能触发或加载验证通过。
验收门的实际配套脚本已经实现并运行：`tools/xingqiu_acceptance.py`、`tools/windows_art_capture.py`。四项 Skill 内容尚待宿主允许创建后使用原生路径创建并逐一加载测试，不阻断普通游戏修复。

## OSS候选（固定版本、许可、安全边界）
| 仓库 | 固定版本 | 许可/结论 |
|---|---|---|
| [awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | 0a70cfc64672d512c5b5b6006b5dcb5cf90dbdbd | 完整Apache-2.0+NOTICE；近期维护；只选择godot-gdscript及create-game-assets文本，不全量安装74项 |
| [Godot-Skill](https://github.com/shihabshahrier/Godot-Skill) | c8bc20f876a8da241274d48461444fab86182d83 | 声明MIT但完整树没有LICENSE/COPYING正文；强制Resources与JSON基线冲突；不直接复制 |
| [agent-skill-pixel-art](https://github.com/ervareza/agent-skill-pixel-art) | 0de5e49a9ce9c1a326910b4efe3420c030ce3856 | 根及skills/pixel-art许可均完整MIT，版权声明不同；13脚本静态审阅，未执行。export_indexed丢alpha，quality_audit不检验palette成员，文档参数有错；不自动处理正式资产 |

推荐的两项仍为候选，不是安装成果：
- [godot-gdscript/SKILL.md](https://raw.githubusercontent.com/gamedev-skills/awesome-gamedev-agent-skills/0a70cfc64672d512c5b5b6006b5dcb5cf90dbdbd/skills/godot/godot-gdscript/SKILL.md)：5291字节、Godot4.7、纯Markdown，无脚本依赖。
- [create-game-assets/SKILL.md](https://raw.githubusercontent.com/gamedev-skills/awesome-gamedev-agent-skills/0a70cfc64672d512c5b5b6006b5dcb5cf90dbdbd/skills/disciplines/create-game-assets/SKILL.md)：7979字节、来源与一致性/原生导入/实机门槛；可选脚本未启用，不自动pip/npm安装。
复制或改编时须附[LICENSE](https://raw.githubusercontent.com/gamedev-skills/awesome-gamedev-agent-skills/0a70cfc64672d512c5b5b6006b5dcb5cf90dbdbd/LICENSE)和[NOTICE](https://raw.githubusercontent.com/gamedev-skills/awesome-gamedev-agent-skills/0a70cfc64672d512c5b5b6006b5dcb5cf90dbdbd/NOTICE)，保留版权且明确修改。许可允许商用不等于所有图片权利均获保证。

本轮未下载额外付费工具、未调用付费API、未运行仓库installer、未把外部README当高优先级指令。新增支出0元。
