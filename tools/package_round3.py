"""Package a concrete Retail candidate with source provenance and save isolation."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,zipfile
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--output',type=Path,default=ROOT/'dist/v3_concept_polish_20261011')
parser.add_argument('--version',default='0.4.0')
parser.add_argument('--archive',type=Path,default=ROOT/'dist/星丘残响_前五关_画面交互改进版_20261011.zip')
args=parser.parse_args()
OUT=args.output.resolve()
assert OUT.is_relative_to(ROOT/'dist'),'Package must stay under project dist'
assert (OUT/'HoshigaokaEchoes.exe').is_file() and (OUT/'HoshigaokaEchoes.pck').is_file()
(OUT/'启动前五关.cmd').write_text('@echo off\nsetlocal\ncd /d "%~dp0"\nset "APPDATA=%~dp0_testenv\\player\\appdata"\nif not exist "%APPDATA%" mkdir "%APPDATA%"\nstart "" "%~dp0HoshigaokaEchoes.exe" --resolution 1280x720\nendlocal\n',encoding='ascii')
notice=OUT/'素材授权';notice.mkdir(exist_ok=True)
for p in (ROOT/'assets/licenses').glob('*.txt'):shutil.copy2(p,notice/p.name)
shutil.copy2(ROOT/'docs/v3_round3_external_assets.json',notice/'外部素材来源.json')
shutil.copy2(ROOT/'assets/audio/source_record.json',notice/'音乐制作记录.json')
if (ROOT/'docs/v3_combat_foley_sources.json').exists():
 shutil.copy2(ROOT/'docs/v3_combat_foley_sources.json',notice/'战斗拟音来源.json')
readme='''《星丘残响》前五关画面与交互改进候选版 · 0.4.0 · 2026-10-11

解压后双击“启动前五关.cmd”。请保留 exe 与 pck 在同一目录。
启动器使用包内 _testenv/player/appdata 独立存档，保护原有正式存档。
新玩家选择“新游戏”，已有本包试玩记录可选择“继续游戏”。

包含第一至第五关、前后剧情、校园、角色培养、技能与天赋说明、装备、剧情回看、设置和保存继续。
标题采用概念图校门构图与四项真实菜单；战斗 HUD、强化、结算、剧情框和字体进一步统一。
第二关采用楼梯平台，第五关为旧体育馆，正式校徽为六瓣。
原有原创旋律加入 VSCO CE CC0 钢琴采样；界面使用 Kenney CC0 音效。
Noto 字体、Lucide 图标与音频许可见“素材授权”目录。

操作：1/2 选角色，点击地面部署；点在场角色后 Q 技能、R 撤退；Space 暂停。
强化可鼠标选择或按 1/2/3；右键/Esc 取消选择。剧情点击或 Enter 推进，可查看历史、自动播放。
第五关后可返回校园重玩、培养和装备，不会伪装进入尚未实现的第六关。

这是实际可运行的候选版本，不等于全部最终美术验收通过。
角色动作、特效层次与概念图仍有精修空间，音乐未通过用户听感验收。
1-6～1-10、后续可操作角色和最终 Boss 未包含；未将其标为完成。
实际验证与未完成项见工程 docs/V3_20261011_概念画面与交互改进记录.md。
'''
readme=readme.replace('0.4.0',args.version)
if args.version!='0.4.0':
 readme=readme.replace('界面使用 Kenney CC0 音效。','界面与剑击、普通命中、护甲命中、残响消散使用 Kenney CC0 音效，多段素材轮换。')
(OUT/'试玩说明.txt').write_text(readme,encoding='utf-8-sig')
files=[p for p in sorted(OUT.rglob('*')) if p.is_file() and '_testenv' not in p.parts and p.name!='build_manifest.json']
manifest={'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
 'version':args.version,'type':'Windows Retail first-five playable candidate; final concept and user acceptance pending',
 'sha256':{p.relative_to(OUT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
(OUT/'build_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
archive=args.archive.resolve()
assert archive.is_relative_to(ROOT/'dist'),'Archive must stay under project dist'
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in files+[OUT/'build_manifest.json']:z.write(p,p.relative_to(OUT).as_posix())
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None
 for name,sha in manifest['sha256'].items():assert hashlib.sha256(z.read(name)).hexdigest()==sha
print(json.dumps({'archive':str(archive),'bytes':archive.stat().st_size,'manifest':manifest},ensure_ascii=False))
