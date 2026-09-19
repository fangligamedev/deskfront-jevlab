# 角色、坦克、武器动作契约（0.6.0）

本文列出**运行时已经实现**的行为、状态和可调用动作。机器版本在 `data/action-catalog.json`，控制服务提供 `GET /api/action-catalog`；数值最终以当前 `GET /api/state` 的 `state.weapons` 为准。界面调参会改变伤害、射速和命中率。

## 读取和发令

先由策划把阵营切为 `agent`。读取 `GET /api/state`，确认 `engine_live=true`，保存 `run_id`、`tick`、存活单位和 `available_actions`。`POST /api/agent/command` 返回 202 只代表排队，必须轮询 `GET /api/result/<id>` 的引擎回执。返回成功表示接受了目标，不保证之后一定到达、命中或活下来。

```json
{"action":"posture","posture":"prone","faction":"green","unit_ids":["green-1"],"run_id":"从当前状态读取","seen_tick":120}
```

```json
{"action":"move","position":[0.54,2.40],"faction":"green","unit_ids":["green-1"],"run_id":"从当前状态读取","seen_tick":121}
```

第一条设置趴姿，第二条沿真实路径爬行。恢复自主姿态用 `posture=auto`。`seen_tick` 必须在当前 tick ±300 内；死亡、越权、过期、越界等仍由引擎拒绝。`unit_ids` 省略/空数组表示整阵营；包含坦克时不能整队请求步兵姿态或手雷。

常见拒绝：`authority_denied`、`stale_run`、`stale_observation`、`invalid_unit_authority`、`invalid_position`、`position_out_of_bounds`、`invalid_target`、`match_finished`；姿态额外有 `invalid_posture`、`infantry_required`、`action_busy`；手雷额外有 `grenade_unavailable`、`no_living_units`。

`available_actions` 是该单位此刻的粗筛选，不代替服务端校验。手雷可用性按最近敌人计算；显式指定不同目标仍可能因距离等条件被拒绝。一次整队手雷指令是原子校验，任何成员不可投掷则整条拒绝，不虚报“已投掷”。

## 人物与职责

| 单位 | 默认武器 | 游戏 AI 职责 | 能力差异 |
|---|---|---|---|
| green-1 / blue-1 / red-1 | rifle | overwatch，精确点射与掩护 | 共享全部步兵姿态、移动、刺刀和手雷动作 |
| green-2 / blue-2 / red-2 | smg | assault，持续短间隔射击、条件满足后绕侧 | 同上；不会因“突击”角色而忽略自保 |
| green-3 / blue-3 / red-3 | rocket | anti_armor，优先装甲、可射击阻挡物 | 同上；射速慢、装填时间长 |
| red-tank | at_cannon | 接近 → 低姿推炮 → 部署 → launch → 首碰撞爆炸 → crew_reload | 3.8 s / 当前为无限后备炮弹 | 2.05 m | 与坦克炮同一破坏规则 |
| cannon | armor，保持距离、炮火支援、倒车脱离 | 独立炮塔，不能趴下、使用刺刀或投掷手雷 |
| 办公室人类 | 无 | 缓慢循环操作电脑 | 非战斗装饰角色，不可接管 |

三个阵营使用同一执行器，没有阵营专属的隐藏战力。策划端 `equip` 可替换步枪、冲锋枪、火箭筒、手枪；Agent 端不允许改装备或改规则。

## 四层状态：不要只看 state

| 层 | 字段及值 | 语义 |
|---|---|---|
| 战术意图 | `order_mode`：take_cover、overwatch、bound、cqb_flank、formation、retreat、reposition、self_preserve、pinned、fire_support、reverse、hold、move、capture、cover、flank、attack、grenade | 想做什么；自保可以中断危险推进 |
| 姿态 | `posture`：stand / crouch / prone / armored；`posture_order`：auto / stand / crouch / prone | 真实播放的身体姿态和外部偏好 |
| 位移 | `locomotion`：idle / run / crouch_run / crawl / cover_step / tracks / reverse / disabled | 跑、低姿移动、爬行、近墙短步、履带前进/倒车 |
| 武器 | `weapon_state`：ready / fire / cooldown / reload / melee / throw / disabled | 和身体姿态独立，不会因换弹自动站起来 |
| CQB | `cqb_stance`：open / crouch / hide / peek | 开阔、低姿掩体、隐蔽、墙角探出 |
| 兼容字段 | `state`：idle / move / aim / cover / fire / reload / suppressed / melee / grenade / blocked / dead | 保留旧客户端；一个字段无法完整描述“趴姿爬行中换弹” |

