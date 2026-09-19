# 创作与复盘 API

本地服务默认 `http://127.0.0.1:8768`。原有 `/api/state`、`/api/agent/command`、四种控制方式继续兼容。新接口使用 JSON；生成任务不会直接更换玩家当前关卡。

| 接口 | 用途 |
| --- | --- |
| GET `/api/studio/catalog` | 可用地形、能力、约束和示例 |
| GET `/api/studio/schema` | 关卡 JSON Schema |
| GET `/api/studio/status` | 模型配置状态、任务、关卡与报告索引 |
| POST `/api/studio/generate` | `{"brief":"希望玩家体验的战术"}`，返回异步 job |
| POST `/api/studio/import` | `{"scenario":完整关卡JSON}`，校验外部模型或人工设计 |
| GET `/api/studio/jobs/{id}` | `running / complete / error`；成功包含 artifact_id |
| GET `/api/studio/scenarios/{id}` | 编辑用 spec、编译后的 level 和真实 validation |
| POST `/api/studio/play` | 载入已验证关卡，返回游戏命令 id |
| POST `/api/studio/analyze` | `{"run_id":"当前局次"}`，当前态势分析任务 |
| POST `/api/studio/report` | `{"run_id":"当前局次"}`，仅结束后的战后报告任务 |
| GET `/api/studio/reports/{id}` | 模型 analysis 与对应引擎 evidence_input |

play 请求示例（instance_id / run_id 必须读取当前 `/api/state`）：

```json
{"scenario_id":"从已保存关卡读取","player_faction":"green","opponent_mode":"lm","instance_id":"当前实例","run_id":"当前局次"}
```

player_faction 可为 green / blue / red / none；opponent_mode 可为 game_ai / lm / agent。none 表示全部旁观。返回 202 仅表示命令排队，继续查询 `/api/result/{id}`。引擎成功加载后，`state.scenario.id` 对应关卡，run_id 更换，paused=true。随后发送 `pause=false` 开局。

运行中的 Agent 仍使用有时效、控制权校验的单兵动作协议。创造场景的权限与战斗动作分离，逐兵 LLM 不能靠输出 scenario 动作修改地图。

命令行：

```sh
python3 tools/studio_cli.py status
python3 tools/studio_cli.py generate --brief '利用侧路掩护推进的中央夺旗关卡'
python3 tools/studio_cli.py import --file data/studio-example.json
python3 tools/studio_cli.py play --id <scenario_id> --player green --opponent lm
python3 tools/studio_cli.py analyze
python3 tools/studio_cli.py report
python3 tools/studio_cli.py get --kind reports --id <report_id>
```

CLI 和 HTTP 接口都不会自动把报告当作指令执行。模型角色和日志 API 见 [调用日志](../LLM_CALL_LOG.md)。
