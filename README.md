# 星丘残响 / Hoshigaoka Echoes

日系校园像素风角色构筑塔防 RPG。Windows PC 首发，Steam 正式发行。

> **当前版本（2026-10-13）：0.5.5，第一章十关与六名角色。**
> 本轮修复空背包分类遮挡、新档继承旧培养和学习记录重复返还，并补强装备选择恢复。验收见 [0.5.5 报告](docs/RELEASE055_ACCEPTANCE_20261013.md)。
> 统一启动器：`D:\星丘残响\启动星丘残响.cmd`；导出目录：`dist/chapter_one_0.5.5_20261013`；保留 0.5.4 可回退。
> 设计依据：V2.1.4 基础规划 + `docs/产品裁决记录.md` 已批准补充 + 用户 V3 成品要求。V2.1.5 草稿不等同于批准规格。
> 自动化不代表人工审美、听感或长期平衡验收。菜单路径退出资源告警仍待处理，详见报告。

素材与数值再生成：运行 `tools/build_chapter_tail.py` 后必须运行 `tools/configure_glass_combat.py`，后者从固定基线重建攻势，避免重复叠加。当前场景配乐生成器为 `tools/render_scene_scores.py`，保留 1—3 关原曲及 9—10 关 Boss 前的弦乐；不要直接运行旧音频生成器覆盖当前配乐。角色素材导入使用 `tools/import_glass_character_art.py`。运行时素材或代码变动后，必须重新导出并核对包指纹。

---

## 1. 技术基线（LOCKED，不得擅改）

| 项目 | 版本 / 取值 |
|---|---|
| 引擎 | Godot 4.7.2 Stable |
| 脚本 | Typed GDScript |
| 渲染器 | Compatibility / OpenGL |
| 目标平台 | Windows 10/11 x86_64 |
| 发行 | Steam（SteamPipe / Depot） |
| 数据 | JSON + typed validation |
| 测试 | GUT 9.7.1（MIT） |
| 版本控制 | Git / GitHub |
| 设计分辨率 | 1920×1080（最低验证 1280×720） |
| 帧率目标 | 60 FPS |

引擎与工具安装位置：`D:\星丘基础\`（引擎 `godot\`，GUT 源包 `gut\`，下载缓存 `downloads\`）。

---

## 2. 环境准备

### 2.1 Godot 4.7.2 Stable

```powershell
# 下载（官方 GitHub Release）
$url = 'https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip'
# 解压到 D:\星丘基础\godot\
# 若 PATH 未配置，下文命令用完整路径调用
```

验证：

```powershell
& 'D:\星丘基础\godot\Godot_v4.7.2-stable_win64_console.exe' --version
# 期望输出：4.7.2.stable.official.ed1daf0bf
```

### 2.2 Export Templates（与引擎版本必须完全一致）

```powershell
$url = 'https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz'
# 下载后用 Godot 编辑器「编辑器 → 管理导出模板 → 从文件安装」，
# 或解压 .tpz 为 .zip 后放入：
#   %APPDATA%\Godot\export_templates\4.7.2.stable\
```

### 2.3 GUT 9.7.1

已随仓库提交于 `addons/gut/`（来源：<https://github.com/bitwes/Gut/releases/tag/v9.7.1>，MIT 许可，LICENSE.md 随附）。

如需重新获取：

```powershell
$url = 'https://github.com/bitwes/Gut/archive/refs/tags/v9.7.1.zip'
# 解压后把 Gut-9.7.1/addons/gut 复制到本工程的 addons/gut
```

### 2.4 Git

```powershell
git --version   # 验证可用
```

---

## 3. 目录结构

```
res://
  addons/gut/               # GUT 9.7.1（MIT）
  assets/                   # art/{characters,enemies,environments,ui}/ , vfx/ , audio/{bgm,sfx}/
  data/                     # SSOT：唯一数据源（见下）
  scenes/                   # bootstrap/ , title/ , home/ , battle/ , story/ , menus/
  scripts/
    app/                    # App , SceneRouter , bootstrap
    data/                   # DataRegistry
    domain/                 # battle/ characters/ enemies/ skills/ economy/ equipment/ story/（Phase 0 为空）
    platform/desktop|steam/ # 平台适配层（Phase 0 为空）
    save/                   # SaveService
    services/               # AudioService
    ui/ , utils/            # utils 含 GameLog
  tests/                    # GUT 测试
  dist/windows/             # 导出产物（git 忽略，绝不混入 res://）
  project.godot
```

### 数据目录（V2.1.4 B6 SSOT — 唯一数据源）

`data/` 下**只有**下列权威文件，**禁止创建同义总表**（如 `stages.json` / `story.json`）：

```
data/
  terms.json                # 中文显示名、内部术语、状态名
  balance.json              # 逻辑格→参考画布参数、laneSpacingPx、tileSizePx、战斗公共参数
  characters.json           # characterId、职业、基础面板、部署费、技能 ID 引用
  skills.json               # skillId、效果、CD、攻击几何、跨线参数（倍率/几何唯一归属）
  enemies.json              # enemyId、面板、标签、机制、weightClass、spriteFramePx
  currencies.json           # 五类资源
  character_growth.json     # 成长曲线
  upgrade_costs.json        # 升级/突破/技能成本
  upgrades.json             # 局内强化
  equipment.json            # 装备固定模板
  equipment_affixes.json    # 固定词条
  mementos.json             # 校园纪念物
  stage_rewards.json        # 首通/重复/章节奖励（奖励数值只在此文件）
  stages/ch1/1-1.json ... 1-10.json   # 关卡（引用 story ID 与 reward ID，禁止内联副本）
  story/<storyId>.json      # 剧情节点
