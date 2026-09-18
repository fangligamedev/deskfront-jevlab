# 研究参考与实现映射

下列仅借鉴公开设计思路，没有使用原作代码或游戏资产，也不把未取得讲义的内容编造成算法细节。

1. Chris Jurney，《Company of Heroes Squad Formations Explained》，AI Game Programming Wisdom 4，第2.1节。[文章](https://forum.arongranberg.com/uploads/short-url/rWod3K2KhNWcOEdjewnsLXQKU6A.pdf)。文章讨论小队层级、跟随目标、到达后的站位预约与掩体选择。本工程采用“小队指令→单兵站位”和预约互斥的简化实现；未实现完整虚拟队长或行军队形层级。
2. Alex Champandard、Philip Dunstan、Matthew Jack，GDC 2012，[Believable Tactics for Squad AI](https://www.gdcvault.com/play/1015665/Believable-Tactics-for-Squad)。官方摘要包含包抄、压制、小队同步与战术寻路。本工程用可观察的效用评分选择占领、掩体、侧翼、撤退；这是本工程自行设计的具体实现，不冒充演讲里的原始公式。
3. Shelby Hubick、Chris Jurney，GDC 2007，[Dealing with Destruction: AI From the Trenches of Company of Heroes](https://gdcvault.com/play/765/Dealing-with-Destruction-AI-From)。已核对官方主题与讲者，未获得完整逐字稿。本工程让路障破坏更新导航和掩体语义，是针对桌面关卡的独立设计。
4. Erin Daly、Joshua Mosqueira，GDC 2007，[Theory into Practice: Single Player RTS design for Company of Heroes](https://gdcvault.com/play/719/Theory-into-Practice-Single-Player)。用户附件将其列为任务阶段设计入口。本工程用“争夺目标→红方劣势→坦克增援→胜负”组织单关卡；不声称重现其原始任务脚本。

用户提供的三张办公室概念画面用于确定灰绿色复古办公室、桌面微型战场和坦克增援的构图方向；生成的新模型是几何与动作可编辑的原创低多边形版本。参考图和附件正文未打进开源包。
