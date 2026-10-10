"""One-shot A0.6 retail export + *measured* pack content verification.

Usage:
    python tools/a0_6_export.py            # export HEAD to dist/a0_6/ and verify
    python tools/a0_6_export.py --verify-only <path\to.pck>

Design notes:
  * Never writes outside dist/a0_6/ -- the historical baselines
    (dist/retail, dist/retail2, dist/windows) are read-only references.
  * Idempotent: re-running replaces only the two files it owns.
  * Verification reads the PCK's own end-of-archive table (not the
    export_presets.cfg exclude_filter text) so "config says so" is never
    mistaken for evidence.
"""
from pathlib import Path
import argparse, datetime, hashlib, json, os, shutil, struct, subprocess, sys, time

ROOT = Path(__file__).resolve().parents[1]
GODOT = Path(r'D:\星丘基础\godot\Godot_v4.7.2-stable_win64_console.exe')
PRESET_NAME = 'Windows Retail'
OUT_DIR = ROOT / 'dist' / 'a0_6'
EXE_NAME = 'HoshigaokaEchoes.exe'
PCK_NAME = 'HoshigaokaEchoes.pck'
PROTECTED = ['dist/retail', 'dist/retail2', 'dist/windows']

# --- requirement: must be inside the pack / must NOT be inside the pack -------
MUST_INCLUDE = ['data/upgrades.json']
MUST_EXCLUDE_PREFIX = ['tests/', 'addons/gut/', 'tools/', 'docs/']


def sha256(path, limit=None):
    h = hashlib.sha256()
    with path.open('rb') as fh:
        while True:
            block = fh.read(1024 * 1024)
            if not block:
                break
            h.update(block)
    return h.hexdigest()


PACK_REL_FILEBASE = 0x2


def read_pck_entries(pck):
    """Parse the Godot 4 PCK index table. Returns (entries, header_info).

    Layout, established by measuring dist/retail/HoshigaokaEchoes.pck (all 355
    entries' md5 verified against their bytes -- see tools/a0_6_export.py
    --verify-only evidence in dist/a0_6/):

        off  0: magic 'GDPC'  u32
        off  4: pack format version u32
        off  8: ver major u32 | off 12: minor u32 | off 16: patch u32
        off 20: pack_flags u32          (bit 1 = PACK_REL_FILEBASE)
        off 24: file_base_offset u64
        off 32: directory_offset  u64   (stored in the "reserved" block; NOT zeros)
        off 40: reserved, zero-filled, up to file_base_offset
        off file_base_offset: resource data ('RSRC')

        directory @ directory_offset:
            file_count u32
            entry * file_count {
                path_len u32, path bytes, zero-pad to 4
                offset u64   <-- RELATIVE to file_base_offset when flags bit1 is set
                size   u64
                md5[16]
                flags  u32
            }

    Trusting the u32 count sitting at file_base_offset instead would read zero
    entries and silently "prove" a pack is empty -- that mistake is why this is
    code rather than a comment.
    """
    with pck.open('rb') as fh:
        head = fh.read(40)
        if len(head) < 40 or head[:4] != b'GDPC':
            raise SystemExit(f'Not a Godot PCK (magic={head[:4]!r})')
        pack_version, ver_major, ver_minor, ver_patch, pack_flags = struct.unpack_from('<5I', head, 4)
        file_base_offset, directory_offset = struct.unpack_from('<QQ', head, 24)
        fh.seek(directory_offset)
        raw_count = fh.read(4)
        if len(raw_count) < 4:
            raise SystemExit(f'Truncated PCK directory at {directory_offset}')
        file_count, = struct.unpack('<I', raw_count)
        if not (0 < file_count < 1_000_000):
            raise SystemExit(f'Implausible PCK entry count {file_count}')
        entries = []
        for _ in range(file_count):
            path_len, = struct.unpack('<I', fh.read(4))
            raw = fh.read(path_len)
            pad = (4 - (path_len % 4)) % 4
            if pad:
                fh.read(pad)
            offset, size = struct.unpack('<QQ', fh.read(16))
            md5 = fh.read(16)
            flags, = struct.unpack('<I', fh.read(4))
            if pack_flags & PACK_REL_FILEBASE:
                offset += file_base_offset
            entries.append({
                'path': raw.rstrip(b'\x00').decode('utf-8', 'replace'),
                'offset': offset, 'size': size, 'md5': md5.hex(), 'flags': flags,
            })
        directory_end = fh.tell()
    info = {'packVersion': pack_version,
            'godotVersion': f'{ver_major}.{ver_minor}.{ver_patch}',
            'packFlags': pack_flags,
            'relativeToFileBase': bool(pack_flags & PACK_REL_FILEBASE),
            'fileBaseOffset': file_base_offset,
            'directoryOffset': directory_offset,
            'directoryBytes': directory_end - directory_offset,
            'entryCount': file_count}
    return entries, info


