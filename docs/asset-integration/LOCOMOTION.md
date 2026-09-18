> 这是资源任务原始交接记录。当前用户已授权集成，正式集成状态与验收以 [0.4.0 报告](../DELIVERY-0.4.0.md) 为准；下文的“待确认/独立预览”描述的是集成前阶段。

# 横向蹲行修正交付 · 2026-09-18

## 结果

独立预览：`http://127.0.0.1:8773/locomotion.html`。近景视频、可操作 Web 导出、Blender 源文件和回归证据已经更新。主游戏没有替换资产。

原先 `cover_peek_left/right` 是原地蹲姿探身，控制器却用 `move_and_slide()` 每秒平移 0.12 米；身体位移与脚步没有关系。这条平移路径已删除。

现在 `cover_shuffle_left/right` 是有明确落脚点的有限步伐，前脚先迈、后脚再收。身体由动画 Root 位移驱动，运行时双骨 IK 根据接触时间锁住支撑脚。足底朝向保持不变，膝盖位置按腿长重新求解。旧战斗演示在横移完成之后再触发探身和射击。

## 动作与控制契约

- 一个完整横步 0.033 米，动画 32/30 秒；模型导入比例保持 0.075。
- 前脚摆动位于归一化时间 0.06–0.44，后脚 0.55–0.93，其余时段保持接触。
- 身体 Root 使用五次平滑曲线；抬脚约 7.5 毫米。
- 接触表和循环策略来自 `data/gait.json`。横步是有限动作，不循环播放原地动作。
- 不足一步时同步缩短 Root 位移和落脚距离，12 毫米短步已验证。到达位置容差 0.5 毫米。
- 停止或切换探身时先完成当前一步，最长约 1.07 秒，再收回移动状态。不会停在半空继续平移。
- 迈步前用角色胶囊扫过整个步长，静态掩体阻挡时不开始这一脚。
- AnimationTree 在物理更新中手动推进，顺序为：采样动作 → 提取 Root → 角色碰撞移动 → 求解膝盖与脚接触 → 更新武器。
- `plant_leg()` 显式使用求得的膝盖位置设置小腿变换，避免读取尚未更新的子骨缓存而拉长腿骨。

## 验证

`evidence/locomotion/qa.json`：10 项通过，覆盖左右完整步、抬脚高度、往返落点、中途停止、静止不漂移、短步、墙体碰撞、接触点漂移及腿长保持。

同一测试运行中：

- 双脚最大抬起约 7.6 / 7.6 毫米。
- 支撑脚骨接触点的逐帧位移低于 0.5 毫米验收线。
- 大腿、小腿骨段长度变化低于 0.5 毫米验收线。
- 12 毫米短步到达误差低于 0.5 毫米。

`before-qa.json` 使用保留的旧控制器执行原地蹲姿横移，测得每帧约 1.996 毫米接触点位移，未通过同一 0.5 毫米门槛。该对照验证本次检查能够检出原问题。

`web-qa.json`：5 项通过，真实浏览器 A、D、S 输入、脚接触约束和浏览器错误检查。等待条件使用游戏状态，避免低帧率浏览器的墙钟时间与游戏时间不同造成误判。

`integration-qa.json`：12 项原有战斗检查通过，包括 22 个动作、50 骨蒙皮、前进 Root Motion、掩体射线、18 刚体布娃娃、爆炸破坏、分层特效与音效触发。

`after.mp4` 是 21 秒 Godot 原生录制，不是离线动画渲染。保留 first、midstep、trailing-step、last 帧以及浏览器截图用于检查。镜头近裁面 0.005、远裁面 30，光源参数与旧预览相同。

资源通过 Forge GLB 骨骼审计及严格许可校验。nisu / Quaternius CC0 来源、Blender 衍生源文件及生成脚本保留，模型哈希已更新。

## 当前边界

此次验收针对平整桌面、固定朝向、静态掩体附近的横向蹲行。前进、奔跑、爬行及复杂地形尚未进行同等级的脚接触验收；不把本轮结果视为所有动作均无滑步。移动障碍物在步中突然插入、坡面和台阶也需后续专门处理。

接触漂移的自动测量对象是脚骨的世界坐标接触锚点，配合录像审看；不是逐像素测量整个蒙皮鞋底。

## 集成与复现

需一同集成：

- `assets/models/toy-soldier.glb` 及现有导入比例设置。
- `data/gait.json`、`scripts/toy_actor.gd`。
- `tools/build_soldier.py`、`source/toy-soldier-retarget.blend` 作为可编辑源文件。
- 调用方通过 `cover_target` 请求局部左右移动，通过 `stop_cover_move()` 停止，通过 `play()` 请求动作切换；不要额外平移角色或在未收步时强制旋转。

预览独立场景为 `locomotion_review.tscn`，专用 Web preset 为 `Locomotion Web`。默认 `Web` preset 仍导出沙盘。

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path combat-review-v2 --script tools/locomotion_qa.gd --fixed-fps 60
node combat-review-v2/tools/locomotion_web_qa.cjs
/Applications/Godot.app/Contents/MacOS/Godot --headless --path combat-review-v2 --export-release 'Locomotion Web'
```

Web 检查要求 8773 静态服务器正在提供 `combat-review-v2` 目录。
