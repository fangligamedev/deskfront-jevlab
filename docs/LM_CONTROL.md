# DeepSeek LLM 独立队员控制（0.6.0）

## 当前能力

顶层和每个阵营均可选择 `game_ai`（游戏 AI）、`lm`（火山方舟 DeepSeek）、`agent`（外部 Agent）、`player`（玩家）。LLM 对每个存活单位单独请求、单独维护最近两条意图；新增坦克也作为独立单位加入。没有用一条整队模型回复伪装为九个智能体。

模型只决定战术意图。Godot 持续负责路径、根运动、瞄准、射击、装填、掩体查询、压制、自保与破坏；不会等待模型而暂停战斗。状态目前完全可见，没有战争迷雾。

## 本机配置

从 `.env.example` 复制为 `.env`（已忽略），设置 `ARK_API_KEY` 和 `DESKFRONT_LM_MODEL`。也可把 `DESKFRONT_LM_ENV_FILE` 指向已存在的外部 dotenv 文件，仅复用其中的 `ARK_API_KEY`，不复制其他工程配置或改动原文件。

```dotenv
DESKFRONT_LM_ENV_FILE=/absolute/path/to/existing-project/.env
DESKFRONT_LM_MODEL=deepseek-v4-flash-260425
DESKFRONT_LM_INTERVAL=3
DESKFRONT_LM_MAX_REQUESTS=600
```

本轮已使用用户指定工程的凭证完成真实火山方舟调用。上面的模型 ID 是本轮实际使用的配置，并非声称所有账号都有该模型；其他环境应填写其已开通的模型/Endpoint ID。

运行 `python3 tools/run.py`。控制服务也可 `python3 tools/server.py --lm-env /path/to/config.env`。Key 仅在 Python 服务端读取，发往 `https://ark.cn-beijing.volces.com/api/v3/chat/completions`；拒绝重定向，不下发至浏览器或 Godot。公开状态只有是否配置、模型名称、调用计数和战术记录。导出包不包含本机 `.env`、`.secrets` 或外部凭证。

