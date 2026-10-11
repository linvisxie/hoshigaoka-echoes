"""Ship 0.5.2 only with matching final Retail evidence and completed fresh campaign."""
from pathlib import Path
import hashlib,json,shutil,subprocess,zipfile
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'_testenv/interaction-revision'
OUT=ROOT/'dist/chapter_one_0.5.2_20261012'
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
reports={'fresh_campaign':BASE/'fresh2/appdata/HoshigaokaEchoes/campaign_report.json','training':BASE/'fresh2/appdata/HoshigaokaEchoes/first_challenge_training.json','ui':BASE/'ui_final/appdata/HoshigaokaEchoes/interaction_report.json','retail':BASE/'retail_final/retail_report.json','audio':BASE/'audio/audio_report.json'}
data={k:json.loads(p.read_text(encoding='utf8')) for k,p in reports.items()}
assert data['fresh_campaign']['ok'] and data['ui']['ok'] and data['retail']['ok']
assert len([k for k in data['fresh_campaign']['summaries'] if k.startswith('1-')])==10
assert data['retail']['pckSha256']==digest(OUT/'HoshigaokaEchoes.pck')
assert data['retail']['exeSha256']==digest(OUT/'HoshigaokaEchoes.exe')
assert data['audio']['rms']>.0001 and data['audio']['clippedSamples']==0
unit=BASE/'unit/gut_final.log'
assert 'Passing Tests       609' in unit.read_text(encoding='utf8')
evidence=OUT/'实机验证';evidence.mkdir(exist_ok=True)
for key,p in reports.items():shutil.copy2(p,evidence/(key+'_report.json'))
shutil.copy2(unit,evidence/'unit.log')
for key,source,patterns in [('fresh_campaign',BASE/'fresh2/appdata/HoshigaokaEchoes/campaign_shots',['battle_1-*.png','result_1-*.png','first_challenge_training_*.png']),('ui',BASE/'ui_final/appdata/HoshigaokaEchoes/frontend_shots',['*.png']),('retail',BASE/'retail_final',['boss_phase_*.png','boss_continuous_*.png','upgrade_*.png','victory.png','pause_retry.png','title.png'])]:
    dest=evidence/key;dest.mkdir(exist_ok=True)
    for pattern in patterns:
        for p in source.glob(pattern):shutil.copy2(p,dest/p.name)
shutil.copy2(BASE/'audio/windows_loopback.wav',evidence/'Boss实机音频采样.wav')
gallery=['<!doctype html><meta charset="utf-8"><title>星丘残响0.5.2实机</title><style>body{background:#0a1122;color:#e6edf9;font:18px/1.8 Microsoft YaHei;margin:30px}img{max-width:100%;border:1px solid #526a8e}figure{max-width:1280px;margin:30px 0}a{color:#8fdaff}</style><h1>0.5.2 实机截图</h1><p>新游戏连续十关、最终导出包Boss战与角色界面。自动化验证不代表用户审美验收。Boss连续帧位于retail目录，每秒采样一次。</p>']
for name,label in [('ui/briefing_reordered.png','拖拽编队与透明头像'),('ui/growth_page2.png','培养第二页'),('ui/character_equipment.png','角色装备'),('ui/backpack_accessory.png','分类背包与错题集'),('ui/story_minase_sara.png','剧情全身立绘'),('ui/archive_chronological.png','顺序剧情档案'),('retail/boss_phase_2.png','最终导出包Boss第二阶段'),('retail/boss_phase_3.png','最终导出包Boss第三阶段'),('retail/victory.png','最终导出包结算')]+[(f'fresh_campaign/battle_1-{i}.png',f'新游戏流程1-{i}') for i in range(1,11)]:
    gallery.append(f'<figure><a href="{name}"><img loading="lazy" src="{name}"></a><figcaption>{label}</figcaption></figure>')