def verify(pck, exe, report):
    entries, info = read_pck_entries(pck)
    report['pckHeader'] = info
    names = [e['path'] for e in entries]
    report['pckEntryCount'] = len(names)
    report['pckTotalBytes'] = pck.stat().st_size
    report['pckFileBaseOffset'] = info['fileBaseOffset']

    def norm(p):
        return p[6:] if p.startswith('res://') else p

    normed = [norm(n) for n in names]
    report['presentRequired'] = {p: (p in normed) for p in MUST_INCLUDE}
    report['forbiddenPresent'] = {}
    for prefix in MUST_EXCLUDE_PREFIX:
        hits = sorted(n for n in normed if n.startswith(prefix) or n == prefix.rstrip('/'))
        report['forbiddenPresent'][prefix] = hits

    # Full integrity sweep: EVERY packed entry's bytes must hash to the md5 the
    # pack's own table records. This is what makes the entry list trustworthy
    # evidence of "what is actually in the build" rather than a claim.
    blob = pck.read_bytes()
    mismatched, out_of_range = [], []
    for e in entries:
        if not (0 <= e['offset'] and 0 <= e['size'] and e['offset'] + e['size'] <= len(blob)):
            out_of_range.append(e['path'])
            continue
        if hashlib.md5(blob[e['offset']:e['offset'] + e['size']]).hexdigest() != e['md5']:
            mismatched.append(e['path'])
    report['integrity'] = {'entriesChecked': len(entries),
                           'bytesHashed': sum(e['size'] for e in entries),
                           'md5Mismatch': mismatched, 'outOfRange': out_of_range,
                           'allMatch': not mismatched and not out_of_range}

    # Explicit byte-level readback of the required file, cross-checked against
    # the on-disk source and against the pack's own md5 for that entry.
    src = ROOT / 'data' / 'upgrades.json'
    entry = next((e for e in entries if norm(e['path']) == 'data/upgrades.json'), None)
    if entry is not None and entry['offset'] + entry['size'] <= len(blob):
        packed = blob[entry['offset']:entry['offset'] + entry['size']]
        src_bytes = src.read_bytes() if src.is_file() else None
        report['upgradesJson'] = {
            'sourcePath': str(src),
            'sourceSize': len(src_bytes) if src_bytes is not None else None,
            'sourceSha256': hashlib.sha256(src_bytes).hexdigest() if src_bytes is not None else None,
            'packedSize': entry['size'],
            'packedMd5Table': entry['md5'],
            'packedMd5Actual': hashlib.md5(packed).hexdigest(),
            'packedSha256': hashlib.sha256(packed).hexdigest(),
            'byteIdenticalToSource': src_bytes == packed,
            'headText': packed[:60].decode('utf-8', 'replace'),
        }
    else:
        report['upgradesJson'] = None

    # Count the packed upgrade definitions from the file's own JSON, so the
    # check is "the right DATA got in", not merely "a file named so exists".
    if report.get('upgradesJson'):
        try:
            loaded = json.loads(blob[entry['offset']:entry['offset'] + entry['size']])
            items = loaded.get('upgrades') or loaded.get('items') or []
            report['upgradesJson']['parsedDefinitionCount'] = len(items)
            report['upgradesJson']['parsedKeys'] = sorted(loaded.keys())[:10]
        except (ValueError, TypeError) as exc:
            report['upgradesJson']['parseError'] = f'{type(exc).__name__}: {exc}'
    return report