`asset_animation` 给出当前真实片段；`animation` 是兼容语义标签。`cover_id` 是预约目标，不等于已到达；只有 `in_cover=true` 才在槽位附近。`survival_reason` 是当前自保原因（low_health / suppressed / flanked），不是模型的自然语言思维。`path_repairs` 统计通路修正次数，`path_failure` 记录最近一次绕行/无安全通路原因，不代表当前仍卡住。`last_shot_at`、`last_shot_target` 是最近真实开火记录；`action_counts` 记录组合状态进入次数，不是持续时间。

## 步兵执行系列

| 情况 / 指令 | 执行系列 | 中断和退出 |
|---|---|---|
| `move` / `capture` | 可达路径 → 跑动；整队用虚拟锚点与柔性队形 → 接敌停止队形推进 → 找掩体或建立射击位置 | 掩体被毁触发重新寻路；高压制/重伤自保优先 |
| `cover` | 排除敌侧、不可达、已预约或空间重叠槽位 → 比较路线暴露和距离 → 预约 → 跑/爬到位 → 蹲守 | 没有安全站位允许查询失败，不硬塞到错误墙面 |
| 墙角交火 | 隐蔽位等待 → 沿掩体端部短距离移动 → 肩部到位后开始暴露计时 → 瞄准/开火 → 返回隐蔽 | 换弹、压制、自保会提早收回；禁止隔着墙开枪 |
| 低掩体交火 | 跑到掩体后 → 蹲姿开火 → 装填/强压制时真正趴低 → 再恢复射击 | 碰撞由实际高度决定，蹲着并不保证无敌 |
| 开阔地交火 | 停止 → 趴下 → 瞄准 → 趴射 / 趴姿装填 | 近距离接敌可改站姿刺刀；重新行军可起身跑 |
| 被压制 | 压制达到阈值 → 趴下；有可达保护位则爬过去，没有则卧倒或向远离威胁的方向爬 | 压制恢复到较低阈值后才允许起身；有最小姿态保持时间，防止反复抖动 |
| 重伤 / 被绕后 | 中断推进 → 隐蔽或查询后方保护位 → self_preserve → 跑/爬撤离 → 保持保护 | 不会自动回血；恢复安全不代表恢复生命值 |
| 游戏 AI 交替推进 | 至少另一人近期真实开火且现在可射击 → 一人短距离推进 → 到位 → 轮换 | 掩护者换弹、受压制或失去射界则取消推进；单人不作有掩护的假动作 |
| `flank` | 查询敌掩体端部可达点 → 从端部绕过 → 攻击敌侧 | 外部 Agent 显式命令仍需自行协调友军；游戏 AI 仅在敌人已受压制/重伤且有支援时主动绕侧 |
| `retreat` | 返回出生阵地路线 → 柔性掩体偏置 → 跑/爬撤离 | 自保优先；不会无视障碍直线逃跑 |
| 刺刀 | 近距离、无墙阻挡、冷却就绪 → 朝敌人刺击 → 伤害 → 冷却 | 不穿墙、不攻击坦克 |
| 手雷 | 库存与距离校验 → 站姿引臂 → 0.62 s 释放 → 弧线逐段碰撞 → 爆炸 → 1.267 s 收势完成 | 受压制过高、换弹或正在贴墙短步则拒绝；死亡不再释放尚未出手的雷 |
| 失去战斗力 | HP=0 → 清空移动/掩体预约 → 禁止命令 → 骨骼布娃娃 | 没有复活、治疗或倒地救援系统 |

当前默认速度：跑 0.18 m/s，低姿 0.075 m/s，爬 0.038 m/s。压制与队形调整还会缩放速度。只有距掩体目标很近的横向调整使用约 33 mm 的接触短步；跨掩体转移不再统一播放慢走。

## 坦克执行系列

发现目标 → 优先反坦克威胁 → 查询适合炮火支援的可达位置 → 先转正车体，再履带移动 → 独立炮塔瞄准 → 开炮 → 冷却 → 再评估。默认支援距离约 0.56 m。近处火箭兵或低于 35% 血量时，以约 0.78 m 为脱离目标距离，倒车保持正面朝威胁。

前进、倒车、左转、右转映射到 T2 对应四个履带片段。炮塔朝向和车体朝向分离；正/侧/后装甲伤害倍率为 0.72 / 1 / 1.4。炮弹也会先命中墙面；能通过摧毁掩体打开射界。HP=0 后停止移动与射击并移除单位碰撞；坦克没有步兵布娃娃、模块断履带或维修技能。

