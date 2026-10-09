"""Project-specific gate: preserve real saves, isolate Godot, retain evidence.
Uses stdlib + bundled Pillow; no downloads, no global configuration writes.
"""
from pathlib import Path
import argparse, datetime, hashlib, json, os, re, subprocess, sys

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GODOT = Path(r'D:\星丘基础\godot\Godot_v4.7.2-stable_win64_console.exe')
REAL = Path(os.environ.get('USERPROFILE', '')) / 'AppData/Roaming/HoshigaokaEchoes'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def saves():
    # All persistent contents, not merely the assumed savegame filename.
    return {str(p.relative_to(REAL)): digest(p) for area in ('save', 'settings')
            for p in (REAL / area).rglob('*') if p.is_file()}

def run(cmd, env, log):
    with log.open('w', encoding='utf-8') as stream:
        result = subprocess.run([str(x) for x in cmd], cwd=ROOT, env=env,
                                stdout=stream, stderr=subprocess.STDOUT, timeout=300)
    text = log.read_text(encoding='utf-8', errors='replace')
    return result.returncode, text

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', type=Path, default=DEFAULT_GODOT)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--minimum-tests', type=int, default=471)
    parser.add_argument('--resources-only', action='store_true')
    args = parser.parse_args()
    output = args.output.resolve()
    if '_testenv' not in output.parts:
        raise SystemExit('Refused: evidence and APPDATA must be under _testenv')
    output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, APPDATA=str(output / 'appdata'))
    before = saves()
    tags = subprocess.check_output(['git', 'show-ref', '--tags'], cwd=ROOT).decode()
    report = {'started': datetime.datetime.now().isoformat(), 'appdata': env['APPDATA'],
              'realSaveSnapshotBefore': before, 'errors': [], 'evidenceType': 'automated'}
    try:
        from PIL import Image
        pngs = sorted([*ROOT.glob('assets/art/**/*.png'), *ROOT.glob('assets/vfx/*.png')])
        report['pngs'] = []
        for path in pngs:
            with Image.open(path) as image:
                image.load()
                report['pngs'].append({'path': path.relative_to(ROOT).as_posix(),
                    'size': list(image.size), 'sha256': digest(path)})
        tests = sorted(ROOT.glob('tests/test_*.gd'))
        expected_tests = sum(len(re.findall(r'^func test_\w+\(', p.read_text(encoding='utf-8'), re.M))
                             for p in tests)
        report['expectedScripts'] = len(tests)
        report['declaredTestFunctions'] = expected_tests
        if not args.resources_only:
            code, text = run([args.godot, '--headless', '--path', ROOT, '--import'], env, output/'import.log')
            if code or re.search(r'SCRIPT ERROR|Parse Error|Failed to load script', text):
                report['errors'].append('Import/class cache failure; inspect import.log')
            code, text = run([args.godot, '--headless', '--path', ROOT, '-s', 'addons/gut/gut_cmdln.gd',
                             '-gdir=res://tests', '-ginclude_subdirs', '-gexit'], env, output/'gut.log')
            counts = {}
            for label in ('Scripts', 'Tests', 'Passing Tests', 'Failing Tests', 'Risky/Pending', 'Asserts'):
                hits = re.findall(r'^'+re.escape(label)+r'\s+(\d+)', text, re.M)
                counts[label] = int(hits[-1]) if hits else 0
            report['gut'] = dict(counts, exitCode=code)
            if code or counts['Scripts'] != len(tests) or counts['Tests'] != expected_tests \
                    or counts['Tests'] < args.minimum_tests or counts['Passing Tests'] != counts['Tests'] \
                    or counts['Failing Tests'] or counts['Risky/Pending'] \
                    or re.search(r'SCRIPT ERROR|Parse Error|Ignoring script', text):
                report['errors'].append('GUT failure/skip/count regression; inspect gut.log')
    except Exception as exc:
        report['errors'].append(f'{type(exc).__name__}: {exc}')
    finally:
        report['realSaveSnapshotAfter'] = saves()
        report['realSavesUnchanged'] = before == report['realSaveSnapshotAfter']
        report['tagsUnchanged'] = tags == subprocess.check_output(['git','show-ref','--tags'], cwd=ROOT).decode()
        if not report['realSavesUnchanged']:
            report['errors'].append('STOP: real persistent data changed; do not restore or delete')
        if not report['tagsUnchanged']:
            report['errors'].append('STOP: existing tag set changed during validation')
        report['finished'] = datetime.datetime.now().isoformat()
        (output/'result.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
        print(json.dumps({k: v for k,v in report.items() if k != 'pngs'}, ensure_ascii=False, indent=2))
    return 1 if report['errors'] else 0

if __name__ == '__main__':
    sys.exit(main())
