#!/usr/bin/env python3
"""Generate an isolated local project; never rewrite release Info.plist/project.yml."""
import json, pathlib, subprocess, sys
root = pathlib.Path(__file__).resolve().parents[1]
channel = sys.argv[1]
assert channel in ('qa', 'dev', 'uitest')
label = {'qa':'QA', 'dev':'Dev', 'uitest':'UITest'}[channel]
name = 'GemmaTrans ' + label
out = root / 'App/build/channels' / channel
out.mkdir(parents=True, exist_ok=True)
spec = json.loads(subprocess.check_output(['ruby','-ryaml','-rjson','-e','puts JSON.generate(YAML.load_file(ARGV[0]))',str(root/'App/project.yml')]))
if 'include' in spec:
    spec['include'] = [str(root/'App'/p) for p in spec['include']]
spec['packages']['GemmaTransCore']['path'] = str(root)
spec['targets'] = {k:v for k,v in spec['targets'].items() if k in ('GemmaTrans','GemmaTransUITests')}
target = spec['targets']['GemmaTrans']
props = target['info']['properties']
props.update(CFBundleDisplayName=name, CFBundleName=name, GTChannel=channel,
             GTCommit=subprocess.check_output(['git','rev-parse','--short=12','HEAD'],cwd=root,text=True).strip(),
             GTBranch=subprocess.check_output(['git','branch','--show-current'],cwd=root,text=True).strip(),
             GTDirty=bool(subprocess.check_output(['git','status','--porcelain','--untracked-files=no'],cwd=root,text=True).strip()))
service = props['NSServices'][0]
service['NSMenuItem'] = {'default':'Translate with '+name}
service['NSPortName'] = name
service.pop('NSKeyEquivalent',None)
if channel == 'qa': service['NSKeyEquivalent'] = {'default':'^~@t'}
target['info']['path'] = str(out/'Info.plist')
settings = target['settings']['base']
settings.update(PRODUCT_NAME=name, PRODUCT_BUNDLE_IDENTIFIER='com.gemmatrans.GemmaTrans.'+channel,
    GEMMATRANS_SOURCE_ROOT=str(root), GEMMATRANS_DEPENDENCY_CHECKOUTS=str(root/'.build/checkouts'))
assets = out/'Channel.xcassets'
assets.mkdir(exist_ok=True)
icon = 'ChannelIcon'
subprocess.run(['swift',str(root/'script/channel_icon.swift'),str(root/'App/GemmaTrans/Assets.xcassets/AppIcon.appiconset'),str(assets/(icon+'.appiconset')),label.upper()],check=True)
settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = icon
props['CFBundleIconName'] = icon
target['sources'].append({'path':str(assets)})
if 'GemmaTransUITests' in spec['targets']:
    test = spec['targets']['GemmaTransUITests']['settings']['base']
    test.update(PRODUCT_BUNDLE_IDENTIFIER='com.gemmatrans.GemmaTrans.'+channel+'.tests', DEVELOPMENT_TEAM='G2XC9VU88M')
spec['schemes'] = {'GemmaTrans': {'build':{'targets':{'GemmaTrans':'all','GemmaTransUITests':['test']}},
    'test':{'targets':['GemmaTransUITests'], 'environmentVariables':{'GT_SERVICE_NAME':'Translate with '+name}}}}
path = out/'project.json'
path.write_text(json.dumps(spec,ensure_ascii=False,indent=2)+'\n')
subprocess.run(['xcodegen','--spec',str(path),'--project-root',str(root/'App'),'--project',str(out)],check=True)
print(out/'GemmaTrans.xcodeproj')
