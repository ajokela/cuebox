#!/usr/bin/env python3
"""Check core boundaries and play the example across a real process restart."""
from pathlib import Path
import argparse
import json
import os
import re
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
DEPENDENCY = re.compile(r'''(?:\b(?:preload|load)\s*\(\s*|\bextends\s+)["'](res://[^"'%]+)["']''')


def check_boundaries():
    for path in (ROOT / 'engine').rglob('*.gd'):
        if path.is_symlink():
            raise RuntimeError('Engine source must not be a symlink: ' + str(path.relative_to(ROOT)))
        for dependency in DEPENDENCY.findall(path.read_text()):
            if not dependency.startswith('res://engine/'):
                raise RuntimeError(f'{path.name} directly loads game content: {dependency}')


def run(command, label):
    result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=180)
    if result.returncode or 'SCRIPT ERROR:' in result.stdout or '\nERROR:' in result.stdout:
        print(result.stdout)
        raise RuntimeError(label + ' failed')
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT', 'godot'))
    args = parser.parse_args()
    check_boundaries()
    print('Engine dependency boundaries pass.', flush=True)
    run([args.godot, '--headless', '--path', '.', '--import'], 'Import')
    proof = 'user://engine-proof/' + uuid.uuid4().hex + '/'
    command = [args.godot, '--headless', '--path', '.', '--script',
               'res://tests/smoke.gd', '--', '--proof-root=' + proof]
    for reload in (False, True):
        output = run(command + (['--reload'] if reload else []), 'Cold Continue' if reload else 'Play')
        reports = [json.loads(line) for line in output.splitlines() if line.startswith('{')]
        if len(reports) != 1 or reports[0].get('pass') is not True or reports[0].get('reload') != reload:
            raise RuntimeError('Missing or failed smoke report: ' + output)
        print(json.dumps(reports[0]), flush=True)
    print('Cuebox checks pass.', flush=True)


if __name__ == '__main__':
    main()
