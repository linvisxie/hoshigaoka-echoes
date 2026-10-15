"""Package verified binaries and evidence; never includes player data."""
from pathlib import Path
import hashlib, html, json, re, shutil, subprocess, zipfile

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent / '_testenv/feedback0517'
OUT = ROOT / 'dist/chapter_one_0.5.17_20261015'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
reports = {}
folders = []
for size in ('720','1080'):
    for kind, sub, report in [('feedback',f'ui{size}_accept','feedback_report.json'),('results',f'results{size}_delivery','result_report.json')]:
        label = kind + size
        root = BASE/sub/'appdata/HoshigaokaEchoes'
        reports[label] = root/report
        folders.append((label,root/'frontend_shots'))
for case in ('feedback','insufficient'):
    for locale in ('zh','en'):
        label = f'retail_{case}_{locale}'
        reports[label] = BASE/label/'retail_hub_report.json'
        folders.append((label,BASE/label))
for label,p in reports.items():
    report = json.loads(p.read_text(encoding='utf8'))
    assert report['ok'],label
    if label.startswith('retail'):
        for ext in ('exe','pck'):
            assert sha(OUT/f'HoshigaokaEchoes.{ext}') == report[ext+'Sha256'],label
        log=(p.parent/'game.log').read_text(encoding='utf8',errors='replace')
        assert 'SCRIPT ERROR' not in log and 'Parse Error' not in log
        assert all('resources still in use at exit' in line for line in log.splitlines() if line.startswith('ERROR:'))
assert re.search(r'Passing Tests\s+655\b',(BASE/'unit_delivery.log').read_text(encoding='utf8'))
assert not subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True).strip(),'Commit reviewed source first'
evidence=OUT/'实机验证'
evidence.mkdir(exist_ok=True)
for label,p in reports.items(): shutil.copy2(p,evidence/(label+'_report.json'))
for name in ('unit_delivery.log','export_delivery.log'): shutil.copy2(BASE/name,evidence/name)
shutil.copy2(BASE/'insufficient_fixture/fixture.json',evidence/'insufficient_fixture_metadata.json')
gallery=['<!doctype html><meta charset="utf-8"><title>0.5.17 验收</title><style>body{background:#091422;color:#edf2ff;font:18px/1.8 sans-serif;margin:30px}img{max-width:100%}figure{max-width:1280px;margin:30px 0}</style><h1>装备提示、强化预览与结算</h1><p>source 为结算与渲染样本；retail 为最终 EXE 的真实 Windows 输入。资源不足使用隔离边界样本；结算测试手动设定胜利结果，不代表完整战斗试玩。</p>']
for label,folder in folders:
    dest=evidence/label
    dest.mkdir(exist_ok=True)
    for p in sorted(folder.glob('*.png')):
        if '_frame_' in p.name: continue
        shutil.copy2(p,dest/p.name)
        link=html.escape(label+'/'+p.name)
        gallery.append(f'<figure><img loading="lazy" src="{link}"><figcaption>{link}</figcaption></figure>')
    if label.startswith('retail'): shutil.copy2(folder/'game.log',evidence/(label+'_game.log'))
(evidence/'实机对照.html').write_text(''.join(gallery),encoding='utf8')
shutil.copy2(ROOT/'docs/RELEASE0517_ACCEPTANCE_20261015.md',OUT/'本轮修改与验证.md')
licenses=OUT/'素材授权'
licenses.mkdir(exist_ok=True)
for p in (ROOT/'assets/licenses').glob('*.txt'): shutil.copy2(p,licenses/p.name)
(OUT/'启动星丘残响.cmd').write_text('@echo off\nsetlocal\ncd /d "%~dp0"\nset "APPDATA=%~dp0_testenv\\player\\appdata"\nif not exist "%APPDATA%" mkdir "%APPDATA%"\nstart "" "%~dp0HoshigaokaEchoes.exe" --resolution 1280x720\nendlocal\n',encoding='ascii')
(OUT/'试玩说明.txt').write_text('《星丘残响》第一章 0.5.17\n双击启动星丘残响.cmd；EXE、PCK 保持同目录。\n修复装备操作提示不消失、预览负余额、结算遗漏装备展示。\n验收报告与截图见本轮修改与验证.md、实机验证/实机对照.html。\n保留 0.5.16 可回退；ZIP 不含玩家存档。\n',encoding='utf-8-sig')
files=[p for p in sorted(OUT.rglob('*')) if p.is_file() and '_testenv' not in p.parts and p.name!='build_manifest.json']
manifest=dict(version='0.5.17',sourceCommit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),sha256={p.relative_to(OUT).as_posix():sha(p) for p in files})
(OUT/'build_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
archive=ROOT/'dist/星丘残响_装备提示与结算修正_0.5.17_20261015.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=4) as z:
    for p in files+[OUT/'build_manifest.json']: z.write(p,p.relative_to(OUT).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None and not any('_testenv' in n for n in z.namelist())
    assert all(hashlib.sha256(z.read(n)).hexdigest()==h for n,h in manifest['sha256'].items())
print(json.dumps(dict(ok=True,archive=str(archive),bytes=archive.stat().st_size,files=len(files),published=False),ensure_ascii=False))
