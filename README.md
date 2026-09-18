# Deskfront · 桌面前线

**Godot + Blender 开源桌面战术原型。** 三支玩具兵小队在办公室桌面交战，人类继续操作电脑。支持玩家 RTS 操作、游戏 AI、逐单位 DeepSeek LM 和外部 Agent。

[完整文档目录](docs/README.md) · [动作接口](docs/AGENT_ACTION_STATES.md) · [贡献指南](CONTRIBUTING.md) · [更新日志](CHANGELOG.md)

当前发布标记 **v9.19**（2026-09-19）；游戏运行时版本 **0.6.0**。本次整理工程、文档和开发流程，不改动上一版战斗规则；历史 V0.1 标签保留。

![蓝军进驻桌面右上角小楼](docs/evidence/v06/web-building-garrison.png)

## 游戏能力

- 三个阵营、九名步兵，三张 JSON 驱动地图；一次红方坦克增援。
- 步枪、冲锋枪、火箭筒、手枪、手雷和刺刀；首碰撞弹道、压制、方向掩体及破坏。
- 先寻找保护，再掩护推进；跑动、低姿移动、匍匐、探头、换弹与撤退。
- 反坦克炮接管、推行、部署、开炮和弃炮；轻武器不会攻击坦克。
- 蓝军沿楼梯进入两层小楼、守窗和撤离；楼板失效会坍塌。
- 本地策划台展示真实状态、参数、控制权、逐单位 LM 决策和引擎回执。

Godot 是唯一战斗状态来源。Blender 原稿、骨骼、动画、素材来源和许可随源码提供。

## 快速开始

从源码运行需要 **Python 3.9+、Godot 4.5.1 和对应版本 Web 导出模板**。浏览器需要 WebGL2。编辑美术才需要 Blender；已验证资源工具版本为 Blender 5.2.1 LTS。Node.js 仅用于可选浏览器测试。

```sh
git clone https://github.com/fangligamedev/deskfront-jevlab.git
cd deskfront-jevlab
git checkout v9.19
python3 tools/project.py import
python3 tools/project.py web
python3 tools/run.py
```

打开 **http://127.0.0.1:8768/**，点击游戏画面启用音频。终端保持运行，Ctrl+C 停止。macOS 也可双击根目录的启动桌面前线.command。找不到引擎时，将 GODOT_BIN 设置为可执行文件路径，或把 godot 加入 PATH。

源码仓库不包含 build/。已有 Web 交付包时只需 Python 和浏览器，运行同样的启动命令；run.py 不自动重建已有导出，修改游戏后需要重新导出。

### 原生运行

Godot 打开 project.godot，按 **F5**。另运行 `python3 tools/server.py`，控制台打开 **http://127.0.0.1:8768/?native=1**。同一端口只连接一个游戏实例，避免网页游戏和原生窗口争用状态。多实例和平台设置见 [开发指南](docs/DEVELOPMENT.md)。

### 可选 LM

不配 Key 也可完整游玩。复制 .env.example 为 .env，设置自己的 ARK_API_KEY 和已开通的 DESKFRONT_LM_MODEL，重启服务，顶部选择「DeepSeek LM」。

步兵与坦克独立决策；默认每局最多 120 次请求、并发 3。真实调用产生供应商费用，重开会重置本局预算。Key 仅在本地服务端读取，不提交 .env。[完整 LM 配置](docs/LM_CONTROL.md)。

## 操作

| 操作 | 输入 |
| --- | --- |
| 接管阵营 | 1 / 2 / 3 |
| 单选 / 框选 / 追加 | 左键士兵 / 左键拖动 / Shift |
| 移动 / 攻击 | 右键地面 / 右键敌人 |
| 镜头 | 中键或 Alt + 左键拖动；方向键平移；滚轮缩放；Home 居中 |
| 掩体 / 守住 / 撤退 | C / H / R |
| 交回游戏 AI | A |
| 手雷 / 手枪 / 切地图 | G / P / F2 |
| 视角 / 静音 / 暂停 | V / M / 空格 |
| 坦克增援 / 隐藏 HUD | T / F1 |

