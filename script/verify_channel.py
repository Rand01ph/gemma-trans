#!/usr/bin/env python3
import json, pathlib, plistlib, subprocess, sys, time
app=pathlib.Path(sys.argv[1]).resolve(); channel=sys.argv[2]
d=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert d['CFBundleIdentifier']=='com.gemmatrans.GemmaTrans.'+channel
assert d['GTChannel']==channel
assert d['NSServices'][0]['NSMenuItem']['default']=='Translate with '+d['CFBundleDisplayName']
exe=str(app/'Contents/MacOS'/d['CFBundleExecutable'])
pid=None
for _ in range(50):
    for row in subprocess.check_output(['ps','-axo','pid=,comm='],text=True).splitlines():
        parts=row.strip().split(None,1)
        if len(parts)==2 and parts[1]==exe: pid=int(parts[0])
    if pid: break
    time.sleep(.2)
assert pid, 'Installed channel did not stay running'
report={'channel':channel,'pid':pid,'executable':exe,'bundleID':d['CFBundleIdentifier'],
        'version':d['CFBundleShortVersionString'],'build':d['CFBundleVersion'],
        'commit':d['GTCommit'],'branch':d['GTBranch'],'dirty':d['GTDirty'],
        'service':d['NSServices'][0]['NSMenuItem']['default'],
        'settingsSuite':'com.gemmatrans.app.'+channel}
out=pathlib.Path.home()/'Library/Application Support/GemmaTrans Local Builds'/channel
out.mkdir(parents=True,exist_ok=True)
(out/'last-launch.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False,indent=2))