```

检索索引由 `DataRegistry` 在加载时生成内存索引，不另存第二份正文。

---

## 4. 常用命令

设 `$godot` 为引擎路径、`$proj` 为本工程路径：

```powershell
$godot = 'D:\星丘基础\godot\Godot_v4.7.2-stable_win64_console.exe'
$proj  = 'D:\星丘残响\hoshigaoka_echoes'
```

### 4.1 导入资源（首次克隆后必做）

```powershell
& $godot --headless --path $proj --import
```

### 4.2 无头运行测试

```powershell
& $godot --headless --path $proj -s addons/gut/gut_cmdln.gd -gexit
```

退出码 0 = 全通过；非 0 = 有失败，可直接用于 CI。

### 4.3 编辑器运行

```powershell
& $godot --path $proj          # 打开编辑器
& $godot --path $proj -e       # 同上
```

### 4.4 导出 Windows Release

```powershell
& $godot --headless --path $proj --export-release "Windows Desktop" "$proj\dist\windows\HoshigaokaEchoes.exe"
```

产物在 `dist/windows/`（exe + 独立 .pck；**不嵌入 exe**，便于签名与内容更新）。

---

## 5. 架构分层（依赖方向自上而下，不得反向）

```
Presentation  (Control / Animation / VFX / Audio)
      ↓
Application   (Scene flow / BattleSession / Menu flow)
      ↓
Domain        (Combat / Character / Enemy / Skill / Economy / Story)
      ↓
Data & Save   (Repositories / Config / SaveGame)
      ↓
Platform      (Windows / Steam services)
```

约束：
- Domain 不依赖具体 Control 节点；伤害公式不得写在 HUD 脚本中。
- Steam API 不得散落在业务代码，统一经 `PlatformService` 接口，且**核心玩法不能依赖 Steam 可用性**。
- `BattleSession` 是单场战斗的权威运行时状态，结束生成 `BattleResult` 再事务式写回存档。

### Autoload

| 名称 | 职责 |
|---|---|
| `App` | 启动、全局流程与版本信息 |
| `DataRegistry` | 配置加载、ID 索引、校验 |
| `SaveService` | 存档、backup、migration |
| `AudioService` | BGM/SFX 总线控制 |
| `SceneRouter` | 场景/菜单路由 |

`BattleSession`、`StageRuntime`、`StoryRunner` 按场景实例化，不进全局单例。
`GameLog`（`scripts/utils/game_log.gd`）以 `class_name` 提供，不占 Autoload 槽位。
（注：日志类命名为 `GameLog` 而非 `Logger`，因 Godot 4.7 已有内建 `Logger` 类。）

### 存档

- 路径：`user://save/savegame.json`、`savegame_backup.json`、`settings/settings.cfg`、`logs/latest.log`
- 自定义用户目录已开启，实际位于 `%APPDATA%\HoshigaokaEchoes`
- 读取流程：`parse → validate → sequential migrate → validate → use`
- 每次写主存档前，上一份已验证存档转为 backup；关卡结算/升级/突破等使用事务式修改

---

## 6. 合规与红线

- **许可证**：每个第三方依赖记录名称、版本、来源、用途、许可证、替代方案；保留 LICENSE / NOTICE。
- **不新增固定月费**：V2.1 不引入服务器、数据库或 SaaS 订阅。
- **凭证不入库**：Steam 密码、builder 凭证、证书、API key 一律不得提交（见 `.gitignore`）。
- **不提交**：`.godot` 缓存、`dist/` 构建产物、临时包。
- **AI/外部资产**须通过 J9.8 八项验收（角色一致性、来源记录、尺寸锚点、透明边缘、像素密度、动画连续性、1280×720 可读性、1080p 实机截图）方可入库。

---

## 7. Phase 0 历史验收状态（非当前完成度）

| 验收项 | 状态 |
|---|---|
| Godot 4.7.2 Stable 可运行 | ✅ `4.7.2.stable.official.ed1daf0bf` |
| Export Templates 安装 | 见「遗留问题」 |
| 工程目录结构 | ✅ 34 个目录 |
| Autoload 骨架 | ✅ App / DataRegistry / SaveService / AudioService / SceneRouter + GameLog |
| 数据目录规范（V2.1.4 SSOT） | ✅ 13 canonical + 10 关卡 + 1 剧情 |
| GUT 接入 | ✅ 9.7.1（MIT） |
| 自动化测试 | ✅ 3 脚本 / 25 测试 全通过 |
| 无头启动 | ✅ `--import` 与 `--headless` 可运行 |
| Windows Release 导出 | 见「遗留问题」 |
| Git 初始化 | ✅ |

---

## 8. 当前开发范围

按用户 2026-10-10 的 V3 指令自主推进第一章完整成品，截止 2026-10-24。先打磨 1-5 实机视觉，再以通过审查的表现扩展其余关卡。功能回归通过、资源导入成功和用户视觉验收分别记录，不互相替代。
