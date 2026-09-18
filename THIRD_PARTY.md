# 第三方组件与来源

- Godot Engine 4.5.1：MIT，导出的 Web/macOS 程序包含 Godot 运行时。版权：Copyright (c) 2014-present Godot Engine contributors; Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur。适用 MIT 条款见本目录 LICENSE。Godot 所含其他库及字体的完整清单见 https://godotengine.org/license/ ，引擎源代码 COPYRIGHT.txt：https://github.com/godotengine/godot/blob/4.5.1-stable/COPYRIGHT.txt 。
- Blender 5.2.1 LTS：建模工具，未捆绑 Blender 程序；原创导出模型不因此继承 Blender 程序 GPL。
- Playwright 1.60.0：Apache-2.0，仅开发测试依赖，不打入运行游戏。
- Godot Forge cleanroom：用于本地计划、资源来源记录及验收；独立工程运行和重建不依赖该插件。
- 网页使用浏览器系统字体，无远程字体、广告、统计或付费模型依赖。

引擎许可证与完整版权文本已随包保存于 `docs/licenses/GODOT-LICENSE.txt` 和 `docs/licenses/GODOT-COPYRIGHT.txt`。

研究来源与实现边界见 docs/REFERENCES.md。参考图仅用于构图，不放进开源源码包或游戏资源。运行模型包含原创 Blender 资源以及经改编的 CC0 第三方资产；可编辑来源、权重和动作保留在 source/latest。

## 0.4.0 新资源

| 资源 | 作者 / 来源 | 许可与修改 |
|---|---|---|
| 玩具兵 | nisu，[Rigged lowpoly WW2 soldier](https://opengameart.org/content/rigged-lowpoly-ww2-soldier) | CC0；纯色材质、重定向、新增接触约束侧步 |
| 动作库 | [Quaternius Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html) | CC0；作者公开预览 GLB，新增根轨迹与手雷动作 |
| T2 坦克 | [Quaternius](https://poly.pizza/m/FA5daiyZQq) | CC0；归一化及独立炮塔适配 |
| 办公人物 | [Quaternius Casual Character](https://poly.pizza/m/kZ3DmIoGip) | CC0；坐姿、服装颜色及原创 office_typing |
| 步枪/手枪 | [Pichuliru Flat Guns West](https://opengameart.org/content/cc0-flat-guns-west) | CC0；缩放、阵营纯色 |
| 手雷 | [Pichuliru Flat Grenades](https://opengameart.org/content/cc0-flat-grenades) | CC0；阵营纯色 |
| 爆炸图集/流向图 | [Unity VFX / Arnklit](https://github.com/Arnklit/godot_particle_flipbook_smoothing) | CC0；渲染器为本项目 MIT 改编实现 |
| 8 个新武器声音 | [Q009 Weapon Sounds](https://opengameart.org/content/q009s-weapon-sounds) | **CC-BY-SA 3.0**；音量、低频、重采样处理详见 audio-catalog.json；这些衍生 WAV 继续以相同许可提供 |
| DeskfrontUI 字体 | [Adobe / Google Noto CJK](https://github.com/notofonts/noto-cjk) | OFL 1.1；改名字体子集，保留版权与许可 |

许可正文在 docs/licenses；逐文件 SHA256 和来源在 .forge/assets.json 与 docs/asset-integration/asset-provenance.json。代码 MIT 不覆盖第三方声音的 CC-BY-SA 许可。原有程序合成音效仍为 CC0。
