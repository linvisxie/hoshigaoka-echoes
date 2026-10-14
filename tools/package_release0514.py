"""Publish the verified bilingual build, preserving latest player saves verbatim."""
from pathlib import Path
import hashlib, html, json, re, shutil, subprocess, zipfile

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent / '_testenv/polish0514'
OUT = ROOT / 'dist/chapter_one_0.5.14_20261014'
OLD = ROOT / 'dist/chapter_one_0.5.13_20261014'

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()

reports = {
    'source720': BASE/'ui720_delivery/appdata/HoshigaokaEchoes/polish_report.json',
    'source1080': BASE/'ui1080_delivery/appdata/HoshigaokaEchoes/polish_report.json',
    'pixels720': BASE/'ui720_delivery/visual_regression.json',
    'pixels1080': BASE/'ui1080_delivery/visual_regression.json',
    'retail_hub': BASE/'retail_delivery/retail_hub_report.json',
}
for name, p in reports.items():
    report = json.loads(p.read_text(encoding='utf8'))
    assert report['ok'], name
    if name.startswith('retail'):
        for ext in ('exe','pck'):
            assert sha(OUT/f'HoshigaokaEchoes.{ext}') == report[ext+'Sha256'], name
assert re.search(r'Passing Tests\s+646\b',(BASE/'unit_final.log').read_text(encoding='utf8'))
for folder in ('retail_delivery',):
    log = (BASE/folder/'game.log').read_text(encoding='utf8',errors='replace')
    assert 'SCRIPT ERROR' not in log and 'Parse Error' not in log
    assert all('resources still in use at exit' in line for line in log.splitlines() if line.startswith('ERROR:'))
assert not subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True).strip(), 'Commit reviewed source first'

# The source of migration is the previous formal release, never a QA fixture.
checkpoint = BASE/'player-checkpoint'
checkpoint.mkdir(exist_ok=True)
preserved = []
for group, folder in [('player',OLD/'_testenv/player/appdata/HoshigaokaEchoes'),('formal',Path.home()/'AppData/Roaming/HoshigaokaEchoes')]:
    for relative in ('save/savegame.json','save/savegame_backup.json','settings/settings.cfg'):
        source = folder/relative
        if not source.exists(): continue
        if source.suffix=='.json': json.loads(source.read_text(encoding='utf-8-sig'))
        dest = checkpoint/group/relative
        dest.parent.mkdir(parents=True,exist_ok=True)
        checksum = sha(source)
        shutil.copy2(source,dest)
        assert sha(dest)==checksum
        preserved.append(dict(group=group,relative=relative,source=str(source),sha256=checksum))
assert any(p['group']=='player' and p['relative']=='save/savegame.json' for p in preserved)
(checkpoint/'checkpoint.json').write_text(json.dumps(preserved,ensure_ascii=False,indent=2),encoding='utf8')

evidence = OUT/'实机验证'
evidence.mkdir(exist_ok=True)
for name,p in reports.items(): shutil.copy2(p,evidence/(name+'_report.json'))
for name in ('unit_final.log','export.log'): shutil.copy2(BASE/name,evidence/name)
gallery = ['<!doctype html><meta charset="utf-8"><title>0.5.14 双语验收</title><style>body{background:#091422;color:#edf2ff;font:18px/1.8 Microsoft YaHei;margin:30px}img{max-width:100%}figure{max-width:1280px;margin:30px 0}</style><h1>0.5.14 校园环境与交互动效</h1><p>source 为源码渲染与合成视口输入；retail 为最终 EXE 真实 Windows 输入、隔离正常通关存档副本。均为自动化验收，并非人工试玩。</p>']
folders = [('source720',BASE/'ui720_delivery/appdata/HoshigaokaEchoes/frontend_shots'),('source1080',BASE/'ui1080_delivery/appdata/HoshigaokaEchoes/frontend_shots'),('retail',BASE/'retail_delivery')]
for name, folder in folders:
    dest = evidence/name
    dest.mkdir(exist_ok=True)
    for p in sorted(folder.glob('*.png')):
        if name!='retail' and not p.name.startswith(('title_petals','campus_no_focus','building_hover','static_reference','motion_reference')): continue
        shutil.copy2(p,dest/p.name)
        link = html.escape(name+'/'+p.name)
        gallery.append(f'<figure><img loading="lazy" src="{link}"><figcaption>{link}</figcaption></figure>')
