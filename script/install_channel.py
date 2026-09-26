#!/usr/bin/env python3
"""Replace only a verified local-channel app; keep one compressed rollback copy."""
import os, pathlib, plistlib, shutil, signal, subprocess, sys, tempfile, time
source, target = map(pathlib.Path,sys.argv[1:3]); channel=sys.argv[3]
expected='com.gemmatrans.GemmaTrans.'+channel
assert channel in ('qa','dev')
def info(path): return plistlib.loads((path/'Contents/Info.plist').read_bytes())
assert info(source)['CFBundleIdentifier']==expected
if target.exists(): assert info(target)['CFBundleIdentifier']==expected, 'Refusing to replace a different application'
subprocess.run(['codesign','--verify','--deep','--strict',str(source)],check=True)
signature=subprocess.run(['codesign','-dv',str(source)],capture_output=True,text=True,check=True).stderr
assert 'TeamIdentifier=G2XC9VU88M' in signature, 'Stable development signature required'
target.parent.mkdir(parents=True,exist_ok=True)
stage=pathlib.Path(tempfile.mkdtemp(prefix='.gemmatrans-stage-',dir=target.parent))/target.name
try:
    subprocess.run(['ditto',str(source),str(stage)],check=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(stage)],check=True)
    # Stop instances of this channel only, including older worktree builds.
    victims=[]
    for line in subprocess.check_output(['ps','-axo','pid=,comm='],text=True).splitlines():
        parts=line.strip().split(None,1)
        if len(parts)!=2 or '.app/Contents/MacOS/' not in parts[1]: continue
        app=pathlib.Path(parts[1].split('.app/Contents/MacOS/')[0]+'.app')
        try:
            if info(app).get('CFBundleIdentifier')==expected:
                pid=int(parts[0]);os.kill(pid,signal.SIGTERM);victims.append(pid)
        except (OSError,ValueError): pass
    deadline=time.monotonic()+10
    for pid in victims:
        while time.monotonic()<deadline:
            try: os.kill(pid,0)
            except ProcessLookupError: break
            time.sleep(.1)
        else: raise RuntimeError('Existing channel did not exit; refusing replacement')
    if target.exists():
        backup=pathlib.Path.home()/'Library/Application Support/GemmaTrans Local Builds'/channel
        backup.mkdir(parents=True,exist_ok=True)
        subprocess.run(['ditto','-c','-k','--keepParent',str(target),str(backup/'previous.zip')],check=True)
        shutil.rmtree(target)
    os.replace(stage,target)
finally:
    shutil.rmtree(stage.parent,ignore_errors=True)
