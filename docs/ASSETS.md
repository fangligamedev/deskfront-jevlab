# 资源与配置文档

## 原始资源

| 资源 | 源文件 | 导出用途 |
| --- | --- | --- |
| office | source/blender/generated/office.blend | 复古 L 形桌、CRT、台灯、椅子、文件柜、文具、纸盒、墙面 |
| infantry-green | source/blender/generated/infantry-green.blend | 苔绿队，17骨骼，8动作 |
| infantry-blue | source/blender/generated/infantry-blue.blend | 钴蓝队，同构骨架 |
| infantry-red | source/blender/generated/infantry-red.blend | 砖红队，同构骨架 |
| worker | source/blender/generated/worker.blend | 坐姿人类与 typing 循环 |
| tank | source/blender/generated/tank.blend | 一辆砖红玩具坦克 |
| sandbag | source/blender/generated/sandbag.blend | 带折边、接缝的沙包，按 JSON 排列 |

全部资源来自本地 `source/blender/build_assets.py`，许可 CC0-1.0。无需付费生成器、在线模型、下载素材或第三方美术资源。文件许可与 SHA-256 在 `.forge/assets.json`，关联源脚本及 `.blend` Hash。

静态办公室按材质合并网格，减少绘制批次。主要使用几何体和 PBR 纯色材质，没有烘焙参考图片到背景。因而可自由改变相机和控制单位。造型是可编辑低多边形复现，不等同于参考图的离线写实质感。

## 坐标与尺度

- 游戏单位为米，Godot +Y 向上、-Z 朝前。Blender 导出器执行 Z-up → Y-up 转换。
- 桌面高度 0.82 米。步兵原始身高约 1.73 单位，游戏以 0.069 倍缩放，显示约 0.12 米高；为俯视操作可读性，比最初概念的四厘米小兵略大。
- 坦克几何约 0.15 × 0.16 × 0.29 米（炮管包含在长度内），玩法使用膨胀后的保守导航范围。
- 环境碰撞使用数据里的二维障碍代理，而非直接把渲染网格全部做复杂碰撞。掩体横向投影决定寻路，高度/类别决定战术语义。

## 动作合同

| ID | 时长 | 循环 | 语义 |
| --- | --- | --- | --- |
| idle | 2 秒 | 是 | 轻微呼吸和观察 |
| run | 1 秒 | 是 | 原地行进；游戏管理位移 |
| aim | 2 秒 | 是 | 举枪观察 |
| fire | 0.417 秒 | 否 | 射击与轻微后坐 |
| crouch | 2 秒 | 是 | 蹲姿掩护 |
| prone | 2 秒 | 是 | 高压制时低姿态 |
| reload | 2 秒 | 否 | 换弹动作；逻辑时间默认 2.2 秒 |
| death | 1.25 秒 | 否 | 倒下；髋骨降低是刻意的收尾，不是移动漂移 |
| typing | 5 秒 | 是 | 人类慢速打字；引擎以 0.6 倍播放 |

详细 clip manifest 在相应 `*-clips.json`。所有动画驱动目标必须匹配导入骨骼，无根骨水平漂移；动作切换由 AnimationTree 控制。Blender 中每个动作在独立 NLA 轨道，编辑时单独 Solo 目标轨道，避免多个轨道叠加预览。

## 规则 JSON

`schema_version` 固定为 1。`factions` 配置 ID、名称、颜色、出生点和战术目标；`soldier` 配置生命、速度、距离、伤害、命中率、弹匣、换弹与压制衰减；`rules` 配置积分上限、比赛时长、增援条件和 AI 决策频率。

`covers` 条目：稳定 `id`、二维 `position=[x,z]`、`size=[width,depth]`、朝向 `normal=[x,z]`、高度、生命、类别。`hp=-1` 代表不可破坏。类别 `sandbag`、`notebook`、`pencil`、`eraser` 由 `battlefield.gd` 构建视觉与战术形状。

`obstacles` 条目定义高物件的投影阻挡。移动了 Blender 里的办公道具后，必须同步改这个代理，否则画面和寻路会不同步。桌面边界是可玩区域，不是整个房间边界。

新增模型流程：修改 Blender 脚本 → `python3 tools/project.py models` → 导入 → 模型/动画审计 → 实机截图 → 更新证据。禁止修改 GLB 后跳过来源登记。