## 武器状态与默认数值

| 武器 | 射击系列 | 间隔 / 弹匣 / 装填 | 有效范围 | 对掩体的默认单发基础伤害 |
|---|---|---|---|---|
| rifle | ready → aim → single fire → cooldown → repeat / reload | 1.05 s / 8 / 2 s | 0.70 m | 0.7 |
| smg | ready → aim → 快速连发 → 空匣装填 | 0.14 s / 24 / 2.5 s | 0.60 m | 0.3 |
| pistol | ready → aim → single fire → cooldown / reload | 0.40 s / 12 / 2 s | 0.42 m | 0.4 |
| rocket | aim → launch → flight → first impact → explosion → reload | 3.8 s / 1 / 3.8 s | 0.92 m | 70 |
| at_cannon | 接近 → 低姿推炮 → 部署 → launch → 首碰撞爆炸 → crew_reload | 3.8 s / 当前为无限后备炮弹 | 2.05 m | 与坦克炮同一破坏规则 |
| cannon | turret align → launch → flight → first impact → explosion → cooldown | 3.4 s / 1000（本局视为足量）/ 无装填动画 | 0.98 m | 85 |
| grenade | windup → release → curved flight → impact/explode → recover | 每兵 2 枚，无补给 | 0.65 m | 48 |
| bayonet | range + obstruction check → thrust → impact → cooldown | 0.85 s，无弹药 | 0.075 m | 不破坏掩体 |

武器射击自动执行，Agent 用 `attack` 选择敌人，不逐发发送 fire。手雷可带 `target_id`。`hold` 仅停止位移，仍自动交战；没有 hold_fire 指令。空匣自动装填，未开放手动提前换弹。SMG 为连续短间隔射击，没有额外的三发点射模式。

## 射线与破坏合同

每个弹丸每个模拟步对上一位置到下一位置做扫掠线段检测，选最近的掩体或身体。手雷弧线和大 dt 会分段；不会仅根据预先选中的目标扣血。单位命中盒随趴/蹲/站和朝向变化；掩体用与地图物理碰撞体一致的有向盒。近失弹可施加压制。友军身体挡子弹，但本版关闭友军伤害。

掩体经历 `intact → damaged → critical → destroyed`；受损变暗，摧毁后原模型消失、散落碎块，碰撞/射线/导航/预约一起更新。爆炸先计算完整掩体的遮挡，再结算破坏，因此打穿墙的那次爆炸不直接穿墙伤到背后单位；下一次攻击可经过缺口。破坏粒度为地图中的一个物件，并非任意网格实时切割。地图沙包、箱子、墙、建筑和岩石都有有限耐久；办公桌、地板等承载环境保持完整。

## 动画资源与未接入片段

当前士兵是 50 骨、28 片段，完整片段来源和时长见机器目录的 `clips`，根运动/循环声明见 `data/gait.json`。运行时使用：站立持枪、战斗跑、蹲姿移动、蹲守、左右贴墙步、左右探角、爬行、趴守、趴射、趴姿/蹲姿/站姿装填、持火箭筒、手枪射击、步枪射击、刺刀、投雷。模型同一套，颜色区分阵营。

`turn_left`、`turn_right`、`dodge_left_rm`、`roll_rm`、`hit`、`death`、`rifle_walk_rm`、`cover_enter`、`cover_exit` 保存在资源里，但当前 AI 没有相应独立技能；转身由控制器驱动，死亡用布娃娃，姿态进入/退出用混合。这些片段**不是可以向 Agent 虚报的可执行动作**。

通用 HTTP 接口已实现；Safetype.ai/Jev 的专属 SDK、鉴权和推理调用尚未接入。状态仍为完全信息，无战争迷雾。没有建筑内部破门清房、攀越、掩体贴边连续 IK、弹道穿透、任意网格断裂和联网同步。


## 0.6 四种控制来源与完整 Action 清单

顶层模式：`game_ai` / `lm` / `agent` / `player`。每个阵营可分别指定。LM 模式逐兵独立，不同队员的单兵命令不会互相清空路线。外部 Agent 仅在 `agent` 模式有权限；不能借公开请求的 `source` 字段伪装成内部 LM。

可调用的 **13 个引擎战术 Action**：`move`、`capture`、`cover`、`flank`、`retreat`、`hold`、`attack`、`grenade`、`posture`。LM 另可选 `wait`，代表不发送新命令、保留当前意图。`fire`、`reload`、`melee`、`hide`、`peek`、`crawl` 是执行状态/动作链，不能冒充现有 API 命令。

