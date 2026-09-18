# Deskfront · 桌面前线 0.2.0

Godot 4.5 + Blender 的原创开源 3D 桌面战术游戏。复古办公室里的三支玩具小队，围绕沙包、文具与中央目标交战；人类继续缓慢操作电脑，失势的红方获得一辆坦克增援。配套真实状态驱动的策划控制台。

## 立即运行

macOS 双击 **启动桌面前线.command**；或在工程目录执行：

```sh
python3 tools/run.py
```

打开 <http://127.0.0.1:8768>。保持终端运行，Ctrl+C 关闭服务。已有 Web 构建时只需要 Python 3.9+ 和支持 WebGL2 的现代浏览器；首次从纯源码启动会调用 Godot 导出，需要 Godot 4.5.1 和对应 Web 导出模板。

原生运行：用 Godot 打开 `project.godot`，按 F6 运行主场景，或按 F5 运行工程。原生版对应控制台使用 <http://127.0.0.1:8768/?native=1>（不启动 Web 实例）。同一个控制服务端口只运行一个游戏实例，避免同时运行网页 iframe 和原生版。

## 操作

| 操作 | 输入 |
| --- | --- |
| 接管整个阵营 | 1 / 2 / 3 或画面底部按钮 |
| 单兵 / 多选 | 左键士兵 / 左键拖动框选 / Shift 追加 |
| 移动 / 指定攻击 | 右键桌面 / 右键敌人；已选单位时左键空地也可移动，地面显示指令环 |
| 找掩体 / 守住 / 撤退 | C / H / R |
| 交还游戏 AI | A |
| RTS 相机 | 中键拖动或 Alt＋左键拖动；方向键平移；滚轮缩放；贴边平移（E开关）；Home 居中 |
| 视角 / 声音 | V 切换办公室、战术、正俯视；M 静音；浏览器首次点击游戏后启用音频 |
| 暂停 / 重开 | 空格 / 胜负后 Enter |
| 坦克演示 / 纯画面 | T / F1 |

占领中央黄铜标记累积 90 分，或使其他阵营失去战斗力。首版三阵营各三名步兵；红方失势时一次坦克增援。坦克能损坏邻近敌人的掩体并更新导航。

每队按编号固定装备：1号步枪（单发），2号冲锋枪（快速连续射击），3号火箭筒（优先反坦克、爆炸范围伤害）。步兵在0.075米内自动刺刀，不能刺穿坦克。射击弹道有实际飞行时间，命中后才扣血，伴随枪口焰、曳光、火箭尾烟、爆炸和原创合成音效。AI开局优先占掩体，在站位稳定后逐段推进。

控制台可以查看实时小地图、AI候选战术、单位生命与压制、掩体预约及事件；可接管阵营、调参数、切视角、暂停与重开。

## 开发与重建

```sh
# 首次安装 Godot 4.5.1、对应 Web/macOS 导出模板，Blender 5.2.1
python3 tools/project.py models       # 重建七个 .blend / GLB，登记资源来源
python3 tools/project.py import
python3 tools/project.py test
python3 tools/project.py web
python3 tools/project.py macos

# 可选：真实浏览器测试
npm install
npx playwright install chromium
npm run test:browser                 # 需先运行 tools/run.py --no-open
```

命令自动发现本机程序，也可设置 `GODOT_BIN`、`BLENDER_BIN`。原生游戏控制服务地址可用 `DESKFRONT_URL` 指定。所有核心规则与关卡代理位于 `data/battle.json`。

## 文档与证据

- [设计文档](docs/DESIGN.md)：关卡目标、战斗机制、交付边界。
- [工程文档](docs/ENGINEERING.md)：状态真相源、模块、寻路、控制服务和构建。
- [资源与配置](docs/ASSETS.md)：Blender源文件、骨骼动作、单位尺度和配置字段。
- [Agent API](docs/AGENT_API.md)：状态、权限、动作校验、回执与适配示例。
- [研究参考](docs/REFERENCES.md)：GDC/《英雄连》文章与本工程的实际映射。
- [交付报告](docs/DELIVERY.md)：已完成项、验收证据和明确限制。

## 开源与边界

代码和文档 MIT；原创模型、骨骼与动作 CC0-1.0，见 `assets/LICENSE.md`。`.blend` 原文件和生成脚本均可修改。没有复制《英雄连》的游戏代码或资产，参考图片未打进发行包。

这是可玩的单关卡低多边形垂直切片，保留概念图的办公室与微型战场构图，不宣称离线写实画质或商业 RTS 的内容规模。Jev 的具体服务协议与凭据尚未提供，交付通用 Agent 接口和可跑示例，**没有假装已接通 Jev**。macOS 构建不签名、不公证。项目已按开源许可组织；未擅自创建远程公开仓库。
