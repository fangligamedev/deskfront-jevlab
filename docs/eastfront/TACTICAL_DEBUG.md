# 东线战术回归修复与 Laya 默认指挥

## 默认入口

打开 `http://127.0.0.1:8794/?view=eastfront`，默认前沿构筑为「DeepSeek 规划 + Laya 本地执行」，远征队为「Laya · 本地战术指挥」。Web 首次启动也使用这套真实配置，不仅修改下拉框。已有旧局需刷新或开始新东线。

DeepSeek 规划后三段关卡，本机 Laya 选择持续推进、南北侧翼或重整，并安排施工顺序。绿色控制权保持 `lm`，Godot 将模型的小队意图落实为站位预约、交替掩护、短距跃进、射击与自保。当前模型决策粒度是小队意图，具体哪名队员移动由确定性的协同执行器分配；并非每帧请求模型预测每名士兵的脚步。

## 根因

1. 双脑快脑提交小队意图，但选择逐兵模型会把绿色设成 `lm`；原协调器只处理 `game_ai`，因此小队战术停止运行。独立逐兵请求仍发 capture/move，把不同队员推向同一旗点。这个组合是实现和界面设计的问题。
2. 东线沿用 `center_flag` 规则，接敌时提前走简化夺旗策略，跳过原有 take_cover → suppress → bound 协同状态机。
3. 施工等待和切换扇区后，上一旗点的 formation 未清除，其更新会把连续推进路径改回旧目标，形成走停或折返。

## 修改

- 双脑的模型控制改为 Laya/JEV 小队指挥，接上原掩体协同器；同一绿色小队不再启动竞争的逐兵调用，旧逐兵命令由引擎拒绝 `squad_director_owns_orders`。
- 单模型布局下仍保留独立逐兵模型。双脑选对应的 Laya/JEV 控制，玩家、外部 Agent 和游戏 AI 仍可选择。
- 东线接敌恢复原小队状态机；空旷安全段分路连续跑动，守军清除后收尾占旗。
- 切段清旧编队；安全推进不允许旧编队重写路线；候选移动点避让队友的在途目标。
- 模型控制也能将受伤者撤回安全补给点。玩家接管停止模型协同。
- 显示真实指挥来源、当前战术阶段、入掩体人数、推进者与有射界的掩护者。模型失效时明确显示错误与本地续行，不伪造模型成功。
- Laya 服务忙碌或网络超时时退避 4 秒再调度，避免固定 2 秒请求持续挤占共享本地服务。

## 实测

- 无头固定 seed 19、错列沙包，绿色 `lm` + 双脑 Laya 执行链：3 名队员都曾实际进入掩体，经历 take_cover / suppress / advance / bound / defend；66.4 游戏秒、39 次射击后自然攻下第一段。13 项断言通过。该测试注入合法关卡，不调用真实模型。
- 双脑施工与补给契约 17 项通过；Godot 语义 113 项通过；Python 接口测试 90 项通过。
- 真实网页默认加载 Laya 组合，点击「应用控制方式」收到成功回执。真实 DeepSeek 规划了 supply_yard → staggered → ridge_pass；197.8 游戏秒已自然突破三段、进入 crossfire。Laya 日志具有 `executed` 回执，采样请求约 105–126 ms（单机样本，不是性能保证）。
- 真实测试后段出现共享 Laya 服务忙碌 429，响应为正在处理上一条请求。没有把此期间本地续行声称为模型实时成功。已追加退避；未声称全程零服务错误。
- 浏览器调试曾记录重启服务时的旧 fetch 断连；刷新后的战场正常同步。

这轮修的是指挥与协同衔接，没有新增下沉战壕地形或骨骼动作。未来仍需扩大布局和敌我兵种组合测试；一次成功推进不代表所有关卡已达到同样的战术表现。

## 复现

```sh
Godot --headless --path . --script tests/eastfront_tactical_regression.gd
Godot --headless --path . --script tests/dual_brain_contract.gd
Godot --headless --path . tests/semantic_probe.tscn
python3 -m unittest discover -s tests -p 'test_*.py'
```

结构化证据：[tactical-debug.json](../evidence/eastfront/tactical-debug.json)。运行中的完整本机观察留在被 Git 忽略的 `output/tactical-debug/`，不提交凭证或完整模型调用数据库。
