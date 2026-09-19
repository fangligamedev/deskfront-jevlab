# Agent 状态与动作接口 v1

默认地址 `http://127.0.0.1:8768`。当前是通用本地接口，**没有实现或验证 Safetype.ai / Jev 的私有 API**。真实接入需要提供其公开 SDK/协议、凭据与调用预算；替换 `tools/agent_example.py` 的决策函数即可保持游戏执行层不变。

## 所有权

先在控制台将指定阵营设为“外部 Agent”。其他阵营可由游戏 AI、LM 或玩家控制。Agent 只能操作被分配的阵营及其存活单位，不能重置、改规则、调用增援或抢走控制权。

## 读取状态

`GET /api/state` 返回 `engine_live`、快照年龄、`state`、排队数量及近期回执。离线时保留最后一帧但标记非实时，Agent 不应继续决策。

快照含 `run_id`、`tick`、时间、暂停、胜负、单位坐标/状态/血量/压制/弹药/目标位置、阵营所有权、分数、掩体/障碍、预约、导航版本、AI战术阶段、原因和事件。坐标为 `[x,z]` 米，高差由 elevation / building_floor 表达，所有数值由 Godot 实际产生。

首版快照为全局完全信息，无战争迷雾；不用于声称与只能看屏幕的 Agent 公平对比。未来可在此接口前增加阵营可见性过滤，而保留动作合同。

## 动作

`POST /api/agent/command`：

```json
{
  "action": "move",
  "faction": "green",
  "unit_ids": ["green-1", "green-2"],
  "position": [0.54, 2.40],
  "run_id": "从最近状态读取",
  "seen_tick": 120
}
```

HTTP 202 仅表示排队，返回 `id`。轮询 `GET /api/result/<id>`，只有 `accepted: true` 才表示 Godot 执行了动作；错误含 `authority_denied`、`stale_run`、`stale_observation`、`invalid_unit_authority`、`position_out_of_bounds`、`invalid_target`。

当前允许 13 个战术动作：`move`（必须给 position）、`capture`、`cover`、`flank`、`retreat`、`hold`、`attack`（必须给敌方 target_id）、`grenade`、`posture`、`man_at_gun`、`leave_gun`、`garrison`、`leave_building`。设施动作必须指定一名单位，garrison 可给 floor=1/2；详细字段、可用性和状态见 [动作全集](AGENT_ACTION_STATES.md)。`unit_ids` 省略或空数组表示整队。`seen_tick` 必须与当前引擎 tick 相差不超过 300；重开后旧 `run_id` 拒绝。

**move、cover 等是战术目标，不是瞬移。** 经过真实寻路、战斗状态机和动画执行。寻路将合法桌面坐标投影到最近可达格；高物件不可穿越。

## 策划端动作

`POST /api/command` 除上述战术动作，还允许 `control`（mode）、`pause`（value）、`speed`（0.25–3）、`camera`（office/battle/top）、`reinforce`、`reset`、`map`（index）、`equip`（weapon）和 `config`。`config` 允许 damage、speed、accuracy、cooldown 四项，并钳制合理范围。生产环境应将管理员与 Agent 端点分别认证；本版只面向本机。

策划客户端从 `GET /api/state` 读取顶层 `instance_id` 及 `state.run_id`，提交 `/api/command` 时携带这两个字段。Web 页面通过 `POST /api/session`（JSON `{}`）创建并接管一个新实例，Agent 不应调用此端点；Agent 继续使用 `/api/agent/command`，按 run_id、seen_tick 和控制权校验。旧页面不能通过省略实例号接管当前游戏。

错误 `session_replaced` 表示页面所属实例已被另一页面替换；`stale_run` 表示观察对应的对局已更换；`command_timeout` 表示 10 秒未收到引擎回执。它们都不是模型拒绝生成回答。`reset`、`map` 的成功依据是跨场景保留的真实引擎回执。

运行示例：

```sh
# 打开网页，将绿色阵营切到 Agent
python3 tools/agent_example.py --faction green --once
# 持续实验
python3 tools/agent_example.py --faction green
```

`GET /api/schema` 查询动作清单。`GET /api/health` 查询服务与引擎状态。`POST /api/sync` 是游戏内部同步端点，不供模型冒充游戏调用。运行数据记录到 `output/session.jsonl`，训练使用前应按 run_id 与回执连接状态/动作，而非把排队指令当成已执行动作。

## 状态演进记录

下列按版本记录增量；当前完整合同以 [动作全集](AGENT_ACTION_STATES.md) 和 data/action-catalog.json 为准。0.6 的外层 lm 调度状态及 at_guns、building、单位 building_phase / gun_id 说明见 [LM 控制](LM_CONTROL.md)。

### 0.2.0 新增只读状态

保持schema_version=1以兼容已有客户端；增加version、viewport、camera_target、camera_size、edge_pan和combat_fx（弹道数量、效果数量、落点计数、音频事件、静音状态、各武器发射计数）。单位增加weapon、weapon_name、weapon_range、reload_remaining、melee_ready、screen_position。weapons字段返回各武器配置。原有attack指令根据兵种自动使用对应武器，火箭优先坦克，近身自动刺刀；不需要伪造一个供应商专属技能协议。


## 0.3.0 战术可观察状态

`tactical.squads[阵营]`包含phase（take_cover/suppress/bound/advance/retreat）、leader、mover、support_ids、threat、anchor、since与reason；`tactical.formations`包含活动队形锚点、目的地、wedge/column和成员；counters统计推进、绕侧、换位、坦克调整和队形更新，path_queries记录实际寻路调用。支持成员指当前静止、未换弹、未被压制、非隐蔽姿态且有射击目标的单位，不表示过去已经命中。

单位新增tactical_role、order_mode、cqb_stance、in_cover、cover_slot、cover_risk、focus_id、formation_speed；坦克有reversing和turret_yaw（相对车体的弧度）。in_cover基于实际位置，预约不等于已经到位。cover_risk是选站时多威胁启发值，不是被击杀概率。

决策source=squad_coordinator，candidates为空、confidence=0；策划台显示真实阶段与解释，不制造模型排名。外部Agent仍通过v1动作提交，掩护协调只自动接管game_ai阵营；整队move/capture/retreat复用柔性行军执行。


## 0.5.0 姿态、自保与动作目录

完整契约见 [AGENT_ACTION_STATES.md](AGENT_ACTION_STATES.md)，机器目录为 `GET /api/action-catalog`。新增 Agent `posture`（auto/stand/crouch/prone），补全 `grenade`（可给 target_id，库存/装填/压制/距离原子校验）。单位暴露 `posture`、`posture_order`、`locomotion`、`weapon_state`、`survival_reason`、`last_shot_at`、`last_shot_target`、`available_actions`、`action_counts`。四层状态彼此独立，不能仅凭旧 state 判断身体动作。

`support_ids` 现在要求近期真的开过火且当前仍可射击。`combat_fx.collision_counts` 记录真实首个碰撞类型，`destruction_count` 记录完整物件摧毁次数，掩体暴露 max_hp、damage_stage 与用于射线的 ray_size/yaw/bottom。射击由几何命中决定，掩体不再仅靠减伤概率；结构破坏后会更新射界和导航。
