# 资源与配置文档（0.5.0）

## 当前运行资产

| 资产 | 运行接入 | 编辑来源 |
|---|---|---|
| toy-soldier.glb | 三阵营共用，50 骨骼 / 28 动作 / 5073 三角形 | source/latest/toy-soldier-retarget.blend |
| tank.glb | T2，0.30 m，4 履带动作，独立炮塔 | source/latest/tank-original.blend |
| rifle / pistol / rocket / grenade.glb | 手部锚点武器、手雷抛物线弹体 | source/latest 下对应 .blend |
| office-sandbox.glb | 扩大办公室、1.91×4.40 m 桌面 | source/latest/sandbox-generated/office-sandbox-editable.blend |
| office-worker.glb | 62 骨骼，8 秒打字循环以 0.6 倍播放 | source/latest/office-worker/office-worker.blend |
| sandbag.glb | 三地图的旋转沙包实体 | source/blender/generated/sandbag.blend |
| fx.png / flow.png / soft_flipbook.gdshader | 枪口、尾烟、爆炸的透明图集混合 | CC0 图集 / MIT shader |
| Q009 衍生 WAV | 8 个分武器声音，20 个同时播放上限 | source/latest/q009 / tools/build_audio.py |
| DeskfrontUI.otf | 中文 HUD | source/latest/fonts / tools/build_ui_font.py |

`toy-soldier.glb.import` 必须保留：root_scale=0.075 且 apply_root_scale=true。单位身高约 0.135 m；不能再额外缩放模型或 root motion。坦克原始朝向 -X，适配器旋转 -π/2 变为游戏 -Z。炮塔重挂时保留归一化后的全局变换。

## 数据与重建

- `data/action-catalog.json`：Agent 命令、四层动作状态与武器系列。
- `data/battle.json`：三阵营配色、默认装备、伤害/弹匣/射程/手雷与现有战术参数。
- `data/sandbox-maps.json`：地图 bounds、spawns、tank_spawn、objective 和可旋转对象。
- `data/gait.json`：侧步根轨迹、支撑/摆动相、单步 0.033 m / 1.067 秒。
- `docs/animation-catalog.json`：动作来源与时长。
- `source/latest/tools/build_*.py`：士兵、桌面、办公人物、武器、音效和地图源脚本。Blender 脚本用 `blender -b --python <脚本>`，音效用 Python + ffmpeg，字体用 Python + fonttools。
- 桌面与办公人物脚本导出到对应 source/latest 子目录，审核后复制 GLB 到 assets/models；其它脚本直接写各自 assets/data 路径。
- 枪械和坦克编辑 .blend 后重新导出 glTF。保留 source/latest 中原始 GLB/FBX 与未改编动画库。
- `python3 tools/project.py record-assets` 只刷新资源与来源哈希，**不再用旧生成目录覆盖最新版资产**。

完整来源和许可证见 [THIRD_PARTY](../THIRD_PARTY.md)。旧版资产和重建器保留供历史版本对照，下面章节仅描述 0.1–0.3 的旧实现，不代表当前运行资源。

---

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

上述模型资源来自本地 `source/blender/build_assets.py`，许可 CC0-1.0。无需付费生成器、在线模型、下载素材或第三方美术资源。文件许可与 SHA-256 在 `.forge/assets.json`，关联源脚本及 `.blend` Hash。

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
| reload | 2 秒 | 否 | 换弹动作；逻辑时间由各武器 reload 配置 |
| death | 1.25 秒 | 否 | 倒下；髋骨降低是刻意的收尾，不是移动漂移 |
| typing | 5 秒 | 是 | 人类慢速打字；引擎以 0.6 倍播放 |

详细 clip manifest 在相应 `*-clips.json`。所有动画驱动目标必须匹配导入骨骼，无根骨水平漂移；动作切换由 AnimationTree 控制。Blender 中每个动作在独立 NLA 轨道，编辑时单独 Solo 目标轨道，避免多个轨道叠加预览。

## 规则 JSON

`schema_version` 固定为 1。`factions` 配置 ID、名称、颜色、出生点和战术目标；`soldier` 配置生命、速度、压制衰减，并保留策划台伤害/冷却/命中率的全局倍率基准；`weapons` 配置各武器的实际射程、伤害、冷却、命中率、弹匣、换弹、弹速、装甲倍率、爆炸半径；`loadout` 对应每队三个兵的装备；`rules` 配置积分上限、比赛时长、增援条件；`tactics`配置小队协调频率与行为参数，旧`rules.ai_interval/cover_hold_seconds`仅为兼容保留，不再驱动协调器。

`covers` 条目：稳定 `id`、二维 `position=[x,z]`、`size=[width,depth]`、朝向 `normal=[x,z]`、高度、生命、类别。`hp=-1` 代表不可破坏。类别 `sandbag`、`notebook`、`pencil`、`eraser` 由 `battlefield.gd` 构建视觉与战术形状。

`obstacles` 条目定义高物件的投影阻挡。移动了 Blender 里的办公道具后，必须同步改这个代理，否则画面和寻路会不同步。桌面边界是可玩区域，不是整个房间边界。

新增模型流程：修改 Blender 脚本 → `python3 tools/project.py models` → 导入 → 模型/动画审计 → 实机截图 → 更新证据。禁止修改 GLB 后跳过来源登记。

## 原创声音与运行时武器附件（0.2.0）

`source/audio/synthesize.py` 可确定性重建九个16-bit、22050Hz、单声道WAV：rifle、smg、rocket、cannon、explosion、impact、bayonet、order、reload。时长0.12–1.05秒，峰值限制在0.78。所有声音为原创程序合成，CC0；未下载枪声录音。源WAV、生成脚本与运行WAV的来源及SHA-256写入`.forge/assets.json`。重建Blender资源会保留音频来源条目。

运行几何武器在`unit.gd::install_weapon()`定义：步枪长枪管与刺刀、冲锋枪短枪管与弹匣、火箭筒粗管及尾罩。使用现有骨骼的休止变换将几何挂入右手附件。效果是Godot原生网格，无贴图和外部VFX插件。


## 0.3.0 炮塔与战术参数

坦克GLB从单一合并模型改为车体与独立`TurretPivot`，炮塔、炮管和舱盖随支点旋转，`Muzzle`标记实际炮口。Blender源文件同步保留，可用`blender -b --python source/blender/build_assets.py -- --only-tank`单独重建，再执行`python3 tools/project.py record-assets`登记。运行时不靠旋转整个车体假装瞄准。

`tactics`的主要参数：update_interval（0.5秒）、formation_lookahead（1.4秒）、formation_width（0.064米）、leader_leash（0.17米）、repath_delta（0.028米）、suppress_seconds（2.4秒）、bound_distance（0.29米）、bound_timeout（5.5秒）、peek_seconds（到角落后0.85秒）、hide_seconds（0.65秒）、pinned_threshold（0.84）、tank_preferred_range（0.56米）、tank_danger_range（0.35米）、tank_replan_seconds（1.5秒）、车体/炮塔转速（1.6/2.6弧度每秒）、前/侧/后装甲倍率（0.72/1/1.4）。权重与少量局部几何阈值仍在tactics.gd中，不声称完全无代码策划。

本轮没有添加外部下载素材或战术参考视频画面到游戏资源。CQB采用现有跑动、蹲姿、换弹与射击骨骼动作和实际位移，不是新增精细贴墙侧身动画。