REAL_APPDATA_GODOT = Path(os.environ.get('APPDATA', '')) / 'Godot'
# The Windows x86_64 templates are the only ones this project's presets need.
# Seeding just these keeps the isolated APPDATA small and the export reproducible
# even on a machine whose Godot profile has not been opened in the editor UI.
TEMPLATE_FILES = ['version.txt',
                  'windows_release_x86_64.exe', 'windows_release_x86_64_console.exe',
                  'windows_debug_x86_64.exe', 'windows_debug_x86_64_console.exe']


def seed_export_templates(appdata_root):
    """Copy the Windows x86_64 export templates into an isolated APPDATA.

    Godot looks up templates under $APPDATA/Godot/export_templates/<version>.
    Redirecting APPDATA to keep the real user profile clean therefore makes the
    templates invisible, so they are copied in explicitly. Idempotent: files
    already present at the right size are left alone.

    Returns a small report so the caller can prove the export was not silently
    running on a stale template set.
    """
    version_file = REAL_APPDATA_GODOT / 'export_templates' / '4.7.2.stable' / 'version.txt'
    version = version_file.read_text(encoding='utf-8').strip() if version_file.is_file() else '4.7.2.stable'
    src = REAL_APPDATA_GODOT / 'export_templates' / version
    dst = appdata_root / 'Godot' / 'export_templates' / version
    report = {'version': version, 'source': str(src), 'target': str(dst), 'files': {}}
    if not src.is_dir():
        report['error'] = f'no export templates at {src}'
        return report
    dst.mkdir(parents=True, exist_ok=True)
    for name in TEMPLATE_FILES:
        s = src / name
        d = dst / name
        if not s.is_file():
            report['files'][name] = 'MISSING-IN-SOURCE'
            continue
        if d.is_file() and d.stat().st_size == s.stat().st_size:
            report['files'][name] = 'cached'
            continue
        shutil.copy2(s, d)
        report['files'][name] = f'copied({s.stat().st_size}B)'
    return report


def export(report):
    if not GODOT.is_file():
        raise SystemExit(f'Godot not found: {GODOT}')
    missing = [p for p in PROTECTED if not (ROOT / p).is_dir()]
    if missing:
        raise SystemExit(f'Refuse: expected baseline dirs missing {missing}')

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    exe, pck = OUT_DIR / EXE_NAME, OUT_DIR / PCK_NAME
    before = {p: (ROOT / p / EXE_NAME).stat().st_mtime for p in PROTECTED
              if (ROOT / p / EXE_NAME).is_file()}
    for stale in (exe, pck):
        if stale.exists():
            stale.unlink()

    # Godot writes editor/import state under APPDATA; keep the real profile clean.
    appdata = OUT_DIR / '_appdata'
    appdata.mkdir(parents=True, exist_ok=True)
    report['templates'] = seed_export_templates(appdata)
    env = dict(os.environ, APPDATA=str(appdata))
    import_ok = run_godot(['--headless', '--path', str(ROOT), '--import'], env,
                          OUT_DIR / 'import.log')
    report['import'] = import_ok
    cmd = [str(GODOT), '--headless', '--path', str(ROOT),
           '--export-release', PRESET_NAME, str(exe)]
    stamp = datetime.datetime.now().isoformat()
    with (OUT_DIR / 'export.log').open('w', encoding='utf-8') as log:
        proc = subprocess.run(cmd, cwd=ROOT, env=env, stdout=log,
                              stderr=subprocess.STDOUT, timeout=900)
    text = (OUT_DIR / 'export.log').read_text(encoding='utf-8', errors='replace')
    report['export'] = {'cmd': cmd, 'exitCode': proc.returncode,
                        'started': stamp,
                        'logTail': text[-2000:],
                        'errors': [ln for ln in text.splitlines()
                                   if 'ERROR' in ln or 'error:' in ln][:20]}
    if not exe.is_file() or not pck.is_file():
        raise SystemExit(f'Export produced no artifacts (exit {proc.returncode}); see dist/a0_6/export.log')
    after = {p: (ROOT / p / EXE_NAME).stat().st_mtime for p in PROTECTED
             if (ROOT / p / EXE_NAME).is_file()}
    report['baselinesUntouched'] = {'before': before, 'after': after, 'equal': before == after}
    if before != after:
        raise SystemExit('STOP: an existing baseline exe changed during export')
    report['artifacts'] = {
        'exe': {'path': str(exe), 'size': exe.stat().st_size, 'sha256': sha256(exe)},
        'pck': {'path': str(pck), 'size': pck.stat().st_size, 'sha256': sha256(pck)},
    }
    return exe, pck


