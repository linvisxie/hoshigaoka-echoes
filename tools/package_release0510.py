"""Publish verified 0.5.10, preserve latest real saves, retain 0.5.9 rollback."""
from pathlib import Path
import hashlib, html, json, re, shutil, subprocess, zipfile

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'_testenv/release0510'
OUT=ROOT/'dist/chapter_one_0.5.10_20261014'
OLD=ROOT/'dist/chapter_one_0.5.9_20261014'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
reports={
    'retail_hub':BASE/'retail_final/retail_hub_report.json',
    'navigation':BASE/'navigation_delivery/retail_hub_report.json',
    'journey':BASE/'journey_final/journey_report.json',
    'boss':BASE/'boss_final/retail_report.json',
    'source_ui':BASE/'ui_acceptance/appdata/HoshigaokaEchoes/hub_report.json',
    'stability':BASE/'stress_verified/appdata/HoshigaokaEchoes/stability_report.json',
    'modal':BASE/'modal/appdata/HoshigaokaEchoes/modal_report.json',
    'audio':BASE/'audio_report.json',
}
for name,p in reports.items(): assert json.loads(p.read_text(encoding='utf-8-sig'))['ok'],name
for name in ['retail_hub','navigation','journey','boss']:
    report=json.loads(reports[name].read_text(encoding='utf8'))
    for ext in ['exe','pck']: assert sha(OUT/f'HoshigaokaEchoes.{ext}')==report[ext+'Sha256'], name
for folder in ['retail_final','navigation_delivery','journey_final','boss_final']:
    log=(BASE/folder/'game.log').read_text(encoding='utf8')
    assert 'SCRIPT ERROR' not in log and 'Parse Error' not in log,folder
    assert all('resources still in use at exit' in line for line in log.splitlines() if line.startswith('ERROR:')),folder
remaining=[line for line in (BASE/'journey_final/game.log').read_text(encoding='utf8').splitlines() if line.startswith('Resource still in use:')]
assert len(remaining)==16 and all(line.endswith('(GDScript)') for line in remaining)
baseline=json.loads((BASE/'journey_baseline/journey_report.json').read_text(encoding='utf8'))
assert not baseline['ok'] and 'previously earned unread after-story' in baseline['error']
for track in json.loads(reports['audio'].read_text(encoding='utf8'))['tracks']:
    assert sha(ROOT/'assets/audio/bgm'/(track['track']+'.wav'))==track['sha256']
assert re.search(r'Passing Tests\s+638\b',(BASE/'unit.log').read_text(encoding='utf8'))
assert not subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True).strip(),'Commit reviewed changes first'
balance=ROOT.parent/'_testenv/release059/balance_verified/appdata/HoshigaokaEchoes/balance_comparison.json'
assert len(json.loads(balance.read_text(encoding='utf8'))['runs'])==30

# Read current player files at publication time; never migrate a QA save.
checkpoint=BASE/'player-checkpoint'
checkpoint.mkdir(exist_ok=True)
preserved=[]
for group,folder in [('player',OLD/'_testenv/player/appdata/HoshigaokaEchoes'),('formal',Path.home()/'AppData/Roaming/HoshigaokaEchoes')]:
    for relative in ['save/savegame.json','save/savegame_backup.json','settings/settings.cfg']:
        source=folder/relative
        if not source.exists(): continue
        if source.suffix=='.json': json.loads(source.read_text(encoding='utf-8-sig'))
        dest=checkpoint/group/relative
        dest.parent.mkdir(parents=True,exist_ok=True)
        checksum=sha(source);shutil.copy2(source,dest);assert sha(dest)==checksum
        preserved.append(dict(group=group,relative=relative,source=str(source),sha256=checksum))
assert any(e['group']=='player' and e['relative']=='save/savegame.json' for e in preserved)
(checkpoint/'checkpoint.json').write_text(json.dumps(preserved,ensure_ascii=False,indent=2),encoding='utf8')

evidence=OUT/'实机验证';evidence.mkdir(exist_ok=True)
for name,p in reports.items(): shutil.copy2(p,evidence/(name+'_report.json'))
shutil.copy2(balance,evidence/'balance_comparison.json')
for name in ['unit.log','import.log','export.log']: shutil.copy2(BASE/name,evidence/name)
for name in ['retail_final','navigation_delivery','journey_final','boss_final']:
    shutil.copy2(BASE/name/'game.log',evidence/(name+'_game.log'))
