"""Package 0.5.1 only after real fresh-campaign, UI and Retail reports pass."""
from pathlib import Path
from PIL import Image
import hashlib,json,shutil,subprocess,zipfile

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'dist/chapter_one_0.5.1_20261011'
BASE=ROOT.parent/'_testenv/chapter-polish'
reports={
    'fresh_campaign':BASE/'fresh/appdata/HoshigaokaEchoes/campaign_report.json',
    'first_challenge_training':BASE/'fresh/appdata/HoshigaokaEchoes/first_challenge_training.json',
    'ui':BASE/'ui/appdata/HoshigaokaEchoes/chapter_ui_report.json',
    'retail':BASE/'retail/retail_report.json',
    'audio':BASE/'audio/audio_report.json',
}
data={k:json.loads(p.read_text(encoding='utf8')) for k,p in reports.items()}
assert data['fresh_campaign']['ok'] and data['retail']['ok']
assert len([k for k in data['fresh_campaign']['summaries'] if k.startswith('1-')])==10
assert all(c['ok'] for c in data['ui']['checks'])
assert data['retail']['pckSha256']==hashlib.sha256((OUT/'HoshigaokaEchoes.pck').read_bytes()).hexdigest()
assert data['audio']['rms']>.0001 and data['audio']['clippedSamples']==0
evidence=OUT/'实机验证';evidence.mkdir(exist_ok=True)
for label,p in reports.items():shutil.copy2(p,evidence/(label+'_report.json'))
shutil.copy2(BASE/'unit/unit_final.log',evidence/'unit.log')
for label,folder,patterns in [
    ('fresh_campaign',BASE/'fresh/appdata/HoshigaokaEchoes/campaign_shots',['battle_1-*.png','result_1-*.png','boss_*.png','first_challenge_training_*.png']),
    ('ui',BASE/'ui/appdata/HoshigaokaEchoes/frontend_shots',['device_selected_interface.png','chinatsu_active.png','growth_page_2.png','ending_silhouette.png']),
    ('retail',BASE/'retail',['boss_phase_*.png','boss_continuous_*.png','victory.png','pause_retry.png'])]:
    dest=evidence/label;dest.mkdir(exist_ok=True)
    for pattern in patterns:
        for p in folder.glob(pattern):shutil.copy2(p,dest/p.name)
motion=sorted((evidence/'fresh_campaign').glob('boss_motion_*.png'))
if motion:
    times={a['capture']:a['wallMs'] for a in data['fresh_campaign']['actions']}
    durations=[max(20,min(2000,times[b.stem]-times[a.stem])) for a,b in zip(motion,motion[1:])]+[400]
    frames=[Image.open(p).convert('RGB') for p in motion]
    frames[0].save(evidence/'Boss采样截图预览.gif',save_all=True,append_images=frames[1:],duration=durations,loop=0)
notice=OUT/'素材授权';notice.mkdir(exist_ok=True)
shutil.copy2(ROOT.parent/'meishu/Hoshigaoka_Art_Preview_Pack/02_visual_bible_overview.png',evidence/'用户原始视觉圣经.png')
gallery=['<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>星丘残响 · 0.5.1 实机对照</title><style>body{margin:0;background:#0a1122;color:#e6edf9;font:16px/1.7 "Microsoft YaHei",sans-serif}main{max-width:1500px;margin:auto;padding:24px}h1{font-size:28px}a{color:#9dd8ff}img{width:100%;height:auto;border:1px solid #456184;border-radius:8px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(480px,1fr));gap:24px}figure{margin:0 0 24px}figcaption{padding:8px 0;color:#b8cae6}p{max-width:1050px}details{margin:24px 0}summary{cursor:pointer;color:#e9ce96}small{color:#9eb0ca}@media(max-width:600px){.grid{display:block}main{padding:14px}}</style><main><h1>星丘残响 · 0.5.1 实机对照</h1><p>以下是运行中的原始截图。点击图片可查看原图；动态预览由连续采样截图组成。自动化通过不等于用户审美验收，人物边缘、过渡和音色仍可继续精修。</p><details><summary>展开用户原始视觉圣经</summary><a href="用户原始视觉圣经.png"><img src="用户原始视觉圣经.png"></a><small>正式校徽六瓣、最终场景体育馆，采用已裁决规格；原参考中的冲突文字不改写角色设定。</small></details><div class="grid">']
for n in range(1,11):
    name=f'fresh_campaign/battle_1-{n}.png'
    gallery.append(f'<figure><a href="{name}"><img loading="lazy" src="{name}" alt="第{n}关真实运行截图"></a><figcaption>1-{n} · 新游戏连续流程实机截图</figcaption></figure>')
