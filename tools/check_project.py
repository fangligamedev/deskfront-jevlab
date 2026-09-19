#!/usr/bin/env python3
"""Offline release contracts. Does not load .env or call any model provider."""
import ast
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]


def tracked_files():
    if (ROOT / '.git').exists():
        return subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')[:-1]
    # A source ZIP has no Git metadata. Do not accidentally use an enclosing repo.
    excluded = {'build', 'output', 'dist', '.godot', '.git', 'node_modules', '__pycache__', '.secrets'}
    return sorted(str(p.relative_to(ROOT)) for p in ROOT.rglob('*') if p.is_file() and not any(x in excluded for x in p.relative_to(ROOT).parts) and p.name != '.env' and not p.name.endswith('.pyc'))


def assigned_set(path, name):
    for node in ast.parse(path.read_text()).body:
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == name for t in node.targets):
            return ast.literal_eval(node.value)
    raise ValueError('Missing constant: ' + name)


def check():
    files = tracked_files()
    errors = []
    def require(ok, message):
        if not ok:
            errors.append(message)
    for name in files:
        path = Path(name)
        require(not (path.name.startswith('.env') and path.name != '.env.example'), 'Tracked dotenv: ' + name)
        require(path.parts[0] not in {'build', 'output', 'dist', '.godot', 'node_modules', '.secrets'}, 'Tracked generated/private directory: ' + name)
    package = json.loads((ROOT / 'package.json').read_text())
    catalog = json.loads((ROOT / 'data/action-catalog.json').read_text())
    tactics = assigned_set(ROOT / 'tools/server.py', 'TACTICS')
    console_only = {name for name, spec in catalog['commands'].items() if spec.get('authority', '').startswith('console only')}
    allowed = assigned_set(ROOT / 'tools/server.py', 'ALLOWED')
    require(console_only <= allowed - tactics, 'Console-only catalog command has invalid HTTP authority')
    require(set(catalog['commands']) - console_only == tactics, 'Action catalog differs from HTTP tactical actions')
    require(catalog['game_version'] == package['version'], 'Runtime and catalog versions differ')
    for name in tactics:
        require('`' + name + '`' in (ROOT / 'docs/AGENT_ACTION_STATES.md').read_text(), 'Undocumented action: ' + name)
    lock = json.loads((ROOT / 'package-lock.json').read_text())
    require(lock['packages']['']['devDependencies'] == package['devDependencies'], 'npm lock differs from package.json')
    manifest = json.loads((ROOT / '.forge/assets.json').read_text())
    for asset in manifest['assets']:
        p = ROOT / asset['path']
        require(p.is_file(), 'Missing asset: ' + asset['path'])
        if p.is_file():
            require(hashlib.sha256(p.read_bytes()).hexdigest() == asset['sha256'], 'Asset hash drift: ' + asset['path'])
        require(bool(asset.get('license')), 'Missing asset license: ' + asset['path'])
        for source, digest in asset.get('source_hashes', {}).items():
            p = ROOT / source
            require(p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest() == digest, 'Source hash drift: ' + source)
    index = (ROOT / 'docs/README.md').read_text()
    markdown = [n for n in files if n.endswith('.md')]
    for name in markdown:
        require('`' + name + '`' in index, 'Missing document index entry: ' + name)
        # Markdown links, excluding code blocks; external URLs and anchors are not fetched.
        text = re.sub(r'```.*?```', '', (ROOT / name).read_text(), flags=re.S)
        for target in re.findall(r'!?\[[^\]]*\]\(([^\s)]+)(?:\s+[^)]*)?\)', text):
            target = urllib.parse.unquote(target.strip('<>')).split('#')[0].split('?')[0]
            if not target or urllib.parse.urlsplit(target).scheme or target.startswith('/'):
                continue
            require((ROOT / name).parent.joinpath(target).exists(), 'Broken link in ' + name + ': ' + target)
    print(json.dumps({'passed': not errors, 'documents': len(markdown), 'assets': len(manifest['assets']), 'actions': len(tactics), 'errors': errors}, ensure_ascii=False, indent=2))
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(check())
