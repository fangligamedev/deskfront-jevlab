# DeepSeek 多题并行与 logprobs

用户提供的 `deepseek-logprobs-share.zip` 可以用于本项目的决策接口优化：同一份观察拆成多个短选择题，并行询问，取得答案 token 的概率，再合成合法游戏指令。它不意味着 DeepSeek 与 JEV 的速度、能力或概率校准相同。

本工程新增原创 Python 适配器 [deepseek_logprobs.py](../../tools/deepseek_logprobs.py)。附件无独立许可证，因此没有把附件 JavaScript、图片或测试代码直接复制进仓库；仅依据其思路实现，与现有 MIT Python 控制器集成。

## 实现

- 战术、危险判断、姿态三个问题共用一次观察；坦克省略姿态题，使用两个请求。
- **一轮多个 HTTP 请求**，每题一个，线程池并发，等待最慢题；不是声称一个 DeepSeek 请求原生返回所有问题。
- 每题使用字母选项、8 token 上限、关闭 thinking、`logprobs=true`、`top_logprobs=20`。已实际验证当前配置的 `deepseek-v4-flash-260425` 返回该结构；其他模型须另测。
- 在前 12 个 token 位置中取覆盖候选字母最多的一处，以数值稳定 softmax 对观察到的合法选项归一化。
- 显示 `coverage/observed_labels/meaning`。没有返回的候选赋零只表示未观测到，不能证明不可能；概率是**已返回选项 token 的条件分布**，不是行动成功率或胜率。熵得到的 confidence 也不是外部校准结果。
- 战术选择与姿态合成一条已有合法动作；危险题作为模型评估保留在日志。Godot 的紧急保命逻辑仍有最终否决权，不靠“危险概率”绕过游戏规则。
- 回复有 logprobs 但没有合法字母时最多重试一次；缺失 logprobs、HTTP 拒绝和网络失败不在题内反复重试。重试返回的 usage 一并累计。
- 三题原始响应、解析分布、最终动作与 Godot 回执均写入既有调用日志。过期、阵亡目标、权限切换的返回可能被合法拒绝，不伪称全部执行成功。

## 配置与成本

`.env` 中设置 `DESKFRONT_LM_PROVIDER=deepseek_logprobs`，沿用 Ark Key、模型 ID、超时、并发参数；重启服务生效。凭证只会发往允许的火山方舟官方推理主机；不会发送到附件来源站点。

`DESKFRONT_LM_MAX_REQUESTS` 当前计数单位是决策轮数。步兵一轮通常 3 个底层请求，格式重试时最多 6 个，坦克通常 2 个；单位并发 3 时，底层可能同时有 9 个请求。每题重复输入战况，输出短了不代表输入成本自动下降。`usage.provider_requests` 和 `logprobs_evaluation` 可审计真实轮次组成。

前沿防线选择不需要三题：JEV 使用结构化 choice；DeepSeek 使用短 JSON 选择模板，来源标记 `deepseek_json_frontier`。不要把这部分称为 logprobs 战术决策。

## 本轮实测

2026-09-20：官方 Ark 模型 `deepseek-v4-flash-260425` 单题探测成功，耗时约 1911 ms、输出 1 token，A/B 候选覆盖完整。这个样本只证明接口能力，不是性能承诺。

网页实战中，三题并行产生了 capture、attack、hold、wait 等指令并得到引擎执行回执；也出现目标死亡等时序拒绝。详细本轮实测数字、机制测试与局限见 [交付报告](DELIVERY.md)。附件图中的“约 3.1 秒”是附件历史样本，本项目没有把它当作固定延迟。
