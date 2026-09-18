#!/usr/bin/env python3
"""Portable, dependency-light build entry point. MIT."""
import argparse,subprocess,shutil,os,pathlib,json,hashlib,datetime,zipfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
MODELS=['office','infantry-green','infantry-blue','infantry-red','worker','tank','sandbag']
def binary(name):
    configured=os.environ.get(name.upper()+'_BIN')
    found=configured or shutil.which(name)
    mac=f'/Applications/{name.title()}.app/Contents/MacOS/{name.title() if name=="godot" else name}'
    if found:return found
    if pathlib.Path(mac).exists():return mac
    raise SystemExit(f'{name} not found; install it or set {name.upper()}_BIN')
def run(args):
    print(' '.join(map(str,args)),flush=True)
    result=subprocess.run(args,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    print(result.stdout)
    if result.returncode or 'SCRIPT ERROR:' in result.stdout:raise SystemExit(result.returncode or 1)
    return result.stdout
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def record_assets():
    # Refresh provenance only. Never copy legacy generated models over integrated assets.
    p=ROOT/'.forge/assets.json';data=json.loads(p.read_text())
    catalog=json.loads((ROOT/'docs/asset-integration/asset-provenance.json').read_text())
    sources={
        'antitank-gun':['antitank-gun.blend','antitank-gun.glb','tools/build_antitank_gun.py'],
        'toy-soldier':['toy-soldier-retarget.blend','soldier-original.fbx','ual-author-preview.glb','tools/build_soldier.py'],
        'tank':['tank-original.blend','tank-original.glb'],
        'rifle':['guns-original.blend'],'pistol':['guns-original.blend'],
        'grenade':['grenades-original.blend'],'rocket':['rocket-launcher.blend','tools/build_extras.py'],
        'office-sandbox':['sandbox-generated/office-sandbox-editable.blend','tools/build_sandbox_office.py'],
        'office-worker':['office-worker/casual-original.glb','office-worker/office-worker.blend','tools/build_office_worker.py'],
        'DeskfrontUI':['fonts/NotoSansCJKsc-Regular.otf','fonts/OFL.txt','tools/build_ui_font.py']}
    by_path={r['path']:r for r in catalog}
    for item in data['assets']:
        file=ROOT/item['path'];item['sha256']=digest(file);item['size_bytes']=file.stat().st_size
        if item['path'] in by_path:
            row=by_path[item['path']];row['sha256']=digest(file);row['bytes']=file.stat().st_size
            item['source_url']=row.get('source_url');item['additional_sources']=row.get('additional_sources',[])
            item['author']=row['author'];item['license']=row['license']
            parents=sources.get(file.stem,[])
            if item['license']=='CC-BY-SA-3.0':parents=['tools/build_audio.py']+[str(f.relative_to(ROOT/'source/latest')) for f in (ROOT/'source/latest/q009').rglob('*.ogg')]
            if parents:item['source_files']=['source/latest/'+x for x in parents]
            elif 'vfx' in item['path']:item['source_files']=['source/latest/fx-license.txt']
        item['source_hashes']={n:digest(ROOT/n) for n in item.get('source_files',[]) if (ROOT/n).is_file()}
        if item['path'] in by_path:
            by_path[item['path']]['source_files']=item.get('source_files',[])
            by_path[item['path']]['source_hashes']=item['source_hashes']
    p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    (ROOT/'docs/asset-integration/asset-provenance.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
def main():
    p=argparse.ArgumentParser();p.add_argument('command',choices=['models','record-assets','import','test','web','macos','bundle']);a=p.parse_args()
    (ROOT/'output').mkdir(exist_ok=True)
    if a.command=='models':run([binary('blender'),'-b','--python',str(ROOT/'source/blender/build_assets.py')]);print('Legacy sources rebuilt in source/blender/generated; current runtime assets preserved.')
    if a.command=='record-assets':record_assets()
    if a.command=='import':run([binary('godot'),'--headless','--editor','--path',str(ROOT),'--quit'])
    if a.command=='test':
        run([binary('godot'),'--headless','--path',str(ROOT),'tests/semantic_probe.tscn'])
        run([binary('godot'),'--headless','--path',str(ROOT),'tests/integration_probe.tscn'])
        run([binary('godot'),'--headless','--path',str(ROOT),'--script','tests/asset_probe.gd'])
        run([binary('godot'),'--headless','--path',str(ROOT),'--script','tests/combat_contract.gd'])
        run([binary('godot'),'--headless','--path',str(ROOT),'--script','tests/lm_contract.gd'])
        run([binary('godot'),'--headless','--path',str(ROOT),'--script','tests/equipment_contract.gd'])
        run([binary('godot'),'--headless','--path',str(ROOT),'--script','tests/equipment_squad.gd'])
        run([os.sys.executable,'-m','unittest','discover','-s','tests','-p','test_*.py','-v'])
    if a.command in ['web','macos']:
        out=ROOT/'build'/a.command;out.mkdir(parents=True,exist_ok=True)
        run([binary('godot'),'--headless','--path',str(ROOT),'--export-release','Web' if a.command=='web' else 'macOS',str(out/('index.html' if a.command=='web' else 'Deskfront.zip'))])
    if a.command=='bundle':
        out=ROOT/'dist';out.mkdir(exist_ok=True)
        excluded={'.git','.godot','node_modules','output','dist','build','__pycache__','.playwright-cli','.secrets'}
        # In a checkout, bundle only the Git index (including newly staged files),
        # so concurrent untracked work does not silently enter an open-source release.
        if (ROOT/'.git').exists():
            listed=subprocess.run(['git','ls-files','-z'],cwd=ROOT,check=True,stdout=subprocess.PIPE).stdout.decode().split('\0')
            candidates=[ROOT/n for n in listed if n]
        else:candidates=ROOT.rglob('*')
        files=[f for f in candidates if f.is_file() and not any(x in excluded for x in f.relative_to(ROOT).parts) and not f.name.endswith(('.blend1','.pyc')) and f.name!='package-audit.json' and (not f.name.startswith('.env') or f.name=='.env.example') and not f.name.endswith('.local.env')]
        manifest={str(f.relative_to(ROOT)):digest(f) for f in files}
        with zipfile.ZipFile(out/'Deskfront-source-0.6.0.zip','w',zipfile.ZIP_DEFLATED) as z:
            for f in files:z.write(f,'deskfront-jevlab/'+str(f.relative_to(ROOT)))
        with zipfile.ZipFile(out/'Deskfront-playable-web-0.6.0.zip','w',zipfile.ZIP_DEFLATED) as z:
            for folder in ['build/web','dashboard','tools','data']:
                for f in (ROOT/folder).rglob('*'):
                    if f.is_file() and '__pycache__' not in f.parts:z.write(f,str(f.relative_to(ROOT)))
            for n in ['README.md','LICENSE','THIRD_PARTY.md','.env.example','启动桌面前线.command']:z.write(ROOT/n,n)
            for f in (ROOT/'docs/licenses').glob('*'):z.write(f,str(f.relative_to(ROOT)))
        (out/'source-hashes.json').write_text(json.dumps(manifest,indent=2))
        mac=ROOT/'build/macos/Deskfront.zip'
        if mac.exists():
            packaged=out/'Deskfront-macos-0.6.0.zip'
            shutil.copy2(mac,packaged)
            with zipfile.ZipFile(packaged,'a',zipfile.ZIP_DEFLATED) as z:
                for f in (ROOT/'docs/licenses').glob('*'):z.write(f,str(f.relative_to(ROOT)))
                for n in ['LICENSE','THIRD_PARTY.md']:z.write(ROOT/n,n)
        (out/'SHA256SUMS.txt').write_text('\n'.join(digest(f)+'  '+f.name for f in out.glob('*.zip'))+'\n')
        print(out)
if __name__=='__main__':main()