def run_godot(args, env, log):
    with log.open('w', encoding='utf-8') as stream:
        proc = subprocess.run([str(GODOT), *args], cwd=ROOT, env=env,
                              stdout=stream, stderr=subprocess.STDOUT, timeout=900)
    text = log.read_text(encoding='utf-8', errors='replace')
    return {'args': args, 'exitCode': proc.returncode,
            'scriptErrors': [ln for ln in text.splitlines()
                             if 'SCRIPT ERROR' in ln or 'Parse Error' in ln][:10]}


def launch_smoke(exe, report, seconds=10.0):
    """Prove the exported EXE is double-click runnable: actually start it.

    Runs with an ISOLATED APPDATA (the game writes save/settings under
    %APPDATA%/HoshigaokaEchoes) so the real player profile is never touched, and
    asserts the process stays alive and logs no script/parse error. This is a
    liveness probe on the real shipped binary, not on the editor.

    TWO scenes are exercised on purpose. The title screen alone is not enough:
    export tokenises scripts without necessarily failing on a script that does
    not parse, so a broken battle_scene.gd ships happily and only blows up when
    that scene is actually loaded. Running the battle scene too is what turns
    "the exe starts" into "the shipped scripts actually run".
    """
    smoke_dir = OUT_DIR / '_smoke'
    smoke_dir.mkdir(parents=True, exist_ok=True)
    runs = {}
    for name, extra in (('title', []), ('battle', ['--', '--scene=battle', '--autoplay'])):
        runs[name] = _run_once(exe, smoke_dir, name, extra, seconds)
    report['launchSmoke'] = runs
    # The scene most likely to expose a broken build is the battle scene; the
    # build is only launchable if both runs stay up and neither logs a script error.
    report['launchSmokeVerdict'] = {
        'launchable': all(r['launchable'] for r in runs.values()),
        'stayedAlive': all(r['stayedAlive'] for r in runs.values()),
        'scriptErrors': {k: v['scriptErrors'] for k, v in runs.items() if v['scriptErrors']},
    }
    return runs


