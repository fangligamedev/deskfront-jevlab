# LLM 输入输出与指令可视化

主游戏新对局默认三方均由 DeepSeek LLM 驱动。服务使用既有火山方舟配置、并发及每局请求预算；没有配置、网络失败或预算耗尽时，控制台明确提示状态，紧急自保属于本地逻辑。旧版语义测试夹具继续显式使用游戏 AI。自定义关卡保留创作台选择的控制方式。

## 操作

东线和游戏工具栏提供蓝色 **打开 Debug Version** 按钮，将路径与 LLM 日志放到独立滚动的右侧面板，保留同一对局。再次点击或按关闭返回。详见 [视图与全屏布局](VIEWS.md)。

- 左下角「LLM 输入 / 输出」常驻打印本局调用。选择跟踪单位可以只看一名士兵；取消「跟随最新返回」可固定一条记录对照。
- IN 是实际发给模型的 user 战场状态，展开可看 system 和完整参数。OUT 是模型实际返回的行动、显式理由；原始响应可展开。ACK 包含 `command_id`、校验决定、引擎回执、拒绝和过期原因。
- 游戏画面下方勾选 **Debug Visualize · 指令可视化**。阵营色实线与箭头是待走路线；1 表示下一路点，后续编号按实际执行顺序（过密时隐藏重叠编号，不改变路线）；金色虚线是已走轨迹；红虚线指向当前攻击目标。单位筛选同时限制世界调试图层。
- 下方单位卡显示下一点三维坐标、最近已接受指令及理由、当前模型请求状态、掩体、目标、压制和阻塞。最近模型建议与实际执行指令分别标注，避免把拒绝/延迟的建议当作已经执行。
- 新开局清空日志选中项和轨迹。完整日志弹窗保留历史局次。Debug 开关跨重开保留；不接管士兵，不改变寻路和战斗规则。关闭后停止采样，并移除图层和高频路径载荷。

日志展示模型显式给出的简短 `reason`，不生成或声称展示模型内部思维过程。`wait` 不制造游戏命令；它的返回保留在 OUT，实际路径和已接受命令继续反映引擎状态。

## 实现

`debug_visualize.gd` 为不接收鼠标输入的 Godot CanvasLayer，逐帧把真实世界坐标投影到当前镜头；普通路线来自单位 `route`，楼梯来自三维 `garrison_path`。每 150ms 采样实际位置，移动超过 5mm 才记录，每单位最多 100 点。场景更换自动释放数据。图层只读，不自行规划或简化路径。

控制命令：`{"action":"debug_visualize","value":true,"unit":"green-1"}`。空 `unit` 显示全部；该命令仅策划/玩家控制台可用，Agent/LLM 不能调用管理动作。`state.debug_visualize` 上报开关、过滤单位、真实路点/轨迹与最近已接受命令。

调用记录复用既有 SQLite 日志。`GET /api/lm/calls?run=<run_id>&unit=<unit_id>` 限定局次/单位，完整内容按 ID 获取；页面每 1.5 秒更新，固定记录不跳走。模型文本通过 `textContent` 显示，沿用服务端密钥脱敏。不会把大型请求塞进每 350ms 的主状态刷新。

## 参考

Riot 官方《[/dev: WASD’s Ranked Release](https://www.leagueoflegends.com/en-sg/news/dev/dev-wasds-ranked-release/)》的 Pathfinding 段落公开了寻路 Debug Visualization 示例。本次参考其可切换路径诊断思路；尚未确认用户记忆中的具体 GDC 场次，没有声称复刻该场演讲的实现。

## 验证

- `godot --headless --path . --script tests/debug_visualize_contract.gd`：默认 LLM、权限不变、真实有序路点、楼梯高度、采样上限、拒绝隔离、回退来源及开关清理。
- `python3 -m unittest discover -s tests -p 'test_*.py'`：接口校验、当前局次日志过滤和既有调用日志/权限/创作台回归。
- `DEBUG_TEST_URL=http://127.0.0.1:8786 node tools/debug_browser_qa.cjs`：独立本地服务、真实 WebGL 和真实配置的 LLM，点击开关、筛选、固定记录、重开以及实际指令关联。测试服务应限制请求预算，不能伪造模型返回。
- Forge build / release：资源、导入、语义、运行与真实 Web 导出门禁。

本次验收先记录了火山方舟 `provider_account_overdue` 错误，随后服务恢复；最终真实在线复测收到模型决策及引擎接受回执。错误返回不冒充战术决策，成功响应会清除恢复前的供应商错误提示。最终调用 ID、原始来源、简短理由与对应回执记录在 `docs/evidence/debug-visualize/web.json`。
