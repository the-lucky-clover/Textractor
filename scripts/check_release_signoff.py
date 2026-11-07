#!/usr/bin/env python3
"""Refuse release when required native/device evidence is missing or source changed."""
import json
import subprocess
from pathlib import Path

REQUIRED = ('native_build', 'unit_tests', 'ui_playtests', 'ocr_benchmark', 'continuity_photo',
            'continuity_multipage', 'camera_cancel', 'voiceover', 'multi_display',
            'scroll_stitching', 'signing', 'app_store_name')

def validate(record):
    missing = [item for item in REQUIRED if record.get('checks', {}).get(item) != 'passed']
    if record.get('status') != 'approved' or missing:
        raise ValueError('Release blocked; missing verification: ' + ', '.join(missing))
    if not record.get('tested_commit') or not record.get('evidence'):
        raise ValueError('Release blocked; tested commit and evidence references are required')

if __name__ == '__main__':
    record = json.loads(Path('qa/release-signoff.json').read_text())
    try:
        validate(record)
        commit = record['tested_commit']
        subprocess.run(['git', 'merge-base', '--is-ancestor', commit, 'HEAD'], check=True)
        subprocess.run(['git', 'diff', '--exit-code', commit, 'HEAD', '--', 'Sources', 'Tests',
                        'Package.swift', 'Package.resolved', 'project.yml', 'build.sh', 'scripts',
                        '.github/workflows'], check=True)
    except (ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
    print('Release evidence accepted for unchanged tested source.')
