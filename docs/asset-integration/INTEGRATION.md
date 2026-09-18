> 这是资源任务原始交接记录。当前用户已授权集成，正式集成状态与验收以 [0.4.0 报告](../DELIVERY-0.4.0.md) 为准；下文的“待确认/独立预览”描述的是集成前阶段。

# 集成契约与资源配置

## 当前边界

样片实现真实 Godot 骨骼动画、CharacterBody3D 根运动、掩体碰撞/射线、刚体 ragdoll、武器事件音效和透明粒子。样片只有三名资产展示兵；主游戏仍是原来的九兵三阵营，尚未合并。

主游戏 `unit.gd` 的位置、生命、AI、掩体预约、网络状态仍应是唯一真值。确认资产以后，让它调用展示层，而不是用样片 `sequence()` 的时间脚本替换游戏 AI。所有伤害与弹药库存继续由主游戏计算。

## 可复用文件

| 文件 | 作用 |
|---|---|
| `assets/models/toy-soldier.glb` | 5073 三角形，50 骨骼，22 动作；同一模型运行时赋阵营纯色 |
| 同名 `.glb.import` | `root_scale=0.075`，应用根缩放；必须连同导入设置复制，运行时兵高约 13.5 cm |
| `scripts/toy_actor.gd` | 动作树、根运动提取、持枪锚点、掩体端点对齐、18 刚体 ragdoll |
| `assets/models/tank.glb` | T2 原始资产，4 履带移动片段；`normalize()` 按整体包围盒缩至 30 cm |
| `assets/models/{rifle,pistol,grenade,rocket}.glb` | 武器/手雷；阵营材质由持有者统一设置 |
| `data/weapons.json` | 武器模型、动作键、试听用弹药规格、飞行时长、事件音效、爆炸尺寸 |
| `scripts/effects.gd` | `fire(kind,from,to)` / `blast(pos,kind)`；弹道、声源、烟尘和破片 |
| `assets/vfx/soft_flipbook.gdshader` | 5×5 序列、双帧流场插值、深度软交界、透明烟尘 |

`weapons.json` 的 ammo 是设计规格，样片可无限试射，不实现库存扣除；主游戏库存和命中计算需接回原有武器逻辑。导入后应把音效发射挂到动画/武器事件，不依赖固定演示时间。

## 动作与掩体

`animation-catalog.json` 明确每个派生片段的来源。作者公开预览中的 127 个动画条目保留在 `source/ual-author-preview.glb`，本样片选取并派生 22 个，未把整个库声称为 CQB 专用动作包。

- `rifle_walk_rm` / `rifle_jog_rm` / `rifle_crouch_rm`：原片段为原地循环，加入本项目标定的根位移轨迹；不是声称原作自带的行走 Root Motion。
- `roll_rm` / `dodge_left_rm`：来源为作者带 RM 的对应片段。
- `cover_enter` / `cover_idle` / `cover_exit`：使用作者蹲姿动作，叠加本项目双手持枪姿态。
- `cover_peek_left/right`：蹲姿派生的探身加端点运动对齐；样片验证低掩体两端。并非完整的高掩体、拐角、翻越系统。
- `grenade_throw`：以待机躯干为底，原创两骨 IK 上举、蓄力、前摆、回收曲线；G 键在 0.62 秒松手发射真实手雷模型。手指张开和完整持物接触还需精修。
- `reload` 源自手枪换弹。双手步枪弹匣操作、完整手指接触和武器套件 IK 尚不属于已完成精修范围。

AnimationTree 在 physics 回调更新，根轨迹由 `get_root_motion_position()` 提取，交给 CharacterBody3D；没有额外把根位移重复加到网格。接入主游戏寻路速度时应调整 TimeScale/动画速率，不应又叠加原先的线性移动。

掩体数据至少需要表面法线、低/高分类、胸口遮挡高度、左右端点、入口位置和预约归属。样片的固定端点用来验证契约，合并时改成主游戏掩体数据。射线检查使用真实碰撞层 1。

## Ragdoll 与破坏

样片中 18 个刚体由 PinJoint3D 连接，模拟结果驱动原蒙皮；不是倒地动画。为减少微型尺度求解误差，独立 World3D 将物理放大 20 倍，随后映回骨骼。复制桌面、掩体和坦克的盒形静态代理；每次死亡快照静态代理，动态物件同步和复杂关节角度限制仍需主游戏适配。

目前展示预切成 8 块的盒体与飞散碎片；不是任意网格运行时布尔破坏。办公室资产继续使用原 Blender 极简模型，可以按同一方法逐物件定义耐久、预破碎片和碰撞替换。

## 声画与性能

常驻光源与主游戏一致。只在爆炸瞬间增加短暂局部光；主画风、办公室模型保持原样。烟尘是透明 billboard + 预渲染序列，包含时间插值和软交界，尚无真实 3D 体积自阴影/多重散射。没有将此样片称为已达 3A 成品品质。

音频采用独立 AudioListener3D 放在桌面战场上方，避免高空正交相机导致声源超出衰减距离。8 个事件使用 AudioStreamPlayer3D；坦克炮声是从 Q009 素材加工的设计音效，并非实录坦克。发射/命中声音分离，音频派生必须保持 CC-BY-SA 3.0。

合并时应给粒子、破片与声音设置并发预算/对象池，接入全局静音、事件日志和武器配置。当前样片按单次事件运行，尚未验证九兵持续混战下的峰值开销。

## 重建与测试

```sh
blender -b --python tools/build_soldier.py
blender -b --python tools/build_extras.py
python3 tools/build_audio.py
godot --headless --editor --import
godot --headless --script tools/acceptance.gd
godot --headless --export-release Web build/web/index.html
```

工具脚本中的 Blender/Godot 命令可使用 PATH，`build_audio.py` 的 ffmpeg 路径按本机安装修改。`register_assets.py` 调用相邻的 Godot Forge CLI 写入来源与哈希。`web_qa.cjs` 使用本机现有 Playwright 路径；换环境需安装 Playwright 并调整 require。

主游戏最终合并前需要：用户画面/声音确认 → 资产层适配 → 九兵三阵营、玩家接管、AI/Agent 状态、掩体预约、坦克与音效回归 → 新版本导出。
