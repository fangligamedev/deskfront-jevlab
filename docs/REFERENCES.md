# 研究参考与实现映射

下列仅借鉴公开设计思路，没有使用原作代码或游戏资产，也不把未取得讲义的内容编造成算法细节。

1. Chris Jurney，《Company of Heroes Squad Formations Explained》，AI Game Programming Wisdom 4，第2.1节。[文章](https://forum.arongranberg.com/uploads/short-url/rWod3K2KhNWcOEdjewnsLXQKU6A.pdf)。文章讨论小队层级、跟随目标、到达后的站位预约与掩体选择。本轮已完整阅读用户提供的4页PDF，并检查其队形插图。实现稳定兵种角色、共享虚拟行军锚点、预测位置、柔性偏移、速度修正、重寻路迟滞、站位预约和交替掩护。原文完整core/left/right层级及自定义路径搜索未逐项复刻。逐页映射见[战术实现](TACTICS.md)。
2. Alex Champandard、Philip Dunstan、Matthew Jack，GDC 2012，[Believable Tactics for Squad AI](https://www.gdcvault.com/play/1015665/Believable-Tactics-for-Squad)。本轮核对官方摘要，并读取公开播放流，抽查约2、6、10、15、20、25、30、35、40、45、50、55、60分钟画面。可确认集中/涌现式设计比较、协同小队、方向偏好、共享知识与小队寻路的演示主题；未取得字幕、未完整听译视频。具体条件与权重由本工程独立设计，详见[战术实现](TACTICS.md)。
3. Shelby Hubick、Chris Jurney，GDC 2007，[Dealing with Destruction: AI From the Trenches of Company of Heroes](https://gdcvault.com/play/765/Dealing-with-Destruction-AI-From)。已核对官方主题与讲者，未获得完整逐字稿。本工程让路障破坏更新导航和掩体语义，是针对桌面关卡的独立设计。
4. Erin Daly、Joshua Mosqueira，GDC 2007，[Theory into Practice: Single Player RTS design for Company of Heroes](https://gdcvault.com/play/719/Theory-into-Practice-Single-Player)。用户附件将其列为任务阶段设计入口。本工程用“争夺目标→红方劣势→坦克增援→胜负”组织单关卡；不声称重现其原始任务脚本。

用户提供的三张办公室概念画面用于确定灰绿色复古办公室、桌面微型战场和坦克增援的构图方向；生成的新模型是几何与动作可编辑的原创低多边形版本。参考图和附件正文未打进开源包。
