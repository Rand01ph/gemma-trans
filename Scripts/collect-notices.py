#!/usr/bin/env python3
"""Copy license texts from the actual resolved sources into each distributed app."""
import argparse
import shutil
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--checkouts', required=True, type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
args.output.mkdir(parents=True, exist_ok=True)
for source, name in [(root / 'LICENSE', 'GemmaTrans-MIT.txt'),
                     (root / 'THIRD_PARTY_NOTICES.md', 'THIRD_PARTY_NOTICES.md')]:
    shutil.copyfile(source, args.output / name)
for source in (root / 'Runtime/LlamaRuntime/LICENSES').iterdir():
    if source.is_file(): shutil.copyfile(source, args.output / source.name)
if not args.checkouts.is_dir():
    raise SystemExit('Resolved dependency checkouts are missing; set GEMMATRANS_DEPENDENCY_CHECKOUTS.')
for dependency in args.checkouts.iterdir():
    if not dependency.is_dir(): continue
    licenses = [source for source in dependency.iterdir()
                if source.is_file() and source.name.upper().startswith(('LICENSE', 'LICENCE', 'COPYING', 'NOTICE'))]
    if not licenses: raise SystemExit('Missing license text for dependency: ' + dependency.name)
    for source in licenses:
        shutil.copyfile(source, args.output / (dependency.name + '-' + source.name))
