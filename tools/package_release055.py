"""Publish verified 0.5.5; preserve current real saves and keep two releases."""
from pathlib import Path
import hashlib, html, json, re, shutil, subprocess, zipfile

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent/'_testenv/release055'
OUT = ROOT/'dist/chapter_one_0.5.5_20261013'
OLD = ROOT/'dist/chapter_one_0.5.4_20261012'
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
reports = {
    'new_save_ui_720': BASE/'ui/appdata/HoshigaokaEchoes/release055_report.json',
    'new_save_ui_1080': BASE/'ui1920/appdata/HoshigaokaEchoes/release055_report.json',
    'shared_ui': BASE/'glass/appdata/HoshigaokaEchoes/glass_ui_report.json',
    'retail_reset': BASE/'retail_final/retail_reset_report.json',
    'retail_boss': BASE/'battle_final/retail_report.json',
}
for name,path in reports.items():
    report = json.loads(path.read_text(encoding='utf-8-sig'))
    assert report['ok'], name
retail = json.loads(reports['retail_reset'].read_text(encoding='utf8'))
for ext in ['exe','pck']:
    assert sha(OUT/f'HoshigaokaEchoes.{ext}') == retail[ext+'Sha256']
boss = json.loads(reports['retail_boss'].read_text(encoding='utf8'))
assert boss['normalExit'] and boss['retry']
for ext in ['exe','pck']: assert boss[ext+'Sha256']==retail[ext+'Sha256']
assert re.search(r'Passing Tests\s+625\b', (BASE/'unit_pass.log').read_text(encoding='utf8'))
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
for name in ['before.log','unit_pass.log','ui_final.log','ui1920.log','glass.log','export_delivery.log']:
    shutil.copy2(BASE/name,evidence/name)
shutil.copy2(BASE/'retail_final/game.log', evidence/'retail_game.log')
shutil.copy2(BASE/'battle_final/game.log', evidence/'retail_boss_game.log')
gallery = ['<!doctype html><meta charset="utf-8"><title>星丘残响 0.5.5 验收</title><style>body{background:#091422;color:#e8efff;font:18px/1.8 Microsoft YaHei;margin:30px}img{max-width:100%;border:1px solid #536f89}figure{max-width:1280px;margin:30px 0}a{color:#90dfff}</style><h1>0.5.5 新档与装备精修</h1><p>Retail 为最终 EXE 真实 Windows 输入；source 为 Godot 源码窗口、视口事件验证。全部使用隔离的旧通关档副本。</p>']
for name,folder in [
    ('retail',BASE/'retail_final'),
    ('retail_boss',BASE/'battle_final'),
    ('source720',BASE/'ui/appdata/HoshigaokaEchoes/frontend_shots'),
    ('source1080',BASE/'ui1920/appdata/HoshigaokaEchoes/frontend_shots'),
    ('shared_ui',BASE/'glass/appdata/HoshigaokaEchoes/frontend_shots'),
]:
    dest = evidence/name
    dest.mkdir(exist_ok=True)
    for picture in sorted(folder.glob('*.png')):
        if picture.stem.startswith('boss_continuous_') and int(picture.stem.rsplit('_',1)[1])%10: continue
        shutil.copy2(picture,dest/picture.name)
        label = html.escape(name+'/'+picture.name)
        gallery.append(f'<figure><a href="{label}"><img loading="lazy" src="{label}"></a><figcaption>{label}</figcaption></figure>')
(evidence/'实机对照.html').write_text(''.join(gallery),encoding='utf8')
shutil.copy2(ROOT/'docs/RELEASE055_ACCEPTANCE_20261013.md',OUT/'本轮修改与验证.md')
licenses = OUT/'素材授权'
licenses.mkdir(exist_ok=True)
for license in (ROOT/'assets/licenses').glob('*.txt'): shutil.copy2(license,licenses/license.name)
(OUT/'启动星丘残响.cmd').write_text('@echo off\nsetlocal\ncd /d "%~dp0"\nset "APPDATA=%~dp0_testenv\\player\\appdata"\nif not exist "%APPDATA%" mkdir "%APPDATA%"\nstart "" "%~dp0HoshigaokaEchoes.exe" --resolution 1280x720\nendlocal\n',encoding='ascii')
(OUT/'试玩说明.txt').write_text('《星丘残响》第一章 0.5.5\n双击启动星丘残响.cmd。EXE 和 PCK 保持同目录。\n修复空装备分类遮挡、新档继承旧培养、上限投料重复返还。\n新游戏会替换当前进度，需再次点击确认；继续游戏保留原进度。\n验收与已知问题见本轮修改与验证.md及实机验证/实机对照.html。\n保留 0.5.4 可回退。ZIP 不含任何玩家存档。\n',encoding='utf-8-sig')
files = [p for p in sorted(OUT.rglob('*')) if p.is_file() and '_testenv' not in p.parts and p.name!='build_manifest.json']
manifest = dict(version='0.5.5',sourceCommit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),shutdownWarningsRecorded=True,sha256={p.relative_to(OUT).as_posix():sha(p) for p in files})
(OUT/'build_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
archive = ROOT/'dist/星丘残响_第一章新档与装备精修_0.5.5_20261013.zip'
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
assert 'chapter_one_0.5.4_20261012' in body
launcher.write_text(body.replace('chapter_one_0.5.4_20261012','chapter_one_0.5.5_20261013'),encoding='ascii')
subprocess.run([shutil.which('pwsh') or 'pwsh','-NoProfile','-Command',"& '"+str(ROOT/'tools/retain_release_versions.ps1')+"' -Keep @('chapter_one_0.5.5_20261013','chapter_one_0.5.4_20261012')"],check=True)
print(json.dumps(dict(ok=True,archive=str(archive),bytes=archive.stat().st_size,files=len(files),preservedFiles=len(preserved)),ensure_ascii=False))
