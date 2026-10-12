"""Publish the tested 0.5.4 binary, preserve player saves, retain two releases."""
from pathlib import Path
import hashlib,html,json,re,shutil,subprocess,zipfile

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'_testenv/release054'
OUT=ROOT/'dist/chapter_one_0.5.4_20261012'
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
reports={
 'fresh_campaign':BASE/'fresh3/appdata/HoshigaokaEchoes/campaign_report.json',
 'ui':BASE/'ui3/appdata/HoshigaokaEchoes/glass_ui_report.json',
 'settlement':BASE/'settlement2/appdata/HoshigaokaEchoes/settlement_ui_report.json',
 'balance_simulation':BASE/'balance/appdata/HoshigaokaEchoes/balance_comparison.json',
 'retail':BASE/'retail_final/retail_report.json',
 'score_assets':BASE/'score_asset_report.json',
 'audio':BASE/'audio/audio_report.json',
 'audio_source':BASE/'audio/source_probe.json',
}
data={k:json.loads(p.read_text(encoding='utf-8-sig')) for k,p in reports.items()}
for k in ['fresh_campaign','ui','settlement','retail','score_assets']:assert data[k]['ok'],k
assert all(data['fresh_campaign']['summaries'][f'1-{i}']['victory'] for i in range(1,11))
assert data['retail']['normalExit'] and data['retail']['retry']
for ext in ['exe','pck']:assert digest(OUT/f'HoshigaokaEchoes.{ext}')==data['retail'][ext+'Sha256']
runtime_log=(BASE/'retail_final/game.log').read_text(encoding='utf8')
assert 'ERROR:' not in runtime_log and 'SCRIPT ERROR' not in runtime_log
unit=BASE/'unit6.log'
assert re.search(r'Passing Tests\s+621\b',unit.read_text(encoding='utf8'))
assert data['audio']['rms']>.0001 and data['audio']['clippedSamples']==0
assert data['audio_source']['audio']['track'].startswith('boss_exam_')
assert not subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True).strip(),'Commit reviewed source before publishing'

# Preserve the latest real player files, including any progress made during work.
# Never migrate the fresh-run or UI verification saves into the player directory.
old=json.loads((BASE/'player-checkpoint/save_checkpoint.json').read_text(encoding='utf-8-sig'))
checkpoint=BASE/'player-checkpoint/publish_current'
checkpoint.mkdir(parents=True,exist_ok=True)
current={}
for group,entries in old.items():
    current[group]=[]
    for item in entries:
        source=Path(item['source']);assert source.is_file(),source
        json.loads(source.read_text(encoding='utf-8-sig'))
        sha=digest(source)
        backup=checkpoint/group/source.name;backup.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(source,backup);assert digest(backup)==sha
        current[group].append(dict(source=str(source),sha256=sha,changedSinceStart=sha!=item['sha256']))
settings_source=Path(old['player'][0]['source']).parent.parent/'settings/settings.cfg'
settings_sha=None
if settings_source.exists():
    settings_sha=digest(settings_source)
    settings_backup=checkpoint/'player/settings.cfg'
    shutil.copy2(settings_source,settings_backup);assert digest(settings_backup)==settings_sha
    current['settings']=[dict(source=str(settings_source),sha256=settings_sha)]
(checkpoint/'save_checkpoint.json').write_text(json.dumps(current,ensure_ascii=False,indent=2),encoding='utf8')

evidence=OUT/'实机验证';evidence.mkdir(exist_ok=True)
for key,path in reports.items():shutil.copy2(path,evidence/(key+'_report.json'))
for name in ['frontline','archer','tail','boss']:
    shutil.copy2(BASE/f'fresh3/appdata/HoshigaokaEchoes/first_challenge_training_{name}.json',evidence/f'training_{name}.json')
for name in ['unit6.log','ui3.log','settlement2.log','fresh3.log','export3.log']:
    shutil.copy2(BASE/name,evidence/name)
shutil.copy2(BASE/'retail_final/game.log',evidence/'retail_game.log')
for key,path in {
 'fresh_campaign':BASE/'fresh3/appdata/HoshigaokaEchoes/campaign_shots',
 'ui':BASE/'ui3/appdata/HoshigaokaEchoes/frontend_shots',
 'settlement':BASE/'settlement2/appdata/HoshigaokaEchoes/frontend_shots',
 'retail':BASE/'retail_final',
}.items():
    target=evidence/key;target.mkdir(exist_ok=True)
    captured={m.group(1) for m in re.finditer(r'^([^\r\n]+) 1280 720\s*$',(BASE/'retail_driver.log').read_text(encoding='utf8'),re.M)} if key=='retail' else None
    for image in path.glob('*.png'):
        if captured is None or image.stem in captured:shutil.copy2(image,target/image.name)
