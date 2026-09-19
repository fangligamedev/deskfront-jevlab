# TypeSafe JEV 战斗控制

2026-09-19，本地工作版已接入官方 `POST https://api.typesafe.ai/v1/systemone`，固定模型 `jev-1.13.0`。源码随 main 更新；未创建或移动历史版本标签。

## 启动

把以下配置写入本机 `.env`（已被 Git 忽略）：

```dotenv
DESKFRONT_LM_PROVIDER=typesafe_jev
TYPESAFE_API_KEY=填入自己的密钥
TYPESAFE_MODEL=jev-1.13.0
```

运行 `python3 tools/run.py`，已有服务需要重启以读取配置。打开 http://127.0.0.1:8768/，点击 **开始 TypeSafe JEV 对战**。三方步兵独立决策；红方坦克驶入完成后同样由 JEV 指挥。在任何阵营下拉框可切换游戏 AI、当前模型 AI、玩家和外部 Agent。

切回 DeepSeek：把 `DESKFRONT_LM_PROVIDER` 改为 `volcengine_ark` 并重启，保留原有 `ARK_API_KEY`、模型等配置。当前没有在同一局里按阵营混用两家模型；四种控制权切换仍然可用。

## 决策流程

JEV 是结构化判断模型，不是聊天生成接口。服务把同一单位的真实状态、目标、敌友、掩体和近期动作发送给它：

1. `tactic`（Choice）：从具体候选指令选择下一动作，返回选择、概率分布和置信度。
2. `danger`（Noul）：判断当前是否需要立即保护，返回概率，保留作观测指标。
3. `posture`（步兵 Choice）：自动、趴下、蹲姿或站姿；坦克不发送此题。

候选覆盖占旗、短途推进、掩体、绕侧、撤退、守住、指定目标攻击、手雷、接管/弃用反坦克炮、进驻/撤离建筑、继续当前任务。以 `available_actions`、目标阵营、武器与距离过滤；每一候选在代码里对应明确指令。不能从模型回答创造管理命令、任意坐标或目标 ID。等待继续现有任务，不产生新引擎命令。

选择后的命令再经过既有动作校验、控制权、观察时效、旗点归属与 Godot 校验；底层导航、弹道、自动射击/换弹、紧急自保仍由游戏执行。危险概率不会直接替代引擎保命规则。各题并行独立，姿态与战术是否最佳仍需实战评测。

理由文字是代码根据 JEV 选项与真实概率生成的摘要，不冒充模型自由文本。实测概率展示值与明确选择偶有轻微不一致，适配器忠实使用其合法 `choice`，保留原概率，不静默改选。

## 日志与凭证

状态接口返回 `provider=typesafe_jev`、`display_name=TypeSafe JEV`；内部控制值继续使用 `lm`，兼容原有 Agent 契约。决策来源为 `typesafe_jev`，错误回退仍明确标为 `local_fallback`。

日志窗口及页面实时输入输出支持两种请求格式：JEV 的 state/questions，DeepSeek 的 messages。JEV 保存原始响应、解析后的判断、候选与概率、代码映射后的游戏指令，以及引擎回执。由此可区别“模型返回”“指令被执行”“战斗效果”。

凭证只在服务端 `.env` 中读取，通过 Authorization 发送至官方固定 HTTPS 主机；拒绝重定向，前端不会获得凭证。本机配置文件权限 0600。两家模型密钥都经过日志脱敏，源码不包含真实 Key。

## 创作沙盒边界

本次 JEV 接入覆盖战斗控制。自然语言关卡生成及叙述式战报继续使用独立的 Ark/DeepSeek 文本配置，UI 分别显示战斗与文本模型。JEV Key 不会发往火山，Ark Key 不会发往 TypeSafe。火山账户欠费只影响该文本功能，不影响 JEV 对战。没有把 JEV 伪装成 Chat Completions 模型。

## 实测与测试

真实无头 Godot 对局，地图 crossroads，三方 JEV，主动触发可见坦克增援：74.6 秒红胜，88 次射击、3 处破坏，剩余 3 名步兵。调用账本记录 94 次请求，75 个引擎成功回执、4 个拒绝、15 个因单位死亡/时效/局次等变化丢弃；坦克和初始九兵均有真实模型决策。模型选择包括短途推进、占旗、掩体、攻击、守住与接管反坦克炮。

浏览器又完成一局 88.7 秒对抗，108 次射击，红方获胜；页面显示 JEV 身份，日志实查 state/questions、原始回答、概率与代码映射。该局暴露的 0.01 概率排序兼容问题已修复并增加回归测试。

这些是接入验收，不是模型胜率排名。三方同用 JEV、红方有坦克，不能据此判定红方或 JEV 普遍更强；掩体利用和长程协作仍有优化空间。

修订后追加 40.6 秒真实验证：7 名步兵存活、27 次射击、2 处破坏，九兵与坦克均获得 JEV 指令；出现 2 次网络/超时并回退到明确标记的本地自保，未出现该概率排序拒绝。Python 52 项与 Godot semantic 113 项通过。

测试与精简证据见 [jev-integration.json](evidence/jev-integration.json)。完整本机报告位于 `output/v06/jev-first-trials.json` 与后续修订验证文件，调用原文保存在 `output/lm-calls.sqlite3`，不提交个人对局数据库。

## 官方依据

- [模型介绍](https://docs.typesafe.ai/introduction)
- [HTTP 契约](https://docs.typesafe.ai/api)
- [模型版本](https://docs.typesafe.ai/models)
- [Choice 结构](https://docs.typesafe.ai/primitives/choice)