接口依据：[火山方舟 Chat API](https://www.volcengine.com/docs/82379/1494384?lang=zh)、[官方 SDK 的服务地址与 API Key 用法](https://www.volcengine.com/docs/82379/1795150)。本轮使用 Chat Completions，JSON 输出、关闭 thinking，未接入另一个厂商的同名模型。

## 一次独立决策

1. 读取当前单位、队友、敌人、掩体、目标、武器规则和最近两条意图。
2. 在服务端异步调用模型。默认并发 3，每单位上次完成后约 3 秒再评估；因此不会每帧调用九个模型。
3. 验证 JSON 字段、动作白名单、姿态、目标阵营、坐标与当前可用性。
4. 仅向该单位提交动作。绑定 `run_id`、原观察 `seen_tick`、`control_epoch` 与唯一 `unit_id`。
5. 等待 Godot 回执。UI 明确区分请求已排队与引擎已接受；接受也不保证未来一定到达或命中。
6. 游戏本地自保可中断危险推进。重伤/强压制期间拒绝 LLM 继续进攻或要求起身，撤离会清除追击目标，防止攻击追击覆盖逃跑路径。坦克保留低血与近距离反坦克威胁的紧急脱离。

玩家点选/框选或切换模式会改变控制权版本；LLM → 玩家 → LLM 也不能复用旧回复。局次变化、死亡、暂停、观察超过 300 tick 或离线均使返回失效。切回游戏 AI 后恢复协调器。

## 可调用动作与状态

引擎动作全集在 [AGENT_ACTION_STATES.md](AGENT_ACTION_STATES.md)，机器目录为 `GET /api/action-catalog`。LLM 可选择相同 13 个战术命令；另有 `wait`，仅保留现有意图，不伪造引擎命令或回执。

步兵可以在单条 LLM 移动等命令中附 `posture`，表达“趴下爬过去”；校验失败不会部分改变姿态。坦克不接受姿态或手雷。所有单兵指令保留队友自己的目标、路线与意图。

| 意图 | 含义 |
|---|---|
| `survive` | 找保护、降低暴露，优先活下来 |
| `support` | 掩护友军；是否真有火力由实际射击状态决定 |
| `advance` | 安全条件下推进 |
| `flank` | 侧翼位置与绕侧 |
| `engage` | 交战、反装甲、压制 |
| `withdraw` | 脱离与撤退 |
| `capture` | 占领目标 |
| `observe` | 保持意图并观察 |

意图是决策标签，不是额外技能。`support` 不能凭空制造压制，`survive` 不能回血，`capture` 也不能跳过路径与控制点规则。

| LLM 生命周期 `phase` | 实际含义 |
|---|---|
| `thinking` | 该单位真实请求正在进行 |
| `submitted` | 已向 Godot 排队，尚无成功回执 |
| `executing` | 引擎接受该动作，仍可能被后续危险中断 |
| `waiting` | 模型选 wait，继续当前动作，无新回执 |
| `rejected` | 当前动作或权限被拒绝，见 `receipt.message` |
| `stale` | 观察或控制权已变化，旧回复被丢弃 |
| `fallback` | 模型失败/预算用完，执行明确标注的本地保命 |
| `inactive` | 已切换为其他控制方式 |
| `dead` | 单位已阵亡，不再请求 |

`origin=deepseek_lm` 才是有效模型决策；`local_fallback` 是本地保护策略，绝不统计为模型表现。控制台展示简短的可观察理由，不索取或展示模型隐藏推理过程。

## 限流、失败与观测

默认每局最多 600 次请求、单次超时 6 秒、输出最多 256 token。模型失败采用退避；预算用完后不会继续扣调用额度，UI 仍显示预算和本地保命。重新开始一局会重新计数。应用重启不跨进程记账，因此这个上限是每局护栏，并非账户级消费上限。

`GET /api/lm/status` 或 `/api/state` 的外层 `lm` 提供：模型名、请求数、token、累计响应延迟、每单位调用/有效决策次数、引擎接受/拒绝、过期和降级次数。战场里的每个单位额外提供最近被引擎接受的 `lm_intent`、`lm_reason`。战斗本体仍以 `state.units` 为唯一真相。

模型可以选择不明智的合法动作，不能把接入成功当作战斗质量优于游戏 AI。特别关注反复 hold、无进展 cover、等掩护导致全队都不前进等独立决策的协调缺口。

## 复现验证

```sh
python3 tools/project.py import
python3 tools/project.py test
# 下列命令会真实调用已配置的火山方舟模型。
python3 tools/lm_trial.py --seconds 40 --maps 0,1,2 --modes game_ai,lm
```

该试验启动独立临时控制服务和真实 Godot 无头引擎，按相同地图/初始游戏种子做三方全游戏 AI 与三方全 LLM 的短时比较。LLM 网络延迟、输出和实时随机消费并非确定性逐帧重放；这不是 LLM 对游戏 AI 的胜率比赛，不能据此宣称孰优孰劣。


## 炮组和建筑的 LLM 契约

观察包含双方全部 `at_guns` 与蓝方 `building` 的实际状态，不隐藏装备所有权、楼层和坍塌。模型可选择 `man_at_gun`、`leave_gun`、`garrison`、`leave_building`；Godot 检查队员归属、路线和生命状态后执行。模型只下达意图，连续推炮、楼梯路径、射击时机和紧急自保由实时执行器完成，坦克仍有自己独立的模型请求。

模型错误或预算用尽时，正在安全推炮/进楼的单位继续当前任务；其他单位使用本地保命。局部危险仍能打断任务。`error_codes` 将 JSON/动作失效与供应商错误分开统计。当前仍没有模型间通信、共享长程指挥和隐藏敌情；此版本不把独立 LLM 宣称为成熟小队指挥系统。

## LLM 战斗启动与可观测状态

界面统一使用 **LLM（大语言模型）**；稳定接口仍保留 `lm`、`/api/lm/status` 与 `DESKFRONT_LM_*`，兼容现有 Agent。

点击顶部「开始 DeepSeek LLM 对战」会逐一等待三个阵营的控制权成功回执，再恢复战斗。若本局已结束或预算耗尽，先重开再接管。该按钮使用真实火山方舟模型；不以本地脚本冒充模型输出。单纯切换下拉框仍尊重暂停状态。

顶部状态明确区分运行、暂停、未接管、预算耗尽、请求退避、对局结束和离线。逐单位卡片标出 DeepSeek LLM 或本地自保。默认请求上限提高到每局 600 次，仍然受预算限制；达到上限后停止付费请求并显示原因。

模型观察新增真实引擎计算的 `self.combat.engageable_targets`（射程内可开火目标，重武器可能先命中遮挡掩体）、`incoming_threats`（当前位置在敌方射程及有效射线内）、`path_active`。新增 `mission` 的推进分工参考、占点距离和全队积分，以及 `progress.idle_seconds`。分工和停滞信息只作为模型输入；最终指令仍由 DeepSeek 生成。模型健康、没有直接威胁又未占点时寻找推进机会，不再执行“只要有掩体就永久 hold”的绝对规则。紧急自保仍由 Godot 实时执行。

真实验证记录见 [LLM 战斗验证](evidence/llm-combat-fix.json)。短时功能试验验证了请求、逐单位决策及执行链路，不是胜率或保命能力基准。
