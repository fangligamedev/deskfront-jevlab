# 发布流程

## 版本

本次发布标记为 v9.19，日期 2026-09-19；运行时仍为 0.6.0。发布标记与语义化工程版本分开，不能自动把前者当成运行时 9.19。

使用 annotated tag。公开标签不强制移动；同名标签存在时检查指向，不能覆盖。保留历史 V0.1。

## 验收

1. 审查本轮文件，排除 .env、日志、缓存和无关草稿。
2. 更新 README、CHANGELOG、[文档索引](README.md)、受影响 API 和资源说明。
3. 运行项目合同检查与离线 Python 测试。
4. 玩法或资源修改需要真实 Godot 与 Web 输入检查；纯文档维护不重复 100 场。
5. 新素材必须有许可证、编辑来源、哈希。检查发行文件不含凭证。
6. 需要交付包时按 [开发指南](DEVELOPMENT.md) 导出和打包，记录 SHA256。

## 发布

先推送提交，再创建和推送标签。仅当本次标签尚未存在时执行：

```sh
git push origin main
git tag -a v9.19 -m "Deskfront v9.19：开源工程、文档与开发流程整理"
git push origin v9.19
git ls-remote origin refs/heads/main refs/tags/v9.19 'refs/tags/v9.19^{}'
```

远端 tag 解引用后的提交必须等于本地发布提交。本地 tag 存在不等于发布成功。若通过 GitHub Git Data API 同步，逐级核对 blob、tree、commit 和 tag SHA，禁止覆盖并发更新。

新工作流的本地检查不能冒充 GitHub CI 已通过。报告中分别说明验证、未验证平台和已知限制。真实 LM 记录写清样本量与本地降级。