shutil.copy2(BASE/'audio/windows_loopback.wav',evidence/'Boss实机音频采样.wav')
shutil.copy2(ROOT/'docs/scene_scores_054.json',evidence/'scene_scores_054.json')
shutil.copy2(ROOT/'docs/RELEASE054_ACCEPTANCE_20261012.md',OUT/'本轮修改与验证.md')
licenses=OUT/'素材授权';licenses.mkdir(exist_ok=True)
for path in (ROOT/'assets/licenses').glob('*.txt'):shutil.copy2(path,licenses/path.name)
gallery=['<!doctype html><meta charset="utf-8"><title>星丘残响0.5.4验收</title><style>body{background:#091422;color:#e8efff;font:18px/1.8 Microsoft YaHei;margin:30px}img{max-width:100%;border:1px solid #536f89}figure{max-width:1280px;margin:30px 0}a{color:#90dfff}</style><h1>0.5.4 实机对照</h1><p><a href="../本轮修改与验证.md">十项逐一验收报告</a></p><p>最终EXE实机、源码完整新档、界面流程与胜负结算分别标明。测试通过不等于人工审美或听感验收通过。fresh_campaign 中旧 result 截图早于胜利动画结束，实际结算请查看 retail 和 settlement。</p><audio controls src="Boss实机音频采样.wav"></audio>']
for folder in ['retail','settlement','ui','fresh_campaign']:
    gallery.append(f'<h2>{folder}</h2>')
    for path in sorted((evidence/folder).glob('*.png')):
        name=html.escape(folder+'/'+path.name)
        gallery.append(f'<figure><a href="{name}"><img loading="lazy" src="{name}"></a><figcaption>{name}</figcaption></figure>')
(evidence/'实机对照.html').write_text(''.join(gallery),encoding='utf8')
(OUT/'启动星丘残响.cmd').write_text('@echo off\nsetlocal\ncd /d "%~dp0"\nset "APPDATA=%~dp0_testenv\\player\\appdata"\nif not exist "%APPDATA%" mkdir "%APPDATA%"\nstart "" "%~dp0HoshigaokaEchoes.exe" --resolution 1280x720\nendlocal\n',encoding='ascii')
(OUT/'试玩说明.txt').write_text('《星丘残响》第一章 0.5.4\n双击启动星丘残响.cmd，EXE与PCK保持同目录。\n角色单击选择/取消、拖动排序；Q技能，R撤退，Space暂停，Esc返回/校园菜单。\n胜利动画结束后进入结算，结算等待玩家操作；失败不推进剧情或后续关卡。\n校园地点与事件包含随进度解锁的同伴交谈与环境记录。\n本轮修改与验证.md及实机验证/实机对照.html包含详细验收。\nZIP不含玩家或测试存档。保留0.5.3可回退。音乐听感、最终审美与长期平衡仍需试玩验收。\n',encoding='utf-8-sig')
files=[p for p in sorted(OUT.rglob('*')) if p.is_file() and '_testenv' not in p.parts and p.name!='build_manifest.json']
manifest={'version':'0.5.4','sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'userArtAcceptance':False,'userMusicAcceptance':False,'sha256':{p.relative_to(OUT).as_posix():digest(p) for p in files}}
(OUT/'build_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
archive=ROOT/'dist/星丘残响_第一章界面音乐与校园整改_0.5.4_20261012.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for path in files+[OUT/'build_manifest.json']:z.write(path,path.relative_to(OUT).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None and not any('_testenv' in n for n in z.namelist())
    assert all(sha==hashlib.sha256(z.read(name)).hexdigest() for name,sha in manifest['sha256'].items())
for item in current['player']:
    source=Path(item['source']);assert digest(source)==item['sha256'],'Source changed during publication; preserve newest'
    destination=OUT/'_testenv/player/appdata/HoshigaokaEchoes/save'/source.name
    destination.parent.mkdir(parents=True,exist_ok=True)
    assert not destination.exists() or digest(destination)==item['sha256'],'Do not overwrite destination progress'
    shutil.copy2(source,destination);assert digest(destination)==item['sha256']
for item in current.get('formal',[]):assert digest(Path(item['source']))==item['sha256']
if settings_sha:
    assert digest(settings_source)==settings_sha,'Player preferences changed during publication'
    settings_destination=OUT/'_testenv/player/appdata/HoshigaokaEchoes/settings/settings.cfg'
    settings_destination.parent.mkdir(parents=True,exist_ok=True)
    assert not settings_destination.exists() or digest(settings_destination)==settings_sha
    shutil.copy2(settings_source,settings_destination);assert digest(settings_destination)==settings_sha
launcher=ROOT.parent/'启动星丘残响.cmd'
text=launcher.read_text(encoding='utf-8-sig')
assert 'chapter_one_0.5.3_20261012' in text or 'chapter_one_0.5.4_20261012' in text
launcher.write_text(text.replace('chapter_one_0.5.3_20261012','chapter_one_0.5.4_20261012'),encoding='ascii')
subprocess.run([shutil.which('pwsh') or 'pwsh','-NoProfile','-Command',"& '"+str(ROOT/'tools/retain_release_versions.ps1')+"' -Keep @('chapter_one_0.5.4_20261012','chapter_one_0.5.3_20261012')"],check=True)
print(json.dumps({'archive':str(archive),'bytes':archive.stat().st_size,'files':len(files),'playerSavePreserved':True},ensure_ascii=False))
