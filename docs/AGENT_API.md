# Agent 状态与动作接口 v1

默认地址 `http://127.0.0.1:8768`。当前是通用本地接口，**没有实现或验证 Safetype.ai / Jev 的私有 API**。真实接入需要提供其公开 SDK/协议、凭据与调用预算；替换 `tools/agent_example.py` 的决策函数即可保持游戏执行层不变。

## 所有权

先在控制台将指定阵营设为“外部 Agent”。其他阵营可以同时由游戏 AI 或玩家控制。Agent 只能操作被分配的阵营及其存活单位，不能重置、改规则、调用增援或抢走控制权。

## 读取状态

`GET /api/state` 返回 `engine_live`、快照年龄、`state`、排队数量及近期回执。离线时保留最后一帧但标记非实时，Agent 不应继续决策。

快照含 `run_id`、`tick`、时间、暂停、胜负、单位坐标/状态/血量/压制/弹药/目标位置、阵营所有权、分数、掩体/障碍、预约、导航版本、AI候选战术和事件。坐标为 `[x,z]` 米，桌面高度固定，所有数值由 Godot 实际产生。

首版快照为全局完全信息，无战争迷雾；不用于声称与只能看屏幕的 Agent 公平对比。未来可在此接口前增加阵营可见性过滤，而保留动作合同。

## 动作

`POST /api/agent/command`：

```json
{
  "action": "move",
  "faction": "green",
  "unit_ids": ["green-1", "green-2"],
  "position": [0.50, 0.35],
  "run_id": "从最近状态读取",
  "seen_tick": 120
}
```

HTTP 202 仅表示排队，返回 `id`。轮询 `GET /api/result/<id>`，只有 `accepted: true` 才表示 Godot 执行了动作；错误含 `authority_denied`、`stale_run`、`stale_observation`、`invalid_unit_authority`、`position_out_of_bounds`、`invalid_target`。

允许动作：`move`（必须给 position）、`capture`、`cover`、`flank`、`retreat`、`hold`、`attack`（必须给敌方 target_id）。`unit_ids` 省略或空数组表示整队。`seen_tick` 必须与当前引擎 tick 相差不超过 300；重开后旧 `run_id` 拒绝。

**move、cover 等是战术目标，不是瞬移。** 经过真实寻路、战斗状态机和动画执行。寻路将合法桌面坐标投影到最近可达格；高物件不可穿越。

## 策划端动作

`POST /api/command` 除上述战术动作，还允许 `control`（mode）、`pause`（value）、`speed`（0.25–3）、`camera`（office/battle/top）、`reinforce`、`reset` 和 `config`。`config` 允许 damage、speed、accuracy、cooldown 四项，并钳制合理范围。生产环境应将管理员与 Agent 端点分别认证；本版只面向本机。

运行示例：

```sh
# 打开网页，将绿色阵营切到 Agent
python3 tools/agent_example.py --faction green --once
# 持续实验
python3 tools/agent_example.py --faction green
```

`GET /api/schema` 查询动作清单。`GET /api/health` 查询服务与引擎状态。`POST /api/sync` 是游戏内部同步端点，不供模型冒充游戏调用。运行数据记录到 `output/session.jsonl`，训练使用前应按 run_id 与回执连接状态/动作，而非把排队指令当成已执行动作。