(evidence/'实机对照.html').write_text(''.join(gallery),encoding='utf8')
licenses=OUT/'素材授权';licenses.mkdir(exist_ok=True)
for p in (ROOT/'assets/licenses').glob('*.txt'):shutil.copy2(p,licenses/p.name)
for p in (ROOT/'dist/chapter_one_0.5.1_20261012/素材授权').glob('*.json'):shutil.copy2(p,licenses/p.name)
for name in ['boss_drive_audio.json','character_fullbody_revision.json','transparent_portrait_revision.json','core_medallion_revision.json','interaction_revision_image_prompts.json']:
    shutil.copy2(ROOT/'docs'/name,licenses/name)
shutil.copy2(ROOT/'docs/INTERACTION_REVISION_20261012.md',OUT/'本轮修改与验证.md')
shutil.copy2(ROOT/'docs/interaction_revision_balance.json',evidence/'battle_balance.json')
(OUT/'启动星丘残响.cmd').write_text('@echo off\nsetlocal\ncd /d "%~dp0"\nset "APPDATA=%~dp0_testenv\\player\\appdata"\nif not exist "%APPDATA%" mkdir "%APPDATA%"\nstart "" "%~dp0HoshigaokaEchoes.exe" --resolution 1280x720\nendlocal\n',encoding='ascii')
(OUT/'试玩说明.txt').write_text('《星丘残响》第一章0.5.2\n\n双击启动星丘残响.cmd。保留exe与pck同目录。\n出战角色左键选择/取消，拖拽头像排序。1～6选人，点击地面部署；Q技能、R撤退、Space暂停。\n新增角色装备页和分类背包；培养左侧记录可直接点击，全部投入会保护当前等级上限。\n包含十关完整流程及三阶段Boss。最终视觉与音色仍待用户试玩验收。\nZIP不含玩家/测试存档；统一启动器保留原玩家进度。实机截图、连续帧、报告、素材来源随包提供。\n',encoding='utf-8-sig')
files=[p for p in sorted(OUT.rglob('*')) if p.is_file() and '_testenv' not in p.parts and p.name!='build_manifest.json']
manifest={'version':'0.5.2','sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'userArtAcceptance':False,'sha256':{p.relative_to(OUT).as_posix():digest(p) for p in files}}
(OUT/'build_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
archive=ROOT/'dist/星丘残响_第一章交互与战斗修订_0.5.2_20261012.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for p in files+[OUT/'build_manifest.json']:z.write(p,p.relative_to(OUT).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert all(digest_value==hashlib.sha256(z.read(name)).hexdigest() for name,digest_value in manifest['sha256'].items())
# Preserve genuine player bytes; test saves remain outside the shipping package.
checkpoint=json.loads((BASE/'player-checkpoint/save_checkpoint.json').read_text(encoding='utf8-sig'))
for label,entries in checkpoint.items():
    for entry in entries:
        source=Path(entry['source']);assert digest(source)==entry['sha256'],'Player save changed during work; preserve current data before switching'
        if label=='player':
            destination=OUT/'_testenv/player/appdata/HoshigaokaEchoes/save'/source.name
            destination.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,destination)
            assert digest(destination)==entry['sha256']
launcher=ROOT.parent/'启动星丘残响.cmd'
old=launcher.read_text(encoding='utf8-sig')
assert 'chapter_one_0.5.1_20261012' in old
launcher.write_text(old.replace('chapter_one_0.5.1_20261012','chapter_one_0.5.2_20261012'),encoding='ascii')
subprocess.run(['powershell','-NoProfile','-Command',"& '"+str(ROOT/'tools/retain_release_versions.ps1')+"' -Keep @('chapter_one_0.5.2_20261012','chapter_one_0.5.1_20261012')"],check=True)
print(json.dumps({'archive':str(archive),'bytes':archive.stat().st_size,'files':len(files),'playerSavePreserved':True},ensure_ascii=False))
