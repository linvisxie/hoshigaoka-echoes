"""Publish the verified bilingual build, preserving latest player saves verbatim."""
from pathlib import Path
import hashlib, html, json, re, shutil, subprocess, zipfile

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent / '_testenv/localization'
OUT = ROOT / 'dist/chapter_one_0.5.11_20261014'
OLD = ROOT / 'dist/chapter_one_0.5.10_20261014'

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()

reports = {
    'source720': BASE/'ui720_final/appdata/HoshigaokaEchoes/localization_report.json',
    'source1080': BASE/'ui1080_final/appdata/HoshigaokaEchoes/localization_report.json',
    'retail_journey_en': BASE/'retail_final_en/journey_report.json',
    'retail_settings': BASE/'retail_settings/retail_language_report.json',
}
for name, p in reports.items():
    report = json.loads(p.read_text(encoding='utf8'))
    assert report['ok'], name
    if name.startswith('retail'):
        for ext in ('exe','pck'):
            assert sha(OUT/f'HoshigaokaEchoes.{ext}') == report[ext+'Sha256'], name
assert re.search(r'Passing Tests\s+642\b',(BASE/'unit_release.log').read_text(encoding='utf8'))
for folder in ('retail_final_en','retail_settings'):
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
for name in ('unit_release.log','export.log'): shutil.copy2(BASE/name,evidence/name)
gallery = ['<!doctype html><meta charset="utf-8"><title>0.5.11 双语验收</title><style>body{background:#091422;color:#edf2ff;font:18px/1.8 Microsoft YaHei;margin:30px}img{max-width:100%}figure{max-width:1280px;margin:30px 0}</style><h1>0.5.11 中文 / English</h1><p>source 为源码渲染与合成视口输入；retail 为最终 EXE 真实 Windows 输入、正常战斗时钟、隔离存档副本。均为自动化验收，并非人工试玩。</p>']
folders = [('source720',BASE/'ui720_final/appdata/HoshigaokaEchoes/frontend_shots'),('source1080',BASE/'ui1080_final/appdata/HoshigaokaEchoes/frontend_shots'),('retail',BASE/'retail_final_en'),('settings',BASE/'retail_settings')]
for name, folder in folders:
    dest = evidence/name
    dest.mkdir(exist_ok=True)
    for p in sorted(folder.glob('*.png')):
        shutil.copy2(p,dest/p.name)
        link = html.escape(name+'/'+p.name)
        gallery.append(f'<figure><img loading="lazy" src="{link}"><figcaption>{link}</figcaption></figure>')
for folder in ('retail_final_en','retail_settings'):
    shutil.copy2(BASE/folder/'game.log',evidence/(folder+'_game.log'))
(evidence/'实机对照.html').write_text(''.join(gallery),encoding='utf8')
shutil.copy2(ROOT/'docs/RELEASE0511_ACCEPTANCE_20261014.md',OUT/'本轮修改与验证.md')
licenses = OUT/'素材授权'
licenses.mkdir(exist_ok=True)
for p in (ROOT/'assets/licenses').glob('*.txt'): shutil.copy2(p,licenses/p.name)
(OUT/'启动星丘残响.cmd').write_text('@echo off\nsetlocal\ncd /d "%~dp0"\nset "APPDATA=%~dp0_testenv\\player\\appdata"\nif not exist "%APPDATA%" mkdir "%APPDATA%"\nstart "" "%~dp0HoshigaokaEchoes.exe" --resolution 1280x720\nendlocal\n',encoding='ascii')
(OUT/'试玩说明.txt').write_text('《星丘残响》第一章 0.5.11\n双击启动星丘残响.cmd；EXE、PCK 保持同目录。\n设置新增语言切换：中文 / English。点击立即生效并记住选择。\n菜单、剧情、技能、装备和战斗提示支持英文。玩家自行填写的名字保持原样。\n修复英文中文残留、培养页资源越界、校园标牌挤压和对齐。\n验收报告与截图见本轮修改与验证.md、实机验证/实机对照.html。\n保留 0.5.10 可回退；ZIP 不含玩家存档。\n',encoding='utf-8-sig')
files = [p for p in sorted(OUT.rglob('*')) if p.is_file() and '_testenv' not in p.parts and p.name!='build_manifest.json']
manifest = dict(version='0.5.11',sourceCommit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),languages=['zh','en'],sha256={p.relative_to(OUT).as_posix():sha(p) for p in files})
(OUT/'build_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
archive = ROOT/'dist/星丘残响_第一章双语版_0.5.11_20261014.zip'
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
