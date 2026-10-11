"""Package the ten-stage Retail candidate; never includes isolated play saves."""
from pathlib import Path
import hashlib,json,shutil,subprocess,zipfile
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'dist/chapter_one_0.5.0_20261011'
assert (OUT/'HoshigaokaEchoes.exe').is_file() and (OUT/'HoshigaokaEchoes.pck').is_file()
(OUT/'启动星丘残响.cmd').write_text('@echo off\nsetlocal\ncd /d "%~dp0"\nset "APPDATA=%~dp0_testenv\\player\\appdata"\nif not exist "%APPDATA%" mkdir "%APPDATA%"\nstart "" "%~dp0HoshigaokaEchoes.exe" --resolution 1280x720\nendlocal\n',encoding='ascii')
notice=OUT/'素材授权';notice.mkdir(exist_ok=True)
for p in (ROOT/'assets/licenses').glob('*.txt'):shutil.copy2(p,notice/p.name)
for name in ['chapter_tail_assets.json','chapter_tail_audio.json','v3_round3_external_assets.json','v3_combat_foley_sources.json','v3_resonance_sfx_record.json','v3_round8_asset_sources.json','v3_round9_asset_sources.json','v3_round9_audio_record.json','v3_round10_asset_sources.json']:
    shutil.copy2(ROOT/'docs'/name,notice/name)
shutil.copy2(ROOT/'assets/audio/source_record.json',notice/'原始音乐制作记录.json')
(OUT/'试玩说明.txt').write_text('''《星丘残响》第一章十关可玩候选版 · 0.5.0 · 2026-10-11

双击“启动星丘残响.cmd”。exe 和 pck 必须放在同一目录。
启动器使用包内 _testenv/player/appdata 独立存档。压缩包不含自动化测试进度。
工程目录上方的统一启动器已保留此前包内玩家进度；新解压的副本从新游戏开始。

包含1-1～1-10、关前关后剧情、校园、培养、装备、剧情档案、设置和存档继续。
6～10关新增保健室、成绩榜区域、旧实验楼、档案室和最终体育馆场景。
结衣治疗、纱良特殊伤害和临时实验装置实际生效；千夏在章节结尾解锁后参与重玩。
无名优等生拥有三阶段、独立技能周期、3秒错题预警、阶段音乐、奖励与章节结尾。
首次通关Boss后在装备背包领取“被划掉的满分试卷”，可装备、不能强化或分解。
最多五名角色同时在场，千夏解锁后提供第六名候补；实验装置不占角色人数。

操作：1～6选角色，点击地面站位部署。选择场上角色后Q技能、R撤退。
纱良Q技能后点击空部署格放装置；右键取消。Space暂停，可重试本次调查。
强化用鼠标或1/2/3；剧情点击或Enter推进，支持历史、自动与回看。

维持前五关的水平三路、透视格侧边、动态六瓣核心和玻璃HUD。
本包是可运行的候选版本，视觉品质与音乐听感仍需用户实际试玩验收。
角色动作的像素边缘和部分过渡、Boss外层纸张与成绩环仍有精修空间。
详见“开发与验证记录.md”；素材来源与许可说明见“素材授权”。
''',encoding='utf-8-sig')
report=ROOT/'docs/CHAPTER_ONE_20261011.md'
if report.exists():shutil.copy2(report,OUT/'开发与验证记录.md')
files=[p for p in sorted(OUT.rglob('*')) if p.is_file() and '_testenv' not in p.parts and p.name!='build_manifest.json']
manifest={'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'version':'0.5.0','type':'Windows Retail ten-stage chapter candidate; final user art/audio acceptance pending','sha256':{p.relative_to(OUT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
(OUT/'build_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
archive=ROOT/'dist/星丘残响_第一章十关可玩候选版_0.5.0_20261011.zip'
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for p in files+[OUT/'build_manifest.json']:z.write(p,p.relative_to(OUT).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for name,sha in manifest['sha256'].items():assert hashlib.sha256(z.read(name)).hexdigest()==sha
print(json.dumps({'archive':str(archive),'bytes':archive.stat().st_size,'sourceCommit':manifest['sourceCommit']},ensure_ascii=False))
