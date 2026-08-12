# 手动训练闭环

第一条纵向链路的产品与技术设计原文保存在产品记录仓库：

`/Users/sansyuan/obsidian_me/obsidian_note_2026-main/Repository/持续学习/Work/训练APP开发/开发文档/创建计划骨架流程开发/手动训练闭环-开发设计文档.md`

本代码库按依赖顺序分五个阶段实现该设计：

1. 建立代码仓库和最小工程。
2. 实现纯 Swift Domain 与 Application 接口。
3. 在 Repository 后实现 SwiftData 持久化。
4. 用四个 SwiftUI Feature 实现手动训练闭环。
5. 固化 Agent 候选命令的契约与示例。

依赖规则和当前阶段边界维护在 [`../../CONTEXT.md`](../../CONTEXT.md) 中。
