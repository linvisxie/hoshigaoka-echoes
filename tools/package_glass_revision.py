"""Publish only the exact 0.5.3 binary that passed isolated Windows validation."""
from pathlib import Path
import hashlib, html, json, shutil, subprocess, zipfile

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent / '_testenv/glass-combat-revision'
OUT = ROOT / 'dist/chapter_one_0.5.3_20261012'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

reports = {
    'fresh_campaign': BASE / 'fresh2/appdata/HoshigaokaEchoes/campaign_report.json',
    'training_tail': BASE / 'fresh2/appdata/HoshigaokaEchoes/first_challenge_training_tail.json',
    'training_boss': BASE / 'fresh2/appdata/HoshigaokaEchoes/first_challenge_training_boss.json',
    'ui': BASE / 'ui_final/appdata/HoshigaokaEchoes/glass_ui_report.json',
    'balance_simulation': BASE / 'balance5/appdata/HoshigaokaEchoes/balance_comparison.json',
    'retail': BASE / 'retail_final/retail_report.json',
    'audio': BASE / 'audio/audio_report.json',
    'audio_source': BASE / 'audio/source_probe.json',
}
data = {k: json.loads(p.read_text(encoding='utf-8-sig')) for k,p in reports.items()}
assert all(data[k]['ok'] for k in ['fresh_campaign','ui','retail'])
assert all(f'1-{i}' in data['fresh_campaign']['summaries'] for i in range(1,11))
assert data['retail']['normalExit'] and data['retail']['retry']
for ext in ['exe','pck']:
    assert digest(OUT / ('HoshigaokaEchoes.'+ext)) == data['retail'][ext+'Sha256']
assert data['audio']['rms'] > .0001 and data['audio']['clippedSamples'] == 0
unit = BASE / 'unit3.log'
assert 'Passing Tests       611' in unit.read_text(encoding='utf8')
assert not subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True).strip(), 'Commit reviewed source before packaging'

# Check all source saves before any player migration or launcher change.
checkpoint = json.loads((BASE/'player-checkpoint/save_checkpoint.json').read_text(encoding='utf-8-sig'))
for entries in checkpoint.values():
    for entry in entries:
        assert digest(Path(entry['source'])) == entry['sha256'], 'Player save changed; do not overwrite'

evidence = OUT/'实机验证'
evidence.mkdir(exist_ok=True)
for key,p in reports.items():
    shutil.copy2(p,evidence/(key+'_report.json'))
shutil.copy2(unit,evidence/'unit.log')
sources = {
    'fresh_campaign': BASE/'fresh2/appdata/HoshigaokaEchoes/campaign_shots',
    'ui': BASE/'ui_final/appdata/HoshigaokaEchoes/frontend_shots',
    'retail': BASE/'retail_final',
}
for key,source in sources.items():
    dest = evidence/key
    dest.mkdir(exist_ok=True)
    for p in source.glob('*.png'):
        shutil.copy2(p,dest/p.name)
shutil.copy2(BASE/'audio/windows_loopback.wav',evidence/'Boss实机音频采样.wav')
gallery = ['<!doctype html><meta charset="utf-8"><title>星丘残响0.5.3实机</title><style>body{background:#0a1122;color:#e6edf9;font:18px/1.8 Microsoft YaHei;margin:30px}img{max-width:100%;border:1px solid #526a8e}figure{max-width:1280px;margin:30px 0}a{color:#8fdaff}</style><h1>0.5.3 实机对照</h1><p>源码新游戏连续十关与最终导出包实测分开保存。自动化验证不代替用户审美及听感验收。</p><p><a href="../本轮修改与验证.md">逐项报告</a></p><audio controls src="Boss实机音频采样.wav"></audio>']
for folder in ['ui','retail','fresh_campaign']:
    for p in sorted((evidence/folder).glob('*.png')):
        name = html.escape(folder+'/'+p.name)
        gallery.append(f'<figure><a href="{name}"><img loading="lazy" src="{name}"></a><figcaption>{name}</figcaption></figure>')
