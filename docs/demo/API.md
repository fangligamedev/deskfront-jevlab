# 演示导演接口

服务端口与当前游戏页面一致，默认 `http://127.0.0.1:8768`。同一个端口只控制一个活动引擎。

## 载入演示

先用 Studio 生成或导入合法场景，之后请求 `POST /api/studio/play`：

```json
{"scenario_id":"scenario-id","player_faction":"none","opponent_mode":"game_ai","demo":true,"demo_driver":"model","instance_id":"current-instance","run_id":"current-run"}
```

`opponent_mode` 为 `game_ai`、`lm` 或 `agent`。`demo_driver` 可选 `model` 或 `local`。载入会开始新局，等待命令回执及新 run_id。

## 观察与执行

`GET /api/state` 的 `state.demo` 包含 `phase`、`running`、`clock`、`participants`、`human_count`、`completed`、`steps`、`deployed`、`timeline`。阶段依次为 `building → deploying → ready → battle → finished`。

`steps` 是当前合法步骤：`place_cover`、`deploy_unit`、`start_battle`。不接受任意脚本或未公开对象 ID。

`POST /api/demo/choose` 请求体包含当前 `instance_id` 与 `run_id`。模型返回经过校验的 `step_id`、`reason`、`call_id`、`provider`、`model`；此时只是选择成功，尚未执行。导演最多每秒一次、每局 64 次请求。

向 `POST /api/command` 提交：

```json
{"action":"demo_step","step_id":"从当前 steps 读取","instance_id":"current-instance","run_id":"current-run"}
```

这是策划控制台权限的编辑操作。读取 `/api/result/{id}` 的真实 `accepted` 回执后才能声称已执行。外部战斗 Agent 仍使用原战术权限，不能借此执行编辑命令。

暂停建场会停止导演时钟与入场。未部署/正在入场的士兵不属于战斗活跃单位。坦克增援在当前演示中会被明确拒绝，避免展示中的备用坦克提前开火。

## 复盘到下一关

调用 Studio report，取得报告 ID。再向 `/api/studio/generate` 提交 `brief` 与 `previous_report_id`。服务端从本地数据库取该报告作为 `previous_battle_analysis`，新关卡保存 `parent_report_id`。不存在的报告、不可达关卡或模型错误会失败，不用本地文字冒充模型报告。

模型原始请求、返回与校验记录位于 `/api/lm/calls`，导演单位标识 `demo-director`。实际编辑回执与引擎事件位于演示时间线导出。Key 只留在服务端。
