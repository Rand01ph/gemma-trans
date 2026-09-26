#!/usr/bin/env python3
"""Export only custom native-menu attachments, never screenshots of the desktop."""
import argparse
import json
import pathlib
import re
import shutil
import subprocess
import tempfile

p=argparse.ArgumentParser()
p.add_argument('result',type=pathlib.Path)
p.add_argument('output',type=pathlib.Path)
a=p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory() as temp:
    subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(a.result),
                    '--output-path',temp],check=True,stdout=subprocess.DEVNULL)
    exported=set()
    for test in json.loads((pathlib.Path(temp)/'manifest.json').read_text()):
        for item in test['attachments']:
            name=item.get('suggestedHumanReadableName','')
            match=re.match(r'(menu-(?:light|dark))_.*\.(png|json)$',name)
            if match:
                target=a.output/(match[1]+'.'+match[2])
                if target.exists(): raise SystemExit(f'Refusing overwrite: {target}')
                shutil.copy2(pathlib.Path(temp)/item['exportedFileName'],target)
                exported.add(target.name)
    if len(exported)!=4: raise SystemExit('Expected light/dark menu screenshots and metadata')