(evidence/'实机对照.html').write_text(''.join(gallery),encoding='utf8')
licenses = OUT/'素材授权'
licenses.mkdir(exist_ok=True)
for p in (ROOT/'assets/licenses').glob('*.txt'):
    shutil.copy2(p,licenses/p.name)
for name in ['glass_character_assets.json','glass_combat_balance.json','orchestral_drive_audio.json']:
    shutil.copy2(ROOT/'docs'/name,evidence/name)
shutil.copy2(ROOT/'docs/glass_character_frames.png',evidence/'glass_character_frames.png')
shutil.copy2(ROOT/'docs/GLASS_COMBAT_REVISION_20261012.md',OUT/'本轮修改与验证.md')
(OUT/'启动星丘残响.cmd').write_text('@echo off\nsetlocal\ncd /d "%~dp0"\nset "APPDATA=%~dp0_testenv\\player\\appdata"\nif not exist "%APPDATA%" mkdir "%APPDATA%"\nstart "" "%~dp0HoshigaokaEchoes.exe" --resolution 1280x720\nendlocal\n',encoding='ascii')
(OUT/'试玩说明.txt').write_text('《星丘残响》第一章0.5.3\n双击启动星丘残响.cmd。保留exe与pck同目录。\n出战卡单击选择/取消，拖动排序；1～6选人，点击地面部署；Q技能、R撤退、Space暂停、Esc返回。\n后半章多路攻势，请结合培养、技能时机与撤退换线。\n本轮修改与验证.md逐项对应反馈；实机验证/实机对照.html含截图与Boss回录。\nZIP不含玩家或测试存档；原统一启动器保留已有玩家进度。保留0.5.2用于回退。\n最终视觉、音色及长期平衡仍需用户试玩验收。\n',encoding='utf-8-sig')
files = [p for p in sorted(OUT.rglob('*')) if p.is_file() and '_testenv' not in p.parts and p.name != 'build_manifest.json']
manifest = {'version':'0.5.3','sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'userArtAcceptance':False,'sha256':{p.relative_to(OUT).as_posix():digest(p) for p in files}}
(OUT/'build_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
archive = ROOT/'dist/星丘残响_第一章清透界面与战斗整改_0.5.3_20261012.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for p in files+[OUT/'build_manifest.json']:
        z.write(p,p.relative_to(OUT).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert not any('_testenv' in n for n in z.namelist())
    assert all(h == hashlib.sha256(z.read(n)).hexdigest() for n,h in manifest['sha256'].items())
for entry in checkpoint['player']:
    source = Path(entry['source'])
    destination = OUT/'_testenv/player/appdata/HoshigaokaEchoes/save'/source.name
    destination.parent.mkdir(parents=True,exist_ok=True)
    assert not destination.exists() or digest(destination) == entry['sha256'], 'Do not overwrite a newer destination save'
    shutil.copy2(source,destination)
    assert digest(destination) == entry['sha256']
launcher = ROOT.parent/'启动星丘残响.cmd'
old = launcher.read_text(encoding='utf-8-sig')
assert 'chapter_one_0.5.2_20261012' in old or 'chapter_one_0.5.3_20261012' in old
launcher.write_text(old.replace('chapter_one_0.5.2_20261012','chapter_one_0.5.3_20261012'),encoding='ascii')
subprocess.run([shutil.which('pwsh') or 'pwsh','-NoProfile','-Command',"& '"+str(ROOT/'tools/retain_release_versions.ps1')+"' -Keep @('chapter_one_0.5.3_20261012','chapter_one_0.5.2_20261012')"],check=True)
print(json.dumps({'archive':str(archive),'bytes':archive.stat().st_size,'files':len(files),'playerSavePreserved':True},ensure_ascii=False))
