"""Final cosmetic revision: actual Retail OS-input smoke for stage 7 or 9.
Reuses the owned-window input helpers from the full Boss replay driver.
Does not claim a full campaign or normal-exit test; the full replay records that separately.
"""
from pathlib import Path
import sys

stage = int(sys.argv.pop(sys.argv.index('--stage') + 1)) if '--stage' in sys.argv else 7
if '--stage' in sys.argv: sys.argv.remove('--stage')
assert stage in (7, 9)
source = Path(__file__).with_name('verify_chapter_retail.py').read_text(encoding='utf8')
prefix = source.split("        time.sleep(2);shot('title')")[0]
body = '''        time.sleep(2);shot('title');key(13);time.sleep(1.2)
        click(1545,590);time.sleep(1)
        click(1180,560) if STAGE==7 else click(280,805)
        time.sleep(1);shot('briefing');click(1600,1005);time.sleep(2)
        final=probe();assert final and final['stage']=='1-'+str(STAGE),str(final and final['stage'])
        shot('battle_final_'+str(STAGE));click(1815,55);time.sleep(.4);shot('pause')
    finally:
        if proc.poll() is None:proc.terminate();proc.wait(timeout=10)
text=(out/'game.log').read_text(encoding='utf8',errors='replace')
assert 'SCRIPT ERROR' not in text and 'Parse Error' not in text
report=dict(type='Final Retail cosmetic-revision OS-input smoke; owned process closed by verifier',ok=True,stage=STAGE,pckSha256=hashlib.sha256(exe.with_suffix('.pck').read_bytes()).hexdigest(),finalProbe=final)
(out/'smoke_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'ok':True,'stage':STAGE,'screenshots':len(captured)}))
'''
exec(compile(prefix + body, str(Path(__file__)), 'exec'), dict(__file__=__file__, STAGE=stage))
