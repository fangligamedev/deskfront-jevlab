# 开发、构建与故障排查

## 依赖

| 工具 | 用途 | 版本 |
| --- | --- | --- |
| Python | 服务、检查、打包、LM | 3.9+，运行无第三方 Python 依赖 |
| Godot | 导入、游戏、导出 | 已验证 4.5.1，导出模板必须同版本 |
| Blender | 编辑/重建美术 | 已验证 5.2.1 LTS，游玩不需要 |
| Node.js / npm | 可选浏览器测试 | 建议 Node 22，依赖锁定在 package-lock.json |
| ffmpeg / fonttools | 重建音频/字体 | 仅对应脚本需要 |

引擎查找顺序：GODOT_BIN / BLENDER_BIN → PATH → macOS 标准安装路径。变量值为可执行文件路径，不附加命令参数。

## 运行

```sh
python3 tools/project.py import
python3 tools/project.py web
python3 tools/run.py
```

打开 http://127.0.0.1:8768/。已有构建不会自动重建；更改 GDScript、规则或资源后重新导出并刷新。dashboard 文件刷新即生效。

原生游戏用 Godot F5，控制台用 ?native=1。单端口仅连接一个游戏实例。多实例可在独立终端设置：

```sh
python3 tools/server.py --port 8776
# 另一个终端，godot 必须在 PATH 中，或替换为完整路径
DESKFRONT_URL=http://127.0.0.1:8776 godot --path .
```

Web 自动使用网页 origin。无头游戏默认关闭桥接，只有 DESKFRONT_HEADLESS_BRIDGE=1 才连接服务。

## 检查

```sh
# 不需要引擎或凭证
python3 tools/check_project.py
python3 -m unittest discover -s tests -p 'test_*.py' -v

# 真实 Godot 行为
python3 tools/project.py import
python3 tools/project.py test

# 先导出 Web 并启动服务，另一个终端执行
npm ci
npx playwright install chromium
npm run test:browser
npm run test:equipment
# 下项会真实调用配置的模型
npm run test:lm
```

npm 命令统一使用 8768。另一个端口可直接运行：
`DESKFRONT_URL=http://127.0.0.1:8776 node tools/equipment_browser_qa.cjs`。
同一端口不能并行跑多个浏览器测试。

```sh
godot --headless --path . --script tests/tactical_rehearsal.gd -- --runs=100 --prefix=release
godot --headless --path . --script tests/tactical_rehearsal.gd -- --start=78 --runs=1 --prefix=repro
# 真实 LM 小样本试验，产生供应商费用
python3 tools/lm_trial.py --seconds 40 --maps 0,1,2 --modes game_ai,lm
```

演练输出保留在 output/v05/*-rehearsal.json；其他检查写 output/。Godot 测试覆盖语义、集成、资源、弹道、LM 权限、设施、三人上下楼。100 场是固定场景回归，不是模型训练或胜率证明。离线 Python 测试使用测试替身，不调用付费 API。

## 导出

```sh
python3 tools/project.py web
python3 tools/project.py macos
python3 tools/project.py bundle
```

输出为 build/web/ 和 build/macos/Deskfront.zip。dist/ 包名读取 package.json 的运行时版本，生成 source-hashes.json 与 SHA256SUMS.txt。

源码包以 Git 索引为边界，发布前先审核并 stage 新文件。Web 包携带运行脚本和文档；编辑完整源码使用源码包或 Git 克隆。macOS 未签名和公证。

## 美术

阅读 [资源文档](ASSETS.md)，保留来源和许可。当前原稿在 source/latest/，运行文件在 assets/。修改后导出、导入、验证动画与碰撞，执行 `python3 tools/project.py record-assets` 更新来源哈希。

`python3 tools/project.py models` 仅重建历史资产，不能用它替换当前全部美术。

## 故障排查

| 现象 | 处理 |
| --- | --- |
| 找不到 Godot | 设置 GODOT_BIN 或 PATH |
| 缺导出模板 | 安装匹配 4.5.1 的模板 |
| 页面是旧版本 | 重新导出 Web，再刷新 |
| 引擎离线 | 启动游戏并确认服务端口一致 |
| 状态跳变 / 暂停无效 | 关闭同端口重复标签页或原生实例 |
| 没有声音 | 点击游戏画面，检查 M 静音和系统音量 |
| LM 不可用 | 检查 .env 的 Key 与模型 ID，重启服务 |
| leave_equipment_first | 先撤楼或弃炮，再移动 |
| 无头 Chromium 帧率低 | 可能使用软件渲染；功能测试不是性能基准 |

报告附版本、复现、日志、截图，分享前移除凭证。
