"""Publish verified 0.5.7; preserve current real saves and keep two releases."""
from pathlib import Path
import hashlib, html, json, re, shutil, subprocess, zipfile

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent/'_testenv/release057'
OUT = ROOT/'dist/chapter_one_0.5.7_20261013'
OLD = ROOT/'dist/chapter_one_0.5.6_20261013'
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
reports = {'retail_hub': BASE/'retail_final/retail_hub_report.json', 'source_reference': BASE/'ui_final/appdata/HoshigaokaEchoes/hub_report.json', 'source_720': BASE/'ui720_final/appdata/HoshigaokaEchoes/hub_report.json', 'pixel': BASE/'pixel_report.json'}
for name,path in reports.items():
    report = json.loads(path.read_text(encoding='utf-8-sig'))
    assert report['ok'], name
retail = json.loads(reports['retail_hub'].read_text(encoding='utf8'))
for ext in ['exe','pck']:
    assert sha(OUT/f'HoshigaokaEchoes.{ext}') == retail[ext+'Sha256']
assert re.search(r'Passing Tests\s+628\b', (BASE/'unit_final.log').read_text(encoding='utf8'))
assert not subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True).strip(), 'Commit reviewed changes before publishing'

# Read the latest player files only at publication time. Never use QA saves.
checkpoint = BASE/'player-checkpoint'
checkpoint.mkdir(exist_ok=True)
preserved = []
for group,folder in [
    ('player', OLD/'_testenv/player/appdata/HoshigaokaEchoes'),
    ('formal', Path.home()/'AppData/Roaming/HoshigaokaEchoes'),
]:
    for relative in ['save/savegame.json','save/savegame_backup.json','settings/settings.cfg']:
        source = folder/relative
        if not source.exists(): continue
        if source.suffix=='.json': json.loads(source.read_text(encoding='utf-8-sig'))
        backup = checkpoint/group/relative
        backup.parent.mkdir(parents=True, exist_ok=True)
        checksum = sha(source)
        shutil.copy2(source, backup)
        assert sha(backup)==checksum
        preserved.append(dict(group=group, relative=relative, source=str(source), sha256=checksum))
assert any(p['group']=='player' and p['relative']=='save/savegame.json' for p in preserved), 'Player save missing; do not publish an empty replacement'
(checkpoint/'checkpoint.json').write_text(json.dumps(preserved,ensure_ascii=False,indent=2),encoding='utf8')

evidence = OUT/'实机验证'
evidence.mkdir(exist_ok=True)
for name,path in reports.items(): shutil.copy2(path,evidence/(name+'_report.json'))
for name in ['unit_final.log','import.log','export_final.log']:
    shutil.copy2(BASE/name,evidence/name)
shutil.copy2(BASE/'retail_final/game.log', evidence/'retail_game.log')
gallery = ['<!doctype html><meta charset="utf-8"><title>星丘残响 0.5.7 验收</title><style>body{background:#091422;color:#e8efff;font:18px/1.8 Microsoft YaHei;margin:30px}img{max-width:100%;border:1px solid #536f89}figure{max-width:1280px;margin:30px 0}a{color:#90dfff}</style><h1>0.5.7 校园 Hub</h1><p>retail 图来自最终 EXE 真实 Windows 输入，使用隔离的旧通关档副本。source 图来自源码实机视口及隔离 UI 夹具，不代表整章实玩。</p>']
for name,folder in [('retail',BASE/'retail_final'), ('source',BASE/'ui_final/appdata/HoshigaokaEchoes/frontend_shots')]:
    dest = evidence/name
    dest.mkdir(exist_ok=True)
    for picture in sorted(folder.glob('*.png')):
        if picture.stem.startswith('boss_continuous_') and int(picture.stem.rsplit('_',1)[1])%10: continue
        shutil.copy2(picture,dest/picture.name)
        label = html.escape(name+'/'+picture.name)
        gallery.append(f'<figure><a href="{label}"><img loading="lazy" src="{label}"></a><figcaption>{label}</figcaption></figure>')
