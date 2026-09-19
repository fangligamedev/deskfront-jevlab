# 全部说明文档

发布标记 **v9.19**，运行时 **0.6.0**。以下为已发布 Markdown 文档完整清单；历史报告记录当时实现，当前使用以 README、API 和开发指南为准。

先读 [项目介绍](../README.md)，开发者读 [开发指南](DEVELOPMENT.md)，Agent 作者读 [动作全集](AGENT_ACTION_STATES.md)。

| 文件 | 说明 / 内容 | 类别 |
| --- | --- | --- |
| `.github/ISSUE_TEMPLATE/bug_report.md` | [bug_report](../.github/ISSUE_TEMPLATE/bug_report.md) | 协作模板 |
| `.github/ISSUE_TEMPLATE/feature_request.md` | [feature_request](../.github/ISSUE_TEMPLATE/feature_request.md) | 协作模板 |
| `.github/PULL_REQUEST_TEMPLATE.md` | [PULL_REQUEST_TEMPLATE](../.github/PULL_REQUEST_TEMPLATE.md) | 协作模板 |
| `AGENTS.md` | [Deskfront](../AGENTS.md) | 当前指南 |
| `CHANGELOG.md` | [更新日志](../CHANGELOG.md) | 当前指南 |
| `CONTRIBUTING.md` | [贡献指南](../CONTRIBUTING.md) | 当前指南 |
| `README.md` | [Deskfront · 桌面前线](../README.md) | 当前指南 |
| `SECURITY.md` | [安全说明](../SECURITY.md) | 当前指南 |
| `THIRD_PARTY.md` | [第三方组件与来源](../THIRD_PARTY.md) | 当前指南 |
| `assets/LICENSE.md` | [资源许可](../assets/LICENSE.md) | 当前指南 |
| `docs/AGENT_ACTION_STATES.md` | [角色、坦克、武器动作契约（0.6.0）](AGENT_ACTION_STATES.md) | 当前指南 |
| `docs/AGENT_API.md` | [Agent 状态与动作接口 v1](AGENT_API.md) | 当前指南 |
| `docs/ASSETS.md` | [资源与配置（运行时 0.6.0）](ASSETS.md) | 当前指南 |
| `docs/ASSET_EQUIPMENT.md` | [已准备资源的运行集成](ASSET_EQUIPMENT.md) | 当前指南 |
| `docs/BRIEF-0.6.0.md` | [0.6 独立 LM 队员](BRIEF-0.6.0.md) | 工作说明 |
| `docs/DELIVERY-0.3.0.md` | [桌面前线 0.3.0 · 战术行为交付报告](DELIVERY-0.3.0.md) | 历史交付 |
| `docs/DELIVERY-0.4.0.md` | [桌面前线 0.4.0 · 最新资源集成交付报告](DELIVERY-0.4.0.md) | 历史交付 |
| `docs/DELIVERY-0.5.0.md` | [桌面前线 0.5.0 · 战术执行迭代交付报告](DELIVERY-0.5.0.md) | 历史交付 |
| `docs/DELIVERY-0.6.0.md` | [Deskfront 0.6 交付报告](DELIVERY-0.6.0.md) | 历史交付 |
| `docs/DELIVERY-v0.1.0.md` | [桌面前线 · 交付报告](DELIVERY-v0.1.0.md) | 历史交付 |
| `docs/DELIVERY-v0.2.0.md` | [桌面前线 0.2.0 · 本轮交付报告](DELIVERY-v0.2.0.md) | 历史交付 |
| `docs/DELIVERY-v9.19.md` | [v9.19 开源整理交付](DELIVERY-v9.19.md) | 本次交付 |
| `docs/DELIVERY.md` | [当前交付](DELIVERY.md) | 当前指南 |
| `docs/DESIGN.md` | [游戏设计](DESIGN.md) | 当前指南 |
| `docs/DEVELOPMENT.md` | [开发、构建与故障排查](DEVELOPMENT.md) | 当前指南 |
| `docs/ENGINEERING.md` | [工程文档](ENGINEERING.md) | 当前指南 |
| `docs/LM_CONTROL.md` | [DeepSeek LM 独立队员控制（0.6.0）](LM_CONTROL.md) | 当前指南 |
| `docs/README.md` | [全部说明文档](README.md) | 当前指南 |
| `docs/REFERENCES.md` | [研究参考与实现映射](REFERENCES.md) | 当前指南 |
| `docs/RELEASING.md` | [发布流程](RELEASING.md) | 当前指南 |
| `docs/TACTICS.md` | [0.5.0 生存优先的桌面战术执行](TACTICS.md) | 当前指南 |
| `docs/asset-integration/INTEGRATION.md` | [集成契约与资源配置](asset-integration/INTEGRATION.md) | 资源集成 |
| `docs/asset-integration/LOCOMOTION.md` | [横向蹲行修正交付 · 2026-09-18](asset-integration/LOCOMOTION.md) | 资源集成 |
| `docs/asset-integration/OFFICE-WORKER.md` | [办公人物替换](asset-integration/OFFICE-WORKER.md) | 资源集成 |
| `docs/asset-integration/SANDBOX.md` | [大沙盘场景交付](asset-integration/SANDBOX.md) | 资源集成 |

## 机器可读记录与许可证

- [动作 JSON](../data/action-catalog.json)、[动画目录](animation-catalog.json)、[资源清单](../.forge/assets.json)。
- [0.6 验证证据](evidence/v06/verification.json)；历史 evidence 目录按版本保留，output 是本机临时记录。
- 根目录 [MIT](../LICENSE)；第三方许可全文位于 docs/licenses，逐素材适用范围见 [第三方声明](../THIRD_PARTY.md)。

本目录由 `python3 tools/docs.py --write-index` 根据 Git 索引生成；新文档先 stage 再更新索引。`python3 tools/docs.py --bundle` 生成完整正文 Markdown 与文档 ZIP，存放于 dist，不提交重复副本。

- [已确认资产应用到主游戏](ASSET-APPLICATION.md)：男性人物补齐、预览资源对照、楼梯寻路适配与实际运行验证。