def _run_once(exe, smoke_dir, name, extra, seconds):
    env = dict(os.environ, APPDATA=str(smoke_dir / name / 'appdata'))
    (smoke_dir / name / 'appdata').mkdir(parents=True, exist_ok=True)
    cmd = [str(exe), *extra]
    out = {'cmd': cmd, 'seconds': seconds, 'appdata': env['APPDATA']}
    with (smoke_dir / f'{name}.log').open('w', encoding='utf-8') as log:
        proc = subprocess.Popen(cmd, cwd=exe.parent, env=env,
                                stdout=log, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + seconds
        exited_early = None
        while time.monotonic() < deadline:
            code = proc.poll()
            if code is not None:
                exited_early = code
                break
            time.sleep(.25)
        if exited_early is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill(); proc.wait()
            out['survivedSeconds'] = round(seconds, 1)
        else:
            out['survivedSeconds'] = 0
        out['exitCodeWhileRunning'] = exited_early
    text = (smoke_dir / f'{name}.log').read_text(encoding='utf-8', errors='replace')
    out['logBytes'] = len(text)
    out['logTail'] = text[-800:]
    out['scriptErrors'] = [ln.strip() for ln in text.splitlines()
                           if 'SCRIPT ERROR' in ln or 'Parse Error' in ln][:10]
    out['stayedAlive'] = exited_early is None
    out['launchable'] = out['stayedAlive'] and not out['scriptErrors']
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--verify-only', type=Path, default=None,
                    help='Skip export; parse and report on an existing .pck')
    ap.add_argument('--json', type=Path, default=None, help='Where to write the report')
    ap.add_argument('--no-launch-smoke', action='store_true',
                    help='Skip starting the exported exe')
    ap.add_argument('--smoke-seconds', type=float, default=10.0)
    a = ap.parse_args()
    started = time.monotonic()
    report = {'tool': 'tools/a0_6_export.py',
              'preset': PRESET_NAME, 'root': str(ROOT),
              'started': datetime.datetime.now().isoformat()}

    if a.verify_only:
        pck = a.verify_only.resolve()
        if not pck.is_file():
            raise SystemExit(f'No such pck: {pck}')
        verify(pck, None, report)
    else:
        exe, pck = export(report)
        verify(pck, exe, report)
        if not a.no_launch_smoke:
            launch_smoke(exe, report, a.smoke_seconds)

    # ---- verdict -------------------------------------------------------------
    problems = []
    for p, ok in report.get('presentRequired', {}).items():
        if not ok:
            problems.append(f'pack MISSING required {p}')
    for prefix, hits in report.get('forbiddenPresent', {}).items():
        if hits:
            problems.append(f'pack CONTAINS excluded {prefix} -> {hits[:5]}')
    integ = report.get('integrity') or {}
    if integ and not integ.get('allMatch'):
        problems.append(f"pack byte integrity failed: mismatch={integ.get('md5Mismatch')[:5]} oob={integ.get('outOfRange')[:5]}")
    if report.get('upgradesJson') and not report['upgradesJson'].get('byteIdenticalToSource'):
        problems.append('packed data/upgrades.json differs byte-wise from the on-disk source')
    if report.get('upgradesJson') and report['upgradesJson'].get('parseError'):
        problems.append(f"packed data/upgrades.json unparseable: {report['upgradesJson']['parseError']}")
    if report.get('baselinesUntouched') and not report['baselinesUntouched']['equal']:
        problems.append('existing baseline artifacts changed')
    if report.get('export', {}).get('exitCode'):
        problems.append(f"export exit code {report['export']['exitCode']}")
    smoke = report.get('launchSmokeVerdict')
    if smoke and not smoke.get('launchable'):
        problems.append(f"exported exe not launchable: stayedAlive={smoke.get('stayedAlive')} "
                        f"scriptErrors={smoke.get('scriptErrors')}")
    report['problems'] = problems
    report['verdict'] = 'PASS' if not problems else 'FAIL'
    report['elapsedSec'] = round(time.monotonic() - started, 1)
    report['finished'] = datetime.datetime.now().isoformat()

    target = a.json or (OUT_DIR / 'export_report.json')
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')

    print('=' * 72)
    if 'artifacts' in report:
        print(f"EXE : {report['artifacts']['exe']['path']}")
        print(f"      {report['artifacts']['exe']['size']:,} bytes  sha256={report['artifacts']['exe']['sha256'][:16]}...")
        print(f"PCK : {report['artifacts']['pck']['path']}")
        print(f"      {report['artifacts']['pck']['size']:,} bytes ({report['artifacts']['pck']['size']/1048576:.2f} MB)  sha256={report['artifacts']['pck']['sha256'][:16]}...")
    elif report.get('pckEntryCount') is not None:
        print(f"PCK : {a.verify_only.resolve()}  {report['pckTotalBytes']:,} bytes")
    print(f"pack header  : {report.get('pckHeader')}")
    print(f"pack entries : {report.get('pckEntryCount')}")
    print(f"required     : {report.get('presentRequired')}")
    print(f"forbidden    : { {k: len(v) for k, v in report.get('forbiddenPresent', {}).items()} }")
    if integ:
        print(f"integrity    : {integ['entriesChecked']} entries, {integ['bytesHashed']:,} bytes hashed, allMatch={integ['allMatch']}")
    uj = report.get('upgradesJson')
    if uj:
        print(f"upgrades.json: packed={uj['packedSize']}B source={uj['sourceSize']}B byteIdentical={uj['byteIdenticalToSource']} defs={uj.get('parsedDefinitionCount')}")
        print(f"               head={uj['headText']!r}")
    for p in problems:
        print('PROBLEM:', p)
    smoke = report.get('launchSmoke') or {}
    for name, run in smoke.items():
        print(f"launch-smoke {name:6s}: stayedAlive={run['stayedAlive']} "
              f"scriptErrors={len(run['scriptErrors'])} log={run['logBytes']}B")
    print(f"VERDICT: {report['verdict']}   ({report['elapsedSec']}s)  report={target}")
    print('=' * 72)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
