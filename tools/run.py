#!/usr/bin/env python3
import subprocess,sys,os,pathlib,urllib.request,webbrowser,time,argparse,json
from project import stamp_build
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser();p.add_argument('--port',type=int,default=8768);p.add_argument('--no-open',action='store_true');a=p.parse_args()
    stamp_build()
    build=ROOT/'build/web/build-info.json'
    stale=not build.exists() or json.loads(build.read_text())!=json.loads((ROOT/'data/build-info.json').read_text())
    if stale or not (ROOT/'build/web/index.html').exists():subprocess.run([sys.executable,str(ROOT/'tools/project.py'),'web'],check=True)
    url=f'http://127.0.0.1:{a.port}'
    try:
        with urllib.request.urlopen(url+'/api/health',timeout=1) as r:
            if b'deskfront-control' not in r.read():raise RuntimeError('Port belongs to another service')
        if not a.no_open:webbrowser.open(url)
        print(url);return
    except OSError:pass
    process=subprocess.Popen([sys.executable,str(ROOT/'tools/server.py'),'--port',str(a.port)],cwd=ROOT)
    try:
        for _ in range(40):
            try:
                urllib.request.urlopen(url+'/api/health',timeout=.5).close();break
            except OSError:time.sleep(.1)
        if not a.no_open:webbrowser.open(url)
        print('保持此终端打开。Ctrl+C 停止服务。',flush=True);process.wait()
    except KeyboardInterrupt:process.terminate();process.wait(timeout=5)
if __name__=='__main__':main()
