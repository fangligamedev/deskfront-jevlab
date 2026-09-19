#!/usr/bin/env python3
"""Build the document inventory and a portable full-text reading package."""
import argparse
import json
from pathlib import Path
import re
import zipfile
import posixpath
from check_project import tracked_files

ROOT = Path(__file__).resolve().parents[1]


def documents():
    files = [n for n in tracked_files() if n.endswith('.md')]
    return sorted(set(n for n in files if n) | {'docs/README.md'})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--write-index', action='store_true')
    parser.add_argument('--bundle', action='store_true')
    args = parser.parse_args()
    files = documents()
    if args.write_index:
        rows = ['# 全部说明文档', '', '当前 main 运行时 **'+json.loads((ROOT/'package.json').read_text())['version']+'**；历史发布标记 **v9.19** 保持不变。以下为源码 Markdown 文档完整清单；历史报告记录当时实现，当前使用以 README、API 和开发指南为准。', '', '先读 [项目介绍](../README.md)，体验 [AI 沙盒](studio/README.md) 与 [JEV](JEV_CONTROL.md)；开发者读 [开发指南](DEVELOPMENT.md)，Agent 作者读 [动作全集](AGENT_ACTION_STATES.md)。', '', '| 文件 | 说明 / 内容 | 类别 |', '| --- | --- | --- |']
        for name in files:
            title = '全部说明文档' if name == 'docs/README.md' else next((s.lstrip('# ').strip() for s in (ROOT / name).read_text().splitlines() if s.startswith('# ')), Path(name).stem)
            category = '本次交付' if name=='docs/DELIVERY-v9.19.md' else '历史交付' if '/DELIVERY-' in name else '资源集成' if '/asset-integration/' in name else '协作模板' if name.startswith('.github/') else '工作说明' if 'BRIEF-' in name else '当前指南'
            target = posixpath.relpath(name, 'docs')
            rows.append('| `' + name + '` | [' + title.replace('|', '/') + '](' + target + ') | ' + category + ' |')
        rows += ['', '## 机器可读记录与许可证', '', '- [动作 JSON](../data/action-catalog.json)、[动画目录](animation-catalog.json)、[资源清单](../.forge/assets.json)。', '- [0.6 验证证据](evidence/v06/verification.json)；历史 evidence 目录按版本保留，output 是本机临时记录。', '- 根目录 [MIT](../LICENSE)；第三方许可全文位于 docs/licenses，逐素材适用范围见 [第三方声明](../THIRD_PARTY.md)。', '', '本目录由 `python3 tools/docs.py --write-index` 根据 Git 索引生成；新文档先 stage 再更新索引。`python3 tools/docs.py --bundle` 生成完整正文 Markdown 与文档 ZIP，存放于 dist，不提交重复副本。', '']
        (ROOT / 'docs/README.md').write_text('\n'.join(rows))
    if args.bundle:
        out = ROOT / 'dist'
        out.mkdir(exist_ok=True)
        book = ['# Deskfront v9.19 · 全部说明文档正文', '', '仓库：https://github.com/fangligamedev/deskfront-jevlab/tree/v9.19', '', '原文件名称见各节；历史报告反映历史版本。文内相对链接转换为 GitHub 标签下的原文件。', '']
        for name in files:
            content = (ROOT / name).read_text()
            def link(match):
                target = match.group(2)
                if target.startswith(('#', '/', 'http:', 'https:', 'mailto:')):
                    return match.group(0)
                normalized = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
                return match.group(1) + 'https://github.com/fangligamedev/deskfront-jevlab/blob/v9.19/' + normalized + ')'
            content = re.sub(r'(!?\[[^\]]*\]\()([^\s)]+)\)', link, content)
            book += ['---', '', '## 原文件：' + name, '', content, '']
        (out / 'Deskfront-docs-v9.19.md').write_text('\n'.join(book))
        indexed = tracked_files()
        included = set(files + ['LICENSE', '.forge/assets.json']) | {n for n in indexed if n.startswith(('docs/', 'data/'))}
        with zipfile.ZipFile(out / 'Deskfront-docs-v9.19.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
            for name in sorted(included):
                archive.write(ROOT / name, name)
        print(out / 'Deskfront-docs-v9.19.md')


if __name__ == '__main__':
    main()
