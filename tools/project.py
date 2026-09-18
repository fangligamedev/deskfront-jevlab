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
    entries=[]
    script=ROOT/'source/blender/build_assets.py'
    for n in MODELS:
        src=ROOT/'source/blender/generated'/f'{n}.glb';dest=ROOT/'assets/models'/src.name
        shutil.copy2(src,dest)
        entries.append({'path':dest.relative_to(ROOT).as_posix(),'kind':'character' if 'infantry' in n or n=='worker' else 'model','origin':'original','license':'CC0-1.0','release_status':'allowed','provider':'local Blender Python','model':'original procedural authored mesh','prompt':'See source/blender/build_assets.py','source_files':[str(script.relative_to(ROOT)),f'source/blender/generated/{n}.blend'],'source_hashes':{str(script.relative_to(ROOT)):digest(script),f'source/blender/generated/{n}.blend':digest(ROOT/f'source/blender/generated/{n}.blend')},'sha256':digest(dest),'size_bytes':dest.stat().st_size,'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat()})
    (ROOT/'.forge/assets.json').write_text(json.dumps({'schema':'godot-forge.asset-provenance-set.v1','assets':entries},indent=2))
def main():
    p=argparse.ArgumentParser();p.add_argument('command',choices=['models','record-assets','import','test','web','macos','bundle']);a=p.parse_args()
    (ROOT/'output').mkdir(exist_ok=True)
    if a.command=='models':run([binary('blender'),'-b','--python',str(ROOT/'source/blender/build_assets.py')]);record_assets()
    if a.command=='record-assets':record_assets()
    if a.command=='import':run([binary('godot'),'--headless','--editor','--path',str(ROOT),'--quit'])
    if a.command=='test':
        run([binary('godot'),'--headless','--path',str(ROOT),'tests/semantic_probe.tscn'])
        run([binary('godot'),'--headless','--path',str(ROOT),'--script','tests/asset_probe.gd'])
        run([os.sys.executable,'-m','unittest','discover','-s','tests','-p','test_*.py','-v'])
    if a.command in ['web','macos']:
        out=ROOT/'build'/a.command;out.mkdir(parents=True,exist_ok=True)
        run([binary('godot'),'--headless','--path',str(ROOT),'--export-release','Web' if a.command=='web' else 'macOS',str(out/('index.html' if a.command=='web' else 'Deskfront.zip'))])
    if a.command=='bundle':
        out=ROOT/'dist';out.mkdir(exist_ok=True)
        excluded={'.git','.godot','node_modules','output','dist','build','__pycache__','.playwright-cli'}
        files=[f for f in ROOT.rglob('*') if f.is_file() and not any(x in excluded for x in f.relative_to(ROOT).parts) and not f.name.endswith(('.blend1','.pyc','.import'))]
        manifest={str(f.relative_to(ROOT)):digest(f) for f in files}
        with zipfile.ZipFile(out/'Deskfront-source-0.1.0.zip','w',zipfile.ZIP_DEFLATED) as z:
            for f in files:z.write(f,'deskfront-jevlab/'+str(f.relative_to(ROOT)))
        with zipfile.ZipFile(out/'Deskfront-playable-web-0.1.0.zip','w',zipfile.ZIP_DEFLATED) as z:
            for folder in ['build/web','dashboard','tools']:
                for f in (ROOT/folder).rglob('*'):
                    if f.is_file() and '__pycache__' not in f.parts:z.write(f,str(f.relative_to(ROOT)))
            for n in ['README.md','LICENSE','THIRD_PARTY.md','启动桌面前线.command']:z.write(ROOT/n,n)
            for f in (ROOT/'docs/licenses').glob('*'):z.write(f,str(f.relative_to(ROOT)))
        (out/'source-hashes.json').write_text(json.dumps(manifest,indent=2))
        mac=ROOT/'build/macos/Deskfront.zip'
        if mac.exists():
            packaged=out/'Deskfront-macos-0.1.0.zip'
            shutil.copy2(mac,packaged)
            with zipfile.ZipFile(packaged,'a',zipfile.ZIP_DEFLATED) as z:
                for f in (ROOT/'docs/licenses').glob('*'):z.write(f,str(f.relative_to(ROOT)))
                for n in ['LICENSE','THIRD_PARTY.md']:z.write(ROOT/n,n)
        (out/'SHA256SUMS.txt').write_text('\n'.join(digest(f)+'  '+f.name for f in out.glob('*.zip'))+'\n')
        print(out)
if __name__=='__main__':main()