全局或按阵营切换「游戏 AI / DeepSeek LM / 外部 Agent / 玩家」。控制台可调整姿态、装备、上楼、撤楼、接管炮和弃炮。设施按钮会接管对应阵营；交回 AI 后继续自主作战。占点累计 90 分或消灭其他阵营获胜，规则以 [battle.json](data/battle.json) 为准。

## 工程结构

| 目录 | 内容 |
| --- | --- |
| assets/ | 实际加载的模型、声音、字体、特效 |
| source/ | Blender 原稿、第三方原始资源和重建脚本 |
| scenes/ / scripts/ | Godot 场景、战斗、战术、设施、角色与同步 |
| data/ | 规则、地图、步态和机器可读动作目录 |
| dashboard/ | 本地策划网页 |
| tools/ / tests/ | 服务、Agent、LM、构建、检查和行为测试 |
| docs/ | 设计、工程、资源、API、研究、交付和证据 |
| .github/ | CI、Issue 和 PR 模板 |
| build/ / output/ / dist/ | 本机导出、日志和交付包，不入 Git |

source/latest/ 是当前资源；source/blender/ 保留历史原稿。不要用旧生成器覆盖当前运行模型。

## 开发与验证

```sh
# 无引擎、无 API Key 的基础检查
python3 tools/check_project.py
python3 -m unittest discover -s tests -p 'test_*.py' -v

# 真实 Godot 行为检查
python3 tools/project.py import
python3 tools/project.py test

# 可选：先导出 Web 并运行服务，再在另一个终端执行
npm ci
npx playwright install chromium
npm run test:browser
```

CI 运行项目合同检查、离线 Python 测试及真实 Godot 导入/测试，不自动调用收费 LM。完整演练、构建和排错见 [开发指南](docs/DEVELOPMENT.md)。

0.6 已有验证：100/100 场战术演练、25 项 RTS Web、6 项设施 Web、11 项真实 LM 接入检查。它们是对应构建的证据，不代表每台机器的性能或模型胜率。[验证记录](docs/evidence/v06/verification.json)。

## 说明文档

[完整目录](docs/README.md) 列出全部已发布 Markdown 文档，区分当前指南和历史报告。

| 文档 | 内容 |
| --- | --- |
| [设计](docs/DESIGN.md) | 场景、目标、战斗、模式与边界 |
| [工程](docs/ENGINEERING.md) | 模块、数据流、状态权威和执行 |
| [开发](docs/DEVELOPMENT.md) | 安装、运行、测试、导出和排错 |
| [资源配置](docs/ASSETS.md) / [设施](docs/ASSET_EQUIPMENT.md) | 原稿、尺度、规则、火炮和小楼 |
| [Agent API](docs/AGENT_API.md) / [动作状态全集](docs/AGENT_ACTION_STATES.md) | HTTP 协议、权限、人物/坦克/武器动作 |
| [LM 接入](docs/LM_CONTROL.md) | 配置、调度、预算与失败处理 |
| [战术](docs/TACTICS.md) / [研究](docs/REFERENCES.md) | GDC 参考与实现映射 |
| [交付报告](docs/DELIVERY.md) | 当前整理发布与玩法验证 |
| [发布流程](docs/RELEASING.md) | 版本、提交、标签与验收 |

## 参与和许可

通过 [Issues](https://github.com/fangligamedev/deskfront-jevlab/issues) 或 PR 参与；先阅读 [贡献指南](CONTRIBUTING.md)。安全问题见 [SECURITY.md](SECURITY.md)。

代码和文档采用 [MIT](LICENSE)。模型/动画主要 CC0；部分 Q009 衍生声音 **CC-BY-SA 3.0**，字体 **OFL 1.1**。代码许可不替代素材的独立许可，详见 [资源许可](assets/LICENSE.md) 和 [第三方来源](THIRD_PARTY.md)。

当前是三地图战术原型，没有联网对战、战争迷雾或成熟的多智能体通信。炮组为单人操作，后备炮弹不限量。Jev 保留通用 Agent 接口，未连接专属 SDK。macOS 导出未签名、未公证。没有使用《英雄连》的代码或资产。
