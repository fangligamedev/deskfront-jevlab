# 东线编辑器与 Agent 接口

坐标沿用米制 `[x,z]`，东方为 +X。Godot 仍是唯一权威；HTTP 返回排队不等于已经执行，请读取 `/api/result/{id}` 的回执。

## 编辑器动作（console）

发送到 `POST /api/command`，携带当前 `/api/state` 的 `instance_id` 与 `state.run_id`：

```json
{"action":"eastfront_start","backend":"model","mode":"game_ai","seed":19,"instance_id":"当前会话","run_id":"当前局次"}
```

开启新东线，`backend` 为 `local/typesafe_jev/volcengine_ark/dual_brain`（兼容旧 `model`，表示当前战斗模型），绿色控制 `mode` 为 `game_ai/player/lm/agent`。原场景会重载并产生新 `run_id`，旧模型决策自动失效。未配置模型时可用本地模式；构筑模型缺席会触发明确后备。

```json
{"action":"eastfront_propose","sequence":7,"template":"crossfire","provider":"external-editor","instance_id":"当前会话","run_id":"当前局次"}
```

只选择当前请求提供的模板。`provider` 是审计说明，不是凭证或认证身份；引擎检查当前 `sequence`、合法模板、占用安全和可达性。返回 `stale_frontier_request/unknown_frontier_template/occupied_frontier/frontier_unreachable` 时没有提交该防线。预览构筑完成后才进入战斗导航。

```json
{"action":"eastfront_follow","value":true,"instance_id":"当前会话","run_id":"当前局次"}
```

控制自动跟随。手动平移自动退出跟随。以上三个编辑器动作不能通过 `/api/agent/command` 的战术权限执行。

## 战术 Agent

先用 console 把绿军切换到 `agent`，再按已有协议提交 `capture/move/cover/flank/retreat/hold/attack/grenade/posture` 等合法动作。例如：

```json
{"action":"capture","faction":"green","unit_ids":["green-1"],"run_id":"当前局次","seen_tick":1500}
```

发往 `POST /api/agent/command`。具体动作必须以该单位最新 `available_actions` 为准；新补员 ID 是 `green-recruit-N`，不要硬编码只有 green-1/2/3。已回收或阵亡单位不能接受指令。

JEV 和 DeepSeek 使用内部兼容控制值 `lm`，每个单位仍由独立的观察—模型—验证—执行回路控制；模型失败时的本地自保会标明 `local_fallback`。前沿导演只选布局，不直接操纵士兵。

## 新状态

### 战斗模型选择

`GET /api/lm/status` 的 `providers` 列出服务端预配置模型 ID 与 configured，不包含 Key。`POST /api/lm/provider` 接受：

```json
{"provider":"typesafe_jev","instance_id":"当前会话","run_id":"当前局次"}
```

可选 `typesafe_jev/deepseek_logprobs/volcengine_ark`。先把所有 `lm` 阵营交还 `game_ai` 并等待引擎回执；控制权未释放时返回 `release_model_control_first`。成功后给所需阵营设置 `mode:lm`。旧回复通过 provider epoch 丢弃，旧排队指令取消，不重置本局预算。会话不匹配、旧局次、模型未配置均拒绝。Key、模型 ID 和目标 API 地址不能由前端请求指定。

`GET /api/state` → `state.eastfront`：

| 字段 | 含义 |
|---|---|
| enabled / direction / axis | 是否东线、east、+x |
| seed / backend | 模板种子和生成来源策略 |
| cleared / active_sector | 已夺取段数、当前目标段号 |
| request | sequence、index、age、合法 candidates；无请求时为空 |
| chunks | 每段 index、phase、template、source、elapsed |
| built / retired / peak_chunks / max_chunks | 构筑、回收、在场峰值与上限 |
| recruits | 累计后方补员数量 |
| hold_seconds / follow / stopped | 本点守旗时间、镜头跟随、远征是否结束 |
| events | 最近 80 条真实引擎事件 |

区块状态：`building → ready → combat → cleared → retired`。`retired` 通过事件记录，区块从快照数组中移除。部署状态 `parked` 的前方守军不能被当作现役攻击目标。`objective.flag.mode` 为 `eastfront_sector`；该模式不提供原中央夺旗的“对方即将一局获胜”告警。

事件包含 `generation_requested / generation_rejected / construction_started / chunk_committed / sector_activated / sector_captured / rear_reinforcement / rear_disengaged / chunk_retired`。原射击、命中和破坏日志保持不变。

## 调度边界

服务端 `EastfrontDirector` 观察真实引擎请求，在后台调用模型；切换网页视图不影响生成。每局最多 128 次防线模型选择；同一序号最多调用一次，网络请求最多等待 5 秒。401/402/403 类拒绝或欠费会停止本局生成模型重试，由引擎在期限后选本地方案。

引擎等待期限为 14 秒有效等待时间（除以游戏倍率，暂停不累加），构筑动画和守点用游戏时间。回复前后均检查局次与请求序号，提交后仍等待引擎回执。战斗模型使用独立的 `DESKFRONT_LM_MAX_REQUESTS` 决策轮数预算，不因进入下一扇区偷偷清零。

服务仍只监听 localhost。没有增加任意文件路径、代码执行、远程资产下载或跨域控制入口。

快慢脑调度、施工状态与波次接口见 [快慢脑说明](DUAL_BRAIN.md)。