for name,label in [('fresh_campaign/boss_phase_2.png','Boss 第二阶段'),('fresh_campaign/boss_warning_phase_2.png','真实错题预警'),('ui/device_selected_interface.png','实验装置操作面板'),('ui/ending_silhouette.png','第一章结束'),('retail/victory.png','最终 Windows 导出包结算'),('Boss采样截图预览.gif','Boss 动作连续采样预览')]:
    gallery.append(f'<figure><a href="{name}"><img loading="lazy" src="{name}" alt="{label}"></a><figcaption>{label}</figcaption></figure>')
gallery.append('</div></main></html>')
(evidence/'实机对照.html').write_text(''.join(gallery),encoding='utf8')
for p in (ROOT/'assets/licenses').glob('*.txt'):shutil.copy2(p,notice/p.name)
for p in (ROOT/'dist/chapter_one_0.5.0_20261011/素材授权').glob('*.json'):shutil.copy2(p,notice/p.name)
for name in ['chapter_tail_assets.json','boss_polish_assets.json','boss_polish_audio.json']:
    shutil.copy2(ROOT/'docs'/name,notice/name)
shutil.copy2(ROOT/'docs/CHAPTER_POLISH_20261011.md',OUT/'本轮优化与验证.md')
shutil.copy2(ROOT/'docs/CHAPTER_ONE_20261011.md',OUT/'上一轮开发记录.md')
(OUT/'启动星丘残响.cmd').write_text('@echo off\nsetlocal\ncd /d "%~dp0"\nset "APPDATA=%~dp0_testenv\\player\\appdata"\nif not exist "%APPDATA%" mkdir "%APPDATA%"\nstart "" "%~dp0HoshigaokaEchoes.exe" --resolution 1280x720\nendlocal\n',encoding='ascii')
(OUT/'试玩说明.txt').write_text('''《星丘残响》第一章 0.5.1 打磨候选版

双击“启动星丘残响.cmd”；exe 与 pck 必须保持同目录。
工程上方统一启动器保留原玩家进度。新解压副本从新游戏开始，包内不含自动化测试存档。
包含完整十关、校园/培养/装备/剧情档案、Boss 三阶段和第一章结尾。
沿用前五关水平三路、透视格侧边、六瓣动态核心和玻璃 HUD。

本轮：重制 Boss 人物动作，分离动态试卷和能量环前后层；错题预警覆盖实际危险格；
修正纱良和千夏动画切片夹入相邻动作的杂点；实验装置显示耐久、剩余寿命、独立头像和收回按钮。
Boss 技能/阶段使用两种新制作的柔和残响音色，区别于 Wave 提示。
已用前九关实际获得的资源完成首次 Boss 培养与十关连续流程，无须借用 Boss 奖励。

1～6 选择角色，点地面部署；选在场角色后 Q 技能、R 撤退。
纱良 Q 后点空格放装置，右键取消；装置到期或收回释放站位。
Space 暂停，可重试；强化鼠标或数字选择；剧情点击/Enter 推进。

这是可运行的打磨候选版本。用户视觉/听感验收尚未通过；动作边缘、细节和过渡仍有精修空间。
本轮优化与验证、实机截图/连续帧、素材来源说明随包提供。
''',encoding='utf-8-sig')
files=[p for p in sorted(OUT.rglob('*')) if p.is_file() and '_testenv' not in p.parts and p.name!='build_manifest.json']
manifest={'version':'0.5.1','sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
          'gameplayCommit':'19553ee','userArtAcceptance':False,
          'sha256':{p.relative_to(OUT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
(OUT/'build_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
archive=ROOT/'dist/星丘残响_第一章十关打磨候选版_0.5.1_20261011.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for p in files+[OUT/'build_manifest.json']:z.write(p,p.relative_to(OUT).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert all(hashlib.sha256(z.read(n)).hexdigest()==sha for n,sha in manifest['sha256'].items())
print(json.dumps({'archive':str(archive),'bytes':archive.stat().st_size,'files':len(files)},ensure_ascii=False))