策划专用动作：`control`、`pause`、`speed`、`camera`、`reinforce`、`config`、`reset`、`map`、`equip`。LM 和外部 Agent 均无权修改这些管理动作。

LM 新增拒绝原因：`lm_single_unit_required`、`stale_control_epoch`、`survival_override`。单兵 LM 可在普通战术命令上附 `posture`；引擎先验证全部必要条件，再应用，紧急自保优先于 LM 站立/蹲姿偏好。玩家主动姿态偏好保持原有逻辑。

LM 的意图与调用状态全集、配置和错误处理见 [LM_CONTROL.md](LM_CONTROL.md)。模型状态与角色姿态/位移/武器/CQB 状态是不同层，必须同时读取。


## 反坦克炮与蓝方两层小楼（本轮新增）

权威快照增加 `state.at_guns`、`state.building`；单兵增加 `gun_id`、`building_phase`、`building_floor`、`elevation`。地面位置仍为 `[x,z]`，高差单独提供。设施动作必须 `unit_ids` 恰好一人，模型不能替同队其他单位发命令。

| Action | 必要条件/参数 | 执行动作系列 |
|---|---|---|
| `man_at_gun` | 同阵营健康步兵；火箭兵保留原职责；可选 `gun_id` | 接近炮尾 → root motion 推炮 → 停车部署 → 自动瞄准可用射界中的敌坦克 → 炮弹/装填 |
| `leave_gun` | 当前炮手 | 停止操作 → 留下炮架 → 恢复个人武器；可再 cover/retreat |
| `garrison` | 蓝方步兵，建筑可用；`floor=1/2`，默认 2 | 从外部入口进入 / 沿外置楼梯和平台上楼 → 窗口驻守 → 隐蔽与探头射击 |
| `leave_building` | 当前进驻者 | 沿已走过的路线下楼 → 回到入口；禁止直接跳楼 |

火炮 `phase`：`parked / approaching / towing / deploying / ready / abandoned / destroyed`。人物火炮状态跟随该系列；`locomotion=push_gun` 使用低姿移动 root motion 和双手 IK，个人武器隐藏。`weapon_state=crew_ready / crew_fire / crew_reload`。当前为**单人操作的轻型玩具炮**；没有假装实现两人装填协同。

建筑 `building_phase`：空值（楼外）、`approaching`（包括楼梯行进）、`stationed`（守窗）、`exiting`（撤离）、`falling`（楼板被毁后的下落）。`locomotion=stairs` 表示当前移动有楼梯高差。守窗按窗口节奏隐蔽/露出，上下楼按同一路径进行碰撞移动；一层和二层共享建筑但分别有射击高度。

所有设施都可能被打断：低血/高压制炮手弃炮，楼内士兵撤离，炮架或楼板摧毁会使原任务失效。轻武器 `attack` 坦克直接返回 `anti_armor_required`；正常索敌也过滤此类目标。坦克会关注敌方已部署反坦克炮。反坦克炮弹走与坦克炮同一套连续射线、首碰撞、遮挡爆炸和掩体破坏逻辑，牵引时不开炮。

设施常见拒绝：`single_crew_member_required`、`no_safe_gun_access`、`not_gun_crew`、`building_unavailable`、`not_garrisoned`、`leave_equipment_first`。`cover/retreat` 对设施使用者先执行安全退出；`hold` 保持设施任务。其他移动/进攻动作需先退出设施，以免新意图把人瞬间移下二楼。

```json
{"action":"man_at_gun","gun_id":"green-at","faction":"green","unit_ids":["green-1"],"run_id":"读取当前局次","seen_tick":120}
```
```json
{"action":"garrison","floor":2,"faction":"blue","unit_ids":["blue-1"],"run_id":"读取当前局次","seen_tick":120}
```

`wait` 仍然仅是 LM 控制器的保持意图，不是 Godot 命令。`gun_id` 仅用于 `man_at_gun`，`floor` 仅用于 `garrison`，无关的可选字段应省略，不能填写 null。

## 中央旗点与坦克部署扩展

`state.objective.flag` 包含 `owner`、`held_seconds`、`required_seconds`、`remaining_seconds`、`contested`。以这些值规划占旗、替补与防守；`capture` 接受命令并不代表占旗成功。

所有单位快照增加 `deployment_phase` 和 `combat_ready`；坦克依次为 `parked → entering → active`。前两阶段不接受战斗动作；LLM 不会对未入场坦克发请求。`state.tank_reserve` 可观察预放和入场过程。详见 [中央夺旗与坦克入场](FLAG_MODE.md)。
