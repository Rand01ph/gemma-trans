#!/usr/bin/env python3
import argparse
import json
import os
import pathlib
import subprocess
import uuid
import time
import shutil

ROOT = pathlib.Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--app', type=pathlib.Path, default=ROOT/'App/build/qa/Build/Products/Debug/GemmaTrans UITest.app')
p.add_argument('--output', type=pathlib.Path, required=True)
p.add_argument('--scene')
p.add_argument('--menu-captures', type=pathlib.Path)
p.add_argument('--appearance', choices=['light','dark'])
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
contract = json.loads((ROOT/'docs/ui/ui-contract.json').read_text())
for scene in [a.scene] if a.scene else contract['scenes']:
    if scene == "menu":
        if not a.menu_captures: raise SystemExit("Native menu captures required: run UI tests and export_ui_menu.py first")
        for name in ["menu-light.png", "menu-light.json", "menu-dark.png", "menu-dark.json"]:
            target = a.output / name
            if target.exists(): raise SystemExit(f"Refusing overwrite: {target}")
            shutil.copy2(a.menu_captures/name, target)
        continue
    for appearance in [a.appearance] if a.appearance else contract['appearances']:
        target = (a.output/f'{scene}-{appearance}.png').resolve()
        if target.exists():
            raise SystemExit(f'Refusing to overwrite capture: {target}')
        cmd = ['open','-n','-W']
        for key,value in {
            'GEMMATRANS_SCREENSHOT_SCENE':scene,
            'GEMMATRANS_NATIVE_CAPTURE':'1',
            'GEMMATRANS_SCREENSHOT_PATH':str(target),
            'GEMMATRANS_SCREENSHOT_APPEARANCE':appearance,
            'GEMMATRANS_TEST_SUITE':'com.gemmatrans.ui-test.'+str(uuid.uuid4())
        }.items(): cmd.extend(['--env',key+'='+value])
        cmd.append(str(a.app.resolve()))
        try:
            process = subprocess.Popen(cmd, stdout=subprocess.DEVNULL)
            deadline = time.monotonic() + 25
            while not target.with_suffix('.json').exists():
                if time.monotonic() > deadline:
                    raise subprocess.TimeoutExpired(cmd, 25)
                time.sleep(0.1)
            metadata = json.loads(target.with_suffix('.json').read_text())
            subprocess.run(['screencapture','-x','-o','-l',str(metadata['windowNumber']),str(target)], check=True)
            pathlib.Path(str(target)+'.captured').touch()
            process.wait(timeout=5)
            pathlib.Path(str(target)+'.captured').unlink()
        except subprocess.TimeoutExpired:
            subprocess.run(['pkill','-f','^'+str(a.app.resolve())+'/Contents/MacOS/'], check=False)
            raise SystemExit(f'Capture timed out: {scene}/{appearance}')
        if not target.exists() or not target.with_suffix('.json').exists():
            raise SystemExit(f'Capture missing: {scene}/{appearance}')
        print(scene, appearance, flush=True)
