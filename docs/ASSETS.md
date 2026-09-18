# 资源与配置（运行时 0.6.0）

## 当前运行资产

| 资产 | 用途 | 编辑来源 |
| --- | --- | --- |
| toy-soldier.glb | 三阵营共用，50 骨骼；材质区分 | source/latest/toy-soldier-retarget.blend |
| tank.glb | T2 履带和独立炮塔 | source/latest/tank-original.blend |
| rifle / pistol / rocket / grenade.glb | 手部武器与投掷物 | source/latest 下相应原稿 |
| antitank-gun.glb | 推行、部署与射击炮组 | source/latest/antitank-gun.blend |
| 两层小楼构件 | 两层火力位、楼梯、可破坏组件 | source/latest/tactical-building.blend 与 building-components.json |
| office-sandbox.glb | 扩大办公室桌面 | source/latest/sandbox-generated/office-sandbox-editable.blend |
| office-worker.glb | 62 骨骼慢速打字角色 | source/latest/office-worker/office-worker.blend |
| sandbag.glb | 沙包 | source/blender/generated/sandbag.blend |
| 特效图集与 shader | 枪口、尾烟、爆炸 | assets/vfx 与来源记录 |
| 武器声音 | 分武器音效 | source/latest/q009、tools/build_audio.py |
| DeskfrontUI.otf | 中文 HUD | source/latest/fonts |

运行路径均在 assets/。当前原稿保留在 source/latest/；历史版本生成器和原稿在 source/blender/，不能覆盖当前资源。详细动画目录见 [animation-catalog.json](animation-catalog.json)，实际可调用状态见 [动作契约](AGENT_ACTION_STATES.md)。

## 坐标与导入

游戏使用米，Godot +Y 向上、-Z 向前。保留 toy-soldier.glb.import 的 root_scale=0.075 和 apply_root_scale=true，不再叠加缩放。身高约 0.135 m；Actor 根运动负责位移。

坦克适配器将原始 -X 朝向归一为游戏 -Z，炮塔保留变换。火炮使用 0.62 运行比例；小楼每层约 0.19 m。两者的尺寸、来源与碰撞边界见 [设施资源](ASSET_EQUIPMENT.md)。地图/桥面/楼层存在高度差，不能把所有单位固定到同一高度。

## 数据配置

| 文件 | 内容 |
| --- | --- |
| data/battle.json | 阵营、武器、伤害、弹匣、战术和胜负 |
| data/sandbox-maps.json | 地图、出生点、目标、旋转物件、建筑与炮位 |
| data/action-catalog.json | 命令与四层动作状态 |
| data/gait.json | 侧步根轨迹和接触相 |
| docs/animation-catalog.json | 动画片段、来源与时长 |
| .forge/assets.json | 运行资产许可、来源、哈希 |
| docs/asset-integration/asset-provenance.json | 逐文件集成记录 |
| docs/asset-integration/equipment-provenance.json | 建筑与火炮原稿记录 |

## 编辑与重建

1. 先检查原始资源许可。
2. 编辑 source/latest 对应原稿或生成脚本。
3. 导出 GLB，按脚本指定目标检查后更新 assets；保留源文件和导入设置。
4. Godot 重新导入，检查骨骼、动画、碰撞、射界与尺度。
5. 运行 `python3 tools/project.py record-assets` 更新资源哈希；再执行项目与行为检查。

Blender 脚本使用 `blender -b --python <脚本>`。音频脚本需要 ffmpeg，字体处理需要 fonttools。不同脚本的导出目标不同，执行前看脚本；不要把 `models` 命令当成重建全部当前美术。

## 许可

代码 MIT 不覆盖所有素材。模型/动作主要 CC0，Q009 衍生声音 CC-BY-SA 3.0，字体 OFL 1.1。[第三方声明](../THIRD_PARTY.md) 与 [资源许可](../assets/LICENSE.md) 是发布依据；许可全文在 docs/licenses/。

参考图片只用于构图研究，不进入源码包或游戏。