shutil.copy2(ROOT/'assets/art/hub/campus_approved.png',evidence/'批准概念图.png')
shutil.copy2(ROOT/'docs/CAMPUS057_ASSET_PROVENANCE.md',OUT/'校园素材来源.md')
gallery.append('<h2>批准概念图</h2><img src="批准概念图.png">')
(evidence/'实机对照.html').write_text(''.join(gallery),encoding='utf8')
shutil.copy2(ROOT/'docs/RELEASE057_ACCEPTANCE_20261013.md',OUT/'本轮修改与验证.md')
licenses = OUT/'素材授权'
licenses.mkdir(exist_ok=True)
for license in (ROOT/'assets/licenses').glob('*.txt'): shutil.copy2(license,licenses/license.name)
(OUT/'启动星丘残响.cmd').write_text('@echo off\nsetlocal\ncd /d "%~dp0"\nset "APPDATA=%~dp0_testenv\\player\\appdata"\nif not exist "%APPDATA%" mkdir "%APPDATA%"\nstart "" "%~dp0HoshigaokaEchoes.exe" --resolution 1280x720\nendlocal\n',encoding='ascii')
(OUT/'试玩说明.txt').write_text('《星丘残响》第一章 0.5.7\n双击启动星丘残响.cmd。EXE 和 PCK 保持同目录。\n按批准概念图重建校园主页，地点交谈、校园漫游、调查公告板和学生手册均可交互；右上资源保留原样式。\n新游戏会替换当前进度，需再次点击确认；继续游戏保留原进度。\n验收与已知问题见本轮修改与验证.md及实机验证/实机对照.html。\n保留 0.5.6 可回退。ZIP 不含任何玩家存档。\n',encoding='utf-8-sig')
files = [p for p in sorted(OUT.rglob('*')) if p.is_file() and '_testenv' not in p.parts and p.name!='build_manifest.json']
manifest = dict(version='0.5.7',sourceCommit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),shutdownWarningsRecorded=True,sha256={p.relative_to(OUT).as_posix():sha(p) for p in files})
(OUT/'build_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
archive = ROOT/'dist/星丘残响_第一章校园Hub_0.5.7_20261013.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=4) as z:
    for path in files+[OUT/'build_manifest.json']: z.write(path,path.relative_to(OUT).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert not any('_testenv' in n for n in z.namelist())
    assert all(hashlib.sha256(z.read(name)).hexdigest()==checksum for name,checksum in manifest['sha256'].items())
for entry in preserved:
    source = Path(entry['source'])
    assert sha(source)==entry['sha256'], 'Player files changed during publication; preserve newest before retry'
    if entry['group']=='player':
        destination = OUT/'_testenv/player/appdata/HoshigaokaEchoes'/entry['relative']
        destination.parent.mkdir(parents=True,exist_ok=True)
        assert not destination.exists() or sha(destination)==entry['sha256'], 'Destination contains different progress'
        shutil.copy2(source,destination)
        assert sha(destination)==entry['sha256']
launcher = ROOT.parent/'启动星丘残响.cmd'
body = launcher.read_text(encoding='ascii')
assert 'chapter_one_0.5.6_20261013' in body
launcher.write_text(body.replace('chapter_one_0.5.6_20261013','chapter_one_0.5.7_20261013'),encoding='ascii')
subprocess.run([shutil.which('pwsh') or 'pwsh','-NoProfile','-Command',"& '"+str(ROOT/'tools/retain_release_versions.ps1')+"' -Keep @('chapter_one_0.5.7_20261013','chapter_one_0.5.6_20261013')"],check=True)
print(json.dumps(dict(ok=True,archive=str(archive),bytes=archive.stat().st_size,files=len(files),preservedFiles=len(preserved)),ensure_ascii=False))