for folder in ('retail_delivery',):
    shutil.copy2(BASE/folder/'game.log',evidence/(folder+'_game.log'))
    shutil.copy2(BASE/folder/'transition_metrics.json',evidence/'windows_transition_metrics.json')
shutil.copy2(BASE/'retail_shutdown_audit/game.log',evidence/'verbose_shutdown.log')
for label, folder in folders[:2]:
    for gif in folder.parent.parent.parent.glob('*.gif'):
        shutil.copy2(gif,evidence/(label+'_'+gif.name))
        gallery.append(f'<figure><img src="{label}_{gif.name}"><figcaption>{label} rendered animation</figcaption></figure>')
(evidence/'实机对照.html').write_text(''.join(gallery),encoding='utf8')
art = OUT/'素材来源'
art.mkdir(exist_ok=True)
for name in ('provenance.json','mio_blink_v1.png'):
    shutil.copy2(ROOT/'assets/art/hub/motion'/name,art/name)
report = (ROOT/'docs/RELEASE0514_ACCEPTANCE_20261014.md').read_text(encoding='utf8')
(OUT/'本轮修改与验证.md').write_text(report.replace('../assets/art/hub/motion/provenance.json','素材来源/provenance.json'),encoding='utf8')
licenses = OUT/'素材授权'
licenses.mkdir(exist_ok=True)
for p in (ROOT/'assets/licenses').glob('*.txt'): shutil.copy2(p,licenses/p.name)
(OUT/'启动星丘残响.cmd').write_text('@echo off\nsetlocal\ncd /d "%~dp0"\nset "APPDATA=%~dp0_testenv\\player\\appdata"\nif not exist "%APPDATA%" mkdir "%APPDATA%"\nstart "" "%~dp0HoshigaokaEchoes.exe" --resolution 1280x720\nendlocal\n',encoding='ascii')
(OUT/'试玩说明.txt').write_text('《星丘残响》第一章 0.5.14\n双击启动星丘残响.cmd；EXE、PCK 保持同目录。\n保留校园构图与文字位置，加入分层樱花、局部风动、光效、人物轻动与交互反馈。\n菜单、剧情、技能、装备和战斗提示支持英文。玩家自行填写的名字保持原样。\n修复鼠标焦点框残留与切换黑屏，统一继续游戏和设置的柔和过渡及确认音效；人物去掉硬边补景，增强地点暖光、纸页、天空及新记录提示。\n验收报告与截图见本轮修改与验证.md、实机验证/实机对照.html。\n保留 0.5.13 可回退；ZIP 不含玩家存档。\n',encoding='utf-8-sig')
files = [p for p in sorted(OUT.rglob('*')) if p.is_file() and '_testenv' not in p.parts and p.name!='build_manifest.json']
manifest = dict(version='0.5.14',sourceCommit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),languages=['zh','en'],sha256={p.relative_to(OUT).as_posix():sha(p) for p in files})
(OUT/'build_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
archive = ROOT/'dist/星丘残响_校园交互精修_0.5.14_20261014.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=4) as z:
    for p in files+[OUT/'build_manifest.json']: z.write(p,p.relative_to(OUT).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None and not any('_testenv' in n for n in z.namelist())
    assert all(hashlib.sha256(z.read(n)).hexdigest()==h for n,h in manifest['sha256'].items())
for entry in preserved:
    source = Path(entry['source'])
    assert sha(source)==entry['sha256'], 'Player files changed during packaging'
    if entry['group']=='player':
        dest = OUT/'_testenv/player/appdata/HoshigaokaEchoes'/entry['relative']
        dest.parent.mkdir(parents=True,exist_ok=True)
        assert not dest.exists() or sha(dest)==entry['sha256']
        shutil.copy2(source,dest)
        assert sha(dest)==entry['sha256']
launcher = ROOT.parent/'启动星丘残响.cmd'
body = launcher.read_text(encoding='ascii')
assert OLD.name in body
launcher.write_text(body.replace(OLD.name,OUT.name),encoding='ascii')
subprocess.run([shutil.which('pwsh') or 'pwsh','-NoProfile','-Command',"& '"+str(ROOT/'tools/retain_release_versions.ps1')+"' -Keep @('"+OUT.name+"','"+OLD.name+"')"],check=True)
print(json.dumps(dict(ok=True,archive=str(archive),bytes=archive.stat().st_size,files=len(files),preservedFiles=len(preserved)),ensure_ascii=False))
