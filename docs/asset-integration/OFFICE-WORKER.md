> 2026-09-19：Business Man 已应用到主游戏 `scenes/main.tscn`，旧 Casual 坐姿版本保存在 `source/archive/office-worker-casual/`。当前验收见 [资源应用报告](../ASSET-APPLICATION.md)。

> 这是资源任务原始交接记录。当前用户已授权集成，正式集成状态与验收以 [0.4.0 报告](../DELIVERY-0.4.0.md) 为准；下文的“待确认/独立预览”描述的是集成前阶段。

# 办公人物替换

本轮按用户要求，把独立沙盘预览中的初模换成 **Quaternius / Business Man**。原模型属于 Ultimate Modular Men Pack，作者及模型发布页均标注 CC0，可修改并随开源工程分发。

来源：
- 作者：https://quaternius.com/packs/ultimatemodularcharacters.html
- 模型：https://poly.pizza/m/JFrLIKqvCH
- 原始 GLB：https://static.poly.pizza/e599abbe-7d73-488c-9d7e-3ead281e705c.glb

模型直接下载自作者在 Poly Pizza 发布的资源。Google Drive 下载超时，未作为实际下载来源。原始包带 24 个动画，本轮坐姿操作电脑是另行制作的动作，不把它宣称为作者原带的打字动作。

## 实际适配

- 保留完整蒙皮、五官、发型、服装及 62 骨骼结构；移除模型附带的非人物辅助物体。
- 按站立 1.72 m 归一化，场景原点为 (-1.12, 0, 0.57)。骨盆、屈膝和脚部按现有椅子与地面布置。
- 采用已确认的短发男性西装造型，保留浅色衬衫和领带，保持粗糙材质。环境照明不变。
- 原创 `office_typing`：8 秒循环，运行速度 0.6，即约 13.3 秒一个周期。左手在键盘操作，右手在鼠标上微动，手指弯曲与轻微头部变化；不是动捕动作。
- 主游戏默认办公室视角使用新人物，可用策划台「办公室」按钮查看。

## 文件

- 引擎资产：`assets/models/office-worker.glb`
- 原始模型：`source/latest/office-worker/business-original.glb`
- 可编辑 Blender：`source/latest/office-worker/office-worker.blend`
- 重建脚本：`source/latest/tools/build_office_worker.py`
- 动作说明：`source/latest/office-worker/animation.json`
- 原初模 `worker.glb` 保留，运行时已不加载。

## 验证

`evidence/office-worker/qa.json`：7 项原生检查，包括蒙皮骨架、动作播放/循环、脚骨位置、两只手腕高度和打字位移。动作起始、中段、结束的实际截图已保存。新增模型通过原始 GLB 和 Godot 导入审计；浏览器实机检查人物近景、全景和换图。24 项严格资源许可/哈希验证通过；沙盘原生 27 项回归检查通过。本轮只更新人物和近景相关内容。

这次是人物外观与坐姿动作替换。没有新增对话、口型或人物自主活动 AI。
