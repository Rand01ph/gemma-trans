#!/usr/bin/env python3
"""Inventory/retire loose same-identity builds inside this repo's worktrees only."""
import argparse, datetime, json, os, pathlib, plistlib, shutil, subprocess
parser=argparse.ArgumentParser();parser.add_argument('--apply',action='store_true');args=parser.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
roots=[pathlib.Path(s[9:]) for s in subprocess.check_output(['git','worktree','list','--porcelain'],cwd=root,text=True).splitlines() if s.startswith('worktree ')]
prune={'.git','.build','Vendor','node_modules','SourcePackages','Intermediates.noindex','Index.noindex','SDKStatCaches.noindex','ModuleCache.noindex','SDKExplicitPrecompiledModules'}
running=subprocess.check_output(['ps','-axo','comm='],text=True).splitlines()
records=[]
manifest=pathlib.Path.home()/'Library/Application Support/GemmaTrans Local Builds'/('retired-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S')+'.json')
def save():
    if args.apply:
        manifest.parent.mkdir(parents=True,exist_ok=True)
        manifest.write_text(json.dumps(records,ensure_ascii=False,indent=2)+'\n')
for tree in roots:
    for folder,dirs,files in os.walk(tree/'App'):
        dirs[:]=[d for d in dirs if d not in prune and not d.endswith(('.xcarchive','.pkg','.xcresult','.dSYM','.framework','.bundle','.xcassets'))]
        for name in dirs[:]:
            if not name.endswith('.app'): continue
            dirs.remove(name);app=pathlib.Path(folder)/name
            try: info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
            except (OSError,ValueError): continue
            if info.get('CFBundleIdentifier')!='com.gemmatrans.GemmaTrans': continue
            # Never touch installed applications or distribution archive containers.
            assert app.is_relative_to(tree/'App')
            record={'app':str(app),'version':info.get('CFBundleShortVersionString'),'status':'candidate'}
            if any(s.startswith(str(app)+'/Contents/MacOS/') for s in running):
                record['status']='running: untouched'
            elif args.apply:
                archive=app.with_name(app.name+'.retired-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S')+'.zip')
                assert not archive.exists()
                subprocess.run(['ditto','-c','-k','--keepParent',str(app),str(archive)],check=True)
                subprocess.run(['unzip','-tq',str(archive)],check=True,stdout=subprocess.DEVNULL)
                record.update(status='archive verified; retirement pending',archive=str(archive))
                records.append(record);save()
                unregister=subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister','-u',str(app)],capture_output=True,text=True)
                record['unregisterExitCode']=unregister.returncode
                shutil.rmtree(app)
                record['status']='archived'
                records.pop()
            records.append(record);save()
            print(json.dumps(record,ensure_ascii=False),flush=True)
