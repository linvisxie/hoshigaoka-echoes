"""Package the verified Windows build, excluding test saves and logs."""
from pathlib import Path
import hashlib,json,subprocess,zipfile
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'dist/v3_first_five_20261010'
files=['HoshigaokaEchoes.exe','HoshigaokaEchoes.pck','启动前五关.cmd']
readme='''《星丘残响》前五关连续流程候选版 · 2026-10-10

解压后双击“启动前五关.cmd”，选择“新游戏”。请保留 exe 与 pck 在同一目录。
启动器使用本目录 _testenv/player/appdata 内的独立存档，不覆盖原有正式进度。

本版包含序章、校园菜单、第一至第五关及前后剧情、澪与悠真的技能/天赋、培养与装备、剧情回看、设置、保存与继续。
操作：1/2 选择角色，点击地面部署；点击已部署角色后 Q 主动技能、R 撤退；鼠标选择强化。
对话点击或 Enter 推进，可使用自动播放与历史记录。第五关后返回校园。

实际 Windows 自动操作已完成五关连续通关，关键回归 590/590 通过。
这是可玩候选版，尚未达到全部最终美术要求；角色动作、UI 造型与概念图仍有差距。
后五关、其余可操作角色与 Boss 不在此包内。没有冒充已完成内容。
素材当前为内部候选，商业发布权利及最终审美验收尚未完成。
详细证据与未完成项见工程 docs/V3_20261010_前五关开发记录.md。
'''
(OUT/'试玩说明.txt').write_text(readme,encoding='utf-8-sig')
manifest={'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
          'type':'Windows Retail internal first-five playable candidate; not final art accepted',
          'sha256':{name:hashlib.sha256((OUT/name).read_bytes()).hexdigest() for name in files}}
(OUT/'build_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
with zipfile.ZipFile(OUT.parent/'星丘残响_前五关试玩_20261010.zip','w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for name in files+['试玩说明.txt','build_manifest.json']: z.write(OUT/name,name)
print(json.dumps(manifest,ensure_ascii=False))