shutil.copy2(BASE/'journey_baseline/journey_report.json',evidence/'before_fix_reproduced_failure.json')
gallery=['<!doctype html><meta charset="utf-8"><title>0.5.10 验收</title><style>body{background:#091422;color:#e8efff;font:18px/1.8 Microsoft YaHei;margin:30px}img{max-width:100%}figure{max-width:1280px;margin:30px 0}a{color:#90dfff}</style><h1>0.5.10 完整流程与按钮修复</h1><p>retail、navigation、journey、boss 为最终 EXE 真实 Windows 输入，使用隔离存档副本，战斗时钟正常；属于自动化实机操作，不是人工游玩。source、modal 为源码渲染视口及 UI 夹具。balance 为上一轮领域模拟，本轮未修改战斗数值。</p>']
folders=[('retail',BASE/'retail_final'),('navigation',BASE/'navigation_delivery'),('journey',BASE/'journey_final'),('boss',BASE/'boss_final'),('source',BASE/'ui_acceptance/appdata/HoshigaokaEchoes/frontend_shots'),('modal',BASE/'modal/appdata/HoshigaokaEchoes/frontend_shots')]
for name,folder in folders:
    dest=evidence/name;dest.mkdir(exist_ok=True)
    for p in sorted(folder.glob('*.png')):
        if p.stem.startswith(('boss_motion_','boss_continuous_')): continue
        if name=='source' and p.stem in ['hub_resource_tip','cultivation_resource_tip']: continue
        shutil.copy2(p,dest/p.name)
        label=html.escape(name+'/'+p.name)
        gallery.append(f'<figure><a href="{label}"><img loading="lazy" src="{label}"></a><figcaption>{label}</figcaption></figure>')
(evidence/'实机对照.html').write_text(''.join(gallery),encoding='utf8')
shutil.copy2(ROOT/'docs/RELEASE0510_ACCEPTANCE_20261014.md',OUT/'本轮修改与验证.md')
for name in ['CAMPUS0510_ASSET_PROVENANCE.md','CAMPUS059_ASSET_PROVENANCE.md','CAMPUS058_ASSET_PROVENANCE.md','CAMPUS057_ASSET_PROVENANCE.md']:
    shutil.copy2(ROOT/'docs'/name,OUT/name)
licenses=OUT/'素材授权';licenses.mkdir(exist_ok=True)
for p in (ROOT/'assets/licenses').glob('*.txt'): shutil.copy2(p,licenses/p.name)
(OUT/'启动星丘残响.cmd').write_text('@echo off\nsetlocal\ncd /d "%~dp0"\nset "APPDATA=%~dp0_testenv\\player\\appdata"\nif not exist "%APPDATA%" mkdir "%APPDATA%"\nstart "" "%~dp0HoshigaokaEchoes.exe" --resolution 1280x720\nendlocal\n',encoding='ascii')
(OUT/'试玩说明.txt').write_text('《星丘残响》第一章 0.5.10\n双击启动星丘残响.cmd；EXE、PCK 保持同目录。\n修复首次胜利后重试失败丢失待看剧情、弹窗键盘焦点和按钮偶发黑底圆角；强化 Boss 三阶段声音递进。\n完整流程、实机 Boss 战和已知问题见本轮修改与验证.md、实机验证/实机对照.html。\n保留 0.5.9 可回退。ZIP 不包含玩家存档。\n',encoding='utf-8-sig')
files=[p for p in sorted(OUT.rglob('*')) if p.is_file() and '_testenv' not in p.parts and p.name!='build_manifest.json']
manifest=dict(version='0.5.10',sourceCommit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),shutdownWarningsRecorded=True,sha256={p.relative_to(OUT).as_posix():sha(p) for p in files})
(OUT/'build_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
archive=ROOT/'dist/星丘残响_第一章流程精修_0.5.10_20261014.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=4) as z:
    for p in files+[OUT/'build_manifest.json']: z.write(p,p.relative_to(OUT).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None and not any('_testenv' in n for n in z.namelist())
    assert all(hashlib.sha256(z.read(n)).hexdigest()==s for n,s in manifest['sha256'].items())
for entry in preserved:
    source=Path(entry['source']);assert sha(source)==entry['sha256'],'Player files changed during publication'
    if entry['group']=='player':
        dest=OUT/'_testenv/player/appdata/HoshigaokaEchoes'/entry['relative']
        dest.parent.mkdir(parents=True,exist_ok=True)
        assert not dest.exists() or sha(dest)==entry['sha256']
        shutil.copy2(source,dest);assert sha(dest)==entry['sha256']
launcher=ROOT.parent/'启动星丘残响.cmd'
body=launcher.read_text(encoding='ascii');assert OLD.name in body
launcher.write_text(body.replace(OLD.name,OUT.name),encoding='ascii')
subprocess.run([shutil.which('pwsh') or 'pwsh','-NoProfile','-Command',"& '"+str(ROOT/'tools/retain_release_versions.ps1')+"' -Keep @('"+OUT.name+"','"+OLD.name+"')"],check=True)
print(json.dumps(dict(ok=True,archive=str(archive),bytes=archive.stat().st_size,files=len(files),preservedFiles=len(preserved)),ensure_ascii=False))
